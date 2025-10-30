#!/bin/sh
#
# (c) 2010-2021 Cezary Jackiewicz <cezary@eko.one.pl>
#
# (c) 2024 modified by Rafał Wabik - IceG - From eko.one.pl forum
#
# (c) 2025 modified for B312-929 mac-vlan support
#

IP=$1
[ -z "$IP" ] && exit 0
[ -e /usr/bin/wget ] || exit 0

# Get credentials from config if available
USERNAME=$(uci -q get 3ginfo.@3ginfo[0].hilink_username)
PASSWORD=$(uci -q get 3ginfo.@3ginfo[0].hilink_password)
AUTH_MODE=$(uci -q get 3ginfo.@3ginfo[0].hilink_auth_mode)
# Default to 'auto' if not set
[ -z "$AUTH_MODE" ] && AUTH_MODE="auto"

getvaluen() {
	echo $(awk -F[\<\>] '/<'$2'>/ {print $3}' /tmp/$1 | sed 's/[^0-9]//g')
}

getvaluens() {
	echo $(awk -F[\<\>] '/<'$2'>/ {print $3}' /tmp/$1 | sed 's/[^0-9-]//g')
}

getvalue() {
	echo $(awk -F[\<\>] '/<'$2'>/ {print $3}' /tmp/$1)
}

# Function to hash password for HiLink
hash_password_sha256() {
	local username="$1"
	local password="$2"
	local token="$3"
	
	# Huawei uses: base64(username + SHA256(password) + token)
	# First get SHA256 of password in uppercase hex
	local pass_hash=""
	
	if command -v sha256sum >/dev/null 2>&1; then
		pass_hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1 | tr 'a-f' 'A-F')
	elif command -v openssl >/dev/null 2>&1; then
		pass_hash=$(echo -n "$password" | openssl dgst -sha256 | cut -d' ' -f2 | tr 'a-f' 'A-F')
	else
		# No SHA256 available, return empty
		return 1
	fi
	
	# Combine username + hash + token and encode to base64
	echo -n "$username$pass_hash$token" | base64
}

# Function to perform login for B312-926/929
do_login() {
	local username="$1"
	local password="$2"
	
	# Get initial token
	/usr/bin/wget -t 5 -O /tmp/webserver-token "http://$IP/api/webserver/SesTokInfo" >/dev/null 2>&1
	local token=$(getvalue webserver-token TokInfo)
	local session=$(getvalue webserver-token SesInfo)
	
	if [ -n "$token" ] && [ -n "$username" ] && [ -n "$password" ]; then
		# Method 1: Try SHA256 hash (password_type=4)
		local pass_hash=$(hash_password_sha256 "$username" "$password" "$token")
		
		if [ -n "$pass_hash" ]; then
			local login_data="<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><Username>$username</Username><Password>$pass_hash</Password><password_type>4</password_type></request>"
			
			/usr/bin/wget -t 3 -O /tmp/login-response "http://$IP/api/user/login" \
				--header "__RequestVerificationToken: $token" \
				--header "Cookie: $session" \
				--header "Content-Type: application/xml" \
				--post-data="$login_data" >/dev/null 2>&1
			
			# Check if login was successful
			if [ -s /tmp/login-response ]; then
				if grep -q "<response>OK</response>" /tmp/login-response || ! grep -q "<error>" /tmp/login-response; then
					# Get new session after login
					/usr/bin/wget -t 5 -O /tmp/webserver-token "http://$IP/api/webserver/SesTokInfo" >/dev/null 2>&1
					session=$(getvalue webserver-token SesInfo)
					token=$(getvalue webserver-token TokInfo)
					
					if [ -n "$session" ]; then
						echo "$session"
						return 0
					fi
				fi
			fi
		fi
		
		# Method 2: Try base64 encoded password (password_type=3)
		pass_hash=$(echo -n "$password" | base64)
		local login_data="<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><Username>$username</Username><Password>$pass_hash</Password><password_type>3</password_type></request>"
		
		/usr/bin/wget -t 3 -O /tmp/login-response "http://$IP/api/user/login" \
			--header "__RequestVerificationToken: $token" \
			--header "Cookie: $session" \
			--header "Content-Type: application/xml" \
			--post-data="$login_data" >/dev/null 2>&1
		
		if [ -s /tmp/login-response ]; then
			if grep -q "<response>OK</response>" /tmp/login-response || ! grep -q "<error>" /tmp/login-response; then
				# Get new session after login
				/usr/bin/wget -t 5 -O /tmp/webserver-token "http://$IP/api/webserver/SesTokInfo" >/dev/null 2>&1
				session=$(getvalue webserver-token SesInfo)
				token=$(getvalue webserver-token TokInfo)
				
				if [ -n "$session" ]; then
					echo "$session"
					return 0
				fi
			fi
		fi
	fi
	
	return 1
}

