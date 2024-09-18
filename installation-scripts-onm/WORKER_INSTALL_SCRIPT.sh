#!/bin/bash
echo "Worker install script"

echo "Installing K3s Agent"
#TODO: Set K3S_SERVER_WIREGUARD_IP and K3S_SERVER_NODE_TOKEN environmental variables that have been created from K3s Server Installation
wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/k3s/install-kube-k3s-agent-u22-wg.sh && chmod +x ./install-kube-k3s-agent-u22-wg.sh && ./install-kube-k3s-agent-u22-wg.sh $K3S_SERVER_WIREGUARD_IP $K3S_SERVER_NODE_TOKEN
