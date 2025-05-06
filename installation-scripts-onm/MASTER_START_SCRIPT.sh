#!/bin/bash
echo "Master start script"

# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"


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
$dau bash -c 'helm repo add kubevela https://kubevela.github.io/charts && helm repo update'

$dau bash -c 'helm install --version 1.9.11 --create-namespace -n vela-system kubevela kubevela/vela-core --wait \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key="node-role.kubernetes.io/control-plane" \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator="Exists" \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule"'

$dau bash -c 'helm repo add nebulous https://eu-nebulous.github.io/helm-charts/'

$dau bash -c 'helm repo add netdata https://netdata.github.io/helmchart/'

$dau bash -c 'helm repo update'

echo "Login to docker registry"
$dau bash -c "kubectl delete secret docker-registry regcred --ignore-not-found"
$dau bash -c "kubectl create secret docker-registry regcred --docker-server=$PRIVATE_DOCKER_REGISTRY_SERVER --docker-username=$PRIVATE_DOCKER_REGISTRY_USERNAME --docker-password=$PRIVATE_DOCKER_REGISTRY_PASSWORD --docker-email=$PRIVATE_DOCKER_REGISTRY_EMAIL"


if [ "$COMPONENTS_IN_CLUSTER" == "yes" ]; then

  if [[ -z "${NEBULOUS_MESSAGE_BRIDGE_PASSWORD}" ]]; then
      echo "ERROR: NEBULOUS_MESSAGE_BRIDGE_PASSWORD environment variable is not set"
      exit 1
  fi
  # If APP_BROKER_PORT is given, use it. Otherwise, use 30356.
  app_broker_port=${APP_BROKER_PORT:-30356}
  # If PUBLIC_IP is given, use it as app_broker_address. Otherwise, determine it.
  app_broker_address=${PUBLIC_IP}

  # If public_ip is not set, fall back to polling multiple services
  if [[ -z "$app_broker_address" ]]; then
    echo "No IP provided. Polling external services to determine public IP..."

    SERVICES=(
      "http://httpbin.org/ip"
      "http://ipinfo.io/ip"
      "http://api.ipify.org"
      "http://ifconfig.me"
      "http://checkip.amazonaws.com"
    )

    extract_ip() {
      echo "$1" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'
    }

    for service in "${SERVICES[@]}"; do
      echo "Trying $service ..."
      response=$(curl -s --max-time 5 "$service")
      ip=$(extract_ip "$response")

      if [[ -n "$ip" ]]; then
        app_broker_address="$ip"
        break
      fi
    done
  fi

  echo "BROKER ADDRESS: $app_broker_address:$app_broker_port"

  # generate a random password for broker admin if not set
  if [[ -z "${APP_BROKER_ADMIN_PASSWORD}" ]]; then
      echo "ERROR: APP_BROKER_ADMIN_PASSWORD environment variable is not set. Generating random password."
      APP_BROKER_ADMIN_PASSWORD=$(openssl rand -base64 32)
      echo "Generated APP_BROKER_ADMIN_PASSWORD: $APP_BROKER_ADMIN_PASSWORD"
  fi
  # generate a random token for influxdb
  INFLUXDB_ADMIN_TOKEN=$(openssl rand -base64 32)
  echo "Generated INFLUXDB_ADMIN_TOKEN: $INFLUXDB_ADMIN_TOKEN"

  # install activemq app
  $dau bash -c "helm install nebulous-activemq-app nebulous/nebulous-activemq-app \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set image.repository=\"quay.io/nebulous/activemq-broker-app-cluster\" \
  --set image.tag=\"componentsinappcluster\" \
  --set fullnameOverride=\"nebulous-activemq\" \
  --set brokerEnv[0].name=\"ARTEMIS_USER\" \
  --set brokerEnv[0].value=\"admin\" \
  --set brokerEnv[1].name=\"ARTEMIS_PASSWORD\" \
  --set brokerEnv[1].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set brokerEnv[2].name=\"ACTIVEMQ_ADMIN_PASSWORD\" \
  --set brokerEnv[2].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set brokerEnv[3].name=\"APPLICATION_ID\" \
  --set brokerEnv[3].value=\"$APPLICATION_ID\" \
  --set brokerEnv[4].name=\"NEBULOUS_MESSAGE_BRIDGE_PASSWORD\" \
  --set brokerEnv[4].value=\"$NEBULOUS_MESSAGE_BRIDGE_PASSWORD\" \
  --set brokerEnv[5].name=\"NEBULOUS_CONTROL_PLANE_BROKER_ADDRESS\" \
  --set brokerEnv[5].value=\"$BROKER_ADDRESS:$BROKER_PORT\" \
  --set brokerEnv[6].name=\"APP_BROKER_ADDRESS\" \
  --set brokerEnv[6].value=\"$app_broker_address:$app_broker_port\" \
  --set service.activemQNodePort=$app_broker_port \
  --set service.type=\"NodePort\""
  
  # install influxdb app
  $dau bash -c "helm install nebulous-influxdb-app nebulous/nebulous-influxdb-app \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set fullnameOverride=\"nebulous-influxdb\" \
  --set secrets.DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\" \
  --set service.type=\"NodePort\""

  # install ai anomaly detection app
  $dau bash -c "helm install nebulous-ai-anomaly-detection nebulous/nebulous-ai-anomaly-detection \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"BROKER_ADDRESS\" \
  --set env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"BROKER_PORT\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"BROKER_USERNAME\" \
  --set env[2].value=\"admin\" \
  --set env[3].name=\"BROKER_PASSWORD\" \
  --set env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\""

  # install prediction orchestrator app
  $dau bash -c "helm install nebulous-prediction-orchestrator nebulous/nebulous-prediction-orchestrator \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set application.env.exnPort=\"61616\" \
  --set application.env.exnHost=\"nebulous-activemq\" \
  --set application.env.exnUsername=\"admin\" \
  --set application.env.exnPassword=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set image.tag=\"main\""

  # install lstm predictor app
  $dau bash -c "helm install nebulous-lstm-predictor nebulous/nebulous-lstm-predictor \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"BROKER_ADDRESS\" \
  --set env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"BROKER_PORT\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"BROKER_USERNAME\" \
  --set env[2].value=\"admin\" \
  --set env[3].name=\"BROKER_PASSWORD\" \
  --set env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\" \
  --set resources.limits.memory=\"3Gi\""

  # install exponential smoothing predictor app
  $dau bash -c "helm install nebulous-exponential-smoothing-predictor nebulous/nebulous-exponential-smoothing-predictor \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"broker_address\" \
  --set env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"broker_port\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"broker_username\" \
  --set env[2].value=\"admin\" \
  --set env[3].name=\"broker_password\" \
  --set env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\" \
  --set resources.limits.memory=\"3Gi\""

  # install slo violation detector app
  $dau bash -c "helm install nebulous-slo-violation-detector nebulous/nebulous-slo-violation-detector \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"BROKER_IP_URL\" \
  --set env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"BROKER_PORT\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"BROKER_USERNAME\" \
  --set env[2].value=\"admin\" \
  --set env[3].name=\"BROKER_PASSWORD\" \
  --set env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set image.tag=\"main\""

  # install monitoring data persistor app
  $dau bash -c "helm install nebulous-monitoring-data-persistor nebulous/nebulous-monitoring-data-persistor \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"broker_ip\" \
  --set env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"broker_port\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"broker_username\" \
  --set env[2].value=\"admin\" \
  --set env[3].name=\"broker_password\" \
  --set env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\""

  # install ems server
  $dau bash -c "helm install ems nebulous/ems-server \
    --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
    --set tolerations[0].operator=\"Exists\" \
    --set tolerations[0].effect=\"NoSchedule\" \
    --set app_uuid=\"$APPLICATION_ID\" \
    --set broker_address=\"nebulous-activemq\" \
    --set broker_port=\"61616\" \
    --set broker_username=\"admin\" \
    --set broker_password=\"$APP_BROKER_ADMIN_PASSWORD\" \
    --set image.tag=\"latest\""

  $dau bash -c "helm install netdata netdata/netdata"

  # install solver
  $dau bash -c "helm install solver nebulous/nebulous-optimiser-solver \
    --set image.tag=\"main-1b2490b9130495c8364a1bfaf0c232b7f74ebbe4-20250505200209\" \
    --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
    --set tolerations[0].operator=\"Exists\" \
    --set tolerations[0].effect=\"NoSchedule\" \
    --set amplLicense.keyValue=\"$LICENSE_AMPL\" \
    --set application.id=\"$APPLICATION_ID\" \
    --set activemq.ACTIVEMQ_HOST=\"nebulous-activemq\" \
    --set activemq.ACTIVEMQ_PORT=\"61616\" \
    --set activemq.ACTIVEMQ_USER=\"admin\" \
    --set activemq.ACTIVEMQ_PASSWORD=\"$APP_BROKER_ADMIN_PASSWORD\""

else
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
fi


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
