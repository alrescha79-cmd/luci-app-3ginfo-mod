#!/bin/sh
# MIT License

# Set execute permissions for scripts
chmod +x /usr/share/3ginfo-lite/3ginfo.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/detect.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/detect_hilink.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/setup-hilink.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/test-hilink.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/check.gcom 2>&1 &
chmod +x /usr/share/3ginfo-lite/info.gcom 2>&1 &
chmod +x /usr/share/3ginfo-lite/vendorproduct.gcom 2>&1 &
chmod +x /usr/share/3ginfo-lite/modem/hilink/alcatel_hilink.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/modem/hilink/huawei_hilink.sh 2>&1 &
chmod +x /usr/share/3ginfo-lite/modem/hilink/zte.sh 2>&1 &

# Initialize UCI config if it doesn't exist
if ! uci -q get 3ginfo.@3ginfo[0] >/dev/null 2>&1; then
	echo "Initializing 3ginfo configuration..."
	uci set 3ginfo.@3ginfo[0]=3ginfo
	uci set 3ginfo.@3ginfo[0].device=''
	uci set 3ginfo.@3ginfo[0].website='http://www.btsearch.pl/szukaj.php?mode=std&search='
	uci set 3ginfo.@3ginfo[0].hilink_ip=''
	uci set 3ginfo.@3ginfo[0].hilink_username=''
	uci set 3ginfo.@3ginfo[0].hilink_password=''
	uci set 3ginfo.@3ginfo[0].hilink_auth_mode='auto'
	uci commit 3ginfo
	echo "3ginfo configuration initialized"
else
	echo "3ginfo configuration already exists, keeping current settings"
fi

# Initialize modemdefine config if it doesn't exist
if ! uci -q show modemdefine >/dev/null 2>&1; then
	echo "Initializing modemdefine configuration..."
	touch /etc/config/modemdefine
	uci commit modemdefine
	echo "modemdefine configuration initialized"
else
	echo "modemdefine configuration already exists, keeping current settings"
fi

# Clear LuCI cache
rm -rf /tmp/luci-indexcache 2>&1 &
rm -rf /tmp/luci-modulecache/ 2>&1 &

# This file will be deleted after first run
exit 0

