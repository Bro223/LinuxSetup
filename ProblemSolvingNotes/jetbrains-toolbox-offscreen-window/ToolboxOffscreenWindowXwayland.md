# JetBrains Toolbox Window Opens Off-Screen (External Monitor Connected) — Left As-Is

- **Date:** 2026-11-09
- **Machine:** Lenovo ThinkPad P52, internal eDP-1 1920x1080 + external HDMI-A-1 1920x1200 (side toggled with SUPER+M)
- **OS:** Arch + Omarchy, Hyprland 0.56.2, XWayland on display :0
- **Status:** KNOWN ISSUE — investigated, root-caused, **deliberately left as-is** (2026-11-09). All fix scaffolding removed.

## Symptom

With the external monitor plugged in, the JetBrains Toolbox window (Java/AWT app
running under XWayland, floating 430-440 x 670-700) often opens outside the
visible area — most often at `at: -440,0`, i.e. 10 px left of the laptop screen
(grabbable by its sliver at the screen edge). With only the internal monitor it
opens correctly. When the coordinate translation happens to flip, the same
launch lands at `3400,0` (top-right of the external) instead — visible.

## Root cause (measured)

1. Toolbox requests its X11 position as **X(1480, 0)** on every show — exactly
   the **top-right of X screen 0** (1480 = 1920 - window width). It has no
   saved position and no setting to change this.
2. XWayland's virtual screen enumerates **HDMI-A-1 first** (GPU connector
   order), so X space is `[external 0..1920 | laptop 1920..3840]`.
3. The Hyprland layout is the mirror: `[laptop 0..1920 | external 1920..3840]`.
4. XWayland's X->Wayland position translation assumes the first X screen sits
   at the origin (left). With the external on the right, that assumption is
   off by exactly one monitor width (1920 px):
   - right answer: 1480 + 1920 = 3400 (top-right of external, visible)
   - what it computes: 1480 - 1920 = **-440** (off the left edge of the laptop)
5. Without the external, X space = [laptop] only, identical to the Hyprland
   layout — no mismatch, window opens fine. Hence "only with external plugged in".

The offset sign varies between launches (XWayland root/primary state at map
time), which is why the placement looks random: -440,0 / 3400,0 / 385,2125.
While the app is running its X surface is also recreated (new X window id) on
activations, re-asserting the bad position — so one-shot fixes don't stick.

## Why it was left as-is

Every fix requires ongoing machinery, and the trade-off wasn't worth it:

- **Hyprland window rule** (`o.window("jetbrains-toolbox", { monitor = "eDP-1" })`,
  tested live): accepted, but made the window vanish on re-map — not a clean
  one-liner on this build.
- **Per-launch placement helper** (launcher spawns a ~20 s self-terminating
  centering script via xwininfo/xdotool delta nudges): worked reliably in
  tests, but the user doesn't want launcher shims/symlinks/.desktop rewrites —
  and Toolbox itself rewrites `~/.local/share/applications/jetbrains-toolbox.desktop`
  on its own starts, so the .desktop hook is fragile anyway.
- **Persistent watcher service**: works for all open paths incl. tray icon,
  but the user rejected an always-on background poller.
- **Source fix**: not available — X output order follows DRM connector order
  (no userspace knob), and the app's position request is hardcoded in the
  Java app. The mirror-layout translation is an XWayland/wlroots weakness.

## Workarounds (manual)

- Drag the window in from the screen edge (a sliver is visible at -440,0).
- Click the tray icon to re-show it; occasionally the landing is visible
  (top-right of the external).
- With the external on the **left** (SUPER+M), the XWayland assumption
  matches and the window opens visibly on the external.

## If it ever needs fixing again

The per-launch helper approach was proven: poll `hyprctl clients` for the
Toolbox client (note: `at:` line precedes `size:`; Hyprland **reuses client
ids** across relaunches), find the X window via `xwininfo -root -tree`
(name "Toolbox", width 200-1000; the tray icon is a 10x10 decoy), nudge with
`xdotool windowmove --relative -- <id> dx dy` (X deltas map 1:1 to Wayland
deltas; the `--` is required for negative coordinates), stop after the
position holds ~2 s. Needs `xdotool` + `xorg-xwininfo` (uninstalled 2026-11-09).