cookie=$(mktemp)

# Try different authentication methods
authenticated=0

# Method 1: Try getting token without authentication first (fastest)
/usr/bin/wget -t 5 -O /tmp/webserver-token "http://$IP/api/webserver/token" >/dev/null 2>&1
token=$(getvaluen webserver-token token)
if [ -n "$token" ]; then
	# Test if this token works
	/usr/bin/wget -t 2 -O /tmp/test-auth "http://$IP/api/monitoring/status" --header "__RequestVerificationToken: $token" >/dev/null 2>&1
	if ! grep -q "100003" /tmp/test-auth 2>/dev/null && ! grep -q "<error>" /tmp/test-auth 2>/dev/null; then
		authenticated=1
	fi
fi

# Method 2: Try SesTokInfo without login
if [ $authenticated -eq 0 ]; then
	/usr/bin/wget -t 5 -O /tmp/webserver-token "http://$IP/api/webserver/SesTokInfo" >/dev/null 2>&1
	sesinfo=$(getvalue webserver-token SesInfo)
	token=$(getvalue webserver-token TokInfo)
	if [ -n "$sesinfo" ] && [ -n "$token" ]; then
		# Test if this works
		/usr/bin/wget -t 2 -O /tmp/test-auth "http://$IP/api/monitoring/status" \
			--header "__RequestVerificationToken: $token" \
			--header "Cookie: $sesinfo" >/dev/null 2>&1
		if ! grep -q "100003" /tmp/test-auth 2>/dev/null && ! grep -q "<error>" /tmp/test-auth 2>/dev/null; then
			authenticated=1
		fi
	fi
fi

