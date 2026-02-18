#!/bin/bash
# Uninstall systemd user services for Audio Player
# Usage: ./uninstall-services.sh

echo "Uninstalling Audio Player user services..."

# Stop services if running
systemctl --user stop camilladsp.service 2>/dev/null || true
systemctl --user stop sense-music.service 2>/dev/null || true

# Disable services
systemctl --user disable camilladsp.service 2>/dev/null || true
systemctl --user disable sense-music.service 2>/dev/null || true

# Remove service files
rm -f ~/.config/systemd/user/camilladsp.service
rm -f ~/.config/systemd/user/sense-music.service

# Reload systemd user daemon
systemctl --user daemon-reload

echo "User services uninstalled successfully!"
