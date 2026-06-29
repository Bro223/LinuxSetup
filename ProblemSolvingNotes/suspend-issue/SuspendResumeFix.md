# Suspend/Resume Fix — NVIDIA Primary on Optimus Laptop

**Date:** 2026-06-28
**Status:** Analysis phase — no changes made yet

 

# NVIDIA suspend resume issue

## Goal
Investigate why suspend/resume fails on my laptop when NVIDIA is the main GPU, while keeping the system safe and avoiding any critical changes for now.

## Current behavior
- Suspend is currently disabled at the system level.
- When suspend/resume is attempted, the internal display backlight turns on after resume, but no image appears.
- The system otherwise works normally with NVIDIA as the main GPU.
- Intel as the main GPU feels laggy under load, so NVIDIA is preferred for daily use.

## Working theory
- The problem is likely related to NVIDIA power management, display reinitialization, or kernel/driver interaction after resume.
- The issue may be fixable, but it is also possible that suspend should remain disabled on this machine if reliability cannot be achieved.

## Safe approach
- Do not make critical changes yet.
- First identify whether the issue is caused by NVIDIA suspend services, kernel mode setting, driver version, or a Wayland/X11 interaction.
- Prefer reversible changes only.

## Possible directions to test later
- NVIDIA suspend/resume services.
- NVIDIA KMS / modeset configuration.
- Driver version changes.
- Display server differences.
- External monitor / dock interaction.

## Current decision
- Suspend remains disabled for now to avoid the broken resume state.

- Only investigate solutions that are reversible.

  

  ## Problem

  When using NVIDIA as primary GPU (card0 = nvidia-dgpu) with internal display eDP-1 physically connected to Intel GPU (card1 = intel-igpu), after suspend+resume:

  - **Backlight turns on** (panel powers up)
  - **No image** on internal display
  - System works perfectly in normal operation — only resume fails

  With Intel as primary GPU, suspend/resume works, but UI is laggy under load (dragging windows, video playback).

  

  Problem description from user perspective:  i want to fix the issue with my system. there is a folder under documents where i store md files for different issues, create new md file there and write down all the progress there so we can after reverse it if something goes wrong. at the moment in fact i do not want you to do any critical changes in system, i just want you to find the solution and tell me if the safe solution exists at all. my problem is that i want to use suspend on my system but i can not use it propersly cause after resume my internal display backlight turns on but there is no image. it is probably related to the fact that i use nvidia as my main gpu, i use it like that cause with intel as main, my interface feels laggy under load when dragging windows when many widnows are ofter and for example some video is playing in browser tab. intel is still even in this case not under full load but it seems laggy for some reason so i decided to move to nvidia as main gpu. system works perfectly but the only thing is that i am unable to use suspend, it is not a big deal and i can use laptop without it but i would like to know if this issue is fixible at all or in my case it is safer to just not use suspend like i do right now. i disabled suspend on the system level and i do not use it anymore and my laptop wont suspend in any case to avoid the resume issue.

---

## System Architecture

```
Laptop: Lenovo ThinkPad (Coffee Lake)
├── Intel UHD Graphics 630 (00:02.0) → eDP-1 (internal display)
│   - card1 = intel-igpu
│   - Backlight: intel_backlight (raw)
│
└── NVIDIA Quadro P1000 (01:00.0) → DP-1/2/3, HDMI-A-1 (external)
    - card0 = nvidia-dgpu
    - Driver: 580.159.04
    - Kernel: nvidia_drm.modeset=1 nvidia_drm.fbdev=1
```

**Current GPU role:** NVIDIA as PRIMARY

- Hyprland: `AQ_DRM_DEVICES=/dev/dri/nvidia-dgpu:/dev/dri/intel-igpu`
- NVIDIA renders → framebuffer displayed through Intel's eDP-1 (reverse PRIME)

**Kernel parameters:**

```
i915.enable_psr=0       # Panel Self Refresh off (avoids resume bugs)
i915.enable_guc=2       # GuC/HuC firmware loaded
i915.enable_dc=0        # Display power saving off
nvidia_drm.modeset=1    # NVIDIA full modesetting
nvidia_drm.fbdev=1      # NVIDIA framebuffer console
initcall_blacklist=sysfb_init   # Prevents simpledrm from loading
```

**Modprobe config (/etc/modprobe.d/nvidia.conf):**

```
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_DynamicPowerManagement=0x02
```

**⚠️ Broken modprobe line (does nothing — parameters land on wrong module):**

```
options nvidia nvidia_drm modeset=1 fbdev=1
# This tries to set 'nvidia_drm', 'modeset', 'fbdev' as nvidia.ko params → ignored
# The kernel cmdline nvidia_drm.modeset=1 nvidia_drm.fbdev=1 actually works
```

---

## Root Cause Analysis

### What happens during suspend

1. `hyprland-suspend.service` / `hypr-suspend.service` — freeze Hyprland
2. `nvidia-suspend.service` → `nvidia-sleep.sh suspend`:
   - Saves current VT number
   - Switches to VT 63
   - Writes "suspend" to `/proc/driver/nvidia/suspend`
3. System suspends to RAM

### What happens during resume

1. Kernel resumes, drivers re-initialize:
   - **NVIDIA** (card0, loaded first) — restores GPU state, framebuffer console
   - **Intel i915** (card1) — re-initializes, brings up eDP-1 connector
2. `nvidia-resume.service`:
   - Writes "resume" to `/proc/driver/nvidia/suspend`
   - Switches back to saved VT (restore VT)
   - Has 10-second delay (from override.conf)
3. Hyprland should re-establish display

