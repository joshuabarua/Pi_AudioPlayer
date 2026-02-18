#!/bin/bash
# Install systemd user services for Audio Player
# Usage: ./install-services.sh
# Run as regular user (not sudo) - it will set up user services

set -e

USERNAME=$(whoami)
USER_ID=$(id -u)

echo "Installing Audio Player user services for: $USERNAME (UID: $USER_ID)"

# Verify the installation exists
if [[ ! -f "$HOME/Audio_Player/sense_music/camilla.yml" ]]; then
    echo "Error: Audio_Player not found at $HOME/Audio_Player"
    echo "Please run this script from your Audio_Player directory"
    exit 1
fi

if [[ ! -f "$HOME/Audio_Player/venv/bin/python" ]]; then
    echo "Error: Virtual environment not found. Please run ./setup.sh first"
    exit 1
fi

# Create user systemd directory if needed
mkdir -p ~/.config/systemd/user/

# Copy service files
cp "$HOME/Audio_Player/camilladsp.service" ~/.config/systemd/user/
cp "$HOME/Audio_Player/sense-music.service" ~/.config/systemd/user/

# Reload systemd user daemon
systemctl --user daemon-reload

# Enable services to start on user login
systemctl --user enable camilladsp.service
systemctl --user enable sense-music.service

echo ""
echo "User services installed successfully!"
echo ""
echo "To start the services now, run:"
echo "  systemctl --user start camilladsp.service"
echo "  systemctl --user start sense-music.service"
echo ""
echo "To stop the services:"
echo "  systemctl --user stop camilladsp.service"
echo "  systemctl --user stop sense-music.service"
echo ""
echo "To check status:"
echo "  systemctl --user status camilladsp.service"
echo "  systemctl --user status sense-music.service"
echo ""
echo "To view logs:"
echo "  journalctl --user -u camilladsp.service -f"
echo "  journalctl --user -u sense-music.service -f"
echo ""
echo "Services will start automatically when you log in."
echo "To enable lingering (services run even after logout):"
echo "  sudo loginctl enable-linger $USERNAME"
