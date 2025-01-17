#!/bin/bash
echo "Master pre-install script\n"

echo "Setting hostname\n"
sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"

echo "Create K3s Dependencies folder $HOME/k3s\n"
sudo -H -u ubuntu bash -c "mkdir -p $HOME/k3s"

echo "Setting Wireguard Interface\n"
sudo -H -u ubuntu bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/onm/onm-bootstrap.sh -O onm-bootstrap.sh  && chmod +x onm-bootstrap.sh'
sudo -H -u ubuntu bash -c "./onm-bootstrap.sh 'CREATE' $APPLICATION_ID $ONM_URL $PUBLIC_IP $SSH_PORT";
echo ""
echo ""


while true; do
    WIREGUARD_VPN_IP=$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)
    if [[ -n "$WIREGUARD_VPN_IP" ]]; then
        echo "WIREGUARD_VPN_IP is set to $WIREGUARD_VPN_IP"
        break
    fi
    echo "Waiting for WIREGUARD_VPN_IP to be set..."
    sleep 2
done


echo "Executing k3s-preinstall script\n"
sudo -H -u ubuntu bash -c "wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/dev/k3s/preinstall-kube-k3s-u22.sh -O ${HOME}/k3s/preinstall-kube-k3s-u22.sh  && chmod +x $HOME/k3s/preinstall-kube-k3s-u22.sh && $HOME/k3s/preinstall-kube-k3s-u22.sh"
sudo -H -u ubuntu bash -c "$HOME/k3s/preinstall-kube-k3s-u22.sh"