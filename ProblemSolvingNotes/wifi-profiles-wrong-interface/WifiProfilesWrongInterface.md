# WiFi Profiles Never Activate After iwd → NetworkManager Migration

**Date:** 2026-08-17
**Files:**

- `/etc/NetworkManager/system-connections/*` (root:root 700)
- NetworkManager profiles (`nmcli connection`)

## Problem

After Omarchy (Quattro) migrated from **iwd** to **NetworkManager**, existing WiFi
connections never activated on boot. NM kept prompting for passwords and created
duplicate `"<name> 1"` profiles.

## Symptoms

- Known WiFi network not connecting automatically
- NetworkManager password prompts for already-saved networks
- Duplicate profiles appear (e.g. `Home` and `Home 1`)
- `nmcli device wifi connect` works manually but nothing auto-connects

## Investigation

Pre-existing profiles in `/etc/NetworkManager/system-connections/` were bound with:

```
interface-name=wlan0
```

but the real wireless interface on this machine is **`wlp0s20f3`** (Intel). A
profile bound to a non-existent interface name never activates; NM then treats the
network as new → prompts and creates `"X 1"` duplicates.

### Root Cause

Profile keyfiles pinned to the old iwd-era interface name (`wlan0`), which does
not exist under NM on this hardware.

## Solution

```bash
# 1. Strip the interface-name= line from all connection keyfiles
sudo sed -i '/^interface-name=/d' /etc/NetworkManager/system-connections/*

# 2. Reload NM
nmcli connection reload

# 3. Delete the duplicate "<name> 1" profiles created during the confusion
nmcli connection delete "Home 1"
```

PSKs are stored with `psk-flags=0` in the keyfiles — nothing is lost, passwords
survive.

## Verification

- WiFi auto-connects at boot on the correct interface
- No more password prompts / duplicate profiles
- `nmcli -s connection show` lists clean profiles

## Notes

- The connections dir is `root:root` mode 700: read via
  `nmcli -s connection show`, mutations need `pkexec`/`sudo`.
- `interface-name=` binding is only useful when you want to *restrict* a profile;
  drop it for generic auto-connect behavior.
