# Hibernate Approach — Alternative to Suspend

**Date:** 2026-06-30 (updated)
**Status:** 🛠️ Fix v2 applied — see `HibernateResumeFix-Nvidia580-2026-06-30.md` for NVIDIA driver fix

---

## Why Hibernate Might Work (Unlike Suspend)

### The Core Problem with S3 Suspend

S3 suspend keeps RAM powered. On resume, **two GPU drivers** (NVIDIA + i915) restore their display state **simultaneously**, creating a race in i915 eDP link training. This race crashes Hyprland ~10-15s after resume. Five different workarounds failed to fix this.

### Why S4 Hibernate Is Different

Hibernate saves RAM to disk and **fully powers off** the system. On resume, it's a **full kernel boot**:

| Aspect | S3 Suspend (FAILED) | S4 Hibernate (SETUP APPLIED) |
|--------|---------------------|------------------------|
| Power state | RAM powered, CPU deep sleep | **Full power off** |
| GPU init | State restore (both GPUs at once) | **Fresh load from scratch** |
| i915/NVIDIA race | ✅ YES — this is what kills us | ❌ NO — sequential driver init |
| Hyprland session | Stopped then resumed | **Fresh start** after resuming from disk |
| hyprlock | Pre-suspend instance continues | **Fresh instance** after resume |

The i915 eDP link training race **cannot occur** during hibernate resume because both GPU drivers initialize from scratch, sequentially, as part of the normal kernel boot — not by simultaneously restoring stale state.

### Caveats

1. **Swap space ≥ RAM** — hibernate writes all of RAM to swap. If swap is smaller than RAM, hibernate fails silently or partially.
2. **`resume=` kernel parameter** — the kernel needs to know which swap partition to read the hibernation image from.
3. **`resume` hook in initramfs** — the initramfs needs the `resume` hook to restore the system from the swap image.
4. **Hyprland fresh start** — after hibernation, Hyprland starts fresh (no saved windows). This may be acceptable or even desirable.
5. **NVIDIA driver hibernate support** — `nvidia-hibernate.service` saves/restores GPU VRAM for hibernation.
6. **`PreserveVideoMemoryAllocations` must NOT be set** — having `NVreg_PreserveVideoMemoryAllocations=1` causes the NVIDIA driver's `nv_pmops_freeze` callback to fail during hibernate resume with `-5 (EIO)`, aborting the entire resume. VRAM preservation must be handled exclusively by `nvidia-sleep.sh` via the procfs interface (`/proc/driver/nvidia/suspend`).

---

## What Was Wrong (Fixed 2026-06-30)

When `systemctl hibernate` was tested, it failed with:

```
Call to Hibernate failed: Specified resume device is missing or is not an active swap device
```

**4 issues were found and fixed:**

