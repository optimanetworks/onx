#!/bin/bash

RESTORE='\033[0m'
RED='\033[00;31m'
GREEN='\033[00;32m'
BLUE='\033[00;34m'
YELLOW='\033[00;93m'
LIGHTGRAY='\033[00;37m'

INFO="[${LIGHTGRAY}I${RESTORE}]"
WARNING="[${YELLOW}W${RESTORE}]"
ERROR="[${RED}E${RESTORE}]"

unset disk_boot
unset disk_list

log_file="/var/log/diskconfig.log"
disk_boot=$( eval $(lsblk -oMOUNTPOINT,PKNAME -P -M | grep 'MOUNTPOINT="/"'); echo $PKNAME | if [[ $PKNAME == *"nvme"* ]]; then sed 's/p[0-9]*$//'; elif [[ $PKNAME == *"sd"* ]]; then sed 's/[0-9]*$//'; elif [[ $PKNAME == *"mmcblk"* ]]; then sed 's/p[0-9]*$//'; fi )
disk_list=($(lsblk -Snpo NAME | grep -v "$disk_boot"))

apt install -qqy jo jq smartmontools

exec > "$log_file" 2>&1

echo -e "=== Diskconfig started at $(date '+%F %T') ==="
echo -e ""$INFO" "$disk_boot" is the boot device."

if [ ${#disk_list[@]} -eq 0 ]; then
	clear
	echo -e ""$ERROR" No storage disks were detected, please insert disk(s) and try again."
	exit 1 
fi

echo -e ""$INFO" Disks detected: "${disk_list[@]}""

marked_list=()

for disk in ${disk_list[@]}; do
	if $(grep /dev/"$disk"1 ); then
		echo -e ""$INFO" "$disk" contains at least one partition."
		part_uuid=$(blkid -s UUID -o value "$disk"1)
		echo -e ""$INFO" "$disk"1 has partition UUID ${GREEN}"$part_uuid"${RESTORE}."
		if $(grep "$part_uuid" /etc/fstab); then
			echo -e ""$INFO" partition UUID ${GREEN}"$part_uuid"${RESTORE} was found in /etc/fstab." 
		else
			echo -e ""$INFO" partition UUID ${YELLOW}"$part_uuid"${RESTORE} was NOT found in /etc/fstab and will be marked."
			marked_list+="$disk"
		fi
	else
		echo -e ""$INFO" "$disk" does not contain a partition and will be marked."
		marked_list+="$disk"
	fi
done

echo -e "=== Marked Disks ==="
for disk in ${marked_list[@]}; do
	echo -e ""$disk" - "$(smartctl -i --json $disk | jq -r '.model_name')" "$(lsblk $disk -Snlpo SIZE)" $(if $(smartctl -H --json $disk | jq '.smart_status.passed'); then echo "${GREEN}HEALTHY${RESTORE}"; else echo "${RED}NOT HEALTHY${RESTORE}"; fi)"
done

read -p "Do you wish to wipe all marked disks and configure them automatically? Any data on the disks will be lost. (Y/N) " -n 1 -r
if [[ $REPLY =~ ^[^Yy]$ ]]; then
	for disk in ${marked_list[@]}; do
		wipefs -a $disk && echo -e ""$INFO" Successfully wiped "$disk"." || echo -e ""$ERROR" Failed to wipe "$disk"."
		parted mktable gpt && echo -e ""$INFO" Successfully created partition table on "$disk"." || echo -e  ""$ERROR" Failed create partition table on "$disk"."
		parted mkpart -a optimal primary 0% 100% && echo -e ""$INFO" Successfully created partition on "$disk"." || echo -e  ""$ERROR" Failed to create partition on "$disk"."
		mkfs.ext4 -F "$disk"1 && echo -e  ""$INFO" Successfully wrote filesystem to "$disk"." || echo -e  ""$ERROR" Failed to write filesystem to "$disk"."
		part_uuid="$(blkid -s UUID -o value "$disk"1)"
		mkdir -p /mnt/Media/"$part_uuid" && echo -e ""$INFO" Successfully created directory /mnt/Media/"$part_uuid"." || echo -e ""$ERROR" Failed to create directory /mnt/Media/"$part_uuid"."
		echo -e "UUID=\""$part_uuid"\"\t/mnt/Media/"$part_uuid"\text4\terrors=continue,nofail\t0\t2" >> /etc/fstab
		mount /mnt/Media/"$part_uuid" && echo -e ""$INFO" Successfully mounted partition to /mnt/Media/"$part_uuid"." || echo -e ""$ERROR" Failed to mount partition to /mnt/Media/"$part_uuid"."
	done
else
	echo -e ""$INFO" Aborting script."
fi

echo -e "=== Diskconfig ended at $(date +%F %T) ===\n"
exit 0