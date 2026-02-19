#!/bin/bash
# Setup Daily Health Check with Telegram Notifications
# Run this once to configure daily monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.config/audio-health-check.conf"

echo "=== Setup Daily Health Check with Telegram ==="
echo ""

# Check if already configured
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Configuration file already exists at: $CONFIG_FILE"
    read -p "Do you want to reconfigure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Create config directory
mkdir -p "$HOME/.config"

echo "📱 Step 1: Telegram Bot Setup"
echo ""
echo "To receive notifications, you need to:"
echo "1. Message @BotFather on Telegram"
echo "2. Create a new bot with /newbot"
echo "3. Copy the bot token (looks like: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz)"
echo "4. Message your bot to get your chat ID"
echo ""
echo "   To get your chat ID:"
echo "   - Send a message to your bot"
echo "   - Visit: https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
echo "   - Look for 'chat':{'id':123456789}"
echo ""

# Get Telegram credentials
read -p "Enter your Telegram Bot Token: " BOT_TOKEN
read -p "Enter your Chat ID: " CHAT_ID

if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    echo "Error: Both Bot Token and Chat ID are required"
    exit 1
fi

# Test the bot connection
echo ""
echo "🔄 Testing Telegram connection..."
TEST_RESULT=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=🎵 Audio System Health Check - Bot configured successfully!" \
    --max-time 30)

if echo "$TEST_RESULT" | grep -q '"ok":true'; then
    echo "✅ Telegram bot test successful!"
else
    echo "❌ Telegram bot test failed!"
    echo "Response: $TEST_RESULT"
    echo ""
    echo "Please check your bot token and chat ID."
    exit 1
fi

# Save configuration
cat > "$CONFIG_FILE" << EOF
# Audio System Health Check Configuration
# Generated on $(date)

TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
TELEGRAM_CHAT_ID="$CHAT_ID"
EOF

chmod 600 "$CONFIG_FILE"
echo "✅ Configuration saved to $CONFIG_FILE"
echo ""

# Make scripts executable
chmod +x "$SCRIPT_DIR/daily-health-check.sh"
chmod +x "$SCRIPT_DIR/diagnose-latency.sh"
chmod +x "$SCRIPT_DIR/verify-optimizations.sh"
chmod +x "$SCRIPT_DIR/health-check.sh"

echo "🔧 Step 2: Choose Scheduling Method"
echo ""
echo "How do you want to schedule the daily check?"
echo "1) Cron (runs as current user)"
echo "2) Systemd Timer (more reliable, survives reboots)"
echo ""
read -p "Choose option (1/2): " SCHEDULE_OPTION

if [[ "$SCHEDULE_OPTION" == "1" ]]; then
    # Setup cron job
    echo ""
    echo "⏰ Setting up Cron job..."
    
    # Create cron entry
    CRON_LINE="0 8 * * * export TELEGRAM_BOT_TOKEN='$BOT_TOKEN' && export TELEGRAM_CHAT_ID='$CHAT_ID' && cd $SCRIPT_DIR && bash $SCRIPT_DIR/daily-health-check.sh > /dev/null 2>&1"
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "daily-health-check.sh"; echo "$CRON_LINE") | crontab -
    
    echo "✅ Cron job added - runs daily at 8:00 AM"
    echo ""
    echo "To change the time, edit your crontab:"
    echo "  crontab -e"
    
elif [[ "$SCHEDULE_OPTION" == "2" ]]; then
    # Setup systemd timer
    echo ""
    echo "⏰ Setting up Systemd Timer..."
    
    mkdir -p "$HOME/.config/systemd/user"
    
    # Create service file
    cat > "$HOME/.config/systemd/user/audio-health-check.service" << EOF
[Unit]
Description=Daily Audio System Health Check
After=network.target

[Service]
Type=oneshot
Environment="TELEGRAM_BOT_TOKEN=$BOT_TOKEN"
Environment="TELEGRAM_CHAT_ID=$CHAT_ID"
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/daily-health-check.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    # Create timer file
    cat > "$HOME/.config/systemd/user/audio-health-check.timer" << EOF
[Unit]
Description=Run Audio Health Check Daily

[Timer]
OnCalendar=daily
Persistent=true
# Run 30 seconds after boot if missed
OnBootSec=30

[Install]
WantedBy=timers.target
EOF

    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable audio-health-check.timer
    systemctl --user start audio-health-check.timer
    
    echo "✅ Systemd timer enabled - runs daily"
    echo ""
    echo "Timer status:"
    systemctl --user status audio-health-check.timer --no-pager | head -5
    echo ""
    echo "To check logs: journalctl --user -u audio-health-check.service"
else
    echo "❌ Invalid option. No scheduler configured."
    echo "You can run the script manually:"
    echo "  $SCRIPT_DIR/daily-health-check.sh"
    exit 1
fi

echo ""
echo "🧪 Step 3: Test the setup..."
read -p "Run a test health check now? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
    export TELEGRAM_CHAT_ID="$CHAT_ID"
    bash "$SCRIPT_DIR/daily-health-check.sh"
    echo ""
    echo "Check your Telegram for the test message!"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Configuration saved: $CONFIG_FILE"
echo ""
echo "To run manually:"
echo "  export TELEGRAM_BOT_TOKEN='your_token'"
echo "  export TELEGRAM_CHAT_ID='your_chat_id'"
echo "  ./daily-health-check.sh"
echo ""
echo "Or load from config:"
echo "  source $CONFIG_FILE && ./daily-health-check.sh"
