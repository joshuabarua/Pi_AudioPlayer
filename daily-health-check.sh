#!/bin/bash
# Daily Health Check with Telegram Notifications
# Run via cron daily or systemd timer
# Usage: ./daily-health-check.sh [TELEGRAM_BOT_TOKEN] [CHAT_ID]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/audio-health-check-$(date +%Y%m%d).log"

# Telegram config (can be passed as args or set as env vars)
TELEGRAM_BOT_TOKEN="${1:-$TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${2:-$TELEGRAM_CHAT_ID}"

# Function to send Telegram message
send_telegram() {
    local message="$1"
    local parse_mode="${2:-HTML}"
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        echo "Warning: Telegram credentials not configured"
        return 1
    fi
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=${parse_mode}" \
        -d "text=${message}" \
        --max-time 30 \
        > /dev/null 2>&1
}

# Function to send file to Telegram
send_telegram_file() {
    local file_path="$1"
    local caption="${2:-Health Check Log}"
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 1
    fi
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "caption=${caption}" \
        -F "document=@${file_path}" \
        --max-time 60 \
        > /dev/null 2>&1
}

# Run diagnostics and save to log
echo "=== Daily Audio System Health Check ===" > "$LOG_FILE"
echo "Date: $(date)" >> "$LOG_FILE"
echo "Hostname: $(hostname)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "[1/3] Running Latency Diagnostics..." | tee -a "$LOG_FILE"
if [[ -f "$SCRIPT_DIR/diagnose-latency.sh" ]]; then
    bash "$SCRIPT_DIR/diagnose-latency.sh" >> "$LOG_FILE" 2>&1
else
    echo "Error: diagnose-latency.sh not found" | tee -a "$LOG_FILE"
fi
echo "" >> "$LOG_FILE"

echo "[2/3] Running Optimization Verification..." | tee -a "$LOG_FILE"
if [[ -f "$SCRIPT_DIR/verify-optimizations.sh" ]]; then
    bash "$SCRIPT_DIR/verify-optimizations.sh" >> "$LOG_FILE" 2>&1
    VERIFY_STATUS=$?
else
    echo "Error: verify-optimizations.sh not found" | tee -a "$LOG_FILE"
    VERIFY_STATUS=1
fi
echo "" >> "$LOG_FILE"

echo "[3/3] Running System Health Check..." | tee -a "$LOG_FILE"
if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
    bash "$SCRIPT_DIR/health-check.sh" >> "$LOG_FILE" 2>&1
    HEALTH_STATUS=$?
else
    echo "Error: health-check.sh not found" | tee -a "$LOG_FILE"
    HEALTH_STATUS=1
fi
echo "" >> "$LOG_FILE"

# Get summary stats
CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}')
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
UPTIME=$(uptime -p)

# Create summary message
SUMMARY="<b>🎵 Audio System Daily Check</b>

<b>📅 Date:</b> $(date '+%Y-%m-%d %H:%M')
<b>🖥️ Host:</b> $(hostname)
<b>⏱️ Uptime:</b> ${UPTIME}

<b>📊 System Status:</b>
🌡️ CPU Temp: ${CPU_TEMP}°C
💾 Disk: ${DISK_USAGE}
🧠 Memory: ${MEMORY_USAGE}%

<b>🔍 Check Results:</b>"

if [[ $VERIFY_STATUS -eq 0 && $HEALTH_STATUS -eq 0 ]]; then
    SUMMARY="${SUMMARY}
✅ All checks PASSED
✅ Optimizations active
✅ Services running"
    STATUS_ICON="✅"
else
    SUMMARY="${SUMMARY}
⚠️ Some checks FAILED
⚠️ Review attached log"
    STATUS_ICON="⚠️"
fi

# Add quick service status
SUMMARY="${SUMMARY}

<b>🎧 Services:</b>"

if pgrep -x camilladsp > /dev/null; then
    SUMMARY="${SUMMARY}
✅ CamillaDSP"
else
    SUMMARY="${SUMMARY}
❌ CamillaDSP (DOWN)"
fi

if pgrep -f "music_display.py" > /dev/null; then
    SUMMARY="${SUMMARY}
✅ Music Display"
else
    SUMMARY="${SUMMARY}
❌ Music Display (DOWN)"
fi

if systemctl is-active --quiet shairport-sync 2>/dev/null; then
    SUMMARY="${SUMMARY}
✅ Shairport Sync"
else
    SUMMARY="${SUMMARY}
❌ Shairport Sync (DOWN)"
fi

SUMMARY="${SUMMARY}

${STATUS_ICON} Full log attached"

# Send Telegram notification
echo "[4/4] Sending Telegram notification..."
send_telegram "$SUMMARY"

# Send log file
send_telegram_file "$LOG_FILE" "Full health check log for $(date +%Y-%m-%d)"

echo ""
echo "=== Health Check Complete ==="
echo "Log saved to: $LOG_FILE"

# Cleanup old logs (keep 7 days)
find /tmp -name "audio-health-check-*.log" -mtime +7 -delete 2>/dev/null || true
