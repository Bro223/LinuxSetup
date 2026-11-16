# Omarchy Bar Weather Icon Missing — Network WAF 403-Blocks the open-meteo URL

- **Date:** 2026-11-16
- **Machine:** Lenovo ThinkPad P52, on a managed **10.103.0.0/22** network (office/managed egress, not home-style)
- **OS:** Arch + Omarchy (shell = quickshell, `omarchy-shell` supervised by `omarchy-launch-shell`), weather plugin `omarchy.weather` (panels/weather)
- **Status:** FIXED — location set to name-only so the panel runs on its wttr.in fallback path

## 1. Problem

The weather icon/button disappeared from the bar. Restoring Omarchy defaults did not
bring it back (and re-enabled the `omarchy.agents` plugin — disable it again, see
`omarchy-agents-panel-rg-spikes` note). Plugin showed `enabled`, bar layout
(`~/.config/omarchy/shell.json` → `bar.layout.centerEnd`) still contained
`omarchy.weather`, and the data path was healthy: location set (Tallinn),
`omarchy-weather-status` returned live data.

## 2. How the widget decides to show

`BarWidget.qml`: `visible: panelLoader.item && panelLoader.item.label !== ""` — the
button hides itself when the panel's `label` (weather glyph) is empty. The label is
only set by a successful fetch, and which fetch sets it depends on the saved
location:

- **Coordinates saved** in `~/.local/state/omarchy/settings/weather.json` →
  label comes from the **open-meteo** fetch only (the wttr.in path skips the label).
- **Name-only location** → label comes from **wttr.in** (`provisionalCurrentIcon`),
  and the panel's 3-day forecast falls back to wttr's own forecast
  (`buildForecastDays` → `wttrNextForecastDays`).

A failed fetch exhausts its 3-retry budget in ~10 s; the next retry is the 15-min
`refreshTimer`. With the button hidden there is no user-visible way to force a
refresh — so one bad startup can keep the icon gone for the whole session.

## 3. Root cause (measured)

The network's egress firewall (plain **nginx 403** block page — not
Open-Meteo's own JSON error) blocks **one specific URL pattern**: open-meteo
forecast queries containing the combination
`daily=…&current=…&forecast_days=4&timezone=auto` — the panel's exact URL.

Bisection (all from this machine, no proxy env involved):

| Variant | Result |
|---|---|
| Panel's exact URL (all 4 param groups, `forecast_days=4&timezone=auto`) | 403 nginx |
| minus `timezone=auto` | 200 |
| `forecast_days=1` instead of `4` | 200 |
| `timezone=utc` instead of `auto` | 400 (reached Open-Meteo's API → block is pattern-based, not length) |
| 191–192 char variants (longer than the blocked 186-char URL) | 200 |
| each param group alone | 200 |

i.e. a bot-signature-style WAF rule on that exact query shape, specific to this
network. Longer URLs pass, so it is not a length threshold.

## 4. Why the icon died right after the defaults restore

The restore wiped the saved weather location. The panel re-detected Tallinn and
saved it **with coordinates** (weather.json mtime = restore time). Coordinates flip
the label source from wttr.in (works here) to open-meteo (403 here) → label never
populates → button hidden. `omarchy-restart-shell` alone could not fix it because
the blocked fetch fails on any network state.

## 5. Fix applied

Set the location back to name-only so the panel runs on its designed fallback:

```json
{"name": "Tallinn"}
```

in `~/.local/state/omarchy/settings/weather.json` (backup: `/tmp/weather.json.bak`),
then `omarchy-restart-shell`. Icon, panel, and 3-day forecast all work via wttr.in.

Label-persistence facts that make this safe: `currentIcon(empty, fallback)` returns
the fallback, so a later failed open-meteo fetch never clears an existing label;
and with coordinates, wttr responses do NOT re-save location
(`weatherResponseCompletesSave`), so the name-only state is stable.

## 6. Notes / revisit

- On a network **without** this WAF rule, editing the location in the weather
  panel (click the location label) re-saves coordinates and restores
  open-meteo-precision current conditions. If the icon ever vanishes again on such
  a network, that is the first thing to check.
- If it recurs on THIS network with a name-only location, suspect the WAF rule
  expanded to wttr.in's `?format=j1` URL — re-run the bisection above.
- The "duplicate IPC handler registered" warnings for all panels in the
  `omarchy-shell` journal are normal in this Omarchy version (each panel
  instantiates twice: bar widget + panel registry) — not a fault indicator.
- The panel's wttr retry budget (3 × ~10 s) with a 15-min fallback timer means a
  fetch failure at shell startup can hide the icon for up to 15 min even on a
  healthy network; `omarchy-restart-shell` clears that state.
