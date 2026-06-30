# Hibernate Setup — Session 2026-06-30

**Date:** 2026-06-30
**Status:** 🛠️ Setup applied — ready to test

---

## Session Overview

After abandoning S3 suspend (5 failed attempts, see `SuspendFix-2026-06-29.md`), the goal shifted to
setting up **S4 hibernate** as an alternative. The error was:

```
$ systemctl hibernate
Call to Hibernate failed: Specified resume device is missing or is not an active swap device
```

This session diagnosed and fixed 4 root causes blocking hibernate from working.

---

## Diagnosis

### Current System State (Before Fix)

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| Swap size vs RAM | ≥ 30G | 31G swap at `/swap/swapfile` | ✅ |
| Kernel `resume=` parameter | points to root device | `resume=/dev/mapper/root` (correct) | ✅ |
| Kernel `resume_offset=` | matches swap file | `30426359` (for old `/swapfile` — **doesn't exist**) | ❌ |
| `resume` hook in initramfs | present in HOOKS | **Not present** in `/etc/mkinitcpio.conf` | ❌ |
| Initramfs rebuilt | after adding resume hook | **No** | ❌ |
| `hibernate.target` | unmasked (`static`) | **masked** (leftover from suspend cleanup) | ❌ |
| `nvidia-hibernate.service` | enabled | enabled | ✅ |
| `disk` in `/sys/power/state` | present | `freeze mem disk` | ✅ |
| Swap offset tool | readable | `btrfs inspect-internal map-swapfile -r` works | ✅ |

### Root Cause

The setup script `.setup-hibernate.sh` was written for `/swapfile` at the root of the Btrfs
volume, but the actual swap file is at `/swap/swapfile` inside the `@` subvolume. The kernel
cmdline had `resume_offset=30426359` which was set for the old (non-existent) `/swapfile`.

Additionally, the `resume` hook was never added to the initramfs, so even with a correct offset,
the kernel couldn't read the swap during boot to restore the hibernation image.

### Correct Offset

```
$ pkexec btrfs inspect-internal map-swapfile -r /swap/swapfile
6834244
```

The correct offset is **6834244** (not 30426359).

---

## Fixes Applied

### Fix 1: Update `resume_offset` in Limine Bootloader

**File:** `/boot/limine.conf`

Changed `resume_offset=30426359` → `resume_offset=6834244` in all 5 kernel entries
(main + 4 snapshots).

**Command:**

```bash
pkexec sed -i 's/resume_offset=30426359/resume_offset=6834244/' /boot/limine.conf
```

**Verification:** 5 occurrences of `resume_offset=6834244`, 0 of old offset.

---

### Fix 2: Add `resume` Hook to Initramfs

**File:** `/etc/mkinitcpio.conf`

**Before:**

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)
```

**After:**

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt resume filesystems fsck)
```

**Command:** `pkexec sed -i` to insert `resume` after `encrypt`.

There is also a drop-in config at `/etc/mkinitcpio.conf.d/omarchy_resume.conf` containing
`HOOKS+=(resume)` — this already appends the resume hook, but adding it to the main HOOKS
line ensures correct ordering (after `encrypt`, before `filesystems`).

---

### Fix 3: Rebuild Initramfs (UKI)

```bash
pkexec mkinitcpio -P
```

Build output:

```
  -> Running build hook: [base]
  -> Running build hook: [udev]
  -> Running build hook: [plymouth]
  -> Running build hook: [keyboard]
  -> Running build hook: [autodetect]
  -> Running build hook: [microcode]
  -> Running build hook: [modconf]
  -> Running build hook: [kms]
  -> Running build hook: [keymap]
  -> Running build hook: [consolefont]
  -> Running build hook: [block]
  -> Running build hook: [encrypt]
  -> Running build hook: [filesystems]
  -> Running build hook: [fsck]
  -> Running build hook: [btrfs-overlayfs]
  -> Running build hook: [resume]
UKI stored in /boot/EFI/Linux/omarchy_linux.efi
Updated: /boot/limine.conf
```

**Verification:** `lsinitcpio /boot/EFI/Linux/omarchy_linux.efi | grep hooks/resume` → present.

**Note:** The mkinitcpio rebuild also updated `/boot/limine.conf` with the new UKI hash
(which reset the main kernel entry's cmdline back to the old `resume_offset=30426359`).
Fix 1 was re-applied after the rebuild.

---

### Fix 4: Unmask `hibernate.target`

```bash
pkexec systemctl unmask hibernate.target
```

**Before:** `masked`
**After:** `static`

This was leftover from the suspend cleanup (all sleep targets were masked).

---

### Bonus Fix: Recreate `hyprland-suspend.service`

The service (which runs hyprlock before hibernate) was deleted during the suspend cleanup.
Recreated at `/etc/systemd/system/hyprland-suspend.service`:

```ini
[Unit]
Description=Suspend hyprland
Before=systemd-suspend.service
Before=systemd-hibernate.service
Before=nvidia-suspend.service
Before=nvidia-hibernate.service

[Service]
Type=oneshot
User=aleks
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/bin/sh -c 'pidof hyprlock >/dev/null 2>&1 || hyprlock & sleep 1'

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
```

Enabled: ✅

---

## Final Verified State

| Item | Status |
|------|--------|
| Swap file `/swap/swapfile` (31G ≥ 30G RAM) | ✅ Active |
| `resume=/dev/mapper/root` in kernel cmdline | ✅ Correct |
| `resume_offset=6834244` in kernel cmdline | ✅ Correct (5 entries) |
| `resume` hook in initramfs (UKI) | ✅ Present |
| `hibernate.target` | ✅ `static` (unmasked) |
| `nvidia-hibernate.service` | ✅ Enabled |
| `hyprland-suspend.service` (hyprlock) | ✅ Created and enabled |
| S3 suspend targets | ✅ Still masked (intentional) |

---

## Test Instructions

```bash
systemctl hibernate
```

### Expected Flow

1. hyprlock locks the screen ✅
2. `nvidia-hibernate.service` saves GPU VRAM
3. RAM written to swap (~10-30s)
4. System powers off completely
5. Press power button → full boot
6. initramfs detects resume image → restores RAM from swap
7. Hyprland starts fresh (new session)
8. Back to desktop

### If It Fails

- **System boots normally** → resume image was discarded (no damage)
- **Black screen after resume** → hold power button 10s, reboot clean
- **Hibernate command errors** → capture the error and check:

  ```bash
  journalctl -b -1 -n 50 | grep -i -E "hibernate|resume|swap"
  ```

### Rollback

```bash
# Restore old offset (if offset is wrong)
pkexec sed -i 's/resume_offset=6834244/resume_offset=30426359/' /boot/limine.conf

# Remove resume hook
pkexec sed -i 's/ encrypt resume / encrypt /' /etc/mkinitcpio.conf
pkexec mkinitcpio -P

# Re-mask hibernate
pkexec systemctl mask hibernate.target
```