# Method 3: Try login with username and password if provided
if [ $authenticated -eq 0 ] && [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
	sesinfo=$(do_login "$USERNAME" "$PASSWORD")
	if [ -n "$sesinfo" ]; then
		authenticated=1
		token=$(getvalue webserver-token TokInfo)
	fi
fi

# Method 4: Try default credentials based on auth mode
if [ $authenticated -eq 0 ] && [ "$AUTH_MODE" = "auto" ]; then
	# Auto mode: try default credentials if manual credentials not configured or failed
	if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
		# No manual credentials configured, try default admin/admin
		sesinfo=$(do_login "admin" "admin")
		if [ -n "$sesinfo" ]; then
			authenticated=1
			token=$(getvalue webserver-token TokInfo)
		fi
	fi
fi
# If AUTH_MODE = "manual", skip default credentials attempt - only use configured credentials

# Method 5: Try cookie-based authentication
if [ $authenticated -eq 0 ]; then
	/usr/bin/wget -q -O /dev/null --keep-session-cookies --save-cookies $cookie "http://$IP/html/home.html" 2>/dev/null
	if [ -s "$cookie" ]; then
		# Test if cookie works
		/usr/bin/wget -t 2 -O /tmp/test-auth "http://$IP/api/monitoring/status" --load-cookies=$cookie >/dev/null 2>&1
		if ! grep -q "100003" /tmp/test-auth 2>/dev/null && ! grep -q "<error>" /tmp/test-auth 2>/dev/null; then
			authenticated=1
		fi
	fi
fi

# Log authentication status
if [ $authenticated -eq 0 ]; then
	logger -t "3ginfo-hilink" "Warning: Authentication to HiLink modem at $IP failed. Please configure credentials in LuCI: System > 3ginfo-lite > Configuration > HiLink authentication tab"
	# Still continue to try fetching data - some endpoints might work without auth
fi

# Fetch modem information
files="device/signal monitoring/status net/current-plmn net/signal-para device/information device/basic_information"
for f in $files; do
	nf=$(echo $f | sed 's!/!-!g')
	success=0
	
	# Try with token + session if both available
	if [ -n "$token" ] && [ -n "$sesinfo" ]; then
		/usr/bin/wget -t 3 -O /tmp/$nf "http://$IP/api/$f" \
			--header "__RequestVerificationToken: $token" \
			--header "Cookie: $sesinfo" >/dev/null 2>&1
		if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
			success=1
		fi
	fi
	
	# Try with token only
	if [ $success -eq 0 ] && [ -n "$token" ]; then
		/usr/bin/wget -t 3 -O /tmp/$nf "http://$IP/api/$f" \
			--header "__RequestVerificationToken: $token" >/dev/null 2>&1
		if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
			success=1
		fi
	fi
	
	# Try with session only
	if [ $success -eq 0 ] && [ -n "$sesinfo" ]; then
		/usr/bin/wget -t 3 -O /tmp/$nf "http://$IP/api/$f" \
			--header "Cookie: $sesinfo" >/dev/null 2>&1
		if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
			success=1
		fi
	fi
	
	# Try with cookie
	if [ $success -eq 0 ]; then
		/usr/bin/wget -t 3 -O /tmp/$nf "http://$IP/api/$f" \
			--load-cookies=$cookie >/dev/null 2>&1
		if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
			success=1
		fi
	fi
	
	# If still failing, try without any auth (some endpoints don't need it)
	if [ $success -eq 0 ]; then
		/usr/bin/wget -t 3 -O /tmp/$nf "http://$IP/api/$f" >/dev/null 2>&1
	fi
done

# Protocol
# Driver=qmi_wwan & Driver=cdc_mbim & Driver=cdc_ether & Driver=huawei_cdc_ncm
PV=$(cat /sys/kernel/debug/usb/devices)
PVCUT=$(echo $PV | awk -F 'Vendor=12d1 ProdID=' '{print $2}' | cut -c-1108)
if echo "$PVCUT" | grep -q "Driver=qmi_wwan"
then
    PROTO="qmi"
elif echo "$PVCUT" | grep -q "Driver=cdc_mbim"
then
    PROTO="mbim"
elif echo "$PVCUT" | grep -q "Driver=cdc_ether"
then
    PROTO="ecm"
elif echo "$PVCUT" | grep -q "Driver=huawei_cdc_ncm"
then
    PROTO="ncm"
fi

RSSI=$(getvalue device-signal rssi)
if [ "$RSSI" == "&lt;=-113dBm" ]; then
	RSSI=
else
	RSSI=$(echo "$RSSI" | sed 's/[^0-9]//g')
fi
if [ -n "$RSSI" ]; then
	CSQ=$(((-1*RSSI + 113)/2))
	CSQ_PER=$(($CSQ * 100/31))
else
	CSQ_PER=$(getvaluen monitoring-status SignalStrength)
	if [ -z "$CSQ_PER" ]; then
		CSQ_PER=$(getvaluen monitoring-status SignalIcon)
		if [ -n "$CSQ_PER" ]; then
			CSQ_PER=$((($CSQ_PER * 20) - 19))
		fi
	fi
	if [ -n "$CSQ_PER" ]; then
		CSQ=$((($CSQ_PER*31)/100))
	fi
fi

MODEN=$(getvaluen monitoring-status CurrentNetworkType)
case $MODEN in
	0)  MODE="NOSERVICE";;
	1)  MODE="GSM";;
	2)  MODE="GPRS";;
	3)  MODE="EDGE";;
	4)  MODE="WCDMA";;
	5)  MODE="HSDPA";;
	6)  MODE="HSUPA";;
	7)  MODE="HSPA";;
	8)  MODE="TDSCDMA";;
	9)  MODE="HSPA+";;
	10) MODE="EVDO rev. 0";;
	11) MODE="EVDO rev. A";;
	12) MODE="EVDO rev. B";;
	13) MODE="1xRTT";;
	14) MODE="UMB";;
	15) MODE="1xEVDV";;
	16) MODE="3xRTT";;
	17) MODE="HSPA+64QAM";;
	18) MODE="HSPA+MIMO";;
	19) MODE="LTE";;
	21) MODE="IS95A";;
	22) MODE="IS95B";;
	23) MODE="CDMA1x";;
	24) MODE="EVDO rev. 0";;
	25) MODE="EVDO rev. A";;
	26) MODE="EVDO rev. B";;
	27) MODE="Hybrydowa CDMA1x";;
	28) MODE="Hybrydowa EVDO rev. 0";;
	29) MODE="Hybrydowa EVDO rev. A";;
	30) MODE="Hybrydowa EVDO rev. B";;
	31) MODE="EHRPD rev. 0";;
	32) MODE="EHRPD rev. A";;
	33) MODE="EHRPD rev. B";;
	34) MODE="Hybrydowa EHRPD rev. 0";;
	35) MODE="Hybrydowa EHRPD rev. A";;
	36) MODE="Hybrydowa EHRPD rev. B";;
	41) MODE="WCDMA (UMTS)";;
	42) MODE="HSDPA";;
	43) MODE="HSUPA";;
	44) MODE="HSPA";;
	45) MODE="HSPA+";;
	46) MODE="DC-HSPA+";;
	61) MODE="TD SCDMA";;
	62) MODE="TD HSDPA";;
	63) MODE="TD HSUPA";;
	64) MODE="TD HSPA";;
	65) MODE="TD HSPA+";;
	81) MODE="802.16E";;
	101) MODE="LTE";;
	*)  MODE="-";;
