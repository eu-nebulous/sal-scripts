#!/bin/bash

# This bash script is designed to prepare and install Kubernetes K3s Distribution for Ubuntu 22.04.
# If an error occur, the script will exit with the value of the PID to point at the logfile.

# Set up the script variables
STARTTIME=$(date +%s)
PID=$(echo $$)
EXITCODE=$PID
DATE=$(date)
LOGFILE="/var/log/preinstall-kube-k3s-u22.$PID.log"

# Set up the logging for the script
sudo touch $LOGFILE
sudo chown $USER:$USER $LOGFILE

# All the output of this shell script is redirected to the LOGFILE
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$LOGFILE 2>&1

# A function to print a message to the stdout as well as as the LOGFILE
log_print(){
  level=$1
  Message=$2
  echo "$level [$(date)]: $Message"
  echo "$level [$(date)]: $Message" >&3
}

# A function to check for the apt lock
Check_lock() {
  i=0
  log_print INFO "Checking for apt lock"
  while [ `ps aux | grep [l]ock_is_held | wc -l` != 0 ]; do
    echo "Lock_is_held $i"
    ps aux | grep [l]ock_is_held
    sleep 10
    ((i=i+10));
  done
  log_print INFO "Exited the while loop, time spent: $i"
  echo "ps aux | grep apt"
  ps aux | grep apt
  log_print INFO "Waiting for lock task ended properly."
}

# Start the Configuration
log_print INFO "Configuration started!"
log_print INFO "Logs are saved at: $LOGFILE"

# Check for lock
Check_lock

# Update the package list
log_print INFO "Updating the package list."
sudo apt-get update
sudo unattended-upgrade -d

# Check for lock
Check_lock

# Install curl
log_print INFO "Installing curl"
sudo apt-get install -y curl || { log_print ERROR "curl installation failed!"; exit $EXITCODE; }

# Turn off the swap memory
log_print INFO "Turning swap off...."
if [ `grep Swap /proc/meminfo | grep SwapTotal: | cut -d" " -f14` == "0" ];
then
  log_print INFO "The swap memory is Off"
else
  sudo swapoff -a || { log_print ERROR "Temporary swap memory can't be turned off "; exit $EXITCODE; }
  sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || { log_print ERROR "swap memory can't be turned off "; exit $EXI
TCODE; }
  log_print INFO "Swap turned off!"
fi

# Declare configuration done successfully
ENDTIME=$(date +%s)
ELAPSED=$(( ENDTIME - STARTTIME ))
log_print INFO "Configuration done successfully in $ELAPSED seconds "
