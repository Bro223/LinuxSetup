# TalTech FortiClient VPN on Omarchy (Arch) — Installation & Verification

- **Date:** 2026-11-11
- **Machine:** Omarchy 4.5.0 laptop (x86_64), Hyprland 0.56.2 (new Lua config parser), dual monitor (eDP 1920×1080 + external HDMI-A-1)
- **OS:** Omarchy 4.5.0 (Arch-based), Wayland session, XWayland present
- **Status:** DONE — tunnel verified end-to-end; connect/disconnect verified by user. Internal-service access not tested (no target supplied).

TalTech's official Linux instructions only ship `.deb`/`.rpm` (behind a UNI-ID
SharePoint download). On Arch, the clean route is the AUR package, which packages
the **identical official Fortinet payload**.

## 1. Package selection

- AUR `forticlient-vpn` 7.4.3.5411-1 — "FortiClient VPN only build from the official
  Fortinet package". Source: `forticlient_vpn_7.4.3.5411_amd64.deb` from
  `https://filestore.fortinet.com/forticlient/downloads/` with sha256 + b2sum in the
  PKGBUILD (makepkg verifies both). Same version TalTech redistributes on SharePoint.
- Do **not** pick a package just because the name matches: there is also an AUR
  `forticlient` (EMS/enterprise edition). This task needs the VPN-only edition; no
  EMS enrollment, no client certificate, no IPsec.
- Install: `yay -S --noconfirm forticlient-vpn` (builds as the ordinary user, ~445 MiB).
- Profile per TalTech's wiki: SSL-VPN, gateway `vpn.taltech.ee`, custom port 443,
  SSO for VPN tunnel enabled, external browser for SAML enabled, UNI-ID + MFA auth.

## 2. Backend service must be enabled (the "trial expired" trap)

Right after install, `fortivpn --version`/`status` reported:
`FortiClient SSLVPN is unavailable: FortiClient VPN trial has expired.`

That is **not** a license problem — it is the backend being down. The package installs
`forticlient.service` (runs `fctsched` + `confighandler` + `firewall`, root,
`Restart=always`) but leaves it disabled. Fix:

```bash
sudo systemctl enable --now forticlient.service
```

After that the CLI works. Leave it enabled at boot — normal operation requires it.

## 3. CLI profile store ≠ GUI profile store

- `fortivpn list` prints "No VPN profile found" **even when a GUI profile exists**.
  GUI-created profiles live in the Electron app's Local Storage under
  `~/.config/FortiClient/` (LevelDB); the CLI `list`/`view` reads a different (CLI)
  store. This build's CLI has no `addprofile` — profile creation is GUI-only.
- Practical split: manage profiles in the GUI; use the CLI for
  `fortivpn status | connect "name" | disconnect`.

## 4. GUI window on Hyprland — the "no visible window" symptom

A previously-seen symptom (other machine): launching FortiClient showed no usable
window. On this machine the GUI opens a **native Wayland** window (Electron 28.0.0 /
Chrome 120, no Ozone flags needed) — the XWayland / `--ozone-platform=x11`
workaround was investigated and is **not needed**.

What actually confuses people on dual-monitor setups: the window opens **on the
monitor where the cursor is**, which can look like a missing window if the cursor
happens to be on the external display. It is not off-screen and not on a hidden
workspace in any broken sense — just on the other screen. No window rule required;
do not add speculative `windowrulev2`/XWayland overrides.

(General Omarchy lesson, unrelated to FortiClient: the active Hyprland config is
`~/.config/hypr/hyprland.lua` under the new parser. Text `windowrule =`/`windowrulev2`
lines in `hyprland.conf` are inert, and `hyprctl keyword ...` fails with
"non-legacy parsers. Use eval." Use Omarchy's `o.window(match, effects)` helper in a
user Lua file, then validate with `hyprctl reload` + `hyprctl configerrors`.)

## 5. Cosmetic log noise

GUI log (`~/.config/FortiClient/logs/main.log`) prints:

```text
ERROR: Failed to add module "FortiClient ZTNA".
Probable cause: "/opt/forticlient/libcertd.so: cannot open shared object file"
```

`libcertd.so` is simply **not in the package** — ZTNA is an enterprise feature and
the VPN-only build ships without it. Cosmetic; no effect on the VPN. Do not try to
"fix" it.

## 6. What the tunnel does while connected (verified live)

- Interface: point-to-point `fctvpn<hash>` (e.g. `fctvpnbccd25d6`) with a /32
  university address.
- **Full tunnel**: `default via <vpn-addr> dev fctvpn...` (public egress becomes the
  university's), plus a direct bypass route for the gateway itself.
- DNS: FortiClient rewrites `/etc/resolv.conf` to the university's internal DNS
  resolvers for the session.
- **On clean disconnect it restores everything**: `/etc/resolv.conf` symlink back to
  the systemd-resolved stub, default route back to the LAN, no stale routes.
  (Verified against a pre-connect baseline.)
- Keyring/Secret Service (`gnome-keyring-daemon` providing `org.freedesktop.secrets`)
  was running but **not needed** for this flow — authentication is browser SSO
  (UNI-ID + MFA); no password is stored locally.

## 7. Rollback

```bash
sudo systemctl disable --now forticlient.service
sudo pacman -Rdd forticlient-vpn
rm -rf ~/.config/FortiClient        # removes the profile + caches
```

## 8. Status table

| Check | Result |
|---|---|
| Official payload, checksums verified, VPN-only edition | pass |
| Backend service enabled + healthy | pass |
| GUI visible/responsive, menu launch | pass (user-verified) |
| UNI-ID + MFA login flow | pass (user completed) |
| Tunnel up with assigned address, routing + DNS | pass |
| Internet through tunnel | pass |
| Authorized internal service access | not tested (no target supplied) |
| Clean disconnect restores baseline / reconnect | pass (user-verified + baseline diff) |
| Fresh reboot persistence | not tested (enablement + menu entry in place) |
