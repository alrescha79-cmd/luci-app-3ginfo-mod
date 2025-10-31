#!/bin/sh
#
# (c) 2025 HiLink modem detection script
# Detects HiLink modems including those connected via mac-vlan
#

# Check common HiLink IP addresses
COMMON_IPS="192.168.8.1 192.168.1.1 192.168.0.1 192.168.100.1"

# Get configured IP from config
CONF_IP=$(uci -q get 3ginfo.@3ginfo[0].hilink_ip)
if [ -n "$CONF_IP" ]; then
	COMMON_IPS="$CONF_IP $COMMON_IPS"
fi

# Check device setting for IP
CONF_DEVICE=$(uci -q get 3ginfo.@3ginfo[0].device)
if echo "x$CONF_DEVICE" | grep -q "192.168."; then
	COMMON_IPS="$CONF_DEVICE $COMMON_IPS"
fi

# Try to detect HiLink modem
for IP in $COMMON_IPS; do
	# Quick ping test
	ping -c 1 -W 1 $IP >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		# Try to access web interface
		RESPONSE=$(wget -t 1 -T 2 -q -O - "http://$IP/api/device/information" 2>/dev/null)
		if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
			# Detect vendor
			if echo "$RESPONSE" | grep -qi "huawei"; then
				echo "huawei" > /tmp/hilink_vendor
			elif echo "$RESPONSE" | grep -qi "zte"; then
				echo "zte" > /tmp/hilink_vendor
			elif echo "$RESPONSE" | grep -qi "alcatel"; then
				echo "alcatel" > /tmp/hilink_vendor
			else
				echo "huawei" > /tmp/hilink_vendor
			fi
			echo "$IP"
			exit 0
		fi
		
		# Try alternative endpoint
		RESPONSE=$(wget -t 1 -T 2 -q -O - "http://$IP/api/device/signal" 2>/dev/null)
		if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
			echo "huawei" > /tmp/hilink_vendor
			echo "$IP"
			exit 0
		fi
	fi
done

# Check for mac-vlan interfaces
for iface in $(ip link show | grep -o "macvlan[0-9]*\|macvtap[0-9]*"); do
	# Get IP from interface
	IP=$(ip addr show $iface | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
	if [ -n "$IP" ]; then
		# Calculate gateway (assuming /24 subnet with .1 as gateway)
		GATEWAY=$(echo $IP | cut -d'.' -f1-3).1
		
		# Try to access modem at gateway
		RESPONSE=$(wget -t 1 -T 2 -q -O - "http://$GATEWAY/api/device/information" 2>/dev/null)
		if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
			# Detect vendor
			if echo "$RESPONSE" | grep -qi "huawei"; then
				echo "huawei" > /tmp/hilink_vendor
			elif echo "$RESPONSE" | grep -qi "zte"; then
				echo "zte" > /tmp/hilink_vendor
			elif echo "$RESPONSE" | grep -qi "alcatel"; then
				echo "alcatel" > /tmp/hilink_vendor
			else
				echo "huawei" > /tmp/hilink_vendor
			fi
			echo "$GATEWAY"
			exit 0
		fi
	fi
done

exit 1
