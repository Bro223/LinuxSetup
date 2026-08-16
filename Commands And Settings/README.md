# Hyprland + System Setup Notes

A collection of useful configs, commands, and tweaks for a Hyprland-based Linux setup, including NVIDIA, multi-GPU, Waybar, Bluetooth, networking, and PDF tools.

## NVIDIA environment variables and render settings

Paste this into `~/.config/hypr/hyprland.conf`:

```ini
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = AQ_DRM_DEVICES,/dev/dri/nvidia-dgpu:/dev/dri/intel-igpu
env = AQ_FORCE_LINEAR_BLIT,0

render {
    direct_scanout = 2
    new_render_scheduling = 1
}

cursor {
    no_hardware_cursors = false
    no_break_fs_vrr = false
}

misc {
    disable_hyprland_logo = true
    enable_swallow = true
    mouse_move_focuses_monitor = true
}
```

What it does:
- Sets NVIDIA-specific environment variables for Hyprland on Wayland.
- Helps with video acceleration, GLX vendor selection, cursor issues, and multi-GPU ordering.
- Enables optimized rendering with direct scanout and new render scheduling.
- Configures cursor behavior with hardware cursor support and FreeSync control.
- Customizes miscellaneous settings for logo visibility, window swallowing, and monitor focus behavior.

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

Omarchy runs the Lua config path, so the override goes in `~/.config/hypr/input.lua`
(not `hyprland.conf` — that file is no longer loaded after the update):

```lua
hl.config({
  input = {
    -- English, Estonian, and Russian layouts; switch with Alt+Shift.
    kb_layout = "us,ee,ru",
    kb_options = "grp:alt_shift_toggle",
  },
})
```

Apply and verify:

```bash
hyprctl reload
hyprctl configerrors        # should be empty
hyprctl getoption input:kb_layout   # str: us,ee,ru
hyprctl devices             # keyboards show: l "us,ee,ru", o "grp:alt_shift_toggle"
```

What it does:
- Enables US, Estonian, and Russian keyboard layouts.
- Switches layouts with `Alt+Shift`.

Note: the old `input.conf` values (`kb_layout = us,ee,ru` / `kb_options = grp:alt_shift_toggle`)
are inert when the Lua config is active — keep the setting in `input.lua`.

## Battery charge threshold (TLP) — laptop battery health

Set charge start/stop thresholds in `/etc/tlp.conf` so the battery only charges
between 75% and 80% (prevents 100% charge stress, extends battery lifespan):

```ini
# /etc/tlp.conf
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
START_CHARGE_THRESH_BAT1=75
STOP_CHARGE_THRESH_BAT1=80
```

Apply:

```bash
sudo systemctl restart tlp
sudo tlp start
```

Verify:

```bash
sudo tlp-stat -b      # battery status + thresholds
cat /sys/class/power_supply/BAT0/charge_control_start_threshold
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

What it does:
- Keeps the battery between 75% and 80% — prevents stress at 100% and extends battery lifespan.
- Thresholds are set for both BAT0 and BAT1.

Note: `/sys/class/power_supply/BAT0/charge_control_start_threshold` may read `74`
— the battery firmware rounds the start threshold down; the TLP config itself is 75.

## Icon theme switching

Current icon theme:

```bash
gsettings get org.gnome.desktop.interface icon-theme
```

Try a new icon theme:

```bash
# Install Papirus on Arch-based systems
sudo pacman -S papirus-icon-theme

# Switch to Papirus
gsettings set org.gnome.desktop.interface icon-theme "Papirus"

# Try the dark variant
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"

# Revert to the current setup
gsettings set org.gnome.desktop.interface icon-theme "Yaru-blue"
```

List installed icon themes:

```bash
ls /usr/share/icons/
```

What it does:
- Lets you quickly switch the tray and desktop icon theme.
- Papirus is a good contrast-heavy option for network and status icons.
- You can try any installed theme by replacing the name in the `gsettings set` command.

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

## Schedule a poweroff with systemd-run

Run this command in a terminal:

```bash
sudo systemd-run --on-active=30min /usr/bin/systemctl poweroff
```

What it does:
- Schedules a poweroff 30 minutes from when the command is started.
- Useful when you want to delay shutdown without keeping a shell open.

## Disable sleep and suspend targets

Disable sleep, suspend, hibernate, and hybrid-sleep targets:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

What it does:
- Prevents the system from entering sleep, suspend, hibernate, or hybrid-sleep modes.
- Masks the systemd targets by creating symlinks to `/dev/null`.

Check the status of the masked targets:

```bash
sudo systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target
```

What it does:
- Shows that all four targets are masked and inactive.

Re-enable sleep and suspend targets:

```bash
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

