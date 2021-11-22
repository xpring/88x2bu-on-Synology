# 88x2bu-on-Synology
install 88x2bu USB wifi onto Synology
1. copy 88x2bu.ko into  /lib/modules/88x2bu.ko
2. chmod 644 88x2bu.ko
3. insmod /lib/modules/88x2bu.ko
4. lsusb to find the USB wifi aaaa:bbbb
5. echo "(aaaa:bbbb,rtl88x2bu)" >> /lib/udev/devicetable/usb.wifi.table
6. nano /lib/udev/script/usb-wifi-util.sh
7. Added between the other rtl-modules lines:
RTL88X2BU_MODULES="88x2bu"
and at the far bottom lines of the file under
select_modules - section
88x2bu)
modules=${RTL88X2BU_MODULES}
;;
DONE

tested on DS3615xs,DSM 6.2-23739

thx to https://github.com/cilynx/rtl88x2BU_WiFi_linux_v5.3.1_27678.20180430_COEX20180427-5959/issues/10
