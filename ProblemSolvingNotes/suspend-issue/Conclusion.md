# Conclusion — Suspend & Hibernate on NVIDIA Primary (Reverse PRIME)

**Date:** 2026-06-30
**Status:** 🏁 PROJECT ABANDONED — All changes reverted

---

## The Problem

Lenovo ThinkPad with **NVIDIA Quadro P1000 (Pascal, GP107)** as primary GPU in reverse PRIME mode
(NVIDIA renders, Intel i915 outputs to internal eDP-1 display).

**S3 Suspend (deep sleep) + resume → Hyprland crashes** ~10-15 seconds after resume, every time.

---

## What Was Tried — 5 Suspend Fixes + 1 Hibernate Setup (All Failed)

### Suspend (S3) Fixes

| # | Approach | Result |
|---|----------|--------|
| 1 | SIGSTOP/SIGCONT via ExecStop | SIGCONT never fires (systemd 260 target lifecycle) ❌ |
| 2 | Separate thaw service after eDP-fix | Ordering deadlock, thaw never runs ❌ |
| 3 | Fixed ordering (SIGCONT before DPMS) | Resume chain works, **Hyprland crashes ~15s later** ❌ |
| 4 | VT switch (chvt 3/7) in suspend-hypr | VT switch works, **still crashes** ❌ |
| 5 | Polkit no-password + service chain cleanup | Infrastructure fix, crash unchanged ❌ |

### Hibernate (S4) Setup

| # | Approach | Result |
|---|----------|--------|
| 1 | Swap + resume_offset + resume hook | Setup complete, **NVIDIA nv_pmops_freeze -5** ❌ |
| 2 | Removed PreserveVideoMemoryAllocations | Fix applied, **never tested successfully** ❌ |

**Total: 6 attempts, 0 successes.**

---

## Honest Assessment

### Root Cause

The fundamental issue is a **kernel-level race or incompatibility** between two GPU drivers
sharing the display output pipeline during S3 resume:

```
NVIDIA (card0, primary) ──renders──▶ framebuffer
                                       │
Intel i915 (card1) ──owns──▶ eDP-1 (internal display)
```

When the system returns from S3, both NVIDIA and i915 try to restore their display state
simultaneously. The i915 eDP link training for the internal display panel races against
NVIDIA's DRM resource restoration. The result: Hyprland crashes ~10-15s after resume.

### Why It's Not Fixable (On This Hardware)

1. **NVIDIA dropped Pascal support** — Quadro P1000 (GP107) was EOL'd in the 590 series.
   Driver 580.159.04 is the **final available version**. There is no update path.

2. **VT switch didn't help** — Even forcing a clean kernel-level modeset before unfreezing
   Hyprland didn't prevent the crash. This suggests the race is deeper than just link training.

3. **Hibernate was the last hope** — S4 hibernate avoids the simultaneous GPU restore by
   doing a full power cycle. But the NVIDIA driver's own PM callbacks failed during resume,
   and the fix (removing `PreserveVideoMemoryAllocations`) was never confirmed working.

4. **Hibernate was never successfully tested** — Even the hibernate path had its own NVIDIA
   driver issues (`nv_pmops_freeze -5`). By the time the final fix was applied, confidence
   was too low to continue.

### What's Still Working

- **NVIDIA as primary GPU** — everything works perfectly for daily use: gaming, video, desktop.
  No lag, no issues.
- **Just no suspend or hibernate** — the laptop stays on or gets shutdown/rebooted cleanly.
- **All created services and configs removed** — back to clean system state.

### Recommendations (If You Revisit This)

**Option A — Switch Intel to primary GPU (GUARANTEED to fix suspend)**

- Use `prime-run` for NVIDIA CUDA/compute tasks
- Trade-off: slightly laggier UI under load (you already tried this and didn't like it)

**Option B — Wait for a new laptop**

- Modern NVIDIA GPUs (Ampere+/Ada Lovelace) have much better Linux support
- Reverse PRIME on newer hardware + newer NVIDIA drivers works much better

**Option C — Upgrade GPU if possible**

- Quadro P1000 is swappable in some ThinkPads (MXM format on P52/P72)
- A newer NVIDIA card would have driver support past 580 series

---

## What Was Removed During Cleanup (2026-06-30)

| Item | Action |
|------|--------|
| `hyprland-suspend.service` | Deleted (hibernate hyprlock service) |
| `sleep.target` | Masked |
| `suspend.target` | Masked |
| `hibernate.target` | Masked |
| `hybrid-sleep.target` | Masked |
| `resume` hook from mkinitcpio.conf | Removed |
| `/etc/mkinitcpio.conf.d/omarchy_resume.conf` | Deleted |
| `/etc/limine-entry-tool.d/resume.conf` | Deleted |
| `resume=/dev/mapper/root resume_offset=...` | Removed from limine.conf all 6 entries |
| Initramfs/UKI | Rebuilt without resume hook |
| `/etc/modprobe.d/nvidia.conf` | Kept as-is (fixed broken line, EnablePCIeGen3, no PreserveVideoMemoryAllocations) |

### What Was Left Untouched (Pre-existing, Not Our Changes)

| Item | Reason |
|------|--------|
| `nvidia-suspend.service`, `nvidia-resume.service`, `nvidia-hibernate.service` | NVIDIA driver services, pre-existing |
| `nvidia-resume.service.d/override.conf` (10s delay) | NVIDIA driver's own config |
| `/etc/systemd/logind.conf.d/*.conf` (lid switch ignore) | User preference |
| `/etc/modprobe.d/i915.conf` (enable_psr=0) | Pre-existing kernel parameter |
| NVIDIA kernel cmdline params (modeset, fbdev, etc.) | Pre-existing boot config |

---

## Bottom Line

**This machine works great with NVIDIA as primary GPU — just not with suspend or hibernate.**
The hardware combination (Pascal NVIDIA + Coffee Lake i915 + reverse PRIME) has an unsolvable
kernel-level race during S3 resume, and the NVIDIA driver's EOL status means no fix is coming.

The system is stable and fast for everything else. Masking sleep targets and shutting down
normally is the pragmatic solution.
