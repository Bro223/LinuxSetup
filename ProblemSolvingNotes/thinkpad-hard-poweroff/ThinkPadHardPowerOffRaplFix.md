# ThinkPad P15 Gen 1 Hard Power-Off Crashes — RAPL Power-Limit Fix

- **Date:** 2026-11-04
- **Machine:** Lenovo ThinkPad P15 Gen 1 (20ST001MGE), Intel i9-10885H (8C/16T, TDP 45W, MTP 90W), Quadro RTX 4000 Max-Q (90W default limit), 64GB RAM
- **OS:** Arch + Omarchy, custom kernel `7.2.8-9-omarchy` (BORE scheduler), NVIDIA 615.78.08
- **BIOS:** N30ET62W (1.98, latest for this model at the time)

## 1. Problem

Sudden **hard power-off** while using the laptop: instant screen-off, no freeze, no flicker,
no shutdown sequence. 2026-11-04 had a crash cluster: six deaths in one day
(boots ending at ~11:42, 11:48 [1s], ~13:40, 16:17 [42s], 17:04, plus 1-second boots at 17:08/17:10).

Death signature (identical every time):

- `last` marks the boot as `crash`
- NVMe `unsafe_shutdowns` counter increments on every death (nvme0 161→181, nvme1 127→140)
- **No** kernel panic, oops, soft/hard lockup, BUG, MCE, AER, thermal trip, or OOM in the journal
- **No** `Rebooting` / `Shutting down` system events — the journal just stops mid-normal-operation
- Deaths in every power state: on AC under load, on battery, at idle, 1 second after boot

## 2. What was ruled out (evidence)

| Suspect | Verdict | Evidence |
|---|---|---|
| Kernel panic / lockup / OOM | out | full journal scan of all Nov 4 boots: zero panic/lockup/OOM lines |
| MCE / memory hardware error | out | `dmesg` clean; RAS collector had nothing |
| AER / PCIe error | out | platform does not even expose AER; no PCIe error storms |
| Thermal shutdown (>100C) | not the killer | no critical-trip event in any journal; NVMe "Critical Composite Temperature Time: 0"; a thermal kill is a graceful *logged* ACPI shutdown, never an unlogged hard cut; 1-second-at-boot deaths happen before heat is possible. **However**: with the old power limits the CPU *does* pin at 100.0C (Tjmax) under moderate load — a real secondary problem, fixed by the same cap (see §4) |
| Power brick / AC input | out | 65W plug-in test; 1-second deaths occurred on battery only |
| Battery | out | 81% health; voltage stable at 11.7-12.4V on 5Hz sampling up to the moment of each clean shutdown |
| Disks | out | SMART clean on both NVMe |
| BIOS outdated | out | 1.98 is latest |
| Cooling | out (as crash cause) | repacked 2 weeks before the crash cluster; PCH 50C, GPU 44-46C at death-adjacent samples |
| `nvidia-powerd` "SBIOS support not found" | noise | fails identically on every boot including multi-day stable ones; exits cleanly; means SBIOS exposes no NVIDIA platform config, not a power fault |
| `thermald` inactive | noise | exits by design: `dytc_lapmode present: Thermald can't run on this platform` — this ThinkPad has Lenovo DYTC **firmware** thermal control, which is the platform's actual thermal management; thermald is an optimization daemon, not a safety mechanism |
| System clock | unrelated | the "2-hour fast boot" on 2026-11-04 was caused by manually setting the BIOS clock: the BIOS displays the raw RTC value (true UTC, no timezone) — it showed 15:25 when local was 17:25, was "fixed" to 17:25, which left the RTC 2h fast; kernel (UTC mode) booted 2h ahead and timesyncd stepped it back ~30s after boot. Self-heals; do NOT "fix" the BIOS clock again |
| Fingerprint reader USB resets | noise | built-in Synaptics Prometheus reader (06cb:00bd, usb 1-9) resets via xhci every ~13.5 min; low-power device, unrelated to power-off; explains why sudo shows "Place your right index finger..." then falls back to password |

## 3. Root cause (working hypothesis, high confidence — confirmation pending)

**Firmware RAPL power limits are far above Intel's spec for this CPU:**