What it does:
- Removes the masks, allowing the system to enter sleep, suspend, hibernate, or hybrid-sleep modes again.

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

Here’s how to document that command in `README.md`‑style Markdown:

***

### Convert `.docx` files to PDF with LibreOffice

Command:

```bash
libreoffice --headless --convert-to pdf --outdir converted *.docx
```

What it does:

- Converts all `.docx` files in the current directory into PDFs.
- Uses `--headless` so LibreOffice runs without a GUI (good for scripts).
- Places the resulting PDFs into the `converted/` directory (must exist or be created beforehand).

Where to use it:

- Run this from a terminal in the folder containing the `.docx` files.
- The output file names match the input (e.g., `document.docx` → `document.pdf` inside `converted/`).

Example setup:

```bash
mkdir converted
libreoffice --headless --convert-to pdf --outdir converted *.docx
```

### Convert image files to PDF with img2pdf

Command:

```bash
img2pdf *.png --output converted/%.pdf
```

What it does:

- Converts all `.png` files in the current directory into individual PDFs.
- The `%.pdf` pattern converts each image to a separate PDF with the same base name.
- Places the resulting PDFs into the `converted/` directory (must exist or be created beforehand).

Where to use it:

- Run this from a terminal in the folder containing the image files.
- The output file names match the input (e.g., `image.png` → `image.pdf` inside `converted/`).
- Works with various image formats: `.png`, `.jpg`, `.jpeg`, `.bmp`, etc.

Example setup:

```bash
mkdir converted
img2pdf *.png --output converted/%.pdf
```

## Sync files and folders with rsync (recursive)

Command:

```bash
rsync -av /path/to/source/ /path/to/destination/
```

What it does:
- Syncs files and folders from source to destination recursively.
- The `-a` flag (archive mode) includes recursive copying (`-r`) automatically, so all folders and files are synced.
- `-v` shows verbose output of what's being copied.
- Trailing slash after source matters: with `/` it copies contents; without `/` it copies the folder itself.

Simple example:

```bash
rsync -R ~/projects/myapp/ ~/backup/myapp/
```

What it syncs:
- **Source:** All files and folders inside `~/projects/myapp/`
- **Destination:** `~/backup/myapp/` (directory structure is preserved)

