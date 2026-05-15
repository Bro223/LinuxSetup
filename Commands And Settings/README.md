# Hyprland + System Setup Notes

A collection of useful configs, commands, and tweaks for a Hyprland-based Linux setup, including NVIDIA, multi-GPU, Waybar, Bluetooth, networking, and PDF tools.

## NVIDIA environment variables

Paste this into `~/.config/hypr/hyprland.conf`:

```ini
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = WLR_NO_HARDWARE_CURSORS,1
env = AQ_DRM_DEVICES,/dev/dri/nvidia-dgpu:/dev/dri/intel-igpu
env = AQ_FORCE_LINEAR_BLIT,0
```

What it does:
- Sets NVIDIA-specific environment variables for Hyprland on Wayland.
- Helps with video acceleration, GLX vendor selection, cursor issues, and multi-GPU ordering.

Optional debug block for visual artifacts while moving windows:

```ini
debug {
  damage_tracking = 0
}
```

What it does:
- Reduces or fixes window move traces in some setups.

Optional older/manual GPU selection example:

```ini
#env = AQ_DRM_DEVICES,/dev/dri/card1:/dev/dri/card2
```

What it does:
- Manually sets GPU device priority if automatic detection is not working as expected.

Useful references:
- [Hyprland NVIDIA wiki](https://wiki.hypr.land/Nvidia/)
- [Hyprland Multi-GPU wiki](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Multi-GPU/#telling-hyprland-which-gpu-to-use)

## Monitor configuration

Paste this into `~/.config/hypr/hyprland.conf`:

```ini
monitor = eDP-1, 1920x1080@60, 0x0, 1
#monitor = HDMI-A-1, 1920x1200@60, auto-right, 1
monitor = HDMI-A-1, 1920x1080@60, auto-left, 1

workspace = 1,monitor:eDP-1
workspace = 2,monitor:HDMI-A-1
```

What it does:
- Configures the laptop display and one external HDMI monitor.
- Assigns workspace 1 to the internal screen and workspace 2 to the external screen.

## Keyboard layout switching

Paste this into `~/.config/hypr/hyprland.conf`:

```ini
kb_layout = us,ee,ru
kb_options = grp:alt_shift_toggle
```

What it does:
- Enables US, Estonian, and Russian keyboard layouts.
- Switches layouts with `Alt+Shift`.

## Waybar language module

Paste this into `~/.config/waybar/config`:

```json
"hyprland/language": {
  "format": "{}",
  "format-us": "US",
  "format-ee": "EE",
  "format-ru": "RU"
}
```

What it does:
- Shows the active Hyprland keyboard layout in Waybar using short labels.

Paste this CSS into `~/.config/waybar/style.css`:

```css
#language {
  min-width: 12px;
  margin: 0 7.5px;
}
```

What it does:
- Adds spacing and minimum width for the language module in Waybar.

## UFW and network discovery

Suggested fix for multicast discovery issues:

```bash
sudo ufw allow 5353/udp
sudo ufw allow 5355/udp
```

What it does:
- Allows mDNS and LLMNR-related UDP traffic for local network discovery.

Note:
- IGMP may also need separate handling because UFW can block multicast protocol traffic.

## Hyprlock and GPU-related fixes

Force Hyprlock or related Wayland apps to use Intel GPU only by adding this to `~/.config/hypr/hyprland.conf` or launching with the variable set:

```ini
env = WLR_DRM_DEVICES,/dev/dri/card0
```

What it does:
- Forces rendering to use the Intel GPU, which can help with DRM loops or compatibility issues.

Kernel parameter for graphics resume issues:

```text
i915.enable_psr=0
```

Where to put it:
- Add it to your kernel command line in GRUB or your bootloader configuration.

What it does:
- Disables Panel Self Refresh on Intel graphics, which can help with resume issues such as `unclaimed mmio`.

Bluetooth delay note:
- A short Bluetooth startup delay can be normal.
- If it becomes persistent, preloading firmware may help.

## Enable systemd-resolved

Run this command in a terminal:

```bash
sudo systemctl enable --now systemd-resolved
```

What it does:
- Enables and starts `systemd-resolved` immediately.
- Useful for fixing or standardizing DNS resolution on the system.

## Bluetooth power on

Run this in a terminal:

```bash
bluetoothctl
```

Then inside the `bluetoothctl` prompt, run:

```text
power on
```

What it does:
- Opens the Bluetooth control shell and powers on the Bluetooth adapter.

## Compress PDF with Ghostscript

Run this in a terminal:

```bash
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook \\
   -dNOPAUSE -dQUIET -dBATCH -sOutputFile=output.pdf input.pdf
```

What it does:
- Compresses a PDF into a smaller file.
- Good for sharing, uploading, or reducing document size.

## Convert PDF to text

Run this in a terminal:

```bash
pdftotext input.pdf output.txt
```

What it does:
- Extracts text from a PDF file into a plain text file.