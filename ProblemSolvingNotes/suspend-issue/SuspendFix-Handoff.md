# Suspend Fix — Handoff (CLOSED)

**Date:** 2026-06-30
**Status:** 🏁 CLOSED — No clean solution found

---

## Final Verdict

**All suspend-related changes reverted.** Suspend targets masked back to original state.

Five different approaches were tried over 2026-06-28 → 2026-06-30:

| Approach | Result |
|----------|--------|
| SIGSTOP/SIGCONT via ExecStop | SIGCONT never fires (systemd 260) ❌ |
| Separate thaw service (deadlock) | Ordering deadlock ❌ |
| SIGCONT before DPMS | Resume works, Hyprland crashes ~15s later ❌ |
| VT switch integration | VT works, still crashes ❌ |

**VT switch was the last credible hypothesis** — it targets the actual kernel-level
i915 eDP link training race. It failed. Hyprland still crashes on resume.

**Likely root cause:** Kernel-level race or incompatibility between NVIDIA 580.159.04
(Pascal, EOL) and i915 on S3 resume in reverse PRIME configuration.

**NVIDIA limitation:** Quadro P1000 (GP107/Pascal) dropped in 590 series.
580.159.04 is the final available driver.

## Recommendation

Switch Intel to primary GPU for clean suspend. Use `prime-run` for NVIDIA CUDA/compute.

## Key Files

| File | Purpose |
|------|---------|
| `SuspendResumeProgress.md` | Full history + conclusion |
| `SuspendFix-2026-06-29.md` | Session log + conclusion |
| `SuspendFix-Handoff.md` | This file (closed) |