### Why it fails

The internal eDP-1 display is physically connected to the Intel GPU (card1-eDP-1). After resume, the Intel GPU's eDP link needs to be re-trained. The kernel message `fbcon: i915drmfb (fb0) is primary device` confirms that **i915 still owns the framebuffer console** even with `nvidia_drm.fbdev=1`.

The failure "backlight on, no image" indicates:

1. ✅ Panel power sequencing works (backlight controller initializes)
2. ✅ Intel GPU partially initializes (backlight is on)
3. ❌ eDP main link training fails OR display pipeline not reconnected

**Likely cause:** The i915 driver's eDP link training after resume fails when another GPU (NVIDIA) holds DRM resources. The eDP connector needs a re-probe to force link re-training, but the normal resume path doesn't trigger it because the display sink is on a *different* GPU than the primary rendering GPU — creating an edge case that neither driver handles perfectly.

---

## Possible Solutions

### Solution 1: Post-resume connector re-probe (SAFEST, try first)

Create a systemd service that after resume:

1. Force-reprobes the eDP-1 connector on the Intel GPU
2. Cycles DPMS to force a modeset

```ini
# /etc/systemd/system/hyprland-resume-eDP-fix.service
[Unit]
Description=Force eDP-1 re-probe after resume
After=nvidia-resume.service
Wants=hyprland.service

[Service]
Type=oneshot
User=aleks
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/1000
# Step 1: Force Intel eDP connector to re-detect
ExecStart=/bin/sh -c 'echo detect > /sys/class/drm/card1-eDP-1/status 2>/dev/null || true'
# Step 2: DPMS cycle to force re-render
ExecStartPost=/usr/bin/sleep 0.5
ExecStartPost=/usr/bin/hyprctl dispatch dpms off eDP-1
ExecStartPost=/usr/bin/sleep 1
ExecStartPost=/usr/bin/hyprctl dispatch dpms on eDP-1

[Install]
WantedBy=sleep.target
```

**Risk:** None. Non-destructive, just alters display state after resume.

---

### Solution 2: VT switch after resume (SAFE)

Force a VT switch (tty → back) after resume to trigger a full GPU modeset on all outputs.

```bash
#!/bin/bash
# /usr/local/bin/resume-edp-fix.sh
sleep 2  # Wait for Hyprland to be ready
CURRENT_VT=$(fgconsole)
chvt 2 && sleep 0.3 && chvt "$CURRENT_VT"
```

**Risk:** Minimal. Brief screen flash during VT switch.

---

### Solution 3: Remove nvidia_drm.fbdev=1 + enable simpledrm (MEDIUM risk)

Remove from kernel cmdline:

- `initcall_blacklist=sysfb_init` → let simpledrm load as fallback fbdev
- `nvidia_drm.fbdev=1` → let i915/simpledrm handle fbdev

Add:

- `i915.fastboot=1` → skip unnecessary modesets during boot

This lets i915 fully control the eDP lifecycle including resume.

**Risk:** May affect external monitor console output. Test by removing and rebooting first without suspending.

---

### Solution 4: i915 module parameters for better resume (LOW risk, additive)

Add to kernel cmdline or modprobe:

```
i915.fastboot=1          # Faster boot, fewer mode resets
i915.enable_fbc=0        # Disable framebuffer compression (can cause eDP issues)
```

Add to `/etc/modprobe.d/i915.conf`:

```
options i915 enable_psr=0 enable_fbc=0 fastboot=1
```

**Risk:** Minimal. These are conservative settings that disable potentially problematic features.

---

### Solution 5: AGGRESSIVE — unbind/rebind i915 after resume (HIGH risk, last resort)

```bash
# This completely reinitializes the Intel GPU
echo 0000:00:02.0 > /sys/bus/pci/drivers/i915/unbind
sleep 1
echo 0000:00:02.0 > /sys/bus/pci/drivers/i915/bind
```

**Risk:** Will crash Hyprland if it has references to the Intel GPU. Only try if nothing else works.

---

## Conclusion

**Is this fixable?** Yes, there are viable approaches. The problem is not fundamental — it's an edge case in reverse PRIME resume handling that can likely be worked around.

**Recommendation:** Start with Solution 1 (post-resume connector re-probe). It's completely safe, non-destructive, and directly addresses the eDP link training issue. If that doesn't work, combine with Solution 2 (VT switch) or Solution 4 (i915 parameters).

**Rollback plan:** If a solution doesn't work, simply disable the service:

```bash
sudo systemctl disable hyprland-resume-eDP-fix.service
# And remove kernel parameter changes if any were made
```

Current suspend is *disabled* (targets masked, logind ignores lid). To test any solution safely:

```bash
# 1. Enable test service
sudo systemctl enable hyprland-resume-eDP-fix.service

# 2. Temporarily unmask suspend
sudo systemctl unmask sleep.target suspend.target

# 3. Suspend to test
sudo systemctl suspend

# 4. If resume works → problem solved
# 5. If resume fails → hard reboot, mask suspend again
sudo systemctl mask sleep.target suspend.target
```

---

## Side Note: Broken modprobe line

The file `/etc/modprobe.d/nvidia.conf` contains:

```
options nvidia nvidia_drm modeset=1 fbdev=1
```

This is incorrect — it passes `nvidia_drm`, `modeset`, `fbdev` as parameters to the `nvidia` module (which ignores them). The working parameters come from the kernel command line (`nvidia_drm.modeset=1`). The line should be:

```
options nvidia_drm modeset=1 fbdev=1
```

This is cosmetic but worth fixing for clarity.
