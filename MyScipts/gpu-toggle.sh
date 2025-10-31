#!/bin/bash

ENV_FILE="/etc/environment"

echo "Which GPU do you want to use for next session?"
echo "1) NVIDIA (dedicated)"
echo "2) Intel (integrated)"
read -p "Enter 1 or 2: " choice

case "$choice" in
  1)
    echo "Switching to NVIDIA GPU..."
    sudo sed -i 's|card1:/dev/dri/card0|card0:/dev/dri/card1|' "$ENV_FILE"
    ;;
  2)
    echo "Switching to Intel GPU..."
    sudo sed -i 's|card0:/dev/dri/card1|card1:/dev/dri/card0|' "$ENV_FILE"
    ;;
  *)
    echo "Invalid option. Exiting..."
    exit 1
    ;;
esac

echo "GPU setting updated. Logging out..."
sleep 2
reboot
#qdbus org.kde.LogoutPrompt /LogoutPrompt promptLogout
