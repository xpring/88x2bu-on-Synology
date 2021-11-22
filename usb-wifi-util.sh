#!/bin/sh
# Copyright (c) 2000-2011 Synology Inc. All rights reserved.

WIRELESS_INFO="/tmp/wireless.info"
WIRELESS_AP_CONF="/usr/syno/etc/wireless_ap.conf"
WIRELESS_MODULE="crypto_algapi ctr ccm gcm seqiv ghash-generic ipv6 rfkill led-class compat compat_firmware_class arc4 cfg80211 mac80211 kfifo"
RT2X00_MODULES="${WIRELESS_MODULE} rt2x00lib rt2800lib rt2x00usb rt2800usb"
RTL8187_MODULES="${WIRELESS_MODULE} eeprom_93cx6 rtl8187"
RTL8188EU_MODULES="${WIRELESS_MODULE} 8188eu"
RTL88x2BU_MODULES="${WIRELESS_MODULE} 88x2bu"
ATH_MODULES="ath"
CARL9170_MODULES="${WIRELESS_MODULE} ${ATH_MODULES} carl9170"
ATH9K_MODULES="${WIRELESS_MODULE} ${ATH_MODULES} ath9k_hw ath9k_common ath9k_htc ath9k"
ZD1211RW_MODULES="${WIRELESS_MODULE} zd1211rw"
RTL8192CU_MODULES="${WIRELESS_MODULE} rtlwifi rtl8192c-common rtl_usb rtl8192cu"
COMPAT_MODULES="rfkill led-class compat cfg80211"
BRCM80211_MODULES="${WIRELESS_MODULE} brcmutil brcmfmac"
R8712U_MODULES="r8712u"
RTL8812AU_MODULES="${COMPAT_MODULES} 8812au"
RTL8821AU_MODULES="${COMPAT_MODULES} 8821au"
PPPOE_RELAY_SCRIPT="/usr/syno/share/pppoerelay/scripts/pppoerelay.sh"
PLATFORM=`/bin/uname -m`
KERNEL_VERSION=`/bin/uname -r | /usr/bin/cut -d'.' -f1-2`
WIRELESS_HANDLER_LOCK="/tmp/lock/lock_wireless_plug"
SZF_IPTABLES_TOOL="/usr/syno/bin/iptablestool"

insert_modules() {
	local mode=$1
	local ap_mod=$2
	local client_mod=$3
	local busnum=$4

	local input_modules=
	local selected_modules=

	if [ "$mode" = "client" ]; then
		input_modules=$client_mod
	else
		input_modules=$ap_mod
	fi
	select_modules "${input_modules}"
	selected_modules=$MODULE_FILES

	for mod in ${selected_modules}; do
		if [ -f /lib/modules/${mod}.ko ]; then
			$SZF_IPTABLES_TOOL --insmod usb.wireless.${busnum} ${mod}.ko
		else
			echo "Modules ${mod} non-exists in /lib/modules/" >> /tmp/usbdebug
		fi
	done
}

reverse_modlist() {
	local modules=$1
	local mod
	local ret=""

	for mod in $modules; do
		ret="$mod $ret"
	done

	echo $ret
}

do_exception_for_8712u_x86() {
	local recordfile='/tmp/iptables_serv_mod_map'
	local using8712_count=`/bin/cat /tmp/wireless.info* | grep rtl8712 | wc -l`

	if [ "${PLATFORM}" != "x86_64"  ]; then
		return
	fi
	if [ 0 != $using8712_count ]; then
		return
	fi

	/bin/sed -i /^8712u=.*/d ${recordfile}
	/sbin/rmmod r8712u
}

remove_modules() {
	local mode=$1
	local ap_mod=$2
	local client_mod=$3
	local busnum=$4

	local input_modules=
	local reverse_modules=

	if [ "$mode" = "client" ]; then
		input_modules=$client_mod
	else
		input_modules=$ap_mod
	fi

	select_modules "${input_modules}"
	reverse_modules=`reverse_modlist "$MODULE_FILES"`

	for mod in ${reverse_modules}; do
		case "${mod}" in
			8712u)
				do_exception_for_8712u_x86
			;;
			*)
				$SZF_IPTABLES_TOOL --rmmod usb.wireless.${busnum} ${mod//-/_}.ko
			;;
		esac
	done
}

