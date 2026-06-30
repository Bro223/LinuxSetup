#!/bin/bash
# Hibernate setup for Lenovo ThinkPad + NVIDIA primary GPU (reverse PRIME)
# Run this as your user — sudo prompts will appear where needed.
# This script is SAFE to run multiple times (idempotent where possible).

set -e

echo "============================================"
echo "  HIBERNATE SETUP"
echo "============================================"

# --- 1. Create swap file on Btrfs ---
echo ""
echo "[1/6] Creating 32G swap file (Btrfs)..."
SWAPFILE=/swapfile
if [ -f "$SWAPFILE" ]; then
    echo "  Swap file already exists at $SWAPFILE, skipping creation."
else
    sudo truncate -s 0 "$SWAPFILE"
    sudo chattr +C "$SWAPFILE"        # Disable CoW (required for Btrfs swap)
    sudo fallocate -l 32G "$SWAPFILE"  # 32GB > 30GB RAM
    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
    echo "  ✅ Swap file created at $SWAPFILE"
fi

# Enable swap temporarily
sudo swapon "$SWAPFILE" 2>/dev/null || echo "  Swap already active"

# Add to fstab if not already there
if ! grep -q "$SWAPFILE" /etc/fstab 2>/dev/null; then
    echo "$SWAPFILE none swap defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
    echo "  ✅ Added to /etc/fstab"
else
    echo "  Already in /etc/fstab"
fi

# --- 2. Get the swap file offset for resume= ---
echo ""
echo "[2/6] Getting swap file offset..."
OFFSET=$(sudo filefrag -v "$SWAPFILE" | awk '$1=="0:" {print $4}' | sed 's/\.//')
if [ -z "$OFFSET" ]; then
    echo "  ❌ Could not determine swap file offset!"
    echo "  Run manually: sudo filefrag -v /swapfile"
    echo "  Look for the physical offset of extent 0."
    exit 1
fi
echo "  Swap file offset: $OFFSET"

# --- 3. Update kernel cmdline ---
echo ""
echo "[3/6] Updating kernel cmdline..."
CMDLINE_FILE=""
if [ -f /boot/loader/entries/*.conf ]; then
    CMDLINE_FILE=$(ls /boot/loader/entries/*.conf 2>/dev/null | head -1)
elif [ -f /etc/kernel/cmdline ]; then
    CMDLINE_FILE=/etc/kernel/cmdline
fi

if [ -n "$CMDLINE_FILE" ]; then
    echo "  Found kernel cmdline at: $CMDLINE_FILE"
    # Replace or add resume_offset
    if sudo grep -q "resume_offset=" /proc/cmdline 2>/dev/null; then
        sudo sed -i "s/resume_offset=[0-9]*/resume_offset=$OFFSET/" "$CMDLINE_FILE"
        echo "  ✅ Updated resume_offset=$OFFSET in $CMDLINE_FILE"
    else
        echo "  resume_offset not found — may be set elsewhere (efibootmgr?)."
        echo "  ⚠️  Manually add: resume_offset=$OFFSET to your kernel parameters."
    fi
else
    echo "  Could not find kernel cmdline file."
    echo "  ⚠️  Check /boot/loader/entries/ or /etc/kernel/cmdline manually."
fi

# --- 4. Add resume hook to initramfs ---
echo ""
echo "[4/6] Adding resume hook to mkinitcpio.conf..."
HOOKS_LINE=$(sudo grep "^HOOKS=" /etc/mkinitcpio.conf)
if echo "$HOOKS_LINE" | grep -q "resume"; then
    echo "  resume hook already present."
else
    # Insert resume after encrypt, before filesystems
    sudo sed -i 's/^HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt resume filesystems fsck)/' /etc/mkinitcpio.conf
    echo "  ✅ Added resume hook to mkinitcpio.conf"
fi

# Rebuild initramfs
echo "  Rebuilding initramfs..."
sudo mkinitcpio -P
echo "  ✅ Initramfs rebuilt"

# --- 5. Recreate hyprland-suspend.service for hyprlock ---
echo ""
echo "[5/6] Creating hyprland suspend service for hibernate..."

SERVICE_FILE=/etc/systemd/system/hyprland-suspend.service
if [ -f "$SERVICE_FILE" ]; then
    echo "  Service already exists."
else
    sudo tee "$SERVICE_FILE" >/dev/null << 'EOF'
[Unit]
Description=Suspend hyprland
Before=systemd-suspend.service
Before=systemd-hibernate.service
Before=nvidia-suspend.service
Before=nvidia-hibernate.service

[Service]
Type=oneshot
User=aleks
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/bin/sh -c 'pidof hyprlock >/dev/null 2>&1 || hyprlock & sleep 1'

[Install]
WantedBy=systemd-suspend.service
WantedBy=systemd-hibernate.service
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable hyprland-suspend.service
    echo "  ✅ hyprland-suspend.service created and enabled"
fi

# --- 6. Unmask hibernate target ---
echo ""
echo "[6/6] Unmasking hibernate.target..."
if systemctl is-enabled hibernate.target 2>/dev/null | grep -q masked; then
    sudo systemctl unmask hibernate.target
    echo "  ✅ hibernate.target unmasked"
else
    echo "  hibernate.target already unmasked"
fi

echo ""
echo "============================================"
echo "  SETUP COMPLETE"
echo "============================================"
echo ""
echo "Now test with:"
echo "    systemctl hibernate"
echo ""
echo "System should:"
echo "  1. Lock screen (hyprlock)"
echo "  2. Save to disk (~30s)"
echo "  3. Power off"
echo "  4. On power button → boot → resume from swap"
echo ""
echo "If hibernate fails (system boots normally):"
echo "  - Check resume_offset is correct:"
echo "    sudo filefrag -v /swapfile"
echo "  - Check the kernel parameter:"
echo "    cat /proc/cmdline"
echo "  - Check the initramfs was rebuilt:"
echo "    lsinitcpio /boot/initramfs-linux.img 2>/dev/null | grep -q resume && echo 'resume present' || echo 'MISSING'"
echo ""
echo "ALWAYS keep suspend.target/sleep.target masked:"
echo "    sudo systemctl mask sleep.target suspend.target"
