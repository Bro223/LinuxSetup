#!/bin/bash
# Hibernate readiness check
echo "============================================"
echo "  HIBERNATE READINESS CHECK"
echo "============================================"

echo ""
echo "--- SWAP vs RAM ---"
SWAP=$(swapon --show --noheadings 2>/dev/null | awk '{sum+=$3} END {print sum/1024/1024 " GB"}' || echo "0")
RAM=$(free -h | grep Mem | awk '{print $2}')
echo "Swap total: $SWAP"
echo "RAM total:  $RAM"

SWAP_MB=$(swapon --show --noheadings 2>/dev/null | awk '{sum+=$3} END {print sum/1024}' || echo "0")
RAM_MB=$(free | grep Mem | awk '{print $2}')
if [ "$SWAP_MB" -ge "$RAM_MB" ] 2>/dev/null; then
    echo "✅ Swap >= RAM"
else
    echo "❌ Swap < RAM — need to resize!"
fi

echo ""
echo "--- KERNEL CMDLINE ---"
cat /proc/cmdline
if cat /proc/cmdline | grep -q "resume="; then
    echo "✅ resume= parameter found"
else
    echo "❌ No resume= parameter — need to add"
fi

echo ""
echo "--- POWER STATES ---"
cat /sys/power/state | grep -q disk && echo "✅ Hibernate (disk) supported" || echo "❌ Hibernate not supported"
cat /sys/power/state

echo ""
echo "--- INITRAMFS RESUME HOOK ---"
if grep -q "resume" /etc/mkinitcpio.conf 2>/dev/null; then
    echo "✅ resume hook found in mkinitcpio.conf"
    grep "resume" /etc/mkinitcpio.conf
else
    echo "❌ No resume hook in mkinitcpio.conf"
fi

echo ""
echo "--- NVIDIA HIBERNATE SERVICE ---"
systemctl is-enabled nvidia-hibernate.service 2>/dev/null && echo "✅ nvidia-hibernate.service enabled" || echo "❌ nvidia-hibernate.service not enabled"
systemctl status nvidia-hibernate.service 2>/dev/null | head -5

echo ""
echo "--- HIBERNATE TARGET ---"
systemctl is-enabled hibernate.target 2>/dev/null
if systemctl is-enabled hibernate.target 2>/dev/null | grep -q masked; then
    echo "❌ hibernate.target is masked — need to unmask"
fi

echo ""
echo "--- HYPRLAND HIBERNATE SERVICE ---"
systemctl is-enabled hyprland-suspend.service 2>/dev/null
echo "(hyprland-suspend.service has WantedBy=systemd-hibernate.service built in)"

echo ""
echo "============================================"
echo "  If all checks pass, run:"
echo "    sudo systemctl unmask hibernate.target"
echo "    systemctl hibernate"
echo "============================================"
