#!/bin/bash
echo "Worker pre-install script"
sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"
sudo -H -u ubuntu bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/onm/onm-bootstrap.sh && chmod +x onm-bootstrap.sh'


if [[ -v NEB_PREV_APP_ID ]]; then
    echo "NEB_PREV_APP_ID is $NEB_PREV_APP_ID. DELETE"
    sudo -H -u ubuntu bash -c "./onm-bootstrap.sh 'DELETE' $NEB_PREV_APP_ID $ONM_URL";    
fi

WIREGUARD_VPN_IP=$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)
if [[ -n "$WIREGUARD_VPN_IP" ]]; then
    WG_NODE_INTERFACE="wg$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)"
    sudo -H -u ubuntu bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/wireguard/wg-deregister-node.sh && chmod +x wg-deregister-node.sh'
    sudo -H -u ubuntu bash -c "./wg-deregister-node.sh ubuntu $WG_NODE_INTERFACE";
fi

echo "export NEB_PREV_APP_ID=$APPLICATION_ID" >> /home/ubuntu/.profile

# Delete wireguard if exists
#WIREGUARD_VPN_IP=$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)
#if [[ -n "$WIREGUARD_VPN_IP" ]]; then
#    echo INFO "WIREGUARD_VPN_IP is set to $WIREGUARD_VPN_IP. Delete it"
#    sudo -H -u ubuntu bash -c "./onm-bootstrap.sh 'DELETE' $APPLICATION_ID $ONM_URL";
#    break
#fi

sudo -H -u ubuntu bash -c "./onm-bootstrap.sh 'CREATE' $APPLICATION_ID $ONM_URL $PUBLIC_IP $SSH_PORT";

while true; do
    WIREGUARD_VPN_IP=$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)
    if [[ -n "$WIREGUARD_VPN_IP" ]]; then
        echo INFO "WIREGUARD_VPN_IP is set to $WIREGUARD_VPN_IP"
        break
    fi
    echo INFO "Waiting for WIREGUARD_VPN_IP to be set..."
    sleep 2
done