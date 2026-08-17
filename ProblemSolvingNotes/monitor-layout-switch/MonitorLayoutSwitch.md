# External Monitor Left/Right Switching + Overlap Flash

**Date:** 2026-08-17
**Files:**

- `~/.config/hypr/monitors.lua` — live Hyprland monitor config (Lua mode)
- `~/.config/hypr/monitor-layout.lua` — layout state, rewritten by the switcher
- `~/.local/bin/omarchy-monitor-layout` — switcher script (left/right/toggle)
- `~/.config/hypr/bindings.lua` — `SUPER+M` → `omarchy-monitor-layout toggle`

## Problem

User works from two desks: in one place the external Dell monitor (HDMI-A-1) sits
**left** of the laptop (eDP-1), in the other **right**. Needed an easy way to
reposition the monitor when changing locations — and a persistent layout.

## Symptoms

- External monitor physically on the wrong side after moving desks
- After switching, eDP-1 visibly **overlapped** the other monitor for a moment
- The legacy `~/.config/hypr/monitors.conf` (with `auto-right` / `auto-left`)
  had no effect

## Investigation

- `hyprctl systeminfo` → `configProvider: lua` — Hyprland 0.56.2 runs the **Lua**
  config (`hyprland.lua` → `monitors.lua`). All `~/.config/hypr/*.conf` files are
  legacy leftovers, **not loaded**. Editing `monitors.conf` does nothing.
- `hyprctl keyword monitor ...` fails with
  `keyword can't work with non-legacy parsers. Use eval.` — the Lua parser only
  accepts `hyprctl eval 'hl.monitor({...})'`.

### Root Cause 1 — overlap flash during switch

The first version moved **both** monitors with two sequential `hyprctl eval`
calls. During the swap the first monitor lands on the second's spot before the
second moves — both screens claim the same coordinates (`0x0`) and Hyprland
renders them stacked (eDP-1 covering the Dell). Reproduced by applying the two
moves step by step with a sleep: both monitors reported `at 0x0` in between.
No `monitor_position_strategy` option exists on this version; any 2-step swap
(monitors crossing each other) passes through the overlapping state.

## Solution

**Anchor the laptop at `0x0` and only move the external monitor.** A switch then
repositions a single monitor that never crosses the laptop:

- External **left** → `position = "-1920x0"` (negative x is valid in Hyprland)
- External **right** → `position = "1920x0"` (+laptop width)

Overlap is impossible by construction. The script:

1. Applies live with `hyprctl eval "hl.monitor({ output = \"HDMI-A-1\", mode =
   \"preferred\", position = \"<pos>\", scale = 1 })"` (moves external first,
   then pins laptop at `0x0` — a no-op in steady state, self-healing if drifted).
2. Rewrites `~/.config/hypr/monitor-layout.lua` (the same two `hl.monitor` calls)
   so the layout survives `hyprctl reload` and reboots. `monitors.lua` includes it
   with a guarded `dofile`.
3. Notifies via `omarchy-notification-send`.

Binding: `o.bind("SUPER + M", "Toggle monitor side", "omarchy-monitor-layout toggle")`
(`SUPER+M` was free; `SUPER+SHIFT+M` = Music stayed untouched).

## Verification

- `omarchy-monitor-layout toggle` both directions: `eDP-1 at 0x0` never moves;
  `HDMI-A-1` goes `-1920x0` ↔ `1920x0`; layout file in sync every time.
- `hyprctl reload` → `ok`, `hyprctl configerrors` empty, layout persisted.
- Final coordinates disjoint (edge-adjacent), no overlap at any step.

## Notes

- Manual fallback: edit the two `hl.monitor` lines in `monitor-layout.lua` and
  `hyprctl reload`.
- Monitor names override via `OMARCHY_EXT_MONITOR` / `OMARCHY_INT_MONITOR`.
- Positions are computed from live monitor widths, so resolution changes are fine.