```
/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw = 90000000   (PL1 long-term = 90 W)
/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw = 135000000  (PL2 short-term burst = 135 W, 2.4 ms window)
```

Intel spec for the i9-10885H: **45 W TDP, 90 W max turbo (MTP)**. The firmware-planted
**135 W burst limit is 50% above Intel's maximum** for this part, on a 7-year-old board whose
VRM/PCB/capacitors are not guaranteed for that transient. A 135 W 2.4 ms burst (a single turbo
spike can trigger it, even near idle) is the largest power transient on the board.

That fits the death signature exactly: instant, unlogged, load-independent, power-state-independent
power loss with NVMe unsafe-shutdown bumps — consistent with a rail sag / overcurrent that makes
the EC cut power. The overheating data (100C at 90 W PL1) shows the same budget being exceeded on
the thermal side too.

**Confirmation still pending:** BIOS/EC System Event Log (F1 at POST → Event Log). A logged
power/overcurrent fault there is the decisive piece and the Lenovo-service ticket.

## 4. The fix (applied, persistent)

Clamp CPU RAPL limits to Intel's recommended envelope: **PL1 = 45 W (TDP), PL2 = 90 W (MTP)**.

Observed effect (same workload, minutes apart):

```
before: CPU=100000mC THM=98000mC load=1.6   (pinned at Tjmax, throttling)
after:  CPU=56000mC  THM=55000mC load=1.1
```

### Files installed (v2 — ceiling semantics, self-healing)

| File | Purpose |
|---|---|
| `/usr/local/bin/rapl-power-limit.sh` | clamps PL1/PL2 **down** if above the ceiling (or 0 = firmware default); never raises; finds the RAPL domain dynamically |
| `/etc/systemd/system/rapl-power-limit.service` | oneshot, runs at every boot (`multi-user.target`), `RemainAfterExit=yes` |
| `/etc/systemd/system/rapl-power-limit.timer` | re-runs the service 2 min after boot, then every 10 min (self-healing) |
| `/etc/rapl-power-limit.orig` | original firmware values + restore commands |

**v2 semantics (updated 2026-11-04):** the script enforces a *ceiling*, not a fixed value — it
only lowers a limit that is above the ceiling (or `0`, which in RAPL means "firmware default" =
90/15... 90/135 on this machine) and never raises anything. Consequences:

- firmware's aggressive 90/135 at every cold boot → clamped to 45/90 within seconds
- anything that pushes limits back up at runtime → clamped again within 10 min (timer)
- eco mode / manually written *lower* limits → left untouched while the system is on
  (a full power cycle always resets RAPL to firmware values, then the boot service clamps to 45/90)

To change the ceiling itself (e.g. a stricter eco default), edit `PL1_MAX` / `PL2_MAX` in the
script.

### Re-apply from scratch (fresh system / after reinstall)

```bash
sudo tee /usr/local/bin/rapl-power-limit.sh >/dev/null <<'EOF'
#!/bin/bash
# CPU power CEILING - crash mitigation on ThinkPad P15 Gen 1 (i9-10885H).
# Firmware ships PL1 90W / PL2 135W (135W burst is 50% above Intel MTP) - suspected
# trigger of the hard power-off crashes. Enforces Intel's envelope as a ceiling:
#   PL1 (long term)  never above 45 W (TDP)
#   PL2 (short burst) never above 90 W (Intel MTP)
# Lower values (eco mode, manual tuning) are left untouched.
# 0 in RAPL means "firmware default" (= 90/135 here), so it is treated as over-ceiling.
# Docs: MyScripts/LocalRepos/LinuxSetup/ProblemSolvingNotes/thinkpad-hard-poweroff/
PL1_MAX=45000000
PL2_MAX=90000000

# Package domain = the intel-rapl domain that exposes constraint_1 (short term).
# Found dynamically so a powercap renumbering in a future kernel cannot break this.
P=""
for d in /sys/class/powercap/intel-rapl:*; do
    if [ -f "$d/constraint_1_power_limit_uw" ]; then P="$d"; break; fi
done
[ -n "$P" ] || exit 0

cur1=$(cat "$P/constraint_0_power_limit_uw" 2>/dev/null) || exit 0
cur2=$(cat "$P/constraint_1_power_limit_uw" 2>/dev/null) || exit 0

if [ "$cur1" = "0" ] || [ "$cur1" -gt "$PL1_MAX" ] 2>/dev/null; then
    echo "$PL1_MAX" > "$P/constraint_0_power_limit_uw"
fi
if [ "$cur2" = "0" ] || [ "$cur2" -gt "$PL2_MAX" ] 2>/dev/null; then
    echo "$PL2_MAX" > "$P/constraint_1_power_limit_uw"
fi
EOF
sudo chmod 755 /usr/local/bin/rapl-power-limit.sh

sudo tee /etc/systemd/system/rapl-power-limit.service >/dev/null <<'EOF'
[Unit]
Description=Conservative CPU power limits (crash mitigation)
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rapl-power-limit.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/rapl-power-limit.timer >/dev/null <<'EOF'
[Unit]
Description=Periodically enforce CPU power ceiling (crash mitigation)

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now rapl-power-limit.service
sudo systemctl enable --now rapl-power-limit.timer
```

