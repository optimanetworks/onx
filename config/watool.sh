#!/bin/bash

install_path="/usr/local/sbin/watool"
log_file="/var/log/watool.log"

log_this () {
	# Log function input with date and time.
	echo `date +%Y/%m/%d' '%H:%M:%S`" $1" >> "$log_file"
}

check_privileges () {
	# Check if the script is ran as root, abort if not the case.
	if (( EUID != 0 )); then
		echo -e "\nThis script must be ran as root.\n"
		exit 1
	fi
}

show_help () {
	# Print help information.
	echo "watool: watool [options]"
	echo "    Tool to automatically install security updates and reboot on a weekly basis."
	echo "    This script has to be ran with root privileges to work." 
	echo ""
	echo "    Valid options:"
	echo ""
	echo "    -h|--help    -  Prints this message."
	echo ""
	echo "    -i|--install -  Installs the script."
	echo ""
	echo "    -r|--run     -  Run the script once."
	echo ""
}

self_install () {
	# Move script to destination file path if needed and create cronjob if it doesn't exist. 
	[ -e "$log_file" ] || touch "$log_file"
	if [ -e "$install_path" ]; then
		echo "Script already installed, exiting..."
		exit 1
	else
		mv $0 "$install_path"
		log_this "Script moved to "$install_path"."
		if [[ $(crontab -l | egrep -v "^(#|$)" | grep -q '/usr/local/sbin/watool --run'; echo $?) == 1 ]]; then
    		set -f
    		echo $(crontab -l ; echo '@weekly /usr/local/sbin/watool --run') | crontab -
    		set +f
			log_this "Cronjob created."
		fi
	fi
}

run_task () {
	# Run unattended-upgrade to check for and install security updates, then reboot.
	unattended-upgrade && log_this "Ran unattended upgrade." || log_this "Unattended upgrade failed."
	log_this "Rebooting..."
	reboot
}

# Script start
case $1 in
	-h|--help)
		show_help
		exit 0
		;;
	-i|--install)
		check_privileges
		self_install
		exit 0
		;;
	-r|--run)
		check_privileges
		run_task
		exit 0
		;;
	"")
		echo "No option parameter passed, exiting..."
		show_help
		log_this "Script ran without option parameter."
		exit 1
		;;
	*)
		echo "Invalid option parameter passed, exiting..."
		show_help
		log_this "Script ran with invalid option parameter: $1"
		exit 1
		;;
esac