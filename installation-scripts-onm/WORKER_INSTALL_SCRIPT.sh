#!/bin/bash
echo "Worker install script"
wget https://opendev.org/nebulous/sal-scripts/raw/branch/master/k8s/install-kube-u22-wg.sh && chmod +x ./install-kube-u22-wg.sh && ./install-kube-u22-wg.sh