select_modules () {
	local modules=$1
	MODULE_FILES=

	case "$modules" in
		rt2870sta|rt3070sta|rt5370sta)
			modules=${modules}
			;;
		8712u|8192cu)
			modules="${COMPAT_MODULES} ${modules}"
			;;
		rt2x00)
			modules=${RT2X00_MODULES}
			;;
		rtl8192cu)
			modules=${RTL8192CU_MODULES}
			;;
		rtl8187)
			modules=${RTL8187_MODULES}
			;;
		rtl8188eu)
			modules=${RTL8188EU_MODULES}
			;;
		rtl8712)
			modules="${COMPAT_MODULES} ${R8712U_MODULES}"
			;;
		rtl8812au)
			modules="${RTL8812AU_MODULES}"
			;;
		88x2bu)
		    modules="${RTL88x2BU_MODULES}"
			;;
		rtl8821au)
			modules="${RTL8821AU_MODULES}"
			;;
		carl9170)
			modules=${CARL9170_MODULES}
			;;
		ath9k)
			modules=${ATH9K_MODULES}
			;;
		zd1211rw)
			modules=${ZD1211RW_MODULES}
			;;
		brcm80211)
			modules=${BRCM80211_MODULES}
			;;
		*)
			echo "Failed to search the suitable modules with vendor[${usb_vendor}] and product[${usb_product}]" >> /tmp/usbdebug
			return;
			;;
	esac

	MODULE_FILES=${modules}
}

remove_info_from_tmp () {
	local infofile=${WIRELESS_INFO}${BUSNAME}
	SKIP_REMOVE=0

	if [ ! -f ${infofile} ]; then
		SKIP_REMOVE=1
		return;
	fi

	/bin/rm ${infofile}
	echo "Remove file [${infofile}]" >> /tmp/usbdebug
}

write_info_to_tmp () {
	local infofile=${WIRELESS_INFO}${BUSNAME}
	SKIP_INSERT=0

	if [ -f "${infofile}" ]; then
		echo "${infofile} exist " >> /tmp/usbdebug
		SKIP_INSERT=1
		return;
	fi

	echo "PRODUCT=${PRODUCT}" > ${infofile}
	echo "AP_SUPPORT=${AP_SUPPORT}" >> ${infofile}
	echo "USB_PRODUCT=${usb_product}" >> ${infofile}
	echo "USB_VENDOR=${usb_vendor}" >> ${infofile}
	echo "CLIENT_MODULE=${CLIENT_MODULE}" >> ${infofile}
	echo "AP_MODULE=${AP_MODULE}" >> ${infofile}
	echo "DEVPATH=${DEVPATH}" >> ${infofile}
	echo "BUSNAME=${BUSNAME}" >> ${infofile}
}

start_wifidaemon () {
	# if still booting, synowifid will start at /etc/init/synowifid-handler.conf
	if ! /usr/syno/bin/synobootseq --is-ready; then
		return;
	fi

	/usr/syno/etc/wifi/wireless_tool.sh link_conf
	/usr/syno/sbin/synoservice --start synowifid
}

# after the wifi driver is inserted, wlan interface will need some time to pop out
# if the wifi daemon start in this interval time, might cannot get any wlan interface
wait_interface_built () {
	local max_counter=10
	local cnt=0
	local wlandir="/sys/${DEVPATH}/net/"
	local ifcnt=0

	while [ $max_counter -gt $cnt ]
	do
		# ex: check /sys//devices/pci0000:01/0000:01:01.0/usb2/2-1/2-1:1.0/net/, should have wlan0
		ifcnt=`/bin/ls $wlandir | /bin/grep -c wlan`

		echo "wait for wlan is ready, sleep $cnt" >> /tmp/usbdebug
		# might more than 1, ex: mon.wlan0 wlan0
		if [ 1 -le $ifcnt ]; then
			echo "wlan is ready!" >> /tmp/usbdebug
			break;
		fi

		cnt=$(( $cnt + 1 ))
		sleep 1
	done

	if [ $max_counter -le $cnt ]; then
		echo "timeout on waiting for wlan ready" >> /tmp/usbdebug
	fi
}

