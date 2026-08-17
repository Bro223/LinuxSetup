# Waybar Phantom "Update Available" Icon

**Date:** 2026-08-17
**Files:**

- `~/.local/share/omarchy` — local omarchy git checkout (tag store)
- Waybar `custom/update` module → `omarchy-update-available`

## Problem

A permanent "update available" icon in the Waybar that `omarchy update` can never
clear — even when the system is fully up to date.

## Symptoms

- Waybar shows an update indicator 24/7
- `omarchy update` runs fine but the icon stays
- No actual pending updates on the system

## Investigation

The `custom/update` module runs `omarchy-update-available`, which compares the
newest git tag on the **omarchy remote** against the newest **local tag** in
`~/.local/share/omarchy` — *not* against pacman packages.

A stale local-only tag — e.g. `v4.0.0-beta3` left over from the abandoned
`quattro` beta branch — makes the local checkout look "older" than remote forever,
because pacman-side updates never touch git tags.

### Root Cause

Stale local git tag in `~/.local/share/omarchy` newer-than-nothing from the
compositor's perspective → comparison always reports "update available".

## Solution

```bash
# 1. Delete the stale local-only tag (commit stays reachable, safe)
git -C ~/.local/share/omarchy tag -d v4.0.0-beta3

# 2. Reset the waybar check (sends RTMIN+7 to re-run the module)
omarchy update available reset
```

## Verification

- Icon disappears from Waybar
- `omarchy update available` reports current state
- Remote tags untouched; git history intact

## Notes

- Don't delete remote tags, only the stale local ones (`git tag -l` to inspect).
- If the module logic changes, re-check what `omarchy-update-available` compares
  before assuming pacman state.