### Clamp behavior — tested 2026-11-04

```
simulated firmware state:  PL2=135000000  -> run script -> PL2=90000000  (clamped down)
simulated eco state:       PL2=40000000   -> run script -> PL2=40000000  (preserved)
final target state:        PL1=45000000   PL2=90000000
```

### Verify

```bash
cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw   # 45000000
cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw   # 90000000
systemctl is-active rapl-power-limit.service                       # active
```

## 5. Is the fix permanent? What can break it?

**Survives (no action needed):**
- reboots — service re-applies at every boot; timer re-checks 2 min after boot and every 10 min
- `pacman -Syu`, omarchy updates, kernel updates (both custom and stock — see §11) — unit +
  script live in `/etc` and `/usr/local`, which package upgrades never touch; the script finds the
  RAPL package domain dynamically, so even a powercap renumbering in a future kernel cannot break it
- **omarchy panel power-profile selector** — tested 2026-11-04 on **all three** profiles
  (performance / balanced / power-saver): none of them changes the RAPL limits (details in §10).
  Extra safeguard: the kernel clamps OS PL1 writes at 45 W on this platform
  (`constraint_0_max_power_uw = 45000000`), so PL1 cannot be pushed back up from userspace anyway
- anything that pushes the limits back up at runtime — the 10-min timer clamps them again

**Can break it (rare, all recoverable):**
- someone deletes the unit/script/timer → re-apply block in §4
- a BIOS update that changes RAPL handling → the unit still wins after boot (applies at
  multi-user.target, re-checked every 10 min); the firmware's aggressive values only apply during
  the first seconds of boot
- a future kernel without the powercap/RAPL interface (very unlikely)
- **inherent limit:** the 1-second-at-boot deaths happen before any userspace unit can run — no
  OS-side fix can protect the first moments of a boot. If those recur, it is purely hardware.

**Restore original (aggressive) limits** if the board is declared healthy and speed is wanted back:

```bash
echo 90000000  | sudo tee /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
echo 135000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw
sudo systemctl disable --now rapl-power-limit.service
```

## 6. Monitoring / crash traps installed (all log-rotation-capped)

| Component | What it does | Log |
|---|---|---|
| `crash-trap-sampler.service` | every 10 s: CPU package temp (coretemp), platform zone temp, load, RAM/swap, AC state, battery voltage, GPU temp/util | `/var/log/crash-trap.log` (~13 MB/day) |
| `crashmon.service` (pre-existing) | 5 Hz battery voltage / AC / load + dmesg delta | `/var/log/crashmon/mon.log` (~30 MB/day), `dmesg.log` |
| journald drop-in `/etc/systemd/journald.conf.d/99-continuous-flush.conf` | `RuntimeFlushSec=1s`, `Storage=persistent` — final-second kernel lines survive a hard cut | journal |
| `/etc/sysctl.d/99-crash-trap.conf` | `hung_task_panic=1`, `hung_task_timeout_secs=120`, `softlockup_panic=1` | — |
| `/etc/sysctl.d/99-nmi.conf` | `kernel.nmi_watchdog=2` — catch hard lockups that die without logging | — |
| **logrotate** (installed 2026-11-04, `logrotate.timer` enabled) | `/etc/logrotate.d/crash-logs`: daily, keep 7, compress, `copytruncate` | caps the three custom logs at ~300 MB total |

