#!/bin/bash
echo "Worker pre-install script"

echo "Setting hostname\n"
sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"

echo "Create K3s Dependencies folder\n"
K3S_DEP_PATH=$HOME/k3s
mkdir -p $K3S_DEP_PATH

echo "Setting Wireguard Interface\n"
sudo -H -u ubuntu bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/onm/onm-bootstrap.sh && chmod +x onm-bootstrap.sh'
sudo -H -u ubuntu bash -c "./onm-bootstrap.sh 'CREATE' $APPLICATION_ID $ONM_URL $PUBLIC_IP $SSH_PORT";
echo ""
echo ""
sleep 60

WIREGUARD_VPN_IP=`ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1`;
echo "WIREGUARD_VPN_IP= $WIREGUARD_VPN_IP";

echo "Executing k3s-preinstall script\n"
sudo -H -u ubuntu bash -c "wget -P ${K3S_DEP_PATH} https://raw.githubusercontent.com/eu-nebulous/sal-scripts/dev/k3s/preinstall-kube-k3s-u22.sh && chmod +x $K3S_DEP_PATH/preinstall-kube-k3s-u22.sh && $K3S_DEP_PATH/preinstall-kube-k3s-u22.sh"
