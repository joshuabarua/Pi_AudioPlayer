#!/bin/bash
# Fix for 20-second connection delay

echo "=== Applying Connectivity Fixes ==="

# 1. Disable WiFi Power Management
echo "Disabling WiFi Power Management..."
sudo iwconfig wlan0 power off || true
sudo bash -c 'cat > /etc/NetworkManager/conf.d/disable-powersave.conf' << 'EOF'
[connection]
wifi.powersave = 2
EOF
echo "✓ WiFi Power Management disabled (persistent via NetworkManager)"

# 2. Optimize Shairport Sync Config
echo "Optimizing Shairport Sync configuration..."
sudo bash -c 'cat > /etc/shairport-sync.conf' << 'EOF'
general =
{
    name = "Jukebox";
    volume_range_db = 60;
    output_backend = "pa";
    latency = 4410;
    drift_tolerance_in_seconds = 0.005;
    resync_threshold_in_seconds = 0.030;
    mdns_backend = "avahi";
    allow_ipv6 = "no";
};

metadata =
{
    enabled = "yes";
    include_cover_art = "no";
    pipe_name = "/tmp/shairport-sync-metadata";
    pipe_timeout = 5000;
};

pa =
{
    application_name = "Shairport Sync";
    sink = "camilla_sink";
    audio_backend_buffer_desired_length_in_seconds = 0.02;
    audio_backend_latency_offset_in_seconds = 0.0;
};

sessioncontrol =
{
    wait_for_completion = "no";
    allow_session_interruption = "yes";
    session_timeout = 20;
};
EOF
echo "✓ Shairport Sync config updated"

# 3. Restart Services
echo "Restarting Shairport Sync..."
systemctl --user restart shairport-sync-user
echo "✓ Service restarted"

echo "=== Fixes Applied ==="
echo "Please test the connection now."
