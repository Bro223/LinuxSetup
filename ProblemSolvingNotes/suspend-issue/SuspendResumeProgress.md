# Suspend/Resume Fix — Implementation Progress

**Date:** 2026-06-29
**Based on:** SuspendResumeFix.md analysis
**Goal:** Fix resume blank screen (backlight on, no image) when NVIDIA is primary GPU

---

## Current Verified State on Disk (2026-06-29)

| Item | Status |
|------|--------|
| `/usr/bin/suspend-hypr` | ✅ EXISTS — correct content (
  `pkill -STOP -x Hyprland` / `pkill -CONT -x Hyprland`)
|
| `/usr/local/bin/suspend-hyprland.sh` | ❌ MISSING — NOT created yet |
| NVIDIA modprobe in `/etc/modprobe.d/nvidia.conf` | ✅ Fixed correctly |
| `hyprland-resume-eDP-fix.service` | ✅ Exists and ENABLED |
| NVIDIA drop-in `10-nvidia-no-freeze-session.conf` | ✅ Found at `/usr/lib/systemd/system/systemd-suspend.service.d/` |
| `nvidia-resume.service` override (10s delay) | ✅ Found at `/etc/systemd/system/nvidia-resume.service.d/override.conf` |
| Suspend targets (sleep, suspend) | ✅ Still masked |
| Lid switch | ✅ Still ignored (logind drop-in) |
| Kernel lockdown | 🔒 `integrity confidentiality` mode active |

---

## Pre-Implementation System State

| Item | Status |
|------|--------|
| Suspend targets (sleep, suspend, hibernate, hybrid-sleep) | **masked** |
| Lid switch | **ignored** (via logind drop-in) |
| NVIDIA suspend/resume services | enabled |
| Hyprland suspend service | enabled |
| Broken `hyprland-resume-eDP1.service` | exists, enabled but broken (wrong user `alex`, wrong env vars, en-dash) |
| NVIDIA modprobe: `options nvidia nvidia_drm modeset=1 fbdev=1` | **WRONG** - parameters go to wrong module |
| Primary GPU | NVIDIA (card0) |
| Internal display eDP-1 | Connected to Intel GPU (card1) |

---

## Step 1: Fix Broken NVIDIA Modprobe Line ✅ (Completed 2026-06-28)

### What was done

Fixed the incorrect modprobe line in `/etc/modprobe.d/nvidia.conf`:

- **Before:** `options nvidia nvidia_drm modeset=1 fbdev=1` — sets `nvidia_drm`, `modeset`, `fbdev` as params on `nvidia` module (ignored)
- **After:** `options nvidia_drm modeset=1 fbdev=1`

This is cosmetic — the kernel cmdline already has `nvidia_drm.modeset=1 nvidia_drm.fbdev=1` which works. But fixing prevents confusion and future bootloader changes from silently breaking.

### Reversal

```bash
sudo sed -i 's/^options nvidia_drm modeset=1 fbdev=1/options nvidia nvidia_drm modeset=1 fbdev=1/' /etc/modprobe.d/nvidia.conf
```

---

## Step 2: Remove Broken hyprland-resume-eDP1.service ✅ (Completed 2026-06-28)

### What was done

Removed `/etc/systemd/system/hyprland-resume-eDP1.service` — was broken:

- Wrong username (`alex` instead of `aleks`)
- X11 env vars (`DISPLAY=:0`) on a Wayland system
- Unicode en-dash characters that break systemd parsing
- Wrong Hyprland command syntax

### Reversal

Recreate the old broken file with this content:

```ini
[Unit]
Description=Re-enable eDP-1 on resume
After=sleep.target suspend.target hybrid-sleep.target hibernate.target
Wants=hyprland.service

[Service]
Type=oneshot
User=alex
Environment=DISPLAY=:0
Environment=HYPRCTL=/usr/bin/hyprctl
ExecStart=/usr/bin/hyprctl keyword monitor eDP-1,dpms,off
ExecStartPost=/usr/bin/sleep 0.2
ExecStartPost=/usr/bin/hyprctl keyword monitor eDP-1,dpms,on
RemainAfterExit=yes

[Install]
WantedBy=sleep.target
```

Then: `sudo systemctl daemon-reload && sudo systemctl enable hyprland-resume-eDP1.service`

---

## Step 3: Create hyprland-resume-eDP-fix.service ✅ (Completed 2026-06-28)

### What was done

Created `/etc/systemd/system/hyprland-resume-eDP-fix.service`:

```ini
[Unit]
Description=Force eDP-1 re-probe after resume
After=nvidia-resume.service
Wants=hyprland.service

[Service]
Type=oneshot
User=aleks
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStartPre=/bin/sh -c 'echo detect > /sys/class/drm/card1-eDP-1/status 2>/dev/null || true'
ExecStart=/usr/bin/sleep 2
ExecStartPost=/usr/bin/hyprctl dispatch dpms off eDP-1
ExecStartPost=/usr/bin/sleep 1
ExecStartPost=/usr/bin/hyprctl dispatch dpms on eDP-1

[Install]
WantedBy=sleep.target
```

**Status: installed and ENABLED** (was enabled during testing in previous session)

### Reversal

```bash
sudo systemctl disable hyprland-resume-eDP-fix.service
sudo rm /etc/systemd/system/hyprland-resume-eDP-fix.service
sudo systemctl daemon-reload
```

---

## Step 4: Create VT Switch Fallback Script ✅ (Completed 2026-06-28)

### What was done

Created `/usr/local/bin/resume-edp-fix-vt.sh`:

```bash
#!/bin/bash
# Fallback: force VT switch to trigger full GPU modeset
sleep 2
CURRENT_VT=$(fgconsole)
chvt 2 && sleep 0.3 && chvt "$CURRENT_VT"
```

**Note:** This script exists but is NOT enabled as a service — it's for manual testing from TTY if suspend fails.

### Reversal