Log growth was the one real weak spot found in review: the two samplers write unbounded
(~45 MB/day combined). With logrotate they now self-limit to 7 days. Default system logging
(journal, dmesg) left untouched at distro defaults.

**Nothing was removed yet** — the root cause is a *hypothesis* (strong, but the BIOS EC log is
pending). Keep all traps until the machine proves stable (suggest 2–4 weeks). Then optionally:
disable `crashmon` (the 5 Hz one) and keep the 10 s sampler.

## 7. Decisions made during this investigation

- **Data backup to the second NVMe (`/mnt/storage`, Hynix nvme0):** full 112 GB backup was done,
  then **removed by user decision**. Rationale: hard power-off on a journaled btrfs/LUKS root
  almost never corrupts data — the realistic corruption risk is a write in flight at the moment of
  death (single files, and btrfs checksums detect that), not whole-filesystem loss. The fix
  itself is fully documented here, so recovery does not depend on the backup.
  Re-enable if wanted: `sudo systemctl enable --now auto-backup.timer`
  (unit + script kept: `/usr/local/bin/auto-backup.sh`, `/etc/systemd/system/auto-backup.{service,timer}`).
- **thermald: disabled** (`systemctl disable thermald`). It cannot run on this platform
  (Lenovo DYTC firmware owns thermal control) and forcing it with `--ignore-cpuid-check` risks
  fighting the firmware's thermal algorithm. It is not a safety mechanism and not a crash cause
  (1-second-at-boot deaths predate its start; idle deaths at 55C can't be turbo overheat).
  Re-enable any time: `sudo systemctl enable thermald` (it will still exit at boot — harmless).
- **TLP: intentionally left disabled** — enabling power-management tooling mid-diagnosis would
  confound the power experiments.

## 8. Still outstanding (user actions)

1. **BIOS EC event log — the decisive evidence.** Next POST: press `F1` → Event Log / Hardware
   Events; look for power-loss / overcurrent / undervoltage codes with timestamps. Screenshot it.
   This decides whether the laptop goes to Lenovo service (board/VRM repair).
2. **A/B kernel test** (see §11 for what the two kernels actually are): at the next *planned*
   reboot, pick the stock entry in the Omarchy Bootloader menu — under **Omarchy** the entry
   commented `//linux`, "Kernel version: 7.2.11-arch1-1" (`omarchy_linux.efi`) instead of the
   default `//linux-omarchy` (7.2.8-9-omarchy). NVIDIA is already DKMS-built for the stock kernel.
3. Optional: **Memtest86+** via F12 overnight to fully retire RAM.

### Interpretation matrix after the next reboot/crash

| Observation | Meaning |
|---|---|
| Machine stable on capped power | power path confirmed as trigger; consider Lenovo service anyway (board is showing age) or keep the cap long-term |
| Crashes continue even at 45/90W | damage is deeper than a software cap can paper over → hardware repair path |
| Stock kernel stable, omarchy kernel crashes | revisit custom kernel/BORE scheduler |
| Both kernels, both power settings, same deaths | board/VRM failure in progress → Lenovo service with the EC log as ticket |

## 9. Known-benign noise on this platform (do not re-investigate)

- `NVRM: ... failed to get target temp from SBIOS` / `platform power mode from SBIOS` (boot)
- `nvidia-powerd: SBIOS support not found for NVPCF ..., exiting` (every boot, clean exit)
- `i915 ... Failed to probe lspcon / LSPCON init failed on port D` (every boot)
- `ucsi_ccg ... i2c_transfer failed -110` (every boot)
- `nvidia-gpu 0000:01:00.3: i2c timeout error e0000000` (chronic, boot)
- `usb 1-9: reset full-speed USB device` every ~13.5 min (built-in Synaptics fingerprint reader)
- GPU PCIe link at Gen1 x16 (2.5 GT/s) vs Gen3 capability (chronic, pre-existing)
- GPU power limit is the driver default 90 W (`nvidia-smi -q -d POWER`) — left as-is

## 10. Power profiles (Omarchy panel) and eco mode — tested 2026-11-04

The panel's backend is **power-profiles-daemon** (`powerprofilesctl`). Available profiles:
`performance`, `balanced`, `power-saver` (eco) — all with `CpuDriver: intel_pstate` and
`PlatformDriver: platform_profile`.

**Empirical result (all three profiles tested):** switching profiles does **not** touch the RAPL
limits — 45/90 stays 45/90. On this platform PPD acts through intel_pstate and the ACPI
`platform_profile` interface (firmware performance level), not through RAPL.

Practical answer to "if I select eco, is it still 45/90?":

- **Yes — 45/90 is the ceiling, and it stays in eco mode.** Eco mode still saves power through its
  own mechanisms (CPU frequency/EPP/firmware performance level), it just doesn't lower the RAPL
  wattage ceiling.
- Manually writing a *lower* RAPL limit (e.g. `echo 25000000 > .../constraint_0_power_limit_uw`)
  also works and the ceiling-clamp leaves it alone while the system is on. Note that a full power
  cycle always resets RAPL to the firmware values (90/135) first, then the boot service clamps
  back to 45/90 — so a manual lower value is *not* persistent across reboots. For a persistent
  eco default, edit `PL1_MAX`/`PL2_MAX` in `/usr/local/bin/rapl-power-limit.sh`.

## 11. Kernels: `linux-omarchy` (custom, running) vs `linux` (stock, installed)

The machine does **not** run stock Arch Linux kernel. Both kernels are installed side by side:

| Package | Version | What it is | State |
|---|---|---|---|
| `linux-omarchy` | 7.2.8-9 (built 2026-10-17) | Omarchy project **custom** kernel: 7.2.8 LTS base + Omarchy patches, notably the **"BORE CPU Scheduler modification 7.0.0"** (custom CPU scheduler) | **running** — default boot entry |
| `linux` | 7.2.11.arch1-1 | Arch **stock** kernel | installed, bootable, NVIDIA 615.78.08 DKMS-built for it |

**How updates work (what `pacman -Syu` means here):**

- The two are **independent pacman packages** with independent upstreams: `linux` updates come
  from the official Arch repos (new 7.2.x point releases), `linux-omarchy` updates come only when
  the Omarchy project ships a new build (from the omarchy repo enabled on this system).
- **Nothing rewrites or overwrites the other.** A stock `linux` update replaces only the stock
  kernel files; the omarchy kernel keeps running until Omarchy publishes a new build *and* you
  reboot into it. Boot entries are auto-generated UKIs (`/boot/limine.conf`, produced by
  limine-entry-tool): one entry per installed kernel version.
- The crash fix itself (RAPL clamp, traps, logrotate) is **userspace** (`/etc` + `/usr/local`)
  and kernel-independent: it applies identically to whichever kernel is booted, and survives all
  of the above updates untouched.

**A/B test procedure:** reboot → Omarchy Bootloader menu → under **Omarchy** select the entry
commented `//linux` ("Kernel version: 7.2.11-arch1-1") instead of the default `//linux-omarchy`
("7.2.8-9-omarchy"). If the machine is stable on stock but crashes on omarchy, the custom
scheduler/kernel is in play; if both behave the same, the hardware power-path theory holds.

## 12. Recurrence 2026-11-05 — crash captured at idle on AC + battery-only boot loop

**User report (2026-11-05):** same silent hard stop. Afterwards the laptop would not boot:
fans spin, power on, screen **completely** off (not dimmed), repeated power-button presses had no
effect, the emergency (puncture) button was required. **Battery-only → black screen every time;
it booted only after plugging AC back in.**

### The traps captured this crash (first successful capture)

| Source | Last record before death |
|---|---|
| crashmon (5 Hz) | `2026-11-04 20:25:03.888 bat_v=11728000 bat_s=Not charging ac_on=1 load=0.04` — next sample never arrived. Death in the 200 ms after. |
| journal | last record `20:20:55` (wpa_supplicant PMKSA cache — benign Wi-Fi noise). **Zero kernel messages 20:15 → 20:25.** |
| NVMe | `unsafe_shutdowns`: nvme0 = 158, nvme1 = 199 (both increment — board-level power loss at the drive level) |

**State at death: AC adapter connected, CPU idle (load 0.04), RAPL 45/90 W cap active**
(`rapl-power-limit.service` + `.timer` verified running on that boot).

### What this changes

1. **Died at idle on AC with the cap active** → "CPU 135 W burst overloading the VRM" is no
   longer the leading theory. Board power at idle is ~20–30 W — nowhere near any
   power-delivery limit.
2. **Boots only on AC, never on battery-only, after the crash** → the failure sits in the
   power-delivery path, below the OS. It is **not a bootloader problem**: Limine never runs
   (fans + black screen = POST stage), a bootloader fault would not appear after a power-loss
   event, and would not be cured by plugging in AC.
3. **Suspects, in order of likelihood:**
   - **TPS6598x PMIC / charger path** — the IC managing AC input + charging (visible in
     upower as `tps6598x-source-psy-i2c-INT3515:00`). A fault can cut board power instantly
     (nothing the OS can log) and latch into a state that cannot sustain battery-only boot
     inrush, but can once AC is re-applied — exactly the observed recovery behavior.
   - **19 V input stage / DC jack / aged input caps** — classic end-of-life failure on
     2019–2020 hardware; marginal input paths drop out randomly and again under boot inrush.
   - **Battery inrush or connector** — battery has 18% capacity loss (76.7/94 Wh, 130 cycles);
     boot inrush on battery alone may sag the rails below threshold; a loose/corroded internal
     battery connector produces exactly this battery-only signature.
   - CPU/GPU VRM stage — less likely: VRM faults usually trigger under load, not idle.
4. **Why the Lenovo diagnostics passed but the machine still dies:** quick/standard tests run
   on AC and do not test boot inrush from battery, charger/PMIC fault latch, or rail stability.
   Passing them does not clear the power path.
5. **Why the omarchy/OS update running on 2026-11-05 cannot fix this:** the failure is below
   the OS (the machine dies in POST, where no Linux code runs). BIOS is already at the latest
   Lenovo firmware for 20ST001MGE (N30ET62W, 1.98); no newer EC firmware exists. If the machine
   stabilizes after the update, that is coincidence or load-pattern correlation, not a causal fix.

### Battery snapshot (2026-11-05, read-only)

- 56%, 11.65 V, 76.7 Wh / 94 Wh design (81.6%), 130 cycles, capacity-level "Normal"
- 50–60% charge-limit band active ("Hold battery charge at 50-60%", thinkpad_acpi stop=60)
- no charger/PMIC i2c errors in this boot's kernel log (only the known-benign nvidia/ucsi i2c noise)

### System state at capture (2026-11-05 15:40)

- RAPL 45/90 W active; all trap services active (crash-trap-sampler, crashmon,
  rapl-power-limit.service + .timer, logrotate.timer)
- GPU idle 47 °C / 10.3 W; AC online
- CPU package hit Tjmax (100 °C) during the omarchy update — DKMS compile bursts within the
  allowed 90 W PL2 burst envelope (thermal, not a crash mechanism; fans audible)
- **no system changes were made during this diagnosis — read-only, per user instruction**

### Next steps (priority order)

1. **BIOS EC event log — the decisive evidence.** At next POST, press `F1` → Event Log /
   Hardware Events. Record every code + timestamp. If the EC saw a power-loss / overcurrent /
   undervoltage event, this names the failure for Lenovo service.
2. **Full (not quick) Lenovo diagnostics, run on AC**, with the extended battery test if offered.
3. **Battery-removal test** (if comfortable opening the bottom cover): disconnect the internal
   battery, run on AC only for a few hours. Stable → battery/connector path implicated. Dies
   even on AC-only → board power path (PMIC/input stage), definitive for service.
4. **Lenovo service** with this evidence package (machine is out of warranty — decide repair
   vs replacement with the EC log in hand).
5. **Data safety:** auto-backup is still disabled (prior user decision). Given the escalated
   failure mode, re-enable it: `sudo systemctl enable --now auto-backup.timer` (units kept).
