# Omarchy "Agents" Panel — Periodic ripgrep (rg) CPU Spikes

- **Date:** 2026-11-09
- **Machine:** Lenovo ThinkPad P52, Intel i7-8850H (6C/12T, TDP 45W, RAPL-capped at PL1 45W / PL2 78W), Quadro P1000 Mobile
- **OS:** Arch + Omarchy 4.5.0-3, kernel `7.2.15-1-omarchy`, Hyprland 0.56.2
- **Status:** FIXED — plugin disabled

## 1. Problem

Recurring short CPU spikes: bursts of **many concurrent `rg` processes** visible in
process monitors (each showing ~1–8% CPU, so individually harmless-looking), running
for seconds, then vanishing. Aggregate load briefly saturated all 6 cores, pushing the
45W-capped package into a system-wide microfreeze feel. Spikes recurred on a
regular cadence and were initially unattributable (Chrome renderers were also
spiking separately, which confused attribution).

## 2. Diagnosis

Deployed a lightweight watcher (`/tmp/rg-watcher.sh`, ps-poll every 200ms, 10-minute
window) that logged every `rg` spawn with pid, ppid, grandparent, and full args.
It captured **20 spawns in one burst** (2026-11-09 17:08:15–17:08:27):

```text
rg (pid=3674860)  --no-ignore --hidden --files-with-matches --glob *.jsonl
                  -e "provider":"google-antigravity" -- /home/aleks/.pi/agent/sessions
 └─ ppid=3674674  python3 /usr/share/omarchy/bin/omarchy-agent-usage-agy
 └─ ppid=3674758  python3 /usr/share/omarchy/bin/omarchy-agent-usage-synthetic
 └─ ppid=3674762  python3 /usr/share/omarchy/bin/omarchy-agent-usage-vibe
     └─ all under: bash /usr/share/omarchy/bin/omarchy-agent-usage-update
```

Parent chain, fully confirmed:

```text
rg  (one per provider, ~23 in a wave, 16 concurrent at peak)
 └─ python3 /usr/share/omarchy/bin/omarchy-agent-usage-<provider>
     └─ bash /usr/share/omarchy/bin/omarchy-agent-usage-update
         └─ Omarchy shell (quickshell) plugin "omarchy.agents" — Main.qml Timer
```

## 3. Root cause

The **agents panel** — a new first-party Omarchy 4.5 bar-widget that tracks AI-agent
usage/limits across providers (claude, codex, copilot, cursor, deepseek, devin, grok,
hermes, kimi, minimax, openrouter, qwen, …). It was introduced with the Omarchy 4.5
update, which is when the spikes started.

Scheduling (from `/usr/share/omarchy/shell/plugins/agents/Main.qml`):

- Timer every `refreshIntervalSec` — default **900s (15 min)**, min 30s
- **`triggeredOnStart: true`** — one scan at shell startup
- Degrades to **180s (3 min)** cadence when any tracked account is near its usage limit
- Each run = ~23 ripgrep invocations (one collector script per provider), all-cores,
  with `--no-ignore --hidden` (broadest scope)

Why it was expensive on this box: the scan target `~/.pi/agent/sessions`
(Pi coding-agent session store) had grown to **1.5 GB / 290 JSONL files**. So every
15 minutes the machine ran a wave of ~20 full-core scans over 1.5 GB.

Note: the `pi` agent process appears next to the `rg` entries in process monitors —
that is adjacency, not causation. `pi` *owns the data being scanned*; it does not
spawn the scans.

## 4. Fix applied

```bash
omarchy plugin disable omarchy.agents
```

The panel is not used on this machine, so disabling the plugin removes all scans.
Reversible with `omarchy plugin enable omarchy.agents`.

## 5. Alternatives considered (not applied)

| Option | Command / how | Trade-off |
|---|---|---|
| Slow the refresh | plugin setting `refreshIntervalSec` → e.g. `3600` (shell → plugin settings UI) | keeps the panel; still bursts hourly, and 3-min cadence kicks in near account limits |
| Shrink the scan target | archive `~/.pi/agent/sessions/*.jsonl` older than ~30 days into a tarball | makes any burst ~5–10× cheaper; also frees >1 GB disk. Worth doing regardless once the store grows again |
| Leave as-is | — | accept a ~10–15s all-core burst every 15 min |

## 6. Ruled out (evidence)

| Suspect | Verdict |
|---|---|
| JetBrains Toolbox / IntelliJ / `jetbrainsd` spawning rg | out — all 20 captured parents were `omarchy-agent-usage-*`; zero from any JetBrains process |
| Chrome / editors / IDE search features | out for this signature — Chrome renderers spike separately and are a different issue (pathological tabs, see freeze-monitor work) |
| Malware / unknown process | out — every spawn has an Omarchy parent and a known args pattern |

## 7. Verification / monitoring

- `omarchy plugin list` shows `omarchy.agents … disabled`.
- If spikes ever recur, redeploy the watcher approach: poll `pgrep rg`, log
  `ps -o ppid=` + parent/grandparent cmdlines. Full evidence from this incident is
  in the (since removed) `/tmp/rg-watcher.log`; the capture format above is the template.
- The 45W RAPL clamp (separate fix) bounds the damage: these bursts now surface as
  brief all-core slowdowns at the power ceiling, not thermal events.