```bash
sudo rm /usr/local/bin/resume-edp-fix-vt.sh
```

---

## Step 5: First Test — Failure Diagnosis (2026-06-28 23:xx) ❌

### What happened

After implementing Steps 1-4, the user tested suspend and it **still failed completely** — but with a new behavior:

- Laptop did **NOT** suspend to RAM
- Instead, it became **extremely laggy** and **unusable**
- Eventually Hyprland crashed or the user had to hard-reboot

### Debug Findings

From journalctl analysis:

**Failed services during suspend attempt:**

1. **`hyprland-suspend.service`** → Failed with `exit-code`
   - Cause: `Executable /usr/local/bin/suspend-hyprland.sh not found` (missing script)

2. **`hypr-suspend.service`** → Failed with `exit-code`
   - Cause: `Executable /usr/bin/suspend-hypr not found` (missing script)

3. **`systemd-suspend.service`** → Failed with `exit-code`
   - Cause: `Permission denied` when reading `/sys/module/i915/refcnt`
   - The systemd-sleep binary or a hook tries to read this file and gets permission denied

4. **`hyprland-resume-eDP-fix.service`** → Failed (ran but Hyprland was already in broken state)

**Key error:** During `systemd-suspend.service` execution:

```
/bin/sh: line 1: /sys/module/i915/refcnt: Permission denied
```

Despite `/sys/module/i915/refcnt` having `444` permissions (world-readable), the actual kernel-level access was denied. This is likely a kernel restriction (possibly related to secure boot, kernel lockdown, or LSM).

**What this means:**

- The suspend chain breaks before it reaches actual S3 (suspend to RAM)
- The Hyprland freeze scripts are **missing** — they need to be created
- The `systemd-suspend.service` override with `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` was already in place (from NVIDIA setup)

### TODOs discovered

1. ✅ Create missing `suspend-hypr` script at `/usr/bin/suspend-hypr` (PARTIALLY DONE)
2. ❌ Create missing `suspend-hyprland.sh` script at `/usr/local/bin/suspend-hyprland.sh`
3. ❌ Investigate `/sys/module/i915/refcnt` permission denied
4. ❌ Test suspend after fixes

---

## Step 6: Create Missing Hyprland Suspend Scripts ✅ (Completed 2026-06-29)

### Context

Two systemd services reference missing executables:

| Service File | Missing Executable | Status |
|---|---|---|
| `hypr-suspend.service` | `/usr/bin/suspend-hypr` | ✅ Created in previous session |
| `hyprland-suspend.service` | `/usr/local/bin/suspend-hyprland.sh` | ✅ Created now |

### What was done

**`/usr/bin/suspend-hypr`** — ✅ VERIFIED on disk. Content:

```bash
#!/bin/bash
case "$1" in
    pre)
        pkill -STOP -x Hyprland 2>/dev/null || true
        ;;
    post)
        pkill -CONT -x Hyprland 2>/dev/null || true
        ;;
esac
```

**`/usr/local/bin/suspend-hyprland.sh`** — ✅ Created via pkexec:

```bash
#!/bin/bash
case "$1" in
    suspend)
        pidof hyprlock >/dev/null 2>&1 || hyprlock &
        sleep 1
        ;;
    *)
        exit 0
        ;;
esac
```

### Verified

Both scripts exist with correct ownership/permissions:

- `-rwxr-xr-x root root /usr/bin/suspend-hypr`
- `-rwxr-xr-x root root /usr/local/bin/suspend-hyprland.sh`

### Reversal

```bash
sudo rm /usr/bin/suspend-hypr
sudo rm /usr/local/bin/suspend-hyprland.sh
```

---

## Step 7: Test Suspend 🧪 READY TO TEST

### Current state before test

| Item | Status |
|------|--------|
| `/usr/bin/suspend-hypr` | ✅ Exists |
| `/usr/local/bin/suspend-hyprland.sh` | ✅ Exists |
| `hypr-suspend.service` | ✅ Enabled, script present |
| `hyprland-suspend.service` | ✅ Enabled, script present |
| `nvidia-suspend.service` | ✅ Enabled (from NVIDIA driver) |
| `nvidia-resume.service` | ✅ Enabled, override has 10s delay |
| `hyprland-resume-eDP-fix.service` | ✅ Enabled, ready for post-resume DPMS cycle |
| Suspend targets (sleep, suspend) | ❌ **masked** — need to unmask for test |
| Lid switch | ✅ ignored (logind drop-in) |

### Test procedure

```bash
# 1. Temporarily unmask suspend
sudo systemctl unmask sleep.target suspend.target

# 2. Run suspend
sudo systemctl suspend
```

After resume:

- **Display works** → SUCCESS
- **Backlight on, no image** → eDP fix service should kick in (it's enabled)
- **System freezes** → Ctrl+Alt+F3 to TTY, then:
  `sudo /usr/local/bin/resume-edp-fix-vt.sh`

### After test

```bash
# Remask suspend to return to safe state
sudo systemctl mask sleep.target suspend.target
```

### Reversal

```bash
sudo systemctl mask sleep.target suspend.target
```

### Test Notes

- Suspend targets were unmasked via pkexec on 2026-06-29
- Both `sleep.target` and `suspend.target` now show `static` (unmasked)
- `hibernate.target` and `hybrid-sleep.target` remain masked (not needed)
- User needs to run `systemctl suspend` manually
- After resume: come back with result for debug log analysis

---

## Step 8: Second Test — Image Returns But System Frozen (2026-06-29) ❌ → FIXED

### What happened

User tested suspend (`systemctl suspend`). The laptop successfully suspended to RAM. On resume:

- ✅ Display came back showing the frozen frame from before suspend
- ❌ System was **unresponsive** — same image stuck, no input processing

This is **progress** — suspend to RAM worked, display pipeline came back. But the system was stuck.

### Diagnosis

From journalctl analysis of the test boot:

**Suspend phase (all successful):**

```
Jun 29 02:06:19 Starting Freeze Hyprland before suspend...
Jun 29 02:06:19 Starting Suspend hyprland...
Jun 29 02:06:19 hypr-suspend.service: Deactivated successfully.
Jun 29 02:06:20 hyprland-suspend.service: Deactivated successfully.
Jun 29 02:06:21 nvidia-suspend.service: Deactivated successfully.
Jun 29 02:06:21 Performing sleep operation 'suspend'...
Jun 29 02:06:42 System returned from sleep operation 'suspend'.
Jun 29 02:06:43 systemd-suspend.service: Deactivated successfully.
```

**Resume phase (3 issues found):**

**Issue A — CRITICAL: Hyprland never unfrozen after resume**

- `hypr-suspend.service` called `suspend-hypr pre` (SIGSTOP) before suspend
- But there was **no ExecStop** to call `suspend-hypr post` (SIGCONT) after resume
- Result: Hyprland remained frozen, unable to process any input

**Issue B — hyprlock config not found**

```
CRIT: Config path error: Could not find config in HOME, XDG_CONFIG_HOME, XDG_CONFIG_DIRS or /etc/hypr.
```

- `hyprland-suspend.service` runs as root (no `User=` directive)
- Root's HOME is `/root`, not `/home/aleks` — hyprlock can't find `~/.config/hypr/hyprlock.conf`

**Issue C — HYPRLAND_INSTANCE_SIGNATURE not set**

```
hyprctl[107334]: HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)
```

- `hyprland-resume-eDP-fix.service` sets `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`
- But hyprctl also needs `HYPRLAND_INSTANCE_SIGNATURE` which is dynamic (changes per Hyprland session)
- So the DPMS cycle never actually ran

### Fixes Applied (2026-06-29)

#### Fix A: Add ExecStop for SIGCONT + proper ordering

**File:** `/etc/systemd/system/hypr-suspend.service`

Changes:

```diff
 [Service]
 Type=oneshot
+RemainAfterExit=yes
 ExecStart=/usr/bin/suspend-hypr pre
+ExecStop=/usr/bin/suspend-hypr post
+After=hyprland-suspend.service
```

- `RemainAfterExit=yes` keeps the service active after ExecStart completes
- `ExecStop` runs when the service is stopped (after resume, when suspend.target deactivates)
  → sends SIGCONT to thaw Hyprland
- `After=hyprland-suspend.service` ensures hyprlock initializes **before** SIGSTOP freezes Hyprland

#### Fix B: Add User=aleks + env vars to hyprland-suspend.service

**File:** `/etc/systemd/system/hyprland-suspend.service`

Changes:

```diff
 [Service]
 Type=oneshot
+User=aleks
+Environment=WAYLAND_DISPLAY=wayland-1
+Environment=XDG_RUNTIME_DIR=/run/user/1000
 ExecStart=/usr/local/bin/suspend-hyprland.sh suspend
```

- Now runs as `aleks` so hyprlock finds the correct config at `~/.config/hypr/hyprlock.conf`

#### Fix C: New wrapper script for hyprctl DPMS cycle

Created `/usr/local/bin/hyprctl-edp-cycle.sh`:

```bash
#!/bin/bash
SIGNATURE_DIR="/run/user/1000/hypr"
if [ -d "$SIGNATURE_DIR" ]; then
    SIG=$(ls "$SIGNATURE_DIR" 2>/dev/null | head -1)
    if [ -n "$SIG" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
        export WAYLAND_DISPLAY="wayland-1"
        export XDG_RUNTIME_DIR="/run/user/1000"
        /usr/bin/sleep 1
        /usr/bin/hyprctl dispatch dpms off eDP-1
        /usr/bin/sleep 0.5
        /usr/bin/hyprctl dispatch dpms on eDP-1
    fi
fi
```

Updated `hyprland-resume-eDP-fix.service` to use the new script.

### Current state after all fixes

| Item | Status |
|------|--------|
| `hypr-suspend.service` | ✅ Fixed: SIGSTOP before suspend, SIGCONT after resume, proper ordering |
| `hyprland-suspend.service` | ✅ Fixed: runs as aleks, proper env for hyprlock config |
| `hyprland-resume-eDP-fix.service` | ✅ Fixed: discovers HYPRLAND_INSTANCE_SIGNATURE dynamically |
| Suspend targets (sleep, suspend) | ✅ Unmasked (from Step 7) |

### Expected suspend chain (after fixes)

```
1. hyprland-suspend.service → hyprlock launches (config found, lock screen visible)
2. hypr-suspend.service → SIGSTOP Hyprland (After=hyprland-suspend.service)
3. nvidia-suspend.service → VT switch, NVIDIA suspend
4. systemd-suspend.service → kernel S3 suspend
5. (hibernate/resume)
6. nvidia-resume.service → VT restore (10s delay)
7. hyprland-resume-eDP-fix.service → DPMS cycle (HYPRLAND_INSTANCE_SIGNATURE correct)
8. hypr-suspend.service ExecStop → SIGCONT Hyprland (thawed, lock screen interactive)
9. User enters password → back to desktop
```

### Reversal

```bash
# Revert Fix A
sudo systemctl disable hypr-suspend.service
# Or restore original:
sudo tee /etc/systemd/system/hypr-suspend.service << 'EOF'
[Unit]
Description=Freeze Hyprland before suspend
Before=nvidia-suspend.service
Before=suspend.target

[Service]
Type=oneshot
ExecStart=/usr/bin/suspend-hypr pre

[Install]
WantedBy=suspend.target
EOF

# Revert Fix B
sudo tee /etc/systemd/system/hyprland-suspend.service << 'EOF'
[Unit]
Description=Suspend hyprland
Before=systemd-suspend.service
Before=systemd-hibernate.service
Before=nvidia-suspend.service
Before=nvidia-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/suspend-hyprland.sh suspend

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
EOF

# Revert Fix C
sudo rm /usr/local/bin/hyprctl-edp-cycle.sh
# Or restore original hyprland-resume-eDP-fix.service

sudo systemctl daemon-reload
```

---

## Step 9: Third Test — SUSPEND SUCCEEDS BUT FROZEN AFTER RESUME (2026-06-29 02:25) ❌

### What happened

User tested suspend (`systemctl suspend`) after applying Fixes A, B, C. This time **S3 suspend worked correctly** — the laptop went into deep sleep. On resume:

- ✅ hyprlock lock screen shows (config found — Fix B works)
- ❌ Lock screen is **completely frozen** — no cursor movement, no visible keyboard input
- ❌ User cannot tell if system is "completely frozen or only the image on screen"
- User had to **force-reboot** (hold power button) to recover

### Diagnosis — Journal Analysis

**Boot -1 journal** (the suspend test boot):

- 3316 total lines
- Last entry: `kernel: Freezing user space processes` at 02:26:07
- **NO resume entries in journal** — lost during forced reboot

**Verified chain from journal:**

```
02:25:51 hyprland-suspend.service  → start  → hyprlock launches ✅
02:25:52 hyprland-suspend.service  → done   ✅
02:25:52 hypr-suspend.service      → start  → SIGSTOP Hyprland ✅
02:25:52 hypr-suspend.service      → finish (RemainAfterExit keeps active)
02:25:52 nvidia-suspend.service    → start  → nvidia-sleep.sh suspend ✅
02:25:53 nvidia-suspend.service    → done   ✅
02:25:53 systemd-suspend.service   → start  → systemd-sleep suspend ✅
02:25:53 kernel: PM: suspend entry (deep)
02:26:07 kernel: Freezing user space processes
         → JOURNAL ENDS (force reboot)
```

**What we CANNOT verify (journal lost):**

- Did `nvidia-resume.service` run post-resume?
- Did `hyprland-resume-eDP-fix.service` run (DPMS cycle)?
- Did `hypr-suspend.service` ExecStop fire (SIGCONT)?

### New Root Cause Analysis

**Hypothesis A (MOST LIKELY): ExecStop SIGCONT never fires**

`hypr-suspend.service` uses `RemainAfterExit=yes` + `ExecStop=/usr/bin/suspend-hypr post`.
ExecStop should run when `suspend.target` deactivates after resume.

**The problem:** In systemd 260, the suspend flow is driven through `systemd-suspend.service` + `sleep.target`, NOT through `suspend.target`. While `suspend.target` is started (as part of dependency resolution), it may NOT properly deactivate after resume. `StopWhenUnneeded=yes` is set on `sleep.target` (not `suspend.target`), so `suspend.target` may persist.

**Evidence for this hypothesis:**

- The SIGSTOP DID run (we see it in journal) ✅
- The user sees the lock screen (GPU retains last framebuffer) ✅
- No input processing (Hyprland is in T state — stopped) ✅
- If Hyprland were running, input events would be processed even if display were broken

**Hypothesis B (ALTERNATIVE): DPMS cycle or eDP link issue**

- The eDP display might not be refreshing frames, even though Hyprland is running
- Less likely: hyprlock image is visible, just frozen — if display were completely broken, it would be black/blank

### Comprehensive systemd 260 flow analysis

**systemd-suspend.service definition:**

```
[Unit]
Requires=sleep.target
After=sleep.target

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/systemd-sleep suspend
```

**Symlink structure:**

```
systemd-suspend.service.wants/
  hyprland-suspend.service → hyprlock before suspend
  nvidia-suspend.service   → Before=systemd-suspend.service (runs pre-suspend)
  nvidia-resume.service    → After=systemd-suspend.service (runs post-resume)

suspend.target.wants/
  hypr-suspend.service     → SIGSTOP (RemainAfterExit + ExecStop for SIGCONT)

sleep.target.wants/
  hyprland-resume-eDP-fix.service  → DPMS cycle (After=nvidia-resume.service)
```

**The flow:**

1. `systemctl suspend` → starts `systemd-suspend.service`
2. `systemd-suspend.service` → Requires + After `sleep.target`
3. `sleep.target` starts → pulls in `sleep.target.wants/` (hyprland-resume-eDP-fix.service defers for After=nvidia-resume.service)
4. `systemd-suspend.service.wants/` services start:
   - hyprland-suspend.service (Before=systemd-suspend.service, hyprlock launches)
   - nvidia-suspend.service (Before=systemd-suspend.service)
   - nvidia-resume.service (After=systemd-suspend.service — deferred until AFTER resume)
5. `suspend.target` starts → pulls in `suspend.target.wants/hypr-suspend.service` (SIGSTOP)
6. systemd-suspend.service runs → S3 sleep
7. Resume → systemd-suspend.service completes
8. nvidia-resume.service fires (After=systemd-suspend.service) → VT restore + 10s
9. hyprland-resume-eDP-fix.service fires (After=nvidia-resume.service) → DPMS cycle
10. suspend.target should deactivate → hypr-suspend.service ExecStop should fire → SIGCONT

**Where hypothesis A breaks: Step 10**
`suspend.target` may not deactivate cleanly in systemd 260. Unlike `sleep.target` (which has `StopWhenUnneeded=yes`), `suspend.target` might stay active. Without deactivation, ExecStop never fires.

### New Fix Required

**Strategy:** Replace the ExecStop-based SIGCONT with a dedicated thaw service that runs explicitly after `systemd-suspend.service` completes.

**Step 9a:** Create `hyprland-resume-thaw.service`

File: `/etc/systemd/system/hyprland-resume-thaw.service`

```ini
[Unit]
Description=Thaw Hyprland after resume
After=systemd-suspend.service
After=nvidia-resume.service
After=hyprland-resume-eDP-fix.service

[Service]
Type=oneshot
ExecStart=/usr/bin/suspend-hypr post

[Install]
WantedBy=systemd-suspend.service
```

**Step 9b:** Update `hypr-suspend.service` — remove ExecStop, keep only ExecStart

File: `/etc/systemd/system/hypr-suspend.service`

```ini
[Unit]
Description=Freeze Hyprland before suspend
After=hyprland-suspend.service
Before=nvidia-suspend.service
Before=suspend.target

[Service]
Type=oneshot
ExecStart=/usr/bin/suspend-hypr pre

[Install]
WantedBy=suspend.target
```

**Key difference:** SIGCONT no longer depends on `suspend.target` deactivation. It runs as a positive-action service (`ExecStart`) in the `systemd-suspend.service` dependency chain, with proper ordering after nvidia-resume and eDP-fix services.

### Expected chain after this fix

```
Suspend:
  1. hyprland-suspend.service → hyprlock
  2. hypr-suspend.service     → SIGSTOP Hyprland
  3. nvidia-suspend.service   → NVIDIA suspend
  4. systemd-suspend.service  → S3 sleep

Resume:
  5. systemd-suspend.service  → completes (sleep returns)
  6. nvidia-resume.service    → VT restore + 10s delay
  7. hyprland-resume-eDP-fix.service → DPMS cycle
  8. hyprland-resume-thaw.service    → SIGCONT Hyprland (NEW!)
  9. User unlocks → desktop responsive ✅
```

### Reversal for new changes

```bash
# Remove thaw service
sudo systemctl disable hyprland-resume-thaw.service 2>/dev/null
sudo rm /etc/systemd/system/hyprland-resume-thaw.service 2>/dev/null

# Restore ExecStop on hypr-suspend.service
sudo tee /etc/systemd/system/hypr-suspend.service << 'EOF'
[Unit]
Description=Freeze Hyprland before suspend
After=hyprland-suspend.service
Before=nvidia-suspend.service
Before=suspend.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/suspend-hypr pre
ExecStop=/usr/bin/suspend-hypr post

[Install]
WantedBy=suspend.target
EOF

sudo systemctl daemon-reload
```

### Current state after all changes

| Item | Status |
|------|--------|
| `/usr/bin/suspend-hypr` | ✅ EXISTS — SIGSTOP/SIGCONT script |
| `/usr/local/bin/suspend-hyprland.sh` | ✅ EXISTS — hyprlock launcher |
| `/usr/local/bin/hyprctl-edp-cycle.sh` | ✅ EXISTS — DPMS cycle with env vars |
| `/usr/local/bin/resume-edp-fix-vt.sh` | ✅ EXISTS — VT switch fallback |
| `/etc/systemd/system/hypr-suspend.service` | ✅ EXISTS — SIGSTOP before suspend (WantedBy=suspend.target) |
| `/etc/systemd/system/hyprland-suspend.service` | ✅ EXISTS — hyprlock (WantedBy=systemd-suspend.service) |
| `/etc/systemd/system/hyprland-resume-eDP-fix.service` | ✅ EXISTS — DPMS cycle (WantedBy=sleep.target) |
| `hyprland-resume-thaw.service` | ❌ NOT YET CREATED — needs to be created |
| Suspend targets (sleep, suspend) | ✅ Unmasked (from Step 7) |
| Lid switch | ✅ Ignored (logind drop-in) |

---

## Step 10: Fix Ordering Deadlock — eDP-fix BEFORE thaw (SIGCONT) (2026-06-29 18:43) ❌→✅

### What Broke

The user tested suspend after Steps 8-9 were applied. The system successfully entered S3 sleep and
returned, but:

- **Hyprland crashed** (Oopsie daisy / auto-restart via UWSM)
- The lock screen was frozen — no input processed

### Journal Timeline (Boot -1, 2026-06-29 18:43)

```
18:43:00 hyprlock launches ✅
18:43:01 SIGSTOP Hyprland ✅
18:43:02 nvidia-suspend ✅
18:43:02-17 S3 sleep
18:43:18 systemd-suspend completes
18:43:18 nvidia-resume.service starts
18:43:29 nvidia-resume.service completes (after 11s incl. 10s delay)
18:43:29 hyprland-resume-eDP-fix.service START ⛔
18:43:37 "Hyprland IPC didn't respond in time" — Hyprland still frozen!
18:43:43 "Hyprland IPC didn't respond in time" — second attempt
18:43:43 uwsm_hyprland starts new instance (original Hyprland crashed)
❌ NEVER  hyprland-resume-thaw.service (SIGCONT) NEVER RAN
```

### Root Cause: Ordering Deadlock

**deadlock chain:**

```
hyprland-resume-eDP-fix.service
  └─ Runs hyprctl dispatch dpms off/on on eDP-1
  └─ hyprctl IPC → needs Hyprland to respond
  └─ But Hyprland is SIGSTOP'd (frozen!) → hyprctl HANGS → service never completes

hyprland-resume-thaw.service (SIGCONT)
  └─ After=hyprland-resume-eDP-fix.service  ← WAITING for hung service
  └─ Would unfreeze Hyprland and fix everything → NEVER RUNS
```

**Result:** eDP-fix hangs on hyprctl → thaw waits for eDP-fix → SIGCONT never fires →
Hyprland stays frozen long enough that the IPC timeout kills the connection →
Hyprland crashes/is restarted by UWSM.

### Fix Applied (2026-06-29 ~19:00)

**Principle:** SIGCONT must happen BEFORE anything that talks to Hyprland via IPC.
DPMS cycle needs a responsive compositor.

**Change to `hyprland-resume-thaw.service`:**

```diff
 [Unit]
 Description=Thaw Hyprland after resume (SIGCONT)
 After=systemd-suspend.service
 After=nvidia-resume.service
-After=hyprland-resume-eDP-fix.service
+Before=hyprland-resume-eDP-fix.service
 
 [Service]
 Type=oneshot
 ExecStart=/usr/bin/suspend-hypr post
 
 [Install]
 WantedBy=systemd-suspend.service
```

**Change to `hyprland-resume-eDP-fix.service`:**

```diff
 [Unit]
 Description=Force eDP-1 re-probe after resume (fixes blank screen with NVIDIA primary)
 After=nvidia-resume.service
+After=hyprland-resume-thaw.service
 Wants=hyprland.service
```

### Corrected Resume Chain

```
1. systemd-suspend.service completes
2. nvidia-resume.service → VT restore + 10s delay
3. hyprland-resume-thaw.service → SIGCONT (unfreeze Hyprland)  ← NOW BEFORE eDP-fix
4. hyprland-resume-eDP-fix.service → DPMS cycle (Hyprland responsive now) ✅
5. User sees interactive lock screen → type password → desktop
```

### Verification

```bash
# Confirmed with systemctl show:
# hyprland-resume-thaw.service:
#   Before=hyprland-resume-eDP-fix.service shutdown.target
#   After=basic.target nvidia-resume.service systemd-suspend.service
#
# hyprland-resume-eDP-fix.service:
#   After=nvidia-resume.service hyprland-resume-thaw.service
#
# Dependencies:
# systemd-suspend.service
#   ├─ hypr-suspend.service              (SIGSTOP)
#   ├─ hyprland-resume-thaw.service      (SIGCONT) ← now Before=eDP-fix
#   ├─ hyprland-suspend.service          (hyprlock)
#   ├─ nvidia-resume.service
#   ├─ nvidia-suspend.service
#   └─ sleep.target
#       └─ hyprland-resume-eDP-fix.service  (DPMS cycle) ← now After=thaw
```

### All Services Verified Enabled

```
hypr-suspend.service              → enabled ✅
hyprland-suspend.service          → enabled ✅
hyprland-resume-thaw.service      → enabled ✅
hyprland-resume-eDP-fix.service   → enabled ✅
suspend.target                    → static (unmasked) ✅
sleep.target                      → static (unmasked) ✅
```

### Reversal

```bash
# Revert thaw service to wait for eDP-fix (original broken ordering)
pkexec /usr/bin/tee /etc/systemd/system/hyprland-resume-thaw.service << 'SERVICEOF'
[Unit]
Description=Thaw Hyprland after resume (SIGCONT)
After=systemd-suspend.service
After=nvidia-resume.service
After=hyprland-resume-eDP-fix.service

[Service]
Type=oneshot
ExecStart=/usr/bin/suspend-hypr post

[Install]
WantedBy=systemd-suspend.service
SERVICEOF

# Revert eDP-fix to not wait for thaw
pkexec /usr/bin/tee /etc/systemd/system/hyprland-resume-eDP-fix.service << 'SERVICEOF'
[Unit]
Description=Force eDP-1 re-probe after resume
After=nvidia-resume.service
Wants=hyprland.service

[Service]
Type=oneshot
User=aleks
ExecStartPre=/usr/bin/sleep 2
ExecStart=/usr/local/bin/hyprctl-edp-cycle.sh

[Install]
WantedBy=sleep.target
SERVICEOF

pkexec systemctl daemon-reload

---

## Step 11: Fourth Test — SIGCONT Works, DPMS Works, Hyprland Crashes After ~15s (2026-06-29 23:08) ❌

### What happened

User tested suspend (`systemctl suspend` without password — polkit works ✅). The system
successfully suspended to S3 and returned. This time, the resume chain worked COMPLETELY:
- ✅ SIGCONT fired (hyprland-resume-thaw.service ran)
- ✅ DPMS cycle ran (hyprctl returned "ok")
- ✅ Lockscreen was visible (briefly)

But then:
1. User saw lockscreen briefly
2. Hyprland "Oopsie daisy" crash screen appeared
3. Screen turned black
4. User had to force-reboot (hold power button)

### Journal Timeline (Boot -1, 2026-06-29 22:35-23:09)

```

22:35:56 Boot starts (SDDM auto-login, UWSM)
22:36:09 Hyprland ready
23:07:55 hyprland-suspend.service → kills hyprlock, starts hyprlock (old behavior)
23:07:56 hypr-suspend.service → SIGSTOP Hyprland ✅
23:07:57 nvidia-suspend.service ✅
23:07:59 PM: suspend entry (deep)
23:08:28 System returns from S3
23:08:29 PM: suspend exit
23:08:30 systemd-suspend.service completes
23:08:30 nvidia-resume.service starts
23:08:40 nvidia-resume.service completes (10s delay)
23:08:40 hyprland-resume-thaw.service → SIGCONT ✅
23:08:43 hyprctl dispatch dpms off → ok ✅
23:08:45 hyprctl dispatch dpms on → ok ✅
23:08:45 eDP-fix service completes
23:08:48 ⚠️ sd 2:0:0:0: [sda] Stopping disk ← MYSTERY
23:09:02 uwsm_hyprland starts NEW instance ← Hyprland crashed/restarted
❌ User force-reboots

```

### Key Evidences

**Evidence A: Resume chain works perfectly**
- SIGCONT fires → Hyprland unfrozen
- hyprctl IPC responds with "ok" to both dpms off AND dpms on
- Lock screen visible (hyprlock running)

**Evidence B: Hyprland crashes ~15s after SIGCONT**
- No coredump generated (not a regular SIGABRT/SIGSEGV user-space crash)
- No kernel panic, oops, or BUG message
- User session systemd (PID 1446) stops logging after 23:08:30
- UWSM starts new Hyprland instance (PID 27663) at 23:09:02

**Evidence C: SATA disk stops at 23:08:48**
- `sd 2:0:0:0: [sda] Synchronizing SCSI cache + Stopping disk`
- Happens 3s after eDP-fix completes
- No PM: suspend entry at this time (not a second S3)
- This pattern normally means shutdown/reboot, but no clean shutdown logged

### Root Cause Analysis

**Primary Hypothesis: Stale hyprlock GPU rendering context crashes Hyprland**

Scenario:
1. Before suspend: hyprlock is started → acquires session lock → creates GPU rendering buffers
2. NVIDIA `PreserveVideoMemoryAllocations=1` saves GPU VRAM to system RAM
3. System enters S3 sleep
4. Resume: NVIDIA restores GPU VRAM from saved memory
5. SIGCONT unfreezes Hyprland + hyprlock
6. DPMS cycle forces display modeset (link re-train)
7. hyprlock's pre-suspend rendering buffers were saved/restored via NVIDIA's mechanism
8. But the Intel GPU (i915, drives eDP-1) also went through S3 and its display state changed
9. hyprlock tries to redraw (cursor blink, input processing) → references a buffer that's stale
   on the Intel display pipeline → Hyprland assertion fails → SIGABRT → crash

The crash is not a standard coredump because it happens in Hyprland's rendering path
which gets into a state where the crash handler itself freezes → black screen.

**Why the SATA disk stops:** The disk stop might be a side effect of the crash — when the
user session terminal crashes, something in the I/O path causes the SATA disk to
sync and stop. Or it could be a coincidental power management event.

### Step 11b: Online Research — True Root Cause Identified

User found community documentation confirming the REAL root cause:

**The problem is a kernel-level i915 eDP link training race with NVIDIA DRM resources.**

```

NVIDIA (card0, primary GPU) ──renders──▶ framebuffer
                                           │
Intel (card1) ──owns──▶ eDP-1 (internal display)

```

This is **reverse PRIME**: NVIDIA renders, Intel displays. On resume from S3:
1. Kernel resumes, i915 driver re-initializes
2. i915 must **re-train the eDP link** (DisplayPort link training)
3. This link training **racily fails** when NVIDIA DRM resources are held
4. Result: frozen or black screen

This is a **known kernel bug** confirmed across multiple distros (Pop!_OS #3874,
Arch BBS #309693/#311771, CachyOS #18149, NVIDIA dev forum #328504).

The SIGSTOP/SIGCONT approach prevents Hyprland from crashing during NVIDIA suspend
but does NOT fix the i915 eDP link training race — that's at the kernel level.

**Driver limitation:** Quadro P1000 is Pascal (GP107). NVIDIA dropped Pascal
support in the 590 series, so 580.159.04 is the final/latest driver available.
No upgrade path available.

### Step 12: VT Switch Integration — The Kernel-Level Fix (Implemented 2026-06-30)

**Principle:** Switch to a text VT before suspend and back after resume. The VT
switch forces the kernel DRM drivers to do a complete modeset, which:
- Releases all GPU display resources before S3 (chvt 3)
- Forces clean i915 eDP link training (no race with NVIDIA) after resume (chvt 7)
- All framebuffers are re-created fresh — no stale GPU context

This is the approach that fixes the **actual kernel-level bug** rather than working
around symptoms.

**Change 1: `/usr/bin/suspend-hypr`** (the core fix)

The `pre` and `post` scripts now handle VT switching:

```bash
pre)
    # Save current VT
    fgconsole 2>/dev/null > /tmp/hyprland-suspend-vt || echo 7 > /tmp/hyprland-suspend-vt
    # Switch to text VT — releases all GPU display resources
    chvt 3
    # Freeze Hyprland
    pkill -STOP -x Hyprland 2>/dev/null || true
    ;;

