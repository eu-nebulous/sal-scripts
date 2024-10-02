#!/bin/bash

# Set up the script variables
STARTTIME=$(date +%s)
PID=$(echo $$)
EXITCODE=$PID
DATE=$(date)
LOGFILE="/var/log/install-kube-k3s-server-u22-wg.$PID.log"

# Set up the logging for the script
sudo touch $LOGFILE
sudo chown $USER:$USER $LOGFILE

# Variables
K3S_DEP_PATH=$HOME/k3s
CILIUM_VERSION=1.15.5
POD_CIDR=10.244.0.0/16
K3S_VERSION=v1.26.15+k3s1
TOKEN=$1

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

log_print INFO "Installing k3s server for APPLICATION_ID: ${TOKEN}"
WIREGUARD_VPN_IP=`ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1`
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION}  INSTALL_K3S_EXEC="--cluster-cidr ${POD_CIDR} --token ${TOKEN} --flannel-backend=none --disable-network-policy --bind-address ${WIREGUARD_VPN_IP} --node-ip ${WIREGUARD_VPN_IP} --write-kubeconfig-mode 644" sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log_print INFO "Setting NODE_TOKEN environmental variable (default expiry 1d)"
NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/token)
log_print INFO "NODE_TOKEN: ${NODE_TOKEN}"

log_print INFO "Installing Helm..."
curl -fsSL -o $K3S_DEP_PATH/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 $K3S_DEP_PATH/get_helm.sh && $K3S_DEP_PATH/get_helm.sh

log_print INFO "Adding Cilium Repo"
# Add Cilium Helm Repo
helm repo add cilium https://helm.cilium.io/
helm repo update

log_print INFO "Installing Cilium"
# Install Cilium with Wireguard parameters
helm install cilium cilium/cilium \
    --version $CILIUM_VERSION \
    --namespace kube-system \
    --set ipam.mode=cluster-pool \
    --set ipam.operator.clusterPoolIPv4PodCIDRList=$POD_CIDR \
    --set encryption.enabled=true \
    --set encryption.type=wireguard

# Declare configuration done successfully
ENDTIME=$(date +%s)
ELAPSED=$(( ENDTIME - STARTTIME ))
log_print INFO "Configuration done successfully in $ELAPSED seconds "
