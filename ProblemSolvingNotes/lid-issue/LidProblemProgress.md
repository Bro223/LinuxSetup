# Lid Problem — Debug & Fix Progress

## Problem Description

Closing and reopening the laptop lid causes system freeze, image freezing, and extreme lag.

- Running **NVIDIA-only mode** (not hybrid) due to hybrid mode lag
- Suspend was previously disabled via `systemctl mask` (but masks were removed by updates)
- Issue persists: something still triggers on lid close and crashes the system

## Root Cause Analysis (2026-06-27)

### Key Findings

1. **Suspend targets are NOT masked** — `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` all show as `static` (built-in/active), not `masked`. The original `systemctl mask` command was likely reverted during an `omarchy update`.

2. **logind.conf has no lid override** — `/etc/systemd/logind.conf` only has `HandlePowerKey=ignore`. All lid-related settings use defaults:
   - `HandleLidSwitch=suspend` (default)
   - `HandleLidSwitchExternalPower=suspend` (default)
   - `HandleLidSwitchDocked=ignore` (default)

3. **NVIDIA suspend services are enabled** — `nvidia-suspend.service`, `nvidia-resume.service`, `nvidia-hibernate.service` all enabled.

4. **Hyprland suspend service is enabled** — `hypr-suspend.service` and `hyprland-suspend.service` run before suspend to freeze Hyprland.

5. **Broken service file** — `/etc/systemd/system/hyprland-resume-eDP1.service` has a Unicode en-dash (`‑`) instead of a regular hyphen (`-`) in its `After=` dependency on `hybrid‑sleep.target`, causing systemd errors.

### Chain of Events (Lid Close → Open)

```
Lid closes
  → systemd-logind detects Lid Switch event
  → HandleLidSwitch=suspend (default) triggers suspend.target
  → suspend.target runs:
      1. hypr-suspend.service — freezes Hyprland
      2. nvidia-suspend.service — runs nvidia-sleep.sh suspend
  → System suspends
Lid opens
  → System resumes
  → nvidia-resume.service runs (with 10s sleep in override.conf)
  → NVIDIA-only mode + resume on Optimus laptop = GPU state corruption
  → System freeze / extreme lag
```

## Fix Applied (2026-06-27)

### Step 1: Ignore Lid Switch in logind

Created `/etc/systemd/logind.conf.d/lid-ignore.conf`:

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

This makes logind completely ignore the lid switch — nothing happens when lid closes or opens.

### Step 2: Mask Suspend Targets

```bash
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Safety net in case any other process tries to trigger suspend.

### Step 3: Fix Broken Service File

Fixed Unicode en-dash in `hyprland-resume-eDP1.service`:

- `hybrid‑sleep.target` → `hybrid-sleep.target`
- Ran `systemctl daemon-reload`

## To Revert If Needed

```bash
# Remove logind lid-ignore config
sudo rm /etc/systemd/logind.conf.d/lid-ignore.conf

# Unmask suspend targets
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Reload systemd configs
sudo systemctl daemon-reload

# Restart logind
sudo systemctl restart systemd-logind
```

## Status

- [x] Diagnosed root cause
- [x] Created logind drop-in to ignore lid switch
- [x] Masked suspend targets
- [x] Fixed broken en-dash in service file
- [x] Test by closing and opening lid

## 2026-06-30 Update: Suspend Fix Attempts Concluded

Suspend-to-RAM was briefly unmasked to attempt fixing NVIDIA-primary reverse PRIME
suspend/resume. **Five different approaches were tested** (SIGSTOP/SIGCONT, DPMS cycle,
VT switching) — all resulted in Hyprland crashing on resume.

**All changes reverted. Suspend targets re-masked.**

See `SuspendResumeProgress.md` and `SuspendFix-2026-06-29.md` for full details.

**Bottom line:** No clean solution for NVIDIA-primary + i915 eDP reverse PRIME suspend
on this hardware (Quadro P1000/Pascal, driver 580.159.04 final, EOL).
Using Intel as primary GPU would fix it but was not applied.
