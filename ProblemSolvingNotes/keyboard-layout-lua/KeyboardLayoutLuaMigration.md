# Keyboard Layout Lost After Hyprland Conf → Lua Migration

**Date:** 2026-08-17
**Files:**

- `~/.config/hypr/input.lua` — the **loaded** input config (Lua mode)
- `~/.config/hypr/input.conf` — legacy, **not loaded**

## Problem

After an `omarchy update`, the custom keyboard layout (US/Estonian/Russian with
Alt+Shift switching) stopped applying — typing reverted to a single layout.

## Symptoms

- `kb_layout` / `kb_options` set in `~/.config/hypr/input.conf` have no effect
- Alt+Shift layout toggle stops working
- `hyprctl getoption input:kb_layout` shows defaults

## Investigation

Omarchy moved Hyprland input config from the legacy `input.conf` to the **Lua**
config (`configProvider: lua`). The main config `hyprland.lua` requires
`hypr.input` → `~/.config/hypr/input.lua`. The old `input.conf` is no longer
sourced, so settings placed there silently do nothing.

### Root Cause

Settings were edited in the legacy file (`input.conf`) after the active config
moved to Lua (`input.lua`).

## Solution

Put the layout settings in `~/.config/hypr/input.lua`:

```lua
input {
    kb_layout = us,ee,ru
    kb_options = grp:alt_shift_toggle
}
```

## Verification

- `hyprctl reload` then check `hyprctl getoption input:kb_layout` /
  `input:kb_options` reflect the new values
- Alt+Shift cycles US → EE → RU as expected

## Notes

- Always confirm which config provider is live first:
  `hyprctl systeminfo | grep configProvider` (lua vs conf).
- The same applies to any legacy `~/.config/hypr/*.conf` — check for the matching
  `*.lua` file before editing.
