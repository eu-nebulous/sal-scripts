#!/bin/bash
echo "Worker pre-install script"
# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"
echo "Setting hostname\n"
sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"

if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
    K3S_DEP_PATH=/home/ubuntu/k3s
    echo "Create K3s Dependencies folder $K3S_DEP_PATH\n"
    $dau bash -c "mkdir -p $K3S_DEP_PATH"

    echo "Setting Wireguard Interface\n"
    $dau bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/onm/onm-bootstrap.sh -O onm-bootstrap.sh && chmod +x onm-bootstrap.sh'
fi





# NEB_PREV_APP_ID env var holds the last APPLICATION_ID the node was part of. If empty, means it hasn't been part of any app cluster. 
if [[ -v NEB_PREV_APP_ID ]]; then
    echo "NEB_PREV_APP_ID is $NEB_PREV_APP_ID. DELETE"
    $dau bash -c "./onm-bootstrap.sh 'DELETE' $NEB_PREV_APP_ID $ONM_URL";    
fi
echo "export NEB_PREV_APP_ID=$APPLICATION_ID" >> /home/ubuntu/.profile

WG_NODE_INTERFACE=$(ip a | awk '{print $2}' | grep '^wg' | awk '{gsub(/:$/,""); sub(/^wg/, ""); print}')
if [[ -n "$WG_NODE_INTERFACE" ]]; then
    echo INFO "Wireward installation found for wg$WIREGUARD_VPN_IP. Delete it"
    $dau bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/wireguard/wg-deregister-node.sh && chmod +x wg-deregister-node.sh'
    $dau bash -c "./wg-deregister-node.sh ubuntu $WG_NODE_INTERFACE";
fi

$dau bash -c "./onm-bootstrap.sh 'CREATE' $APPLICATION_ID $ONM_URL $PUBLIC_IP $SSH_PORT";
echo ""
echo ""

while true; do
    WIREGUARD_VPN_IP=$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)
    if [[ -n "$WIREGUARD_VPN_IP" ]]; then
        echo INFO "WIREGUARD_VPN_IP is set to $WIREGUARD_VPN_IP"
        break
    fi
    echo INFO "Waiting for WIREGUARD_VPN_IP to be set..."
    sleep 2
done
