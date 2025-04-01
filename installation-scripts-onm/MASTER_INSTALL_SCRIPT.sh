#!/bin/bash
echo "Master install script"
# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"
if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
    echo "Installing K3s Server"
    K3S_DEP_PATH=/home/ubuntu/k3s
    $dau bash -c "wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/k3s/install-kube-k3s-server-u22-wg.sh -O ${K3S_DEP_PATH}/install-kube-k3s-server-u22-wg.sh && chmod +x $K3S_DEP_PATH/install-kube-k3s-server-u22-wg.sh && $K3S_DEP_PATH/install-kube-k3s-server-u22-wg.sh $APPLICATION_ID"
else
    wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/k8s/install-kube-u22-wg.sh && chmod +x ./install-kube-u22-wg.sh && ./install-kube-u22-wg.sh
fi

echo "Installing Helm..."
$dau bash -c ' curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh'
# Add KubeVela Helm repository and update
$dau bash -c 'curl -fsSl https://kubevela.io/script/install.sh | bash'
echo "Configuration complete."   