esac

if [ "x$MODE" = "xLTE" ] || [ "x$MODE" = "xNOSERVICE" ]; then
	# Try multiple sources for RSRP
	RSRP=$(getvaluens device-signal rsrp)
	[ -z "$RSRP" ] && RSRP=$(getvaluens device-signal Rsrp)
	[ -z "$RSRP" ] && RSRP=$(getvaluens monitoring-status rsrp)
	[ -z "$RSRP" ] && RSRP=$(getvaluens net-signal-para rsrp)
	
	# Try multiple sources for SINR
	SINR=$(getvaluens device-signal sinr)
	[ -z "$SINR" ] && SINR=$(getvaluens device-signal Sinr)
	[ -z "$SINR" ] && SINR=$(getvaluens monitoring-status sinr)
	[ -z "$SINR" ] && SINR=$(getvaluens net-signal-para sinr)
	
	# Try multiple sources for RSRQ
	RSRQ=$(getvaluens device-signal rsrq)
	[ -z "$RSRQ" ] && RSRQ=$(getvaluens device-signal Rsrq)
	[ -z "$RSRQ" ] && RSRQ=$(getvaluens monitoring-status rsrq)
	[ -z "$RSRQ" ] && RSRQ=$(getvaluens net-signal-para rsrq)
fi

# Get RSSI for all modes
if [ -z "$RSSI" ]; then
	RSSI=$(getvaluens device-signal Rssi)
	[ -z "$RSSI" ] && RSSI=$(getvaluens monitoring-status rssi)
	[ -z "$RSSI" ] && RSSI=$(getvaluens net-signal-para rssi)
