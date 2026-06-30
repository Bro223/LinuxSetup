# Hibernate Resume Fix — NVIDIA 580 Series `nv_pmops_freeze` -5 Error

**Date:** 2026-06-30
**Status:** ✅ Fix applied — ready to test

---

## The Problem

`systemctl hibernate` appeared to work (system powered off), but on the next boot it started
**cleanly** — the hibernation session was completely lost. This looked like the resume image
wasn't being found, which was very confusing because:

- `resume=/dev/mapper/root` was correct
- `resume_offset=6834244` was correct (verified with `btrfs inspect-internal map-swapfile -r`)
- `resume` hook was in the initramfs
- `hibernate.target` was unmasked
- Swap file was 31G ≥ 30G RAM

---

## Diagnosis

### Journal from boot after hibernate

```
Jun 30 01:35:17 omarchy kernel: PM: Image signature found, resuming
Jun 30 01:35:17 omarchy kernel: PM: hibernation: resume from hibernation
...
Jun 30 01:35:17 omarchy kernel: PM: Image loading progress: 100%
Jun 30 01:35:17 omarchy kernel: PM: Image loading done
Jun 30 01:35:17 omarchy kernel: PM: hibernation: Read 7795012 kbytes in 5.02 seconds (1552.79 MB/s)
Jun 30 01:35:17 omarchy kernel: PM: Image successfully loaded
```

**The resume image was found, loaded, and decompressed successfully (7.8GB in 5s)!** ❌ No one suspected this.

### Then NVIDIA blocked the restore

```
Jun 30 01:35:17 omarchy kernel: NVRM: GPU 0000:01:00.0: PreserveVideoMemoryAllocations module
          parameter is set. System Power Management attempted without driver procfs suspend
          interface. Please refer to the 'Configuring Power Management Support' section in
          the driver README.
Jun 30 01:35:17 omarchy kernel: nvidia 0000:01:00.0: PM: pci_pm_freeze(): nv_pmops_freeze
          [nvidia] returns -5
Jun 30 01:35:17 omarchy kernel: nvidia 0000:01:00.0: PM: failed to quiesce async: error -5
Jun 30 01:35:17 omarchy kernel: PM: hibernation: Failed to load image, recovering.
Jun 30 01:35:17 omarchy kernel: PM: hibernation: resume failed (-5)
```

**Root cause found.** The NVIDIA driver was trying to handle VRAM preservation via kernel PM
callbacks (`nv_pmops_freeze`) during the image restore, but the GPU had gone through a fresh
PCIe re-enumeration during boot and the restored driver state didn't match the hardware state.

---

## Root Cause Analysis

### What Happens During Hibernate Resume

| Step | What happens | Status |
|------|-------------|--------|
| 1 | Kernel boots, PCIe re-enumerates GPU as a fresh device | ✅ Normal |
| 2 | Initramfs: LUKS password → `/dev/mapper/root` available | ✅ |
| 3 | Resume hook finds swap image → kernel loads 7.8GB | ✅ |
| 4 | Kernel restores RAM with old NVIDIA driver state | ✅ |
| 5 | Kernel calls NVIDIA's `freeze` callback to quiesce GPU | ❌ **FAILS** |
| 6 | NVIDIA driver: `nv_pmops_freeze` returns `-5 (EIO)` | ❌ |
| 7 | Kernel: `PM: hibernation: resume failed (-5)` → clean boot | ❌ |

### Why `PreserveVideoMemoryAllocations=1` Causes This

The kernel parameter `NVreg_PreserveVideoMemoryAllocations=1` tells the NVIDIA driver to
save/restore GPU VRAM during kernel PM freeze/thaw callbacks. During hibernate RESUME:

1. The GPU initialized fresh via PCIe during boot (new hardware state)
2. The hibernation image contains the old driver state (from before hibernate)
3. The kernel calls `nv_pmops_freeze` as part of the image restore process
4. NVIDIA driver sees "I should preserve VRAM" but the GPU hardware state doesn't match
   the saved driver state → **returns `-5` (EIO)**

