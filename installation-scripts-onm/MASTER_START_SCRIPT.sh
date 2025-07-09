#!/bin/bash
echo "Master start script"

# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"

if [[ -z "$NEBULOUS_SCRIPTS_BRANCH" ]]; then
    NEBULOUS_SCRIPTS_BRANCH="r1"
fi
echo "NEBULOUS_SCRIPTS_BRANCH is set to: $NEBULOUS_SCRIPTS_BRANCH"

if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  echo "KUBECONFIG=${KUBECONFIG}" | sudo tee -a /etc/environment
fi

while true; do
    WIREGUARD_VPN_IP=$(ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1)
    if [[ -n "$WIREGUARD_VPN_IP" ]]; then
        echo INFO "WIREGUARD_VPN_IP is set to $WIREGUARD_VPN_IP"
        break
    fi
    echo INFO "Waiting for WIREGUARD_VPN_IP to be set..."
    sleep 2
done
echo "modprobe br_netfilter"
sudo modprobe br_netfilter
echo "modprobe br_netfilter done"

sudo kubeadm init --apiserver-advertise-address ${WIREGUARD_VPN_IP} --service-cidr 10.96.0.0/16 --pod-network-cidr 10.244.0.0/16


id -u ubuntu &> /dev/null
if [[ $? -eq 0 ]]
then
  #USER ubuntu is found
  mkdir -p /home/ubuntu/.kube && sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config && sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config
else
  echo "User Ubuntu is not found"
fi
#$dau kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml;
$dau bash -c 'helm repo add cilium https://helm.cilium.io/ && helm repo update'
$dau bash -c 'helm install cilium cilium/cilium --namespace kube-system --set encryption.enabled=true --set encryption.type=wireguard'

echo "Installing Vela CLI"
$dau bash -c 'curl -fsSl https://kubevela.io/script/install.sh | bash'
echo "Configuration complete."

echo "Setting KubeVela..."
# Function to check for worker nodes and install KubeVela
cat > /home/ubuntu/install_kubevela.sh << 'EOF'
#!/bin/bash
echo "Start install_kubevela.sh"
sudo -H -E -u ubuntu bash -c 'vela install -y --version 1.9.11'
echo "Vela installation done."
if [ "$SERVERLESS_ENABLED" == "yes" ]; then
  echo "Serverless installation."

  # Install Cosign
  export COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | jq -r '.tag_name')
  curl -LO "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
  sudo mv cosign-linux-amd64 /usr/local/bin/cosign
  sudo chmod +x /usr/local/bin/cosign

  # Update system and install jq
  sudo apt update
  sudo apt install -y jq

  # Apply Knative Serving CRDs and core components
  kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.4/serving-crds.yaml
  kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.4/serving-core.yaml

  # Download and apply Kourier
  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/kourier.yaml
  kubectl apply -f kourier.yaml

  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/serverless-platform-definition.yaml
  kubectl apply -f serverless-platform-definition.yaml

  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/config-features.yaml
  kubectl apply -f config-features.yaml

  # Patch config-domain with PUBLIC_IP
  MASTER_IP=$(curl -s ifconfig.me)

  # Patch config-domain with MASTER_IP
  kubectl patch configmap/config-domain \
    --namespace knative-serving \
    --type merge \
    --patch "{\"data\":{\"${MASTER_IP}.sslip.io\":\"\"}}"

  # Patch config-network to use Kourier ingress
  kubectl patch configmap/config-network \
    --namespace knative-serving \
    --type merge \
    --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

  # Apply default domain configuration
  kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.4/serving-default-domain.yaml

  kubectl apply -f https://raw.githubusercontent.com/kubevela/samples/master/06.Knative_App/componentdefinition-knative-serving.yaml

  if [ -n "$LOCAL_SERVERLESS_SERVICES" ]; then
    echo "LOCAL_SERVERLESS_SERVICES is set to: $LOCAL_SERVERLESS_SERVICES"

    sudo wget -q -O /usr/local/bin/label-serverless-services.sh \
      https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/label-serverless-services.sh

    sudo chmod +x /usr/local/bin/label-serverless-services.sh

    sudo touch /var/log/label-serverless-services.log
    sudo chown ubuntu:ubuntu /var/log/label-serverless-services.log

    nohup /usr/local/bin/label-serverless-services.sh \
      >> /var/log/label-serverless-services.log 2>&1 &
  fi
fi
echo "End install_kubevela.sh"
EOF

chmod +x /home/ubuntu/install_kubevela.sh

cat > /home/ubuntu/kubevela_installer_service.sh << 'EOF'
#!/bin/bash

