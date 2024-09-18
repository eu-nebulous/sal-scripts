#!/bin/bash
echo "Master install script"

echo "Installing K3s Server"
wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/k3s/install-kube-k3s-server-u22-wg.sh && chmod +x ./install-kube-k3s-server-u22-wg.sh && ./install-kube-k3s-server-u22-wg.sh