Error `-5` in Linux kernel = `-EIO`. The NVIDIA driver can't communicate with the GPU
properly because the driver's internal state expects a suspended GPU, but the GPU was
freshly initialized.

### Why Removing It Fixes the Problem

Without `PreserveVideoMemoryAllocations=1`:

- The kernel PM freeze callback only quiesces the GPU (stops DMA, disables interrupts)
- VRAM preservation is handled **completely** by `nvidia-sleep.sh` via the procfs interface
  at `/proc/driver/nvidia/suspend`
- The procfs interface works correctly because `nvidia-sleep.sh` runs in userspace AFTER
  the GPU has fully initialized

This is EXACTLY what the NVIDIA driver's own error message recommends:
> "System Power Management attempted **without driver procfs suspend interface**"

---

## Fix Applied

### File: `/etc/modprobe.d/nvidia.conf`

**Before:**

```
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
```

**After:**

```
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_EnablePCIeGen3=1
# PreserveVideoMemoryAllocations deliberately NOT set
```

Changes:

1. **Removed** `NVreg_PreserveVideoMemoryAllocations=1` — lets `nvidia-sleep.sh` handle
   VRAM via procfs (the correct approach per NVIDIA README)
2. **Added** `NVreg_EnablePCIeGen3=1` — forces PCIe Gen3 link speed for stable GPU
   initialization across boots (precautionary)

### Services Confirmed Active

```
nvidia-hibernate.service  → enabled ✅ (runs nvidia-sleep.sh hibernate)
nvidia-resume.service     → enabled ✅ (runs nvidia-sleep.sh resume, with 10s delay)
nvidia-suspend.service    → enabled ✅ (not used, S3 is masked)
```

### Initramfs Rebuilt

```bash
pkexec mkinitcpio -P
```

UKI stored at `/boot/EFI/Linux/omarchy_linux.efi`.

### Limine Boot Entries Verified

All 5 kernel entries have `resume_offset=6834244` (correct offset for `/swap/swapfile`).

---

## Expected Hibernate Flow After Fix

### Hibernate (systemctl hibernate)

1. `hyprland-suspend.service` → hyprlock locks screen
2. `nvidia-hibernate.service` → `nvidia-sleep.sh hibernate`:
   - Saves current VT
   - Switches to VT 63
   - Writes `"hibernate"` to `/proc/driver/nvidia/suspend`
   - NVIDIA driver saves VRAM to `/var/tmp/nvidia-sleep-*`
3. Kernel saves RAM to swap (30GB → ~15s)
4. System powers off completely

### Resume (press power button)

1. Kernel boots, PCIe re-enumerates
2. Initramfs: LUKS password → `/dev/mapper/root`
3. Resume hook finds swap image at offset 6834244
4. **Kernel loads image without NVIDIA freeze failure** (PreserveVideoMemoryAllocations=0)
   ✅
5. Userspace boots (services, systemd)
6. `nvidia-resume.service` (after 10s delay):
   - Writes `"resume"` to `/proc/driver/nvidia/suspend`
   - NVIDIA driver restores VRAM from `/var/tmp/nvidia-sleep-*`
   - Restores VT
7. Hyprland starts with fully restored GPU state

---

## Verification

After reboot, verify the fix is active:

```bash
# Check PreserveVideoMemoryAllocations is NOT set
cat /proc/driver/nvidia/params | grep PreserveVideoMemoryAllocations

# Check EnablePCIeGen3 is set
cat /proc/driver/nvidia/params | grep EnablePCIeGen3

# Test hibernate
systemctl hibernate
```

On next boot:

```bash
# Check if resume was attempted
journalctl -b -1 | grep -E "Image signature|resume from|resume failed|Image successfully"
```

---

## Rollback

```bash
# Restore PreserveVideoMemoryAllocations
pkexec sed -i 's/^options nvidia NVreg_EnablePCIeGen3=1/options nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=\/var\/tmp/' /etc/modprobe.d/nvidia.conf
pkexec mkinitcpio -P
```
