# Suspend Test Instructions — 🏁 CLOSED

**No clean solution exists for NVIDIA-primary reverse PRIME suspend on this hardware.**

All suspend-related changes have been reverted. Suspend targets are masked.

See `SuspendResumeProgress.md` and `SuspendFix-2026-06-29.md` for the full history
of 5 attempted fixes (all failed).

## Current State

```
sleep.target         → masked
suspend.target       → masked
hibernate.target     → masked
hybrid-sleep.target  → masked
```

The laptop will NOT suspend under any circumstance — lid close is ignored, and
systemd targets are masked. This is the intended safe state.

## If You Want to Try Again

1. Read `SuspendResumeProgress.md` for the full history of what was tried
2. Read `SuspendFix-2026-06-29.md` for session logs
3. Consider switching Intel to primary GPU first
4. Then unmask targets: `sudo systemctl unmask sleep.target suspend.target`
5. Then test: `systemctl suspend`
