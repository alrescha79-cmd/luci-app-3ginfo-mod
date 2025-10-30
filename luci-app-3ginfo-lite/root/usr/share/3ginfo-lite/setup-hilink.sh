#!/bin/sh
#
# Quick setup script for HiLink modem authentication
#

echo "=== HiLink Modem Quick Setup ==="
echo

# Detect HiLink modem IP
RES="/usr/share/3ginfo-lite"
if [ -x "$RES/detect_hilink.sh" ]; then
	DETECTED_IP=$($RES/detect_hilink.sh)
	if [ -n "$DETECTED_IP" ]; then
		echo "✓ HiLink modem detected at: $DETECTED_IP"
		HILINK_IP="$DETECTED_IP"
	else
		echo "! No HiLink modem auto-detected"
		read -p "Enter HiLink modem IP address [192.168.8.1]: " HILINK_IP
		HILINK_IP=${HILINK_IP:-192.168.8.1}
	fi
else
	read -p "Enter HiLink modem IP address [192.168.8.1]: " HILINK_IP
	HILINK_IP=${HILINK_IP:-192.168.8.1}
fi

echo
echo "Current configuration:"
CURRENT_IP=$(uci -q get 3ginfo.@3ginfo[0].hilink_ip)
CURRENT_USER=$(uci -q get 3ginfo.@3ginfo[0].hilink_username)
CURRENT_PASS=$(uci -q get 3ginfo.@3ginfo[0].hilink_password)

echo "  IP: ${CURRENT_IP:-<not set>}"
echo "  Username: ${CURRENT_USER:-<not set>}"
echo "  Password: ${CURRENT_PASS:+<configured>}${CURRENT_PASS:-<not set>}"

echo
echo "Setting up new configuration..."

# Set IP
uci set 3ginfo.@3ginfo[0].hilink_ip="$HILINK_IP"
echo "✓ Set HiLink IP: $HILINK_IP"

# Ask for username
read -p "Enter username [admin]: " USERNAME
USERNAME=${USERNAME:-admin}
uci set 3ginfo.@3ginfo[0].hilink_username="$USERNAME"
echo "✓ Set username: $USERNAME"

# Ask for password
echo -n "Enter password: "
read -s PASSWORD
echo
if [ -z "$PASSWORD" ]; then
	echo "! Warning: No password set"
	read -p "Try default password 'admin'? [Y/n]: " USE_DEFAULT
	if [ "$USE_DEFAULT" != "n" ] && [ "$USE_DEFAULT" != "N" ]; then
		PASSWORD="1sampek8"
		echo "✓ Using default password: admin"
	fi
fi

if [ -n "$PASSWORD" ]; then
	uci set 3ginfo.@3ginfo[0].hilink_password="$PASSWORD"
	echo "✓ Password configured"
fi

# Ask about authentication mode
echo
echo "Authentication mode:"
echo "  1) Automatic - Try configured password, fallback to default 'admin/admin' if not set"
echo "  2) Manual only - Only use configured password, never try default credentials"
read -p "Select mode [1/2, default=1]: " AUTH_MODE_CHOICE

if [ "$AUTH_MODE_CHOICE" = "2" ]; then
	uci set 3ginfo.@3ginfo[0].hilink_auth_mode='manual'
	echo "✓ Authentication mode: Manual only - will only use configured credentials"
else
	uci set 3ginfo.@3ginfo[0].hilink_auth_mode='auto'
	echo "✓ Authentication mode: Automatic - will try default 'admin/admin' if needed"
fi

# Commit changes
uci commit 3ginfo
echo
echo "✓ Configuration saved!"

# Test connection
echo
echo "Testing connection to modem..."
TEST_RESULT=$(wget -t 2 -T 3 -q -O - "http://$HILINK_IP/api/device/information" 2>&1)

if echo "$TEST_RESULT" | grep -q "100003"; then
	echo "⚠ Modem requires authentication"
	echo "  The configured credentials will be used automatically"
elif echo "$TEST_RESULT" | grep -q "<response>"; then
	echo "✓ Successfully connected to modem!"
	DEVICE_NAME=$(echo "$TEST_RESULT" | awk -F[\<\>] '/<DeviceName>/ {print $3}')
	[ -n "$DEVICE_NAME" ] && echo "  Device: $DEVICE_NAME"
else
	echo "✗ Could not connect to modem at $HILINK_IP"
	echo "  Please check:"
	echo "  1. Modem IP address is correct"
	echo "  2. Modem is powered on and accessible"
	echo "  3. Network connection to modem"
fi

echo
echo "=== Setup Complete ==="
echo
echo "You can now check modem info with:"
echo "  /usr/share/3ginfo-lite/3ginfo.sh"
echo
echo "Or in LuCI: Status > 3ginfo-lite"