fi

MODEL=$(getvalue device-information DeviceName)
if [ -n "$MODEL" ]; then
	class=$(getvalue device-information Classify)
	MODEL="Huawei $MODEL ($class)"
else
	MODEL=$(getvalue device-basic_information devicename)
	class=$(getvalue device-basic_information classify)
	[ -n "$MODEL" ] && MODEL="Huawei $MODEL ($class)"
fi

FW=$(getvalue device-information SoftwareVersion)
if [ -n "$FW" ]; then
	rev=$(getvalue device-information HardwareVersion)
	FW="$rev / $FW"
fi

if [ -z "$FW" ]
then
	FW='-'
fi

if [ -z "$TEMP" ]
then
	TEMP='-'
fi

COPSA=$(getvaluen net-current-plmn Numeric)
COPSB=$(echo "${COPSA}" | cut -c1-3)
COPSC=$(echo -n $COPSA | tail -c 2)
COPS_MCC="$COPSB"
COPS_MNC="$COPSC"

COPS=$(getvalue net-current-plmn ShortName)

if [[ $COPSA =~ ^[0-9]+$ ]]; then
	if [ -z "$COPS" ]
	then
		COPS=$(awk -F[\;] '/^'$COPSA';/ {print $3}' $RES/mccmnc.dat | xargs)
	fi
	LOC=$(awk -F[\;] '/^'$COPSA';/ {print $2}' $RES/mccmnc.dat)
fi

# operator location from temporary config
LOCATIONFILE=/tmp/location
if [ -e "$LOCATIONFILE" ]; then
	touch $LOCATIONFILE
	LOC=$(cat $LOCATIONFILE)
	if [ -n "$LOC" ]; then
		LOC=$(cat $LOCATIONFILE)
			if [[ $LOC == "-" ]]; then
				rm $LOCATIONFILE
				LOC=$(awk -F[\;] '/^'$COPSA';/ {print $2}' $RES/mccmnc.dat)
				if [ -n "$LOC" ]; then
					echo "$LOC" > /tmp/location
				fi
			else
				LOC=$(awk -F[\;] '/^'$COPSA';/ {print $2}' $RES/mccmnc.dat)
				if [ -n "$LOC" ]; then
					echo "$LOC" > /tmp/location
				fi
			fi
	fi
else
	if [[ "$COPS_MCC$COPS_MNC" =~ ^[0-9]+$ ]]; then
		if [ -n "$LOC" ]; then
			LOC=$(awk -F[\;] '/^'$COPS_MCC$COPS_MNC';/ {print $2}' $RES/mccmnc.dat)
				echo "$LOC" > /tmp/location
			else
				echo "-" > /tmp/location
		fi
	fi
fi

# Try multiple sources for LAC
LAC_HEX=$(getvalue net-signal-para Lac)
[ -z "$LAC_HEX" ] && LAC_HEX=$(getvalue net-signal-para lac)
[ -z "$LAC_HEX" ] && LAC_HEX=$(getvalue monitoring-status lac)
[ -z "$LAC_HEX" ] && LAC_HEX=$(getvalue device-signal lac)

if [ -z "$LAC_HEX" ]; then
	/usr/bin/wget -t 3 -O /tmp/add-param "http://$IP/config/deviceinformation/add_param.xml" > /dev/null 2>&1
	LAC_HEX=$(getvalue add-param lac)
	rm /tmp/add-param 2>/dev/null
fi

# Convert LAC to hex if it's decimal
if [ -n "$LAC_HEX" ] && [ "$LAC_HEX" != "-" ]; then
	# Check if it's already hex (contains A-F) or decimal
	if ! echo "$LAC_HEX" | grep -qi '[a-f]'; then
		# It's decimal, convert to hex
		LAC_DEC=$LAC_HEX
		LAC_HEX=$(printf %X $LAC_DEC 2>/dev/null)
	fi
fi

