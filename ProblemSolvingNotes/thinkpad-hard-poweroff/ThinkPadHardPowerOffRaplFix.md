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

### Files installed

| File | Purpose |
|---|---|
| `/usr/local/bin/rapl-power-limit.sh` | writes the two limits |
| `/etc/systemd/system/rapl-power-limit.service` | oneshot, runs at every boot (`multi-user.target`), `RemainAfterExit=yes` |
| `/etc/rapl-power-limit.orig` | original firmware values + restore commands |

### Re-apply from scratch (fresh system / after reinstall)

```bash
sudo tee /usr/local/bin/rapl-power-limit.sh >/dev/null <<'EOF'
#!/bin/bash
# Conservative CPU power limits (crash mitigation, see ProblemSolvingNotes/thinkpad-hard-poweroff)
# Original firmware values saved in /etc/rapl-power-limit.orig
P=/sys/class/powercap/intel-rapl:0
[ -d "$P" ] || exit 1
echo 45000000 > $P/constraint_0_power_limit_uw   # PL1 45W (TDP)
echo 90000000 > $P/constraint_1_power_limit_uw   # PL2 90W (Intel MTP)
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

sudo systemctl daemon-reload
sudo systemctl enable --now rapl-power-limit.service
```

### Verify

```bash
cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw   # 45000000
cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw   # 90000000
systemctl is-active rapl-power-limit.service                       # active
```

## 5. Is the fix permanent? What can break it?

**Survives (no action needed):**
- reboots — unit re-applies at every boot
- `pacman -Syu`, omarchy updates, kernel updates — unit + script live in `/etc` and `/usr/local`,
  which package upgrades never touch; RAPL sysfs path (`/sys/class/powercap/intel-rapl:0`) is stable
  across kernel versions
- **omarchy panel power-profile selector** — tested 2026-11-04: switching
  `balanced` → `performance` via `powerprofilesctl` (the panel's backend, power-profiles-daemon)
  leaves our limits untouched. Extra safeguard: the kernel clamps OS PL1 writes at 45 W on this
  platform (`constraint_0_max_power_uw = 45000000`), so PL1 cannot be pushed back up from userspace
  anyway.

**Can break it (rare, all recoverable):**
- someone deletes the unit/script → re-apply block in §4
- a BIOS update that changes RAPL handling → the unit still wins after boot (applies at
  multi-user.target); the firmware's aggressive values only apply during the first seconds of boot
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
2. **A/B kernel test:** at the next *planned* reboot, boot stock `linux` (`7.2.11-arch1-1`,
   NVIDIA already DKMS-built for it) from Limine instead of `linux-omarchy` — separates the
   custom kernel/BORE scheduler from the hardware theory.
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
