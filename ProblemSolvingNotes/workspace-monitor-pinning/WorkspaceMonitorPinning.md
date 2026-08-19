# Workspace-to-Monitor Pinning (1,3,5 → eDP-1, 2,4 → HDMI-A-1)

**Date:** 2026-08-19
**Files:**

- `~/.config/hypr/monitors.lua` — live Hyprland monitor config (Lua mode); workspace pinning lives here
- `~/.config/hypr/monitors.conf` — legacy leftover, **not loaded** (see below)
- `~/.config/hypr/hyprland.lua` — main config; `configProvider: lua`

## Problem

When the external Dell monitor (HDMI-A-1) was plugged in, Hyprland handed
**workspace 1 to the external screen** and the internal laptop panel (eDP-1)
ended up with workspace 2. User is used to the internal panel being workspace 1
and wanted a fixed, predictable split:

- **eDP-1 (internal):** workspaces 1, 3, 5
- **HDMI-A-1 (external):** workspaces 2, 4

## Symptoms

- After plugging HDMI, `hyprctl workspaces` showed `ws1 → HDMI-A-1`, `ws2 → eDP-1`
- The old `monitors.conf` already contained `workspace = 1,monitor:eDP-1` but had no effect

## Investigation

- `hyprctl systeminfo` → `configProvider: lua` — Hyprland 0.56.2 runs the Lua
  config. All `~/.config/hypr/*.conf` files are legacy leftovers, **not loaded**
  (same root cause as the monitor-layout-switch note). Editing `monitors.conf`
  does nothing.
- The Lua config API has no `workspace = N, monitor:M` syntax; the equivalent is
  `hl.workspace_rule({ workspace = "N", monitor = "M" })`. Verified against the
  Hyprland v0.56.2 source (`src/config/lua/bindings/LuaBindingsConfigRules.cpp`):
  `WORKSPACE_RULE_FIELDS` includes `monitor`, `default`, `persistent`,
  `gaps_in`, `gaps_out`, `border_size`, `decorate`, `layout`, `layout_opts`, …
  and `workspace` is the **required** selector field.
- Rules with the same workspace selector **merge** (`replaceOrAdd` → `mergeLeft`
  in `WorkspaceRuleManager.cpp`), so Omarchy's per-workspace layout rules
  (`hl.workspace_rule({ workspace = "N", layout = ... })` from
  `omarchy-hyprland-workspace-layout-toggle`) coexist with monitor rules without
  clobbering.

### Root Cause / Key Behavior

Workspace rules bind a workspace to a monitor but **do not retroactively move
existing workspaces on `hyprctl reload`**. After adding the rules and reloading,
workspaces stayed where they were until moved manually. The rules only *hold*
workspaces on their bound monitor (e.g. after a manual move, reload keeps them
there) and steer future workspace creation / monitor hotplug.

## Solution

In `~/.config/hypr/monitors.lua` (loaded via `require("hypr.monitors")`):

```lua
hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "3", monitor = "eDP-1" })
hl.workspace_rule({ workspace = "4", monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "5", monitor = "eDP-1" })
```

Apply: `hyprctl reload` (auto-reloads on save anyway), then re-home the
already-existing workspaces once, because rules don't relocate on reload:

```bash
hyprctl dispatch 'hl.dsp.workspace.move({ workspace = 2, monitor = "HDMI-A-1" })'
hyprctl dispatch 'hl.dsp.workspace.move({ workspace = 5, monitor = "eDP-1" })'
```

### New dispatch syntax (Lua provider)

`hyprctl dispatch` no longer takes legacy strings like
`moveworkspacetomonitor 1 eDP-1`. It wraps the argument in
`return hl.dispatch(...)` and expects a Lua dispatcher call — the namespace is
`hl.dsp.*` (registered in `LuaBindingsDispatchers.cpp`):

- Move workspace: `hyprctl dispatch 'hl.dsp.workspace.move({ workspace = N, monitor = "M" })'`
- Focus workspace: `hyprctl dispatch 'hl.dsp.focus({ workspace = N })'`
- Move window: `hyprctl dispatch 'hl.dsp.window.move({ workspace = N })'`

(`hl.focus` / `hl.workspace.move` without `dsp.` are **not** valid — those are
config-rule functions, not dispatchers.)

## Verification

- `hyprctl reload` → `ok`, `hyprctl configerrors` empty.
- Final state (persists across reloads):

  ```
  ws 1 -> eDP-1      ws 2 -> HDMI-A-1
  ws 5 -> eDP-1
  ```

- eDP-1 focused, ws1 active; HDMI-A-1 shows ws2 with the moved windows.
- When the external is unplugged its workspaces return to the laptop
  automatically; on replug the rules pull them back to HDMI-A-1.

## Notes

- Backup before editing: `cp ~/.config/hypr/monitors.lua{,.bak.$(date +%s)}`.
- `omarchy-monitor-layout` (SUPER+M) only rewrites monitor positions in
  `monitor-layout.lua`; it does not touch workspace rules.
- If more workspaces are needed, extend the same pattern (odd → eDP-1,
  even → HDMI-A-1). Omarchy binds SUPER+1..10 by default
  (`/usr/share/omarchy/default/hypr/bindings/tiling.lua`).