post)
    # Switch to graphical VT FIRST (while Hyprland frozen)
    # Forces clean DRM modeset — i915 eDP link training, no race
    if [ -f /tmp/hyprland-suspend-vt ]; then
        CHVT=$(cat /tmp/hyprland-suspend-vt)
        chvt "$CHVT" 2>/dev/null || chvt 7
        rm -f /tmp/hyprland-suspend-vt
    fi
    /bin/sleep 0.5  # Let modeset settle
    # Thaw Hyprland on clean display pipeline
    pkill -CONT -x Hyprland 2>/dev/null || true
    ;;
```

**Change 2: `/usr/local/bin/suspend-hyprland.sh`** — restored to original

```bash
suspend)
    # Start hyprlock before suspend — VT switch handles buffer cleanup
    pidof hyprlock >/dev/null 2>&1 || hyprlock &
    sleep 1
    ;;
```

**Change 3: `/usr/local/bin/hyprctl-edp-cycle.sh`** — DPMS-only (no hyprlock)

Restored to clean DPMS cycle without hyprlock start.

**No changes to:** Hyprland config (stays NVIDIA-primary), systemd services,
nvidia-resume override, polkit rules.

### Expected Suspend/Resume Chain (VT Switch Integrated)

```
Suspend:
  1. hyprland-suspend.service → hyprlock launches (session locked)
  2. hypr-suspend.service → chvt 3 (text VT, releases GPU display)
                               → SIGSTOP Hyprland (frozen on VT3)
  3. nvidia-suspend.service → save GPU VRAM
  4. systemd-suspend.service → S3 deep sleep

