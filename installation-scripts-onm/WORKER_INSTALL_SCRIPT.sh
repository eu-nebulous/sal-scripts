#!/bin/bash
echo "Worker install script"
wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/r1/k8s/install-kube-u22-wg.sh && chmod +x ./install-kube-u22-wg.sh && ./install-kube-u22-wg.sh