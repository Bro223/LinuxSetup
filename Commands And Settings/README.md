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

## Sync files and folders with rsync (recursive)

Command:

```bash
rsync -R /path/to/source/ /path/to/destination/
```

What it does:
- Syncs files and folders from source to destination.
- The `-R` flag preserves the directory structure (recursive), so all folders inside the source folder get synced too.
- Trailing slash after source matters: with `/` it copies contents; without `/` it copies the folder itself.

Simple example:

```bash
rsync -R ~/projects/myapp/ ~/backup/myapp/
```

What it syncs:
- **Source:** All files and folders inside `~/projects/myapp/`
- **Destination:** `~/backup/myapp/` (directory structure is preserved)

Useful flags:
- `-a` : Archive mode (preserves permissions, timestamps, etc.)
- `-v` : Verbose (shows what's being copied)
- `--delete` : Deletes files in destination that don't exist in source
- `-P` : Shows progress and partial file transfers

Example with flags:

```bash
rsync -avR --delete ~/projects/myapp/ ~/backup/myapp/
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
