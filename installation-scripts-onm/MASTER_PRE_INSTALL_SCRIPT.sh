#!/bin/bash
echo "Master pre-install script\n"

sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"
sudo -H -u ubuntu bash -c 'https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/onm/onm-bootstrap.sh && chmod +x onm-bootstrap.sh'
sudo -H -u ubuntu bash -c "./nm-bootstrap-script.sh 'CREATE' 'MASTER' $APPLICATION_ID $ONM_IP $PUBLIC_IP $SSH_PORT";
echo ""
echo ""
sleep 60

WIREGUARD_VPN_IP=`ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1`;
echo "WIREGUARD_VPN_IP= $WIREGUARD_VPN_IP";
