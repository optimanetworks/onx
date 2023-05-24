#!/bin/bash

src_url="https://raw.githubusercontent.com/optimanetworks/onx/main/config/watool.sh"
install_path="/usr/local/sbin/watool"
log_file="/var/log/watool.log"
config_file="/usr/local/etc/watool.conf"

# Text Colors
RES='\033[0m'; RED='\033[00;31m'; GRE='\033[00;32m'; BLU='\033[00;34m'; YEL='\033[00;93m'
# Unicode Characters
checkmark="${GRE}\U2714${RES}"; crossmark="${RED}\U2716${RES}"

log_this () {
	# Log function input with date and time.
	echo -e "[`date +%Y-%m-%d' '%H:%M:%S`] $1" | tee -a "$log_file"
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
	echo "    Configuration parameters are found in $config_file."
	echo ""
	echo "    Valid options:"
	echo ""
	echo "    -h|--help    -  Prints this message."
	echo ""
	echo "    -i|--install -  Installs the script."
	echo ""
	echo "    --uninstall  -  Uninstalls the script."
	echo ""
	echo "    -U|--update  -  Update the existing script."
	echo ""
	echo "    -c|--config  -  Change configuration parameters interactively."
	echo ""
	echo "    -r|--run     -  Run the script once."
	echo ""
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

ch_val () {
	# $1: Key, $2: New Value, $3: Filepath
	sed -ri "s/^[#]*\s*${1}=.*/$1=\"$2\"/" "$3"
}

cron_mgr () {
	case $1 in
		CREATE)
			if ! $(crontab -l | egrep -v "^(#|$)" | grep -q "$install_path --run"); then
    			crontab -l | { cat; echo "$INTERVAL $install_path --run"; } | crontab -
				log_this "[$checkmark] Cronjob created."
			fi
			;;
		REMOVE)
			if $(crontab -l | egrep -v "^(#|$)" | grep -q "$install_path --run"); then
				crontab -l | grep -v "$install_path --run"
				log_this "[$checkmark] Cronjob removed."
			fi
			;;
		CHECK) $(crontab -l | egrep -v "^(#|$)" | grep -q "$install_path --run") && return 0 || return 1 ;;
	esac
}

mk_config () {
	touch $config_file
	echo -e '# This is the configuration file for watool.\nRESTART=false\nUPDATES=false\nINTERVAL="@weekly"' > $config_file
	. $config_file
	log_this "[$checkmark] Config created."
}

ch_config () {
	case $1 in
		RESTART)
			clear
			yesno "Enable automatic reboots? (Y/N): " && ch_val RESTART true $config_file || ch_val RESTART false $config_file
			;;
		UPDATES)
			clear
			yesno "Enable automatic security updates? (Y/N): " && ch_val UPDATES true $config_file || ch_val UPDATES false $config_file
			;;
		INTERVAL)
			clear
			echo -e "At what interval should the system run this tool?"
			echo -e "Leave blank to use default value (Current: $INTERVAL)."
			echo -e ""
			echo -e "Helpful tool: https://crontab.guru/"
			echo -e ""
			read -p "Cron schedule expression: " cron_expr
			[ -z $cron_expr ] || ch_val INTERVAL "$cron_expr" $config_file 
			;;
	esac
}

installer () {
	# Move script to destination file path if needed and create cronjob if it doesn't exist. 
	[ -e "$log_file" ] || touch "$log_file"
	[ -e "$config_file" ] || mk_config
	. $config_file
	if [ -e "$install_path" ]; then
		log_this "[$crossmark] Script already installed, exiting..."; exit 1
	else
		wget -qO $install_path $src_url
		chmod +x $install_path
		log_this "[$checkmark] Script downloaded to $install_path."
		cron_mgr CREATE
		log_this "[$checkmark] Installation procedure completed. Use 'sudo watool --config' to configure settings, all are disabled by default."
	fi
}

uninstaller () {
	cron_mgr REMOVE
	rm $config_file && log_this "[$checkmark] Config file deleted."
	rm $install_path && log_this "[$checkmark] Script deleted."
}

updater () {
	[ -e "$config_file" ] || mk_config
	. $config_file
	cron_mgr CHECK || cron_mgr CREATE
	wget -qO $install_path $src_url
	chmod +x $install_path && log_this "[$checkmark] Updated script in $install_path."
}

run_task () {
	# Run unattended-upgrade to check for and install security updates, then reboot.
	. $config_file
	if $UPDATES; then
		unattended-upgrade && log_this "[$checkmark] Ran unattended upgrade." || log_this "[$crossmark] Unattended upgrade failed."
	fi
	if $RESTART; then
		log_this "Rebooting..."
		/sbin/shutdown -r now || log_this "[$crossmark] Reboot failed."
	fi
}

# Script start
case $1 in
	-h|--help)
		show_help
		exit 0
		;;
	-i|--install)
		check_privileges
		installer
		exit 0
		;;
	--uninstall)
		check_privileges
		uninstaller
		exit 0
		;;
	-U|--update)
		check_privileges
		updater
		exit 0
		;;
	-c|--config)
		check_privileges
		while true; do
			clear
			. $config_file
			$RESTART && MRESTART=$checkmark || MRESTART=$crossmark
			$UPDATES && MUPDATES=$checkmark || MUPDATES=$crossmark
			echo -e "Select a parameter to change:"
			echo -e "1) Enable/disable reboot function (Current: $MRESTART)"
			echo -e "2) Enable/disable automatic security updates (Current: $MUPDATES)"
			echo -e "3) Change schedule (Current: $INTERVAL)"
			echo -e ""
			echo -e "0) Quit"
			echo -e "-----------------------------------------------------------------"
			read -s -n1 minput
			case $minput in
				1)
					$RESTART && ch_val RESTART false $config_file || ch_val RESTART true $config_file
					;;
				2)
					$UPDATES && ch_val UPDATES false $config_file || ch_val UPDATES true $config_file
					;;
				3)
					ch_config INTERVAL
					cron_mgr REMOVE
					cron_mgr CREATE
					;;
				0)
					exit 0
					;;
			esac
		done
		;;
	-r|--run)
		check_privileges
		run_task
		exit 0
		;;
	"")
		show_help
		log_this "[$crossmark] Script ran without option parameter."
		exit 1
		;;
	*)
		show_help
		log_this "[$crossmark] Script ran with invalid option parameter: $1"
		exit 1
		;;
esac