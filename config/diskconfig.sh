#!/bin/bash

INFO="\n[INFO]\t"
WARNING="\n[WARN]\t"
ERROR="\n[ERR]\t"

unset disk_boot
unset disk_list

log_file="/var/log/diskconfig.log"
disk_boot=$( eval $(lsblk -oMOUNTPOINT,PKNAME -P -M | grep 'MOUNTPOINT="/"'); echo $PKNAME | if [[ $PKNAME == *"nvme"* ]]; then sed 's/p[0-9]*$//'; elif [[ $PKNAME == *"sd"* ]]; then sed 's/[0-9]*$//'; elif [[ $PKNAME == *"mmcblk"* ]]; then sed 's/p[0-9]*$//'; fi )
disk_list=($(lsblk -Snpo NAME | grep -v "$disk_boot"))

mediaserver_stop () {
	echo -e ""$INFO" Stopping Nx Witness Mediaserver."
	systemctl stop networkoptix-mediaserver.service 
}

mediaserver_start () {
	echo -e ""$INFO" Starting Nx Witness Mediaserver."
	systemctl start networkoptix-mediaserver.service 
}

if (( EUID != 0 )); then
	echo -e ""$ERROR" This script must be ran as root."
	exit 1
fi

if [ ! -e "$log_file" ]; then touch "$log_file"; fi

apt install -qqy jq smartmontools

exec &>> >(tee "$log_file")

echo -e "=== Diskconfig started at $(date '+%F %T') ==="
echo -e ""$INFO" "$disk_boot" is the boot device."

if [ ${#disk_list[@]} -eq 0 ]; then
	clear
	echo -e ""$ERROR" No storage disks were detected, please insert disk(s) and try again."
	exit 1 
fi

echo -e ""$INFO" Disks detected: "${disk_list[@]}""

marked_list=()

read -p "networkoptix-mediaserver.service needs to be stopped while disk configuration takes place, do you want to continue? (Y/N) " -n 1 -r user_in
if [[ $user_in =~ ^[Yy]$ ]]; then
	mediaserver_stop
else
	echo -e ""$INFO" Aborting script."
	exit 1
fi
unset user_in

for disk in ${disk_list[@]}; do
	if [ -e "$disk"1 ]; then
		echo -e ""$INFO" "$disk" contains at least one partition."
		part_uuid=$(blkid -s UUID -o value "$disk"1)
		echo -e ""$INFO" "$disk"1 has partition UUID "$part_uuid"."
		if [[ $(grep "$part_uuid" /etc/fstab) ]]; then
			echo -e ""$INFO" Partition UUID "$part_uuid" was found in /etc/fstab.\n"

			read -p "Do you wish to have it marked for formatting/configuration anyway? " -n 1 -r user_in
			echo -e ""
			if [[ $user_in =~ ^[Yy]$ ]]; then
				marked_list+="$disk "
				unset mountpoint
				mountpoint=$(grep "$part_uuid" /etc/fstab | awk '{print $2}')
				umount -f "$mountpoint"
				sed -i "/$part_uuid/d" /etc/fstab
				echo -e ""$INFO" "$disk" will be marked."
			fi
			unset user_in

		elif [[ $(grep "$disk"1 /etc/fstab ) ]]; then
			echo -e ""$INFO" "$disk" was found in /etc/fstab.\n"

			read -p "Do you wish to have it marked for formatting/configuration anyway? " -n 1 -r user_in
			echo -e "\n"
			if [[ $user_in =~ ^[Yy]$ ]]; then
				marked_list+="$disk "
				unset mountpoint
				mountpoint=$(grep "$disk"1 /etc/fstab | awk '{print $2}')
				umount -f "$mountpoint"
				sed -i "/$disk/d" /etc/fstab
				echo -e ""$INFO" "$disk" will be marked.\n"
			fi
			unset user_in

		else
			echo -e ""$INFO" partition UUID "$part_uuid" was NOT found in /etc/fstab and will be marked.\n"
			marked_list+="$disk"
		fi
	else
		echo -e ""$INFO" "$disk" does not contain a partition and will be marked.\n"
		marked_list+="$disk "
	fi
done

echo -e "=== Marked Disks ==="

if [ ${#marked_list[@]} -eq 0 ]; then
	mediaserver_start
	echo -e ""$ERROR" No disks were marked, aborting script."
	echo -e "=== Diskconfig ended at $(date '+%F %T') ===\n"
	exit 1
fi

for disk in ${marked_list[@]}; do
	echo -e ""$disk" - "$(smartctl -i --json $disk | jq -r '.model_name')" "$(lsblk $disk -Snlpo SIZE)" $(if $(smartctl -H --json $disk | jq '.smart_status.passed'); then echo "HEALTHY"; else echo "NOT HEALTHY"; fi)"
done

read -p "Do you wish to wipe all marked disks and configure them automatically? Any data on the disks will be lost. (Y/N) " -n 1 -r user_in
if [[ $user_in =~ ^[Yy]$ ]]; then
	for disk in ${marked_list[@]}; do
		wipefs -a $disk && echo -e ""$INFO" Successfully wiped "$disk"." || echo -e ""$ERROR" Failed to wipe "$disk"."
		parted $disk mktable gpt && echo -e ""$INFO" Successfully created partition table on "$disk"." || echo -e  ""$ERROR" Failed create partition table on "$disk"."
		parted $disk mkpart -a optimal primary 0% 100% && echo -e ""$INFO" Successfully created partition on "$disk"." || echo -e  ""$ERROR" Failed to create partition on "$disk"."
		mkfs.ext4 -F "$disk"1 && echo -e  ""$INFO" Successfully wrote filesystem to "$disk"." || echo -e  ""$ERROR" Failed to write filesystem to "$disk"."
		part_uuid="$(blkid -s UUID -o value "$disk"1)"
		mkdir -p /mnt/Media/"$part_uuid" && echo -e ""$INFO" Successfully created directory /mnt/Media/"$part_uuid"." || echo -e ""$ERROR" Failed to create directory /mnt/Media/"$part_uuid"."
		echo -e "UUID=\""$part_uuid"\"\t/mnt/Media/"$part_uuid"\text4\terrors=continue,nofail\t0\t2" >> /etc/fstab
		mount -v /mnt/Media/"$part_uuid"
	done
else
	mediaserver_start
	echo -e ""$INFO" Aborting script."
	exit 1
fi
unset user_in
mediaserver_start
echo -e "=== Diskconfig ended at $(date '+%F %T') ===\n"
exit 0