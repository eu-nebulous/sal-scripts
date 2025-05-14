#!/bin/bash
echo "Master pre-install script\n"

# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"

echo "Setting hostname\n"
sudo hostnamectl set-hostname "$variables_PA_JOB_NAME"

if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
    K3S_DEP_PATH=/home/ubuntu/k3s
    echo "Create K3s Dependencies folder $K3S_DEP_PATH\n"
    $dau bash -c "mkdir -p $K3S_DEP_PATH"
fi



echo "Setting Wireguard Interface\n"
$dau bash -c 'wget https://raw.githubusercontent.com/eu-nebulous/overlay-network-manager/main/network-manager/bootstrap-agent-scripts/onm/onm-bootstrap.sh -O onm-bootstrap.sh  && chmod +x onm-bootstrap.sh'
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

if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
    echo "Executing k3s-preinstall script\n"
    $dau bash -c "wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/k3s/preinstall-kube-k3s-u22.sh -O ${K3S_DEP_PATH}/preinstall-kube-k3s-u22.sh  && chmod +x $K3S_DEP_PATH/preinstall-kube-k3s-u22.sh && $K3S_DEP_PATH/preinstall-kube-k3s-u22.sh"
    $dau bash -c "$K3S_DEP_PATH/preinstall-kube-k3s-u22.sh"
fi