plug_in_usb_wireless () {
	local topology=`/bin/get_key_value /etc/synoinfo.conf net_topology`
	local mode=""
	local ready=""

	write_info_to_tmp
	if [ 1 == $SKIP_INSERT ]; then
		return
	fi

	if [ "x${topology}" = "xclient" -o "x${topology}" = "x" ]; then
		mode="client"
	else
		mode="ap"
	fi

	echo "Enable ${mode}-mode of wireless dongle" >> /tmp/usbdebug
	insert_modules "${mode}" "${AP_MODULE}" "${CLIENT_MODULE}" "${BUSNAME}"

	wait_interface_built

	ready=`/usr/syno/bin/synowireless --is-server-ready`
	if [ "x${ready}" = "x1" ]; then
		/usr/syno/bin/synowireless --refresh-wlan-status
	else
		start_wifidaemon
	fi
}

#FIXME hotplug event has chance to go into this function more than once
plug_in_usb_wireless_lock () {
	[ ! -d /tmp/lock ] && /bin/mkdir /tmp/lock
	(flock -x 666
		plug_in_usb_wireless
	) 666>${WIRELESS_HANDLER_LOCK}
}

plug_out_single_device () {
	local topology=`/bin/get_key_value /etc/synoinfo.conf net_topology`
	local mode=""
	local adapter_list=""

	remove_info_from_tmp
	if [ 1 == $SKIP_REMOVE ]; then
		return
	fi

	if [ "x${topology}" = "xclient" -o "x${topology}" = "x" ]; then
		mode="client"
	else
		mode="ap"
	fi

	remove_modules "${mode}" "${AP_MODULE}" "${CLIENT_MODULE}" "${BUSNAME}"

	/usr/syno/bin/synowireless --refresh-wlan-status

	adapter_list=`/usr/syno/bin/synowireless --get-adapter-list`
	if [ "${adapter_list}" = "null" ]; then
			/usr/syno/sbin/synoservice --stop synowifid
		if [ "${topology}" = "router" ]; then
			/etc/rc.network stop-bridge-interface lbr0
		elif [ "${topology}" = "bridge" ]; then
			/etc/rc.network stop-bridge-interface br0
		fi
	fi
}

# mainly used by HA
plug_out_all_device () {
	local topology=`/bin/get_key_value /etc/synoinfo.conf net_topology`
	local mode=""
	local ready=""
	local adapter_list=""

	if [ "x${topology}" = "xclient" -o "x${topology}" = "x" ]; then
		mode="client"
	else
		mode="ap"
	fi

	for eachinfo in `/bin/ls ${WIRELESS_INFO}*`; do
		AP_MODULE=`get_key_value ${eachinfo} AP_MODULE`
		CLIENT_MODULE=`get_key_value ${eachinfo} CLIENT_MODULE`
		BUSNAME=`/bin/echo $eachinfo | /bin/sed 's/\/tmp\/wireless\.info//g'`
		/bin/rm $eachinfo
		remove_modules "${mode}" "${AP_MODULE}" "${CLIENT_MODULE}" "${BUSNAME}"
	done

	ready=`/usr/syno/bin/synowireless --is-server-ready`
	if [ "x${ready}" = "x1" ]; then
		/usr/syno/bin/synowireless --refresh-wlan-status
	fi

	adapter_list=`/usr/syno/bin/synowireless --get-adapter-list`
	if [ "${adapter_list}" = "null" ]; then
			/usr/syno/sbin/synoservice --stop synowifid
		if [ "${topology}" = "router" ]; then
			/etc/rc.network stop-bridge-interface lbr0
		elif [ "${topology}" = "bridge" ]; then
			/etc/rc.network stop-bridge-interface br0
		fi
	fi
}

load_all_device () {
	local topology=$1
	local mode=""
	local ready=""

	if [ "x${topology}" = "xclient" -o "x${topology}" = "x" ]; then
		mode="client"
	else
		mode="ap"
	fi

	for eachinfo in `/bin/ls ${WIRELESS_INFO}*`; do
		AP_MODULE=`get_key_value ${eachinfo} AP_MODULE`
		CLIENT_MODULE=`get_key_value ${eachinfo} CLIENT_MODULE`
		BUSNAME=`/bin/echo $eachinfo | /bin/sed 's/\/tmp\/wireless\.info//g'`
		insert_modules "${mode}" "${AP_MODULE}" "${CLIENT_MODULE}" "${BUSNAME}"
	done
}

unload_all_device () {
	local topology=$1
	local mode=""
	local ready=""

	if [ "x${topology}" = "xclient" -o "x${topology}" = "x" ]; then
		mode="client"
	else
		mode="ap"
	fi

	for eachinfo in `/bin/ls ${WIRELESS_INFO}*`; do
		AP_MODULE=`get_key_value ${eachinfo} AP_MODULE`
		CLIENT_MODULE=`get_key_value ${eachinfo} CLIENT_MODULE`
		BUSNAME=`/bin/echo $eachinfo | /bin/sed 's/\/tmp\/wireless\.info//g'`
		remove_modules "${mode}" "${AP_MODULE}" "${CLIENT_MODULE}" "${BUSNAME}"
	done
}

