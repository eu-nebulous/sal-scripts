#!/bin/bash
echo "Master start script"

# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "KUBECONFIG=${KUBECONFIG}" | sudo tee -a /etc/environment

echo "Installing Vela CLI"
$dau bash -c 'curl -fsSl https://kubevela.io/script/install.sh | bash'
echo "Configuration complete."

echo "Setting KubeVela..."
$dau bash -c 'helm repo add kubevela https://kubevela.github.io/charts && helm repo update'
$dau bash -c 'vela install --version 1.9.11'

$dau bash -c 'helm repo add nebulous https://eu-nebulous.github.io/helm-charts/'

$dau bash -c 'helm repo add netdata https://netdata.github.io/helmchart/'

$dau bash -c 'helm repo update'

echo "Login to docker registry"
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
  --set activemq.ACTIVEMQ_PORT=$BROKER_PORT'

echo "Add volumes provisioner"
$dau bash -c "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.27/deploy/local-path-storage.yaml"  

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
  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/serverless/kourier.yaml
  kubectl apply -f kourier.yaml

  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/serverless/serverless-platform-definition.yaml
  kubectl apply -f serverless-platform-definition.yaml

  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/serverless/config-features.yaml
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
  echo "Serverless installation completed."
fi

if [ "$WORKFLOW_ENABLED" == "yes" ]; then
  echo "Workflow installation.";

  wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/main/workflow/workflow.yaml

  helm install argo-workflows argo-workflows --repo https://argoproj.github.io/argo-helm --namespace argo --create-namespace --values workflow.yaml;
  
  kubectl -n argo create rolebinding argo-workflows-server --role=argo-workflows-workflow --serviceaccount=argo:argo-workflows-server;
  kubectl -n argo create rolebinding argo-workflows-workflow-controller --role=argo-workflows-workflow --serviceaccount=argo:argo-workflows-workflow-controller;
  kubectl -n argo create rolebinding default --role=argo-workflows-workflow --serviceaccount=argo:default;

  echo "Workflow installation completed.";
fi