if [ -z "$LAC_HEX" ] || [ "$LAC_HEX" = "0" ]
then
	LAC_HEX='-'
fi

# Try multiple sources for CID
CID_HEX=$(getvalue net-signal-para CellID)
[ -z "$CID_HEX" ] && CID_HEX=$(getvalue net-signal-para cellid)
[ -z "$CID_HEX" ] && CID_HEX=$(getvalue monitoring-status cellid)
[ -z "$CID_HEX" ] && CID_HEX=$(getvalue device-signal cell_id)

# If CID is in decimal, convert to hex
if [ -n "$CID_HEX" ] && [ "$CID_HEX" != "-" ]; then
	if ! echo "$CID_HEX" | grep -qi '[a-f]'; then
		# It's decimal
		CID_DEC=$CID_HEX
		CID_HEX=$(printf %X $CID_DEC 2>/dev/null)
	fi
fi

if [ -z "$CID_HEX" ]
then
	CID_HEX='-'
fi

if [ -z "$CID_DEC" ]
then
	if [ -n "$CID_HEX" ] && [ "$CID_HEX" != "-" ]; then
		CID_DEC=$(echo $((0x$CID_HEX)))
	else
		CID_DEC='-'
	fi
fi

# Get additional information - try to fetch more endpoints
# Get device info for IMEI, IMSI, ICCID and cell info
for endpoint in "device/information" "device/basic_information" "net/current-plmn" "monitoring/status" "monitoring/traffic-statistics" "net/cell-info"; do
	nf=$(echo $endpoint | sed 's!/!-!g')
	if [ ! -s "/tmp/$nf" ] || grep -q "100003" /tmp/$nf 2>/dev/null; then
		success=0
		# Try with token + session
		if [ -n "$token" ] && [ -n "$sesinfo" ]; then
			/usr/bin/wget -t 2 -O /tmp/$nf "http://$IP/api/$endpoint" \
				--header "__RequestVerificationToken: $token" \
				--header "Cookie: $sesinfo" >/dev/null 2>&1
			if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
				success=1
			fi
		fi
		# Try with token only
		if [ $success -eq 0 ] && [ -n "$token" ]; then
			/usr/bin/wget -t 2 -O /tmp/$nf "http://$IP/api/$endpoint" \
				--header "__RequestVerificationToken: $token" >/dev/null 2>&1
			if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
				success=1
			fi
		fi
		# Try with session only
		if [ $success -eq 0 ] && [ -n "$sesinfo" ]; then
			/usr/bin/wget -t 2 -O /tmp/$nf "http://$IP/api/$endpoint" \
				--header "Cookie: $sesinfo" >/dev/null 2>&1
			if [ -s "/tmp/$nf" ] && ! grep -q "100003" /tmp/$nf 2>/dev/null; then
				success=1
			fi
		fi
		# Try with cookie
		if [ $success -eq 0 ]; then
			/usr/bin/wget -t 2 -O /tmp/$nf "http://$IP/api/$endpoint" \
				--load-cookies=$cookie >/dev/null 2>&1
		fi
	fi
done

# Extract IMEI
NR_IMEI=$(getvalue device-information Imei)
[ -z "$NR_IMEI" ] && NR_IMEI=$(getvalue device-basic_information Imei)

# Extract IMSI
NR_IMSI=$(getvalue device-information Imsi)
[ -z "$NR_IMSI" ] && NR_IMSI=$(getvalue device-basic_information Imsi)

# Extract ICCID
NR_ICCID=$(getvalue device-information Iccid)
[ -z "$NR_ICCID" ] && NR_ICCID=$(getvalue monitoring-status Iccid)
[ -z "$NR_ICCID" ] && NR_ICCID=$(getvalue device-basic_information Iccid)

