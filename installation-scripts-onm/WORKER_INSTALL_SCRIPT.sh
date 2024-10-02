#!/bin/bash
echo "Worker install script"

echo "Installing K3s Agent"
K3S_DEP_PATH=$HOME/k3s

sudo -H -u ubuntu bash -c "wget -P ${K3S_DEP_PATH} https://raw.githubusercontent.com/eu-nebulous/sal-scripts/dev/k3s/install-kube-k3s-agent-u22-wg.sh && chmod +x $K3S_DEP_PATH/install-kube-k3s-agent-u22-wg.sh && $K3S_DEP_PATH/install-kube-k3s-agent-u22-wg.sh $APPLICATION_ID"
