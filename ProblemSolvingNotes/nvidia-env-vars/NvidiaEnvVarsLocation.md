# NVIDIA Env Vars Must Go in hyprland.conf, Not envs.conf

**Date:** 2026-07-16 (correction)
**Files:**

- `~/.config/hypr/hyprland.conf` — the **loaded** file for NVIDIA env vars
- `~/.config/hypr/envs.conf` — user override, **NOT sourced for NVIDIA envs**

## Problem

NVIDIA-related environment variables (e.g. `NVD_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`,
`LIBVA_DRIVER_NAME`, `ELECTRON_OZONE_PLATFORM_HINT`) placed in the user's
`~/.config/hypr/envs.conf` did not take effect.

## Symptoms

- GPU/Vulkan/VA-API behavior not matching the configured env vars
- `hyprctl getenv` (or the app's env) shows the vars unset
- User explicitly reported this as a bug caused by following the wrong doc

## Investigation

Omarchy's `hyprland.conf` sources the **default** omarchy envs directly:

```
source = ~/.local/share/omarchy/default/hypr/envs.conf
```

It does **not** source the user-level `~/.config/hypr/envs.conf` override. So edits
in the user's `envs.conf` are silently ignored — the defaults win.

### Root Cause

The config only loads the packaged default envs file; the user override file is
not wired into the source chain (a real Omarchy config quirk, not user error).

## Solution

Put NVIDIA env vars directly in `~/.config/hypr/hyprland.conf`:

```conf
env = NVD_BACKEND,direct
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia
env = ELECTRON_OZONE_PLATFORM_HINT,auto
```

## Verification

- `hyprctl reload`, then confirm the vars are present
- Target apps (browser, video playback) use the NVIDIA path as configured

## Notes

- `envs.conf` may still be the right place on other Omarchy versions — verify the
  `source =` lines in `hyprland.conf` first.
- With `configProvider: lua`, prefer `hl.env(...)` in `monitors.lua` / a Lua file
  instead of the legacy conf syntax.