Useful flags:
- `-a` : Archive mode (includes recursion, preserves permissions, timestamps, etc.)
- `-v` : Verbose (shows what's being copied)
- `--delete` : Deletes files in destination that don't exist in source
- `-P` : Shows progress and partial file transfers
- `-R` or `--relative` : Preserves the full source path structure (rarely needed for local backups)

Example with flags:

```bash
rsync -av --progress --delete ~/projects/myapp/ ~/backup/myapp/
```

## Copy files to remote server with scp (SSH)

Command:

```bash
scp /path/to/local/file user@remote-host:/path/to/remote/destination/
```

What it does:
- Securely copies files from your local machine to a remote server via SSH.
- Uses the same authentication as SSH (keys or password).

Simple example:

```bash
scp ~/myfile.txt user@example.com:/home/user/files/
```

What it syncs:
- **Source:** `~/myfile.txt` (local file on your machine)
- **Destination:** `/home/user/files/` on `example.com` as `user`

Copy from remote to local (reverse direction):

```bash
scp user@example.com:/home/user/files/myfile.txt ~/downloads/
```

Copy entire directories:

```bash
scp -r user@example.com:/home/user/project ~/backup/
```

## Run a local PHP development server

Command:

```bash
php -S 127.0.0.1:8000
```

What it does:
- Starts a built-in PHP development server on `localhost:8000`.
- `127.0.0.1` means the server is only accessible from your local machine.
- Access it in your browser at `http://127.0.0.1:8000`

Variations:

```bash
# With a router script (for frameworks)
php -S 127.0.0.1:8000 router.php

# With custom document root (-t for document-root)
php -S 127.0.0.1:8000 -t public/ router.php

# Custom port
php -S 127.0.0.1:9000

# Accessible from any machine on your network
php -S 0.0.0.0:8000
```

## Delete files and folders

### Remove a single file

Command:

```bash
rm filename.txt
```

What it does:
- Permanently deletes the file `filename.txt`.
- Cannot be undone, so be careful.

### Remove a folder and all its contents (recursive)

Command:

```bash
rm -rf foldername/
```

What it does:
- `-r` : Recursively delete the folder and everything inside it (all subfolders and files).
- `-f` : Force delete without prompting for confirmation.
- Cannot be undone, so be very careful with this command.

Safe alternative (prompts before deletion):

```bash
rm -r foldername/
```

What it does:
- Same as above but prompts you before deleting each file (slower but safer).

## Docker Compose commands

### Start containers in the background

Command:

```bash
docker compose up -d
```

What it does:
- Starts all services defined in `docker-compose.yml`.
- `-d` flag runs containers in the background (detached mode).

### Build and start containers (rebuild images)

Command:

```bash
docker compose up -d --build
```

What it does:
- Rebuilds all images from their Dockerfiles.
- Starts containers in the background.
- Useful when you've made changes to your code or Dockerfile.

### Stop and remove containers

Command:

```bash
docker compose down
```

What it does:
- Stops all running containers defined in `docker-compose.yml`.
- Removes the containers (but keeps volumes and networks by default).

### Use with custom project name

Command:

```bash
docker compose -p myproject up -d
```

What it does:
- `-p myproject` : Sets a custom project name (useful when running multiple instances).
- Helpful for organizing containers by project name.

## Execute commands inside a running Docker container

Command:

```bash
docker exec -it container-id bash
```

What it does:
- `-i` : Keep STDIN open even if not attached (interactive).
- `-t` : Allocate a pseudo-terminal.
- `-it` together gives you an interactive shell inside the container.
- Useful for debugging, running commands, or exploring the container filesystem.

Examples:

```bash
# Start a bash shell inside the container
docker exec -it my-container bash

# Run a single command
docker exec -it my-container ls -la

# Run as a specific user
docker exec -u www-data -it my-container bash
```

## List running Docker containers

Command:

```bash
docker ps
```

What it does:
- Lists all running containers with their IDs, names, images, status, and ports.
- Shows container details needed for `docker exec` commands.

Examples:

```bash
# Show all containers (including stopped ones)
docker ps -a

# Show only container IDs
docker ps -q
```

## Copy files to/from Docker containers

Command:

```bash
docker cp /path/to/local/file container-id:/path/in/container/
```

What it does:
- Copies files from your local machine into a running container.
- Works bidirectionally (container to local and local to container).

Examples:

```bash
# Copy file FROM local TO container
docker cp ~/myfile.txt my-container:/app/

# Copy file FROM container TO local
docker cp my-container:/app/myfile.txt ~/downloads/

# Copy entire directory
docker cp ~/myproject/ my-container:/app/
```

## Git version control commands

### Stage all changes

Command:

```bash
git add .
```

What it does:
- Stages all modified and new files for commit.
- `.` means "everything in current directory and below".

### Commit staged changes

Command:

```bash
git commit -m "commit message"
```

What it does:
- Creates a commit with the staged changes.
- `-m` flag lets you add a commit message directly.

Example:

```bash
git commit -m "VSD-7508: Fixed login bug"
```

### Push commits to remote repository

Command:

```bash
git push
```

What it does:
- Uploads your local commits to the remote repository (origin/main by default).
- Pushes the current branch to its remote tracking branch.

### Stage, commit, and push in one line

Command:

```bash
git add . && git commit -m "update notes" && git push
```

What it does:
- Stages all changes, creates a commit with a generic message, and pushes it to the remote repository.
- Use this when you want a quick all-in-one publish command.

## File and directory listing

### List files with detailed info (fancy ls)

Command:

```bash
lsd
```

What it does:
- Modern replacement for `ls` command with colors and icons.
- Shows file types, permissions, and sizes in an easy-to-read format.

Examples:

```bash
# Show all files including hidden ones
lsd -a

# List with detailed information
lsd -l

# Show all with details
lsd -la
```

## Fix Wi-Fi conflicts between iwd and NetworkManager (Omarchy setup)

Use this minimal fix set to stop Omarchy's iwd from fighting NetworkManager and make NM handle Wi‑Fi cleanly. If `iwd.service` is still running while NetworkManager is also running, they conflict over Wi‑Fi control.

### Main fix (5 steps)

```bash
# 1) Stop the standalone iwd service so it doesn't grab Wi-Fi first
sudo systemctl disable --now iwd.service

# 2) Keep NetworkManager as the only manager
sudo systemctl enable --now NetworkManager.service

# 3) If you previously forced NM to use iwd, remove that backend file
sudo rm -f /etc/NetworkManager/conf.d/wifi_backend.conf

# 4) Restart NM
sudo systemctl restart NetworkManager.service

# 5) Check status
systemctl status iwd NetworkManager systemd-networkd
nmcli device status
```

### Extra safety (optional, if using Omarchy defaults)

If you want to be extra safe and ensure Omarchy's default network stack stays out of the way, also keep `systemd-networkd` disabled:

```bash
sudo systemctl disable --now systemd-networkd.service systemd-networkd-wait-online.service
```

### Troubleshooting

For eduroam/TalTech cases, `connect-failed, status: 1` lines in iwd logs mean the standalone iwd attempt is failing during enterprise authentication. Once iwd is disabled as a service, test with:

```bash
nmcli device wifi list
```

Then reconnect through NetworkManager instead of the Omarchy Wi‑Fi icon.

If `nmcli device status` still shows Wi‑Fi as unavailable after that, run:

```bash
rfkill list
nmcli radio wifi on
sudo ip link set wlan0 up
sudo systemctl restart NetworkManager
```

### Key rule

**Only one thing should manage Wi‑Fi**. In most cases, that should be NetworkManager, not Omarchy's standalone iwd service.

## Manage the local LLM model server

Control the local language model server using the convenience script at `~/.local/bin/llama-server-ctl`:

### Start the server

Command:

```bash
~/.local/bin/llama-server-ctl start
```

What it does:
- Starts the local model server in the background.
- The server is then available for API calls or local inference.

### Stop the server

Command:

```bash
~/.local/bin/llama-server-ctl stop
```

What it does:
- Stops the running model server.
- Useful when you need to free up GPU/CPU resources or perform maintenance.

### Check server status

Command:

```bash
~/.local/bin/llama-server-ctl status
```

What it does:
- Shows whether the model server is currently running or stopped.

### Restart the server

Command:

```bash
~/.local/bin/llama-server-ctl restart
```

What it does:
- Stops and immediately starts the server again.
- Useful for reloading configuration changes or troubleshooting issues.

### Clear saved sessions and checkpoints

Command:

```bash
du -sh ~/.pi/agent/sessions ~/.pi/agent/ayu/checkpoints/sessions 2>/dev/null
rm -rf ~/.pi/agent/sessions
rm -rf ~/.pi/agent/ayu/checkpoints/sessions
rm -f ~/.pi/agent/ayu/checkpoints/sessions/ephemeral/.git/objects/pack/tmp_pack_*
```

What it does:
- Shows how much space the stored Pi agent sessions and checkpoint sessions are using.
- Removes the saved session logs and the `ayu` checkpoint sessions to free up disk space.
- Removes temporary Git pack files inside the ephemeral checkpoint session tree.

### Clear saved session checkpoints

Command:

```bash
rm -rf ~/.pi/agent/ayu/checkpoints/sessions
```

What it does:
- Removes stored session checkpoint data for the `ayu` agent.
- Use this when you want to reset persisted session state.

### Always use no-session mode

If you always want no-session behavior, add a shell alias or wrapper:

```bash
alias pi='pi --no-session'

pi --no-session
```

What it does:
- Makes `pi` run in no-session mode by default.
- You can also call `pi --no-session` directly when you want to bypass sessions without an alias.

### Common pi agent commands

Command:

```bash
pi "Read package.json and summarize the dependencies"
pi -p "List all .ts files in src/"
pi --continue "What did we discuss?"
pi --resume
pi --name "Refactor auth module"
pi --list-models
pi --export ~/.pi/agent/sessions/session.jsonl output.html
```

What it does:
- `pi "..."` starts an interactive agent session with an initial prompt.
- `pi -p "..."` runs non-interactively and exits after processing the prompt.
- `pi --continue` reopens the previous session thread.
- `pi --resume` lets you pick an existing session to continue.
- `pi --name` gives the session a readable label.
- `pi --list-models` shows available models for selection or cycling.
- `pi --export` converts a session log into HTML for review or sharing.

### Current local models

Both Qwen models are currently running:

```
┌──────────────────────────────┬────────────────┬────────────┐
│ Model                        │ Port           │ Status     │
├──────────────────────────────┼────────────────┼────────────┤
│ Qwen 2.5 3B (Q4_K_M, 2.0 GB) │ localhost:8000 │ ✅ Running │
├──────────────────────────────┼────────────────┼────────────┤
│ Qwen 2.5 7B (Q4_K_M, 4.4 GB) │ localhost:8001 │ ✅ Running │
└──────────────────────────────┴────────────────┴────────────┘
```

Both models are added as separate providers in pi's `models.json`:
- `local-3b` → model ID `qwen2.5-3b-instruct` on `localhost:8000`
- `local-7b` → model ID `qwen2.5-7b-instruct` on `localhost:8001`

### Manage individual models

You can control both models together or manage them separately:

Command:

```bash
~/.local/bin/llama-server-ctl status           # Show status of both
~/.local/bin/llama-server-ctl start            # Start both models
~/.local/bin/llama-server-ctl stop 7b          # Stop only the 7B model
~/.local/bin/llama-server-ctl restart 3b       # Restart only the 3B model
```

What it does:
- Without a model suffix, commands apply to both models.
- With `3b` or `7b` suffix, you can manage individual models (useful for freeing resources).

### Auto-start status

**Models do NOT auto-start on boot.** No systemd service, no autostart entry, and no shell script is configured to start them automatically. They only run when you explicitly start them. Your GPU stays free for games and normal work. 🎮

### Stop the models

To stop only the 7B model:

```bash
bash /home/aleks/.local/share/llama-server/start.sh stop 7b
```

To stop all running models:

```bash
bash /home/aleks/.local/share/llama-server/start.sh stop
```

What it does:
- Frees up GPU memory and CPU resources.
- The models can be started again anytime you need them.

### Where to run commands from

You can run the start.sh script from anywhere using the full path:

```bash
bash /home/aleks/.local/share/llama-server/start.sh [command]
```

Or navigate to the directory first:

```bash
cd /home/aleks/.local/share/llama-server
bash start.sh [command]
```

### Full manual usage reference

```bash
# Start the 7B (smarter, slower)
bash /home/aleks/.local/share/llama-server/start.sh start 7b

# Or start the 3B (faster, lighter)
bash /home/aleks/.local/share/llama-server/start.sh start 3b

# Check what's running
bash /home/aleks/.local/share/llama-server/start.sh status

# Stop all models
bash /home/aleks/.local/share/llama-server/start.sh stop
```





## Tmux session and window management

A comprehensive list of tmux commands for managing sessions, windows, and panes in Omarchy.

### Basic session management

| Action | Command (inside tmux) | Outside/alternative |
|--------|---|---|
| **List sessions** | `Ctrl+Space` then `s` (interactive picker) | `tmux ls` |
| **Detach (exit without killing)** | `Ctrl+Space` then `d` | – |
| **Create named session** | – | `tmux new -s codelocal` |
| **Create named session (detached)** | – | `tmux new -ds codelocal` |
| **Attach to existing session** | – | `tmux attach -t codelocal` |
| **Switch to another session inside tmux** | `Ctrl+Space` then `s` (pick) or `tmux switch -t name` | – |

### Window / tab management

| Action | Command |
|--------|---------|
| **New window** | `Ctrl+Space` then `c` |
| **Rename current window** | `Ctrl+Space` then `,` |
| **Close current window (kill)** | `Ctrl+Space` then `&` → `y` |
| **Close specific window** | `tmux kill-window -t 2` |
| **Close all windows except current** | `tmux kill-window -a` |
| **Jump to window by number** | `Alt+1` … `Alt+9` (Omarchy) |
| **Previous / next window** | `Alt+h` / `Alt+l` (Omarchy) |
| **Move window left / right** | `Alt+H` / `Alt+L` (Omarchy) |

### Pane management (inside a window)

| Action | Command |
|--------|---------|
| **Split pane vertically** | `Ctrl+Space` then `%` |
| **Split pane horizontally** | `Ctrl+Space` then `"` |
| **Close current pane** | `Ctrl+Space` then `x` → `y` or type `exit` |
| **Navigate panes** | Arrow keys after prefix, or `Ctrl+Space` + arrow |
| **Kill pane (direct)** | `tmux kill-pane -t 0` |

### Omarchy‑specific layout helpers

| Command | What it does |
|---------|---|
| `tdl [agent]` | Three‑way split: editor (left), agent (right), terminal (bottom) |
| `tdlm [agent]` | Same layout per subdirectory (multiple windows) |
| `tsl [panes] [command]` | Grid of panes |

### One‑liner to create a session with named windows

Command:

```bash
tmux new -s codelocal -n editor \; \
  neww -n build \; \
  neww -n git \; \
  selectw -t 0
```

What it does:
- Spawns a session named `codelocal` with three windows: `editor`, `build`, and `git`.
- Lands in window 0 (the `editor` window) by default.
- Useful for quickly setting up a project workspace with predefined window names.