# Wait for at least one worker node to be ready
while true; do
    WORKER_NODES=$(sudo -H -E -u ubuntu kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o json | jq '.items | length')
    if [ "$WORKER_NODES" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Found $WORKER_NODES worker node(s), proceeding with KubeVela installation..." >> /home/ubuntu/vela.txt
        /home/ubuntu/install_kubevela.sh >> /home/ubuntu/vela.txt 2>&1
        # Disable the service after successful installation
        sudo systemctl disable kubevela-installer.service
        exit 0
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Waiting for worker nodes to be ready..." >> /home/ubuntu/vela.txt
    sleep 10
done
EOF
chmod +x /home/ubuntu/kubevela_installer_service.sh

# Create systemd service file
cat << EOF | sudo tee /etc/systemd/system/kubevela-installer.service
[Unit]
Description=KubeVela One-time Installer Service
After=network.target

[Service]
Type=simple
User=ubuntu
ExecStart=/home/ubuntu/kubevela_installer_service.sh
Restart=no
Environment="LOCAL_SERVERLESS_SERVICES=${LOCAL_SERVERLESS_SERVICES}"
Environment="SERVERLESS_ENABLED=${SERVERLESS_ENABLED}"

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable kubevela-installer.service
sudo systemctl start kubevela-installer.service

$dau bash -c 'helm repo add nebulous https://eu-nebulous.github.io/helm-charts/'

$dau bash -c 'helm repo add netdata https://netdata.github.io/helmchart/'

$dau bash -c 'helm repo update'

echo "Login to docker registry"
$dau bash -c "kubectl delete secret docker-registry regcred --ignore-not-found"
$dau bash -c "kubectl create secret docker-registry regcred --docker-server=$PRIVATE_DOCKER_REGISTRY_SERVER --docker-username=$PRIVATE_DOCKER_REGISTRY_USERNAME --docker-password=$PRIVATE_DOCKER_REGISTRY_PASSWORD --docker-email=$PRIVATE_DOCKER_REGISTRY_EMAIL"

echo "Starting EMS"
$dau bash -c 'helm install ems nebulous/ems-server \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule" \
  --set app_uuid=$APPLICATION_ID \
  --set broker_address=$BROKER_ADDRESS \
  --set image.tag="latest" \
  --set broker_port=$BROKER_PORT'


$dau bash -c 'helm install netdata netdata/netdata'

echo "Starting Solver"
$dau bash -c 'helm install solver nebulous/nebulous-optimiser-solver \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule" \
  --set amplLicense.keyValue="$LICENSE_AMPL" \
  --set application.id=$APPLICATION_ID \
  --set activemq.ACTIVEMQ_HOST=$BROKER_ADDRESS \
  --set activemq.ACTIVEMQ_PORT=$BROKER_PORT \
  --set image.tag="main-3aee09dd6d701bc54d9a5ed173dfbcc4e2808e9f-20250506181924"'

echo "Add volumes provisioner"
$dau bash -c "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.27/deploy/local-path-storage.yaml"  


if [ "$WORKFLOW_ENABLED" == "yes" ]; then
  echo "Workflow installation.";

  $dau bash -c 'helm install argo-workflows argo-workflows \
    --repo https://argoproj.github.io/argo-helm \
    --namespace argo \
    --create-namespace \
    --set crds.install=true \
    --set crds.keep=false \
    --set workflow.serviceAccount.create=true \
    --set workflow.serviceAccount.name="argo" \
    --set workflow.rbac.create=true \
    --set "controller.workflowNamespaces={argo}" \
    --set controller.metricsConfig.enabled=true \
    --set controller.telemetryConfig.enabled=true \
    --set controller.serviceMonitor.enabled=true \
    --set "server.authModes={server}" \
    --set "controller.tolerations[0].effect=NoSchedule" \
    --set "controller.tolerations[0].key=node.kubernetes.io/unschedulable" \
    --set "controller.tolerations[0].operator=Exists" \
    --set "controller.tolerations[1].effect=NoSchedule" \
    --set "controller.tolerations[1].operator=Exists" \
    --set "controller.priorityClassName=system-node-critical" \
    --set controller.nodeSelector.node-role\\.kubernetes\\.io/control-plane="" \
    --set "server.tolerations[0].effect=NoSchedule" \
    --set "server.tolerations[0].key=node.kubernetes.io/unschedulable" \
    --set "server.tolerations[0].operator=Exists" \
    --set "server.tolerations[1].effect=NoSchedule" \
    --set "server.tolerations[1].operator=Exists" \
    --set "server.priorityClassName=system-node-critical" \
    --set server.nodeSelector.node-role\\.kubernetes\\.io/control-plane=""'
  
  sudo -H -E -u ubuntu bash -c 'kubectl -n argo create rolebinding argo-workflows-server --role=argo-workflows-workflow --serviceaccount=argo:argo-workflows-server'
  sudo -H -E -u ubuntu bash -c 'kubectl -n argo create rolebinding argo-workflows-workflow-controller --role=argo-workflows-workflow --serviceaccount=argo:argo-workflows-workflow-controller'
  sudo -H -E -u ubuntu bash -c 'kubectl -n argo create rolebinding default --role=argo-workflows-workflow --serviceaccount=argo:default'

  $dau bash -c "kubectl -n argo create secret docker-registry regcred --docker-server=$PRIVATE_DOCKER_REGISTRY_SERVER --docker-username=$PRIVATE_DOCKER_REGISTRY_USERNAME --docker-password=$PRIVATE_DOCKER_REGISTRY_PASSWORD --docker-email=$PRIVATE_DOCKER_REGISTRY_EMAIL"
  $dau bash -c 'kubectl -n argo patch serviceaccount default -p "{\"imagePullSecrets\": [{\"name\": \"regcred\"}]}"'

  echo "Workflow installation completed.";
fi