plug_out_usb_wireless () {
	if [ "true" == "$FORCE" ]; then
		plug_out_all_device
	else
		plug_out_single_device
	fi
}

#FIXME hotplug event has chance to go into this function more than once
plug_out_usb_wireless_lock () {
	[ ! -d /tmp/lock ] && /bin/mkdir /tmp/lock
	(flock -x 666
		plug_out_usb_wireless
	) 666>${WIRELESS_HANDLER_LOCK}
}

set_wireless_parameters () {
	usb_vendor=${SYNO_USB_VENDER}
	usb_product=${SYNO_USB_PRODUCT}
	PRODUCT=${PRODUCT}
	CLIENT_MODULE=${SYNO_USB_DRIVER}
	FORCE=${FORCE}
	AP_MODULE=
	AP_SUPPORT=
	case "${CLIENT_MODULE}" in
		rt2870sta|rt3070sta|rt5370sta)
			AP_SUPPORT="yes"
			AP_MODULE="rt2x00"
			;;
		rtl8712)
			AP_SUPPORT="no"
			if [ "${PLATFORM}" != "x86_64" -a "${PLATFORM}" != "i686" -a "${PLATFORM}" != "armv7l" \
			   -a "${PLATFORM}" != "aarch64" -a "${PLATFORM}" != "aarch32" ]; then
				CLIENT_MODULE="8712u"
			fi
			;;
		rtl8192cu)
			AP_SUPPORT="no"
			if [ "${KERNEL_VERSION}" != "4.4" ]; then
				CLIENT_MODULE="8192cu"
			fi
			;;
		rt2x00|carl9170|ath9k|zd1211rw|brcm80211)
			AP_SUPPORT="yes"
			AP_MODULE="${CLIENT_MODULE}"
			;;
		*)
			AP_SUPPORT="no"
			;;
	esac

	local _vid=`echo $PRODUCT | cut -d/ -f1 | sed 's/^0*//'`
	local _pid=`echo $PRODUCT | cut -d/ -f2 | sed 's/^0*//'`
	local _rev=`echo $PRODUCT | cut -d/ -f3 | sed 's/^0*//'`
	[ -z "$_vid" ] && _vid="0"
	[ -z "$_pid" ] && _pid="0"
	[ -z "$_rev" ] && _rev="0"
	PRODUCT=$_vid/$_pid/$_rev
	BUSNAME=`echo ${DEVICE} | sed 's/\// /g' | awk '{print $4 $5}' | sed -e 's/^[0]*//'`
	# for linux 3.10, there is no $DEVICE
	if [ -z "${BUSNAME}" ]; then
		BUSNAME=$USEC_INITIALIZED
	fi
}

runha=`/bin/get_key_value /etc/synoinfo.conf runha`

if [ "xyes" == "x$runha" ]; then
	echo "ha enabled, skip wifi dongle" >> /tmp/usbdebug
	exit;
fi

support_wireless=`/bin/get_key_value /etc.defaults/synoinfo.conf support_wireless`

if [ "xyes" != "x$support_wireless" ]; then
	echo "DS do not support wireless, skip wifi dongle" >> /tmp/usbdebug
	exit;
fi

action=$1
shift;
case $action in
	[Pp][Ll][Uu][Gg]-[Ii][Nn])
		set_wireless_parameters "$@"
		plug_in_usb_wireless
		${PPPOE_RELAY_SCRIPT} reload
		;;
	[Pp][Ll][Uu][Gg]-[Oo][Uu][Tt])
		set_wireless_parameters "$@"
		plug_out_usb_wireless
		${PPPOE_RELAY_SCRIPT} reload
		;;
	[Ll][Oo][Aa][Dd]-[Dd][Rr][Ii][Vv][Ee][Rr])
		# use by switch topology by synowifid
		load_all_device "$@"
		;;
	[Uu][Nn][Ll][Oo][Aa][Dd]-[Dd][Rr][Ii][Vv][Ee][Rr])
		# use by switch topology by synowifid
		unload_all_device "$@"
		;;
	*)
		echo "Usage: [plug-in|plug-out]"
esac

exit 0