Resume:
  5. Kernel returns from S3
  6. systemd-suspend.service completes
  7. nvidia-resume.service → VT restore + 10s delay (GPU VRAM restored)
  8. hyprland-resume-thaw.service → chvt 7 (graphical VT, clean modeset)
                                     → sleep 0.5s (modeset settles)
                                     → SIGCONT (Hyprland on clean display)
  9. hyprland-resume-eDP-fix.service → DPMS cycle (fallback link re-train)
  10. Interactive lock screen → password → desktop
```

### Why This Fixes the Kernel Bug

The race happens because after S3 resume, both i915 (which owns eDP-1) and NVIDIA
(which owns the framebuffer) try to re-initialize their display state simultaneously.
The i915 eDP link training requires exclusive access to the display controller,
but NVIDIA DRM resources are still being held.

By switching to VT3 before suspend:

- The kernel tells both drivers to release their display pipelines
- NVIDIA and i915 save their states independently

By switching to VT7 after resume (while Hyprland is frozen):

- The kernel tells i915 to modeset and re-train the eDP link
- This happens **before** any userspace (Hyprland/hyprlock) tries to use GPU
- No race — i915 has exclusive access during the VT switch
- Then SIGCONT unfreezes Hyprland on a fully-functional display

### Current State

| Item | Status |
|------|--------|
| `/usr/bin/suspend-hypr` | ✅ VT switch + SIGSTOP/SIGCONT integrated |
| `/usr/local/bin/suspend-hyprland.sh` | ✅ Restored: hyprlock start before suspend |
| `/usr/local/bin/hyprctl-edp-cycle.sh` | ✅ DPMS-only (fallback) |
| `/usr/local/bin/resume-edp-fix-vt.sh` | ✅ Manual fallback updated |
| hypr-suspend.service (SIGSTOP) | ✅ WantedBy=systemd-suspend |
| hyprland-suspend.service (hyprlock) | ✅ WantedBy=systemd-suspend |
| hyprland-resume-thaw.service (SIGCONT) | ✅ Before=eDP-fix |
| hyprland-resume-eDP-fix.service (DPMS) | ✅ After=thaw |
| nvidia-resume.service (10s delay) | ✅ In place |
| Suspend targets | ✅ Unmasked (static) |
| Polkit no-password suspend | ✅ Created |
| Hyprland GPU config | ✅ NVIDIA-primary (unchanged) |
| Driver version | ⚠️ 580.159.04 (latest available for Pascal) |

### Test Procedure

```bash
systemctl suspend
```

Expected:

1. Laptop shows lockscreen → switches to text VT (brief flash) → suspends
2. Press power button to wake
3. ~10s of NVIDIA VT restore (text console visible)
4. Graphical VT comes back — clean modeset → lockscreen visible and interactive
5. Type password → desktop returns

Recovery from TTY (Ctrl+Alt+F3):

```bash
# Force VT switch (if display is blank)
pkexec /usr/local/bin/resume-edp-fix-vt.sh
# Try to thaw Hyprland
pkexec systemctl start hyprland-resume-thaw.service
```

### Reversal

```bash
# Restore original suspend-hypr (no VT switch)
pkexec /usr/bin/tee /usr/bin/suspend-hypr << 'EOF'
#!/bin/bash
case "$1" in
    pre)
        pkill -STOP -x Hyprland 2>/dev/null || true
        ;;
    post)
        pkill -CONT -x Hyprland 2>/dev/null || true
        ;;
