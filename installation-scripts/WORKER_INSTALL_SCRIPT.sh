#!/bin/bash
echo "Worker install script"
wget https://opendev.org/nebulous/sal-scripts/raw/branch/master/k8s/install-kube-u22.sh && chmod +x ./install-kube-u22.sh && ./install-kube-u22.sh