# Get PCI (Physical Cell ID) - try multiple variations
PCI=$(getvalue device-signal pci)
[ -z "$PCI" ] && PCI=$(getvalue device-signal Pci)
[ -z "$PCI" ] && PCI=$(getvalue device-signal PCI)
[ -z "$PCI" ] && PCI=$(getvalue device-signal PhysCellId)
[ -z "$PCI" ] && PCI=$(getvalue device-signal physcellid)
[ -z "$PCI" ] && PCI=$(getvalue net-signal-para pci)
[ -z "$PCI" ] && PCI=$(getvalue net-signal-para Pci)
[ -z "$PCI" ] && PCI=$(getvalue net-cell-info pci)
[ -z "$PCI" ] && PCI=$(getvalue net-cell-info PhysCellId)
[ -z "$PCI" ] && PCI=$(getvalue monitoring-status pci)
[ -z "$PCI" ] && PCI=$(getvaluen device-signal pci)
[ -z "$PCI" ] && PCI=$(getvaluen net-signal-para pci)
[ -z "$PCI" ] && PCI=$(getvaluen net-cell-info pci)

# Get EARFCN - try multiple variations
EARFCN=$(getvalue device-signal earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue device-signal Earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue device-signal EARFCN)
[ -z "$EARFCN" ] && EARFCN=$(getvalue device-signal dlEarfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue device-signal DlEarfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue device-signal dlfrequency)
[ -z "$EARFCN" ] && EARFCN=$(getvalue net-signal-para earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue net-signal-para Earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue net-cell-info earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvalue net-cell-info dlfrequency)
[ -z "$EARFCN" ] && EARFCN=$(getvalue monitoring-status earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvaluen device-signal earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvaluen net-signal-para earfcn)
[ -z "$EARFCN" ] && EARFCN=$(getvaluen net-cell-info earfcn)

# Get Band - try multiple variations
PBAND=$(getvalue net-signal-para band)
[ -z "$PBAND" ] && PBAND=$(getvalue net-signal-para Band)
[ -z "$PBAND" ] && PBAND=$(getvalue device-signal band)
[ -z "$PBAND" ] && PBAND=$(getvalue device-signal Band)
[ -z "$PBAND" ] && PBAND=$(getvalue device-signal BAND)
[ -z "$PBAND" ] && PBAND=$(getvalue device-signal lteband)
[ -z "$PBAND" ] && PBAND=$(getvalue device-signal LteBand)
[ -z "$PBAND" ] && PBAND=$(getvalue device-signal workmode)
[ -z "$PBAND" ] && PBAND=$(getvalue net-cell-info band)
[ -z "$PBAND" ] && PBAND=$(getvalue net-cell-info Band)
[ -z "$PBAND" ] && PBAND=$(getvalue monitoring-status band)
[ -z "$PBAND" ] && PBAND=$(getvaluen device-signal band)
[ -z "$PBAND" ] && PBAND=$(getvaluen net-signal-para band)
[ -z "$PBAND" ] && PBAND=$(getvaluen net-cell-info band)

# Registration status from monitoring/status
REG_STATUS=$(getvalue monitoring-status ServiceStatus)
case "$REG_STATUS" in
	"2") REG="1";; # Service available
	*) 
		# Try to determine from other indicators
		if [ -n "$COPS" ] && [ "$COPS" != "-" ] && [ -n "$MODE" ] && [ "$MODE" != "-" ] && [ "$MODE" != "NOSERVICE" ]; then
			REG="1" # Registered
		else
			REG="-"
		fi
		;;
esac

# Try to get LAC/CID from alternative sources if still empty
if [ "$LAC_HEX" = "-" ]; then
	LAC_HEX=$(getvalue monitoring-status lac)
fi

if [ "$CID_HEX" = "-" ]; then
	CID_HEX=$(getvalue monitoring-status cellid)
	if [ -n "$CID_HEX" ] && [ "$CID_HEX" != "-" ]; then
		CID_DEC=$CID_HEX
		CID_HEX=$(printf %X $CID_DEC)
	fi
fi

rm $cookie
break