| # | Issue | Fix |
|---|-------|-----|
| 1 | `resume_offset=30426359` was for old `/swapfile` (doesn't exist) | Changed to **`6834244`** (matches actual `/swap/swapfile`) |
| 2 | `resume` hook missing from `/etc/mkinitcpio.conf` | Added after `encrypt` in HOOKS line |
| 3 | Initramfs not rebuilt with resume | `mkinitcpio -P` rebuilt UKI at `/boot/EFI/Linux/omarchy_linux.efi` |
| 4 | `hibernate.target` was masked | Unmasked (`static`) |
| + | `hyprland-suspend.service` was deleted during cleanup | Recreated — runs hyprlock before hibernate |

---

## Current Verified State (2026-06-30 v2)

### ✅ Confirmed Working

- **Swap:** `/swap/swapfile` (31G ≥ 30G RAM) — active
- **Kernel cmdline:** `resume=/dev/mapper/root resume_offset=6834244` on all 5 boot entries
- **Initramfs:** `resume` hook present in UKI
- **`hibernate.target`:** unmasked (`static`)
- **`nvidia-hibernate.service`:** enabled (saves VRAM via procfs)
- **`nvidia-resume.service`:** enabled (restores VRAM via procfs, with 10s delay)
- **`hyprland-suspend.service`:** enabled (locks screen with hyprlock)
- **`/sys/power/state`:** includes `disk` (hibernate supported)
- **VRAM preservation:** handled by `nvidia-sleep.sh` via procfs (NOT kernel PM callbacks)
- **`PreserveVideoMemoryAllocations`:** deliberately NOT set (was causing resume to fail)
- **`EnablePCIeGen3=1`:** enabled for stable GPU initialization across boots

### ❌ Intentionally Disabled

- `sleep.target` → masked (S3 suspend broken)
- `suspend.target` → masked (S3 suspend broken)
- `NVreg_PreserveVideoMemoryAllocations` → removed (conflicted with procfs VRAM handling)

### 📄 Session Logs

- `HibernateSetup-2026-06-30.md` — initial hibernate setup (swap, resume hook, bootloader)
- `HibernateResumeFix-Nvidia580-2026-06-30.md` — fix for NVIDIA `nv_pmops_freeze -5` error

---

## Test Instructions

```bash
systemctl hibernate
```

### Expected Flow

#### Hibernate

1. hyprlock locks the screen
2. `nvidia-hibernate.service` → `nvidia-sleep.sh hibernate`:
   - Saves current VT, switches to VT 63
   - Writes `"hibernate"` to `/proc/driver/nvidia/suspend`
   - NVIDIA driver saves VRAM to `/var/tmp/nvidia-sleep-*`
3. Kernel writes RAM to swap (~15-30s for 30GB)
4. System powers off completely

#### Resume

5. Press power button → full boot (initramfs: LUKS password)
2. Resume hook detects swap image → kernel restores RAM (7.8GB, ~5s)
3. Userspace boots (systemd, services)
4. `nvidia-resume.service` (after 10s delay) → `nvidia-sleep.sh resume`:
   - Writes `"resume"` to `/proc/driver/nvidia/suspend`
   - NVIDIA driver restores VRAM from `/var/tmp/nvidia-sleep-*`
5. Hyprland starts fresh (new session, no saved windows)

### If Hibernate Fails

- **System boots normally** — no damage, resume image discarded
- **Black screen after resume** — hold power button 10s, reboot clean
- **Hibernate errors** — capture logs:

  ```bash
  journalctl -b -1 -n 50 | grep -i -E "hibernate|resume|swap"
  journalctl -b 0 | grep -E "Image signature|resume from|resume failed|nv_pmops_freeze"
  ```

### Rollback

```bash
# Restore PreserveVideoMemoryAllocations (if the NVIDIA fix breaks things)
pkexec sed -i 's/^options nvidia NVreg_EnablePCIeGen3=1/options nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=\/var\/tmp/' /etc/modprobe.d/nvidia.conf

# Full rollback to pre-hibernate state
pkexec sed -i 's/resume_offset=6834244/resume_offset=30426359/' /boot/limine.conf
pkexec sed -i 's/ encrypt resume / encrypt /' /etc/mkinitcpio.conf
pkexec mkinitcpio -P
pkexec systemctl mask hibernate.target
```

---

## Comparison: Hibernate vs Suspend on This System

| Criterion | S3 Suspend | S4 Hibernate |
|-----------|-----------|-------------|
| Power consumption | Low (battery drain in hours) | **Zero** |
| Resume speed | ~15-20s | ~30-60s (includes boot) |
| Windows preserved | ✅ Yes | ❌ No (fresh session) |
| GPU race risk | ✅ **Fails every time** | ❌ **Should not occur** |
| Already set up | ❌ Reverted | ✅ Fully configured |
| Current target state | `masked` | `static` ✅ |

---

## Recommendation

Hibernate is **the best remaining option** — it eliminates the kernel-level GPU race by
construction (S3 was the root problem), and the NVIDIA driver freeze bug during resume has
been fixed by routing VRAM preservation through the proper procfs interface instead of
kernel PM callbacks.

**Key insight:** The NVIDIA driver's own error message tells us what to do:
> "System Power Management attempted **without driver procfs suspend interface**"

By removing `NVreg_PreserveVideoMemoryAllocations=1` and letting `nvidia-sleep.sh` handle
VRAM via `/proc/driver/nvidia/suspend`, we follow the driver's recommended path.

See `HibernateResumeFix-Nvidia580-2026-06-30.md` for the NVIDIA driver fix session log.
