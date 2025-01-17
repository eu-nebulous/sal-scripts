#!/bin/bash
echo "Worker install script"

echo "Installing K3s Agent"

sudo -H -u ubuntu bash -c "wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/dev/k3s/install-kube-k3s-agent-u22-wg.sh -O ${HOME}/k3s/install-kube-k3s-agent-u22-wg.sh && chmod +x $HOME/k3s/install-kube-k3s-agent-u22-wg.sh && $HOME/k3s/install-kube-k3s-agent-u22-wg.sh $APPLICATION_ID"
