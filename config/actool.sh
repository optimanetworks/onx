#!/bin/bash

fs_loc=$(mount | grep 'on '.*'/ ' | awk '{print $1}')
boot_dev=$( eval $(lsblk -oMOUNTPOINT,PKNAME -P -M | grep 'MOUNTPOINT="/"'); echo $PKNAME | if [[ $PKNAME == *"nvme"* ]]; then sed 's/p[0-9]*$//'; elif [[ $PKNAME == *"sd"* ]]; then sed 's/[0-9]*$//'; elif [[ $PKNAME == *"mmcblk"* ]]; then sed 's/p[0-9]*$//'; fi )
fstab_o=$(grep '/dev/.* / ext4' /etc/fstab)
fstab_n="${fstab_o/defaults/defaults,data=journal}"
# Text Colors
RES='\033[0m'; RED='\033[00;31m'; GRE='\033[00;32m'; BLU='\033[00;34m'; YEL='\033[00;93m'
# Unicode Characters
checkmark="${GRE}\U2714${RES}"; crossmark="${RED}\U2716${RES}"

check_privileges () {
	# Check if the script is ran as root, abort if not the case.
	if (( EUID != 0 )); then
		msg ERROR "This script must be ran as root."; exit 1
	fi
}

msg () {
	case $1 in
		OK) echo -e "[$checkmark] $2";;
		NOK) echo -e "[$crossmark] $2";;
	esac
}

yesno () {
	# Simple text-based yes/no prompt.
	local confirm
	until [ "$confirm" == [YyNn] ]; do
		read -p "$1" -n2 confirm
		case $confirm in
			[Yy]) return 0;;
			[Nn]) return 1;;
			*) echo "Invalid input, try again.";;
		esac
	done
}

check_privileges
clear
echo -e "Old /etc/fstab entry:"
echo -e "${YEL}$fstab_o${RES}"
echo -e ""
echo -e "New /etc/fstab entry:"
echo -e ""
echo -e "${GRE}$fstab_n${RES}"
yesno "Continue? (Y/N): " || exit 0
clear
sed -i 's|'"$fstab_o"'|'"$fstab_n"'|' /etc/fstab && msg OK "Updated /etc/fstab entry." || msg NOK "Failed to update /etc/fstab entry."
hdparm -W 0 /dev/$boot_dev && msg OK "Turned off write caching on /dev/$boot_dev." || msg NOK "Failed to turn off write caching on /dev/$boot_dev."
tune2fs $fs_loc -o journal_data && msg OK "Turned on data journalling on $fs_loc." || msg NOK "Failed to turn on data journalling on $fs_loc."
yesno "System needs to reboot. Reboot now? (Y/N): " || exit 0
/sbin/shutdown -r now
exit 0