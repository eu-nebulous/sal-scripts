#!/bin/bash

# Get the public IP
public_ip=${5:-$(curl -s http://httpbin.org/ip | grep -oP '(?<="origin": ")[^"]*')}

# Set up the script variables
STARTTIME=$(date +%s)
PID=$(echo $$)
LOGFILE="/var/log/nm-bootstrap-script.$PID.$public_ip.log"

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

log_print INFO "Starting nm-bootstrap-script with the following parameters: ACTION=$ACTION, NODE_TYPE=$NODE_TYPE,
                APPLICATION_UUID=$APPLICATION_UUID, ONM_IP=$ONM_IP, PUBLIC_IP=$public_ip,
                LOGGED_IN_USER=$logged_in_user, SSH_PORT=$SSH_PORT"

# Get the isMaster variable from the environment variable
if [ "$NODE_TYPE" == "MASTER" ]; then
  IS_MASTER="true";
elif [ "$NODE_TYPE" == "WORKER" ]; then
  IS_MASTER="false"
fi

# Check if string1 is equal to string2
if [ "$ACTION" == "CREATE" ]; then
  log_print INFO "Creating Wireguard folder to home directory..."
  # Create Wireguard Folder to accept the wireguard scripts
  mkdir -p /home/${logged_in_user}/wireguard

  log_print INFO "Creating OpenSSH Public/Private Key Pair..."
  # Create OpenSSH Public/Private Key files
  ssh-keygen -C wireguard-pub -t rsa -b 4096 -f /home/${logged_in_user}/wireguard/wireguard -N ""

  log_print INFO "Moving wireguard.pub file to authorized_keys file..."
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

log_print INFO "Current Payload is: $PAYLOAD"

if [ "$ACTION" == "CREATE" ]; then
  curl -v -X POST -H "Content-Type: application/json" -d "$PAYLOAD" http://${ONM_IP}:8082/api/v1/node/create
elif [ "$ACTION" == "DELETE" ]; then
  curl -v -X DELETE -H "Content-Type: application/json" -d "$PAYLOAD" http://${ONM_IP}:8082/api/v1/node/delete
fi

# Declare configuration done successfully
ENDTIME=$(date +%s)
ELAPSED=$(( ENDTIME - STARTTIME ))
log_print INFO "nm-bootstrap-script.sh: Configuration done successfully in $ELAPSED seconds "