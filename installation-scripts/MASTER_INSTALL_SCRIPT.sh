#!/bin/bash
echo "Master install script"

wget https://opendev.org/nebulous/sal-scripts/raw/branch/master/k8s/install-kube-u22.sh && chmod +x ./install-kube-u22.sh && ./install-kube-u22.sh

echo "Installing Helm..."
sudo -H -u ubuntu bash -c ' curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh'

# Add KubeVela Helm repository and update
echo "Installing Kubevela..."
sudo -H -u ubuntu bash -c 'curl -fsSl https://kubevela.io/script/install.sh | bash'
echo "Configuration complete."
