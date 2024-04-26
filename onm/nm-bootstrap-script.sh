#!/bin/bash

# Get the public IP
public_ip=${5:-$(curl -s http://httpbin.org/ip | grep -oP '(?<="origin": ")[^"]*')}

# Set up the script variables
STARTTIME=$(date +%s)
PID=$(echo $$)
LOGFILE="/var/log/onm-bootstrap.$PID.$public_ip.log"

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
    log_print INFO "onm-bootstrap($PID): Checking for apt lock"
    while [ `ps aux | grep [l]ock_is_held | wc -l` != 0 ]; do
      log_print INFO "onm-bootstrap($PID): Lock_is_held $i"
      ps aux | grep [l]ock_is_held
      sleep 10
      ((i=i+10));
  done

  log_print INFO "onm-bootstrap($PID): Exited the while loop, time spent: $i"
  log_print INFO "onm-bootstrap($PID): ps aux | grep apt"
  ps aux | grep apt
  log_print INFO "onm-bootstrap($PID): Waiting for lock task ended properly."
}

# Function to check for the wg command
check_wg_installed() {
    log_print "onm-bootstrap($PID): Checking if WireGuard (wg) is installed..."

    # Using command -v to check for the wg command
    if command -v wg >/dev/null 2>&1; then
        log_print "onm-bootstrap($PID): WireGuard (wg) is installed."
        log_print "onm-bootstrap($PID): Location: $(which wg)"
    else
        log_print "onm-bootstrap($PID): WireGuard (wg) is not installed."
    fi
}

# "CREATE" or "DELETE" Overlay Node
ACTION=$1
# Define Application Node Type ("MASTER","WORKER")
NODE_TYPE=$2
# Application UUID
APPLICATION_UUID=$3
# Overlay Network Manager Public IP
ONM_IP=$4
# SSH Port
SSH_PORT=${6:-22}

# Get the Application UUID from the environment variable
application_uuid=$APPLICATION_UUID

# Get the currently logged in user (assuming single user login)
logged_in_user=$(whoami)

# Start the Configuration
log_print INFO "onm-bootstrap ($PID): Configuration started!"
log_print INFO "onm-bootstrap ($PID): Logs are saved at: $LOGFILE"

log_print INFO "onm-bootstrap($PID): Starting onm-bootstrap with the following parameters: ACTION=$ACTION, NODE_TYPE=$NODE_TYPE,
                APPLICATION_UUID=$APPLICATION_UUID, ONM_IP=$ONM_IP, PUBLIC_IP=$public_ip,
                LOGGED_IN_USER=$logged_in_user, SSH_PORT=$SSH_PORT"

log_print INFO "onm-bootstrap($PID): Updating apt..."
Check_lock

sudo apt-get update


log_print INFO "onm-bootstrap($PID): Installing wireguard and resolvconf..."

Check_lock
# Install WireGuard package
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y resolvconf

# Check if Wireguard is installed
check_wg_installed

# Get the isMaster variable from the environment variable
if [ "$NODE_TYPE" == "MASTER" ]; then
  IS_MASTER="true";
elif [ "$NODE_TYPE" == "WORKER" ]; then
  IS_MASTER="false"
fi

# Check if string1 is equal to string2
if [ "$ACTION" == "CREATE" ]; then
  log_print INFO "onm-bootstrap($PID): Creating Wireguard folder to home directory..."
  # Create Wireguard Folder to accept the wireguard scripts
  mkdir -p /home/${logged_in_user}/wireguard

  log_print INFO "onm-bootstrap($PID): Creating OpenSSH Public/Private Key Pair..."
  # Create OpenSSH Public/Private Key files
  ssh-keygen -C wireguard-pub -t rsa -b 4096 -f /home/${logged_in_user}/wireguard/wireguard -N ""

  log_print INFO "onm-bootstrap($PID): Moving wireguard.pub file to authorized_keys file..."
  cat /home/${logged_in_user}/wireguard/wireguard.pub >> /home/${logged_in_user}/.ssh/authorized_keys
fi

PRIVATE_KEY_FILE=$(cat /home/${logged_in_user}/wireguard/wireguard | base64 | tr '\n' ' ')

PAYLOAD=$(cat <<EOF
{
  "privateKeyBase64": "${PRIVATE_KEY_FILE}",
  "publicKey": "$(</home/${logged_in_user}/wireguard/wireguard.pub)",
  "publicIp": "${public_ip}",
  "applicationUUID": "${application_uuid}",
  "sshUsername": "${logged_in_user}",
  "isMaster": "$IS_MASTER",
  "sshPort": "$SSH_PORT"
}
EOF
)

log_print INFO "onm-bootstrap($PID): Current Payload is: $PAYLOAD"

if [ "$ACTION" == "CREATE" ]; then
  curl -v -X POST -H "Content-Type: application/json" -d "$PAYLOAD" http://${ONM_IP}:8082/api/v1/node/create
elif [ "$ACTION" == "DELETE" ]; then
  curl -v -X DELETE -H "Content-Type: application/json" -d "$PAYLOAD" http://${ONM_IP}:8082/api/v1/node/delete
fi

# Declare configuration done successfully
ENDTIME=$(date +%s)
ELAPSED=$(( ENDTIME - STARTTIME ))
log_print INFO "onm-bootstrap($PID): onm-bootstrap.sh: Configuration done successfully in $ELAPSED seconds "
