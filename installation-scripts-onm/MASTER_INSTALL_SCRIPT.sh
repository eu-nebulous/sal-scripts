#!/bin/bash
echo "Master install script"

K3S_DEP_PATH=$HOME/k3s

echo "Installing K3s Server"
sudo -H -u ubuntu bash -c "wget -P ${K3S_DEP_PATH} https://raw.githubusercontent.com/eu-nebulous/sal-scripts/dev/k3s/install-kube-k3s-server-u22-wg.sh && chmod +x $K3S_DEP_PATH/install-kube-k3s-server-u22-wg.sh && $K3S_DEP_PATH/install-kube-k3s-server-u22-wg.sh $APPLICATION_ID"
