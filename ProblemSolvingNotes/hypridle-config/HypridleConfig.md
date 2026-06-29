# Hypridle Configuration — Current Setup

**Date:** 2026-06-27
**File:** `~/.config/hypr/hypridle.conf`

## Current Config

```
listener {
    timeout = 150       # 2.5 minutes
    on-timeout = omarchy-launch-screensaver
}

listener {
    timeout = 152       # 2.5 min + 2s
    on-timeout = pidof hyprlock || hyprlock
}

listener {
    timeout = 300       # 5 minutes
    on-timeout = ~/.config/hypr/scripts/idle-dim.sh
    on-resume = ~/.config/hypr/scripts/idle-restore.sh
}
```

## Behavior Summary

| Time | Action |
|------|--------|
| 2.5 min idle | Launch screensaver (omarchy-launch-screensaver) |
| 2.5 min + 2s | Lock screen (hyprlock, skip if already running) |
| 5 min idle | Dim all displays |
| On resume | Restore all displays |

## Script: `idle-dim.sh`

**Purpose:** Dim all displays when idle timeout hits.

- **Internal display (eDP/LVDS):** Sets backlight to 0 via `brightnessctl`
- **External monitors:** Sends DPMS off via `hyprctl dispatch dpms off`

Does NOT dpms-off the internal display — only dims backlight, avoiding DPMS issues on the built-in panel.

## Script: `idle-restore.sh`

**Purpose:** Restore all displays on resume from idle.

- **Internal display (eDP/LVDS):** Restores backlight to max (`24242` on `intel_backlight`)
- **External monitors:** Sends DPMS on via `hyprctl dispatch dpms on`

## Notes

- Both scripts use `jq` to parse `hyprctl monitors -j` JSON output
- Internal display is identified by matching `^(eDP|LVDS)` regex
- All other monitors are treated as external and handled via DPMS
- Uses `intel_backlight` — if switching to NVIDIA-only display, this may need adjustment
