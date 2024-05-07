#!/bin/bash
echo "Worker pre-install script"
sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"
sudo -H -u ubuntu bash -c 'wget https://opendev.org/nebulous/sal-scripts/raw/branch/master/onm/nm-bootstrap-script.sh && chmod +x nm-bootstrap-script.sh'
sudo -H -u ubuntu bash -c "./nm-bootstrap-script.sh 'CREATE' 'WORKER' $APPLICATION_ID 158.39.201.249 $PUBLIC_IP $SSH_PORT";

WIREGUARD_VPN_IP=`ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1`;
echo "WIREGUARD_VPN_IP= $WIREGUARD_VPN_IP";
