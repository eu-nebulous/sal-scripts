#!/bin/bash
echo "Worker install script"
# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"
if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
    echo "Installing K3s Agent"
    K3S_DEP_PATH=/home/ubuntu/k3s
    $dau bash -c "wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/dev/k3s/install-kube-k3s-agent-u22-wg.sh -O ${K3S_DEP_PATH}/install-kube-k3s-agent-u22-wg.sh && chmod +x $K3S_DEP_PATH/install-kube-k3s-agent-u22-wg.sh && $K3S_DEP_PATH/install-kube-k3s-agent-u22-wg.sh $APPLICATION_ID"
else
    wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/k8s/install-kube-u22-wg.sh && chmod +x ./install-kube-u22-wg.sh && ./install-kube-u22-wg.sh
fi