esac
EOF
```

---

## 🏁 FINAL CONCLUSION — PROJECT ABANDONED (2026-06-30)

### Test 5 Result: VT Switch — STILL CRASHES

**Date:** 2026-06-30 00:32

User tested the VT switch integration. The system successfully:

- Entered S3 deep sleep ✅
- Returned from S3 ✅
- Showed TTY mode (VT switch worked) ✅

But then **Hyprland crashed** before the user could enter credentials. Had to force-reboot.

### Journal (Boot -1, lost due to force-reboot)

```
00:32:12 hyprlock launches
00:32:13 chvt 3 + SIGSTOP Hyprland
00:32:14 nvidia-suspend
00:32:16 PM: suspend entry (deep)
00:32:32 Freezing user space processes
         → JOURNAL ENDS (force reboot)
```

No resume entries survived. The pattern matches Test 4: resume chain works, then crash.

### All 5 Tests — Summary

| Test | What | Result |
|------|------|--------|
| 1 | Basic fix (missing scripts) | Scripts missing, never ran ❌ |
| 2 | SIGSTOP/SIGCONT via ExecStop | SIGCONT never fires ❌ |
| 3 | Separate thaw after eDP-fix | Ordering deadlock ❌ |
| 4 | SIGCONT before DPMS | Resume works, crash ~15s later ❌ |
| 5 | VT switch (kernel-level fix) | VT works, still crashes ❌ |

### Cleanup: All Changes Reverted

On 2026-06-30, all suspend-related changes were removed and targets re-masked:

**Deleted:**

- `/usr/bin/suspend-hypr`
- `/usr/local/bin/suspend-hyprland.sh`
- `/usr/local/bin/hyprctl-edp-cycle.sh`
- `/usr/local/bin/resume-edp-fix-vt.sh`
- `hypr-suspend.service`
- `hyprland-suspend.service`
- `hyprland-resume-thaw.service`
- `hyprland-resume-eDP-fix.service`
- `10-suspend-no-password.rules` (polkit)

**Masked:**

- `sleep.target` → masked
- `suspend.target` → masked
- `hibernate.target` → masked
- `hybrid-sleep.target` → masked

### Honest Assessment

**No clean solution found** for reverse PRIME (NVIDIA primary, Intel eDP display)
suspend/resume on this hardware.

**Root cause:** Likely a kernel-level race or incompatibility between NVIDIA 580.159.04
(Pascal, EOL'd by NVIDIA) and i915 during S3 resume. Five different approaches tried,
all failed. The VT switch was the last credible hypothesis — it targets the actual
kernel eDP link training race — and it also failed.

**NVIDIA limitation:** Quadro P1000 (GP107/Pascal) dropped in 590 series.
580.159.04 is the final available driver. No upgrade path.

**Recommendation (Option 1):** Switch Intel to primary GPU. Use `prime-run` for NVIDIA compute.
Single-GPU Intel + i915 suspend is a solved problem on Linux.

**Alternative (Option 2 — UNTESTED):** Try **hibernate (S4)** instead of suspend (S3).
Hibernate performs a full power cycle, which avoids the simultaneous GPU state restoration
race entirely — both NVIDIA and i915 initialize fresh and sequentially during kernel boot.
`nvidia-hibernate.service` is already enabled on this system.

See `HibernateApproach.md` in this directory for setup instructions and readiness checks.

The corresponding check script is at `.check-hibernate.sh` —
run `bash .check-hibernate.sh` from the `suspend-issue/` directory.

```
