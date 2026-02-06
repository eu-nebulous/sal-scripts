#!/bin/bash
echo "Master start script"

# dau - do as ubuntu
dau="sudo -H -E -u ubuntu"
NEBULOUS_SCRIPTS_BRANCH="main"
if [[ -z "$NEBULOUS_SCRIPTS_BRANCH" ]]; then
    NEBULOUS_SCRIPTS_BRANCH="r1"
fi
echo "NEBULOUS_SCRIPTS_BRANCH is set to: $NEBULOUS_SCRIPTS_BRANCH"

if [[ "$CONTAINERIZATION_FLAVOR" == "k3s" ]]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  echo "KUBECONFIG=${KUBECONFIG}" | sudo tee -a /etc/environment
else
  export KUBECONFIG=/home/ubuntu/.kube/config
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

echo "Deciding on the pod network plugin to use. USE_FLANNEL to yes to use Flannel, otherwise it will use Cilium"
if [ "$USE_FLANNEL" == "yes" ]; then
  echo "Using Flannel"
  $dau bash -c 'kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml';
else
  echo "Using Cilium"
  $dau bash -c 'helm repo add cilium https://helm.cilium.io/ && helm repo update'
  $dau bash -c 'helm install cilium cilium/cilium --namespace kube-system --set encryption.enabled=true --set encryption.type=wireguard'
fi

echo "Installing Vela CLI"
$dau bash -c 'curl -fsSl https://kubevela.io/script/install.sh | bash'
echo "Configuration complete."

cat > /home/ubuntu/kubevela-values.yaml << EOF
nodeSelector:
  "node-role.kubernetes.io/control-plane": ""
tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
EOF

$dau bash -c 'helm repo add kubevela https://kubevela.github.io/charts && helm repo update'

cat > /home/ubuntu/patch-pin-to-control-plane.yaml << EOF
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      nodeSelector:
        "node-role.kubernetes.io/control-plane": ""
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
EOF

echo "Setting KubeVela..."
# Delete the flag file if it exists
$dau bash -c 'rm -f /tmp/vela_ready.flag'
# Function to check for worker nodes and install KubeVela
cat > /home/ubuntu/install_kubevela.sh << 'EOF'
#!/bin/bash
echo "Start install_kubevela.sh"
echo "-----${KUBECONFIG}---------"
sudo cat ${KUBECONFIG}
echo "--------------"
# Retry vela install with a 10-second delay between attempts
attempt=1
until sudo -H -E -u ubuntu bash -c 'helm upgrade --install --create-namespace -n vela-system kubevela kubevela/vela-core --version 1.9.11 --values /home/ubuntu/kubevela-values.yaml --wait'; do
  echo "Vela install failed. Retrying in 10 seconds... ($attempt/)"
  attempt=$((attempt+1))
  sleep 10
done
echo "Vela installation done."
if [ "$SERVERLESS_ENABLED" == "yes" ]; then
  echo "Serverless installation."

  # Install Cosign
  export COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | jq -r '.tag_name')
  sudo curl -LO "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
  sudo mv cosign-linux-amd64 /usr/local/bin/cosign
  sudo chmod +x /usr/local/bin/cosign

  # Update system and install jq
  sudo apt update
  sudo apt install -y jq

  # Apply Knative Serving CRDs and core components
  kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.4/serving-crds.yaml
  kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.12.4/serving-core.yaml
  kubectl patch deployment -n knative-serving activator --patch "$(cat /home/ubuntu/patch-pin-to-control-plane.yaml)"
  kubectl patch deployment -n knative-serving autoscaler --patch "$(cat /home/ubuntu/patch-pin-to-control-plane.yaml)"
  kubectl patch deployment -n knative-serving controller --patch "$(cat /home/ubuntu/patch-pin-to-control-plane.yaml)"
  kubectl patch deployment -n knative-serving webhook --patch "$(cat /home/ubuntu/patch-pin-to-control-plane.yaml)"

  # Download and apply Kourier
  sudo wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/kourier.yaml
  kubectl apply -f kourier.yaml

  sudo wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/serverless-platform-definition.yaml
  kubectl apply -f serverless-platform-definition.yaml


  sudo wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/knative-serving-definition.yaml
  kubectl apply -f knative-serving-definition.yaml

  sudo wget https://raw.githubusercontent.com/eu-nebulous/sal-scripts/$NEBULOUS_SCRIPTS_BRANCH/serverless/config-features.yaml
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

is_vela_installed() {
  if vela ls &>/dev/null; then
      return 0
  else
      return 1
  fi
}

# Wait for at least one worker node to be ready
while true; do
    WORKER_NODES=$(sudo -H -E -u ubuntu kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o json | jq '.items | length')
    if [ "$WORKER_NODES" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Found $WORKER_NODES worker node(s), proceeding with KubeVela installation..." >> /home/ubuntu/vela.txt
        /home/ubuntu/install_kubevela.sh >> /home/ubuntu/vela.txt 2>&1
        if is_vela_installed; then
          echo "Vela installation successful" >> /home/ubuntu/vela.txt
          # Disable the service after successful installation
          echo "Disabling kubevela-installer.service" >> /home/ubuntu/vela.txt
          sudo systemctl disable kubevela-installer.service
          # Create a flag file to indicate that vela is ready. This flag will be read by the script that runs `vela up -f ...`.
          # This is is needed to avoid the vela up command to fail if the vela installation has not completed yet.
          echo "touching /tmp/vela_ready.flag" >> /home/ubuntu/vela.txt
          touch /tmp/vela_ready.flag
          exit 0
        else
          echo "'vela ls' returned an error. Trying again in 30 seconds..." >> /home/ubuntu/vela.txt
          sleep 30
        fi
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
Environment="APPLICATION_ID=${APPLICATION_ID}"
Environment="NEBULOUS_SCRIPTS_BRANCH=${NEBULOUS_SCRIPTS_BRANCH}"
Environment="KUBECONFIG=${KUBECONFIG}"

[Install]
WantedBy=multi-user.target
EOF



$dau bash -c 'helm repo add nebulous https://eu-nebulous.github.io/helm-charts/'
$dau bash -c 'helm repo add netdata https://netdata.github.io/helmchart/'
$dau bash -c 'helm repo update'

if [[ -n "${PRIVATE_DOCKER_REGISTRY_SERVER}" ]]; then
    echo "Private Docker registry server is configured: ${PRIVATE_DOCKER_REGISTRY_SERVER}"
    if [[ -z "${PRIVATE_DOCKER_REGISTRY_SERVER}" ]] || [[ -z "${PRIVATE_DOCKER_REGISTRY_USERNAME}" ]] || [[ -z "${PRIVATE_DOCKER_REGISTRY_PASSWORD}" ]] || [[ -z "${PRIVATE_DOCKER_REGISTRY_EMAIL}" ]]; then
        echo "ERROR: One or more required Docker registry environment variables are not set or empty"
        echo "Please ensure PRIVATE_DOCKER_REGISTRY_SERVER, PRIVATE_DOCKER_REGISTRY_USERNAME, PRIVATE_DOCKER_REGISTRY_PASSWORD, and PRIVATE_DOCKER_REGISTRY_EMAIL are properly configured"
    fi
    
    echo "Login to docker registry"
    $dau bash -c "kubectl delete secret docker-registry regcred --ignore-not-found"
    $dau bash -c "kubectl create secret docker-registry regcred --docker-server=$PRIVATE_DOCKER_REGISTRY_SERVER --docker-username=$PRIVATE_DOCKER_REGISTRY_USERNAME --docker-password=$PRIVATE_DOCKER_REGISTRY_PASSWORD --docker-email=$PRIVATE_DOCKER_REGISTRY_EMAIL"

fi


if [ "$COMPONENTS_IN_CLUSTER" == "yes" ]; then
  echo "Installing nebulous components in cluster"
  if [[ -z "${NEBULOUS_MESSAGE_BRIDGE_PASSWORD}" ]]; then
      echo "ERROR: NEBULOUS_MESSAGE_BRIDGE_PASSWORD environment variable is not set"
      exit 1
  fi
  # If APP_BROKER_PORT is given, use it. Otherwise, use 30356.
  app_broker_port=${APP_BROKER_PORT:-30356}
  influxdb_port=${INFLUXDB_PORT:-32754}
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
  echo "Installing ActiveMQ"
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
  --set-string brokerEnv[1].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set brokerEnv[2].name=\"ACTIVEMQ_ADMIN_PASSWORD\" \
  --set-string brokerEnv[2].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set brokerEnv[3].name=\"APPLICATION_ID\" \
  --set-string brokerEnv[3].value=\"$APPLICATION_ID\" \
  --set brokerEnv[4].name=\"NEBULOUS_MESSAGE_BRIDGE_PASSWORD\" \
  --set-string brokerEnv[4].value=\"$NEBULOUS_MESSAGE_BRIDGE_PASSWORD\" \
  --set brokerEnv[5].name=\"NEBULOUS_CONTROL_PLANE_BROKER_ADDRESS\" \
  --set-string brokerEnv[5].value=\"$CONTROL_PLANE_BROKER_ADDRESS:$CONTROL_PLANE_BROKER_PORT\" \
  --set brokerEnv[6].name=\"APP_BROKER_ADDRESS\" \
  --set-string brokerEnv[6].value=\"$app_broker_address:$app_broker_port\" \
  --set brokerEnv[7].name=\"INFLUXDB_URL\" \
  --set-string brokerEnv[7].value=\"http://$app_broker_address:$influxdb_port\" \
  --set brokerEnv[8].name=\"INFLUXDB_ORG\" \
  --set-string brokerEnv[8].value=\"my-org\" \
  --set brokerEnv[9].name=\"INFLUXDB_TOKEN\" \
  --set-string brokerEnv[9].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set service.activemQNodePort=$app_broker_port \
  --set service.type=\"NodePort\" \
  --wait"
  
  # install influxdb app
  echo "Installing InfluxDB"
  $dau bash -c "helm install nebulous-influxdb-app nebulous/nebulous-influxdb-app \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set fullnameOverride=\"nebulous-influxdb\" \
  --set secrets.DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\" \
  --set service.influxdbNodePort=$influxdb_port \
  --set service.type=\"NodePort\" \
  --wait"

  # install ai anomaly detection app
  echo "Installing AI Anomaly Detection"
  $dau bash -c "helm install nebulous-ai-anomaly-detection nebulous/nebulous-ai-anomaly-detection \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"BROKER_ADDRESS\" \
  --set-string env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"BROKER_PORT\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"BROKER_USERNAME\" \
  --set-string env[2].value=\"admin\" \
  --set env[3].name=\"BROKER_PASSWORD\" \
  --set-string env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set-string env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\""

  # install prediction orchestrator app
  echo "Installing Prediction Orchestrator"
  $dau bash -c "helm install nebulous-prediction-orchestrator nebulous/nebulous-prediction-orchestrator \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set application.env.exnPort=\"61616\" \
  --set application.env.exnHost=\"nebulous-activemq\" \
  --set application.env.exnUsername=\"admin\" \
  --set application.env.exnPassword=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set application.env.influxToken='$INFLUXDB_TOKEN' \
  --set image.tag=\"main\""

  # install lstm predictor app
  echo "Installing LSTM Predictor"
  $dau bash -c "helm install nebulous-lstm-predictor nebulous/nebulous-lstm-predictor \
  --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
  --set tolerations[0].operator=\"Exists\" \
  --set tolerations[0].effect=\"NoSchedule\" \
  --set env[0].name=\"BROKER_ADDRESS\" \
  --set env[0].value=\"nebulous-activemq\" \
  --set env[1].name=\"BROKER_PORT\" \
  --set-string env[1].value=61616 \
  --set env[2].name=\"BROKER_USERNAME\" \
  --set-string env[2].value=\"admin\" \
  --set env[3].name=\"BROKER_PASSWORD\" \
  --set-string env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set-string env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\" \
  --set resources.limits.memory=\"3Gi\""

  # install exponential smoothing predictor app
  echo "Installing Exponential Smoothing Predictor"
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
  --set-string env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set-string env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\" \
  --set resources.limits.memory=\"3Gi\""

  # install slo violation detector app
  echo "Installing SLO Violation Detector"
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
  --set-string env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set image.tag=\"main\""


  # install monitoring data persistor app
  echo "Installing Monitoring Data Persistor"
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
  --set-string env[3].value=\"$APP_BROKER_ADMIN_PASSWORD\" \
  --set env[4].name=\"INFLUXDB_TOKEN\" \
  --set-string env[4].value=\"$INFLUXDB_ADMIN_TOKEN\" \
  --set image.tag=\"main\""

  # install ems server
  echo "Installing EMS"
  $dau bash -c "helm install ems nebulous/ems-server \
    --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
    --set tolerations[0].operator=\"Exists\" \
    --set tolerations[0].effect=\"NoSchedule\" \
    --set app_uuid=\"$APPLICATION_ID\" \
    --set broker_address=\"nebulous-activemq\" \
    --set broker_port=\"61616\" \
    --set broker_username=\"admin\" \
    --set-string broker_password=\"$APP_BROKER_ADMIN_PASSWORD\" \
    --set client.image.tag=\"ems-client-$NEBULOUS_SCRIPTS_BRANCH\""

  $dau bash -c "helm install netdata netdata/netdata"

  # install solver
  echo "Installing Solver"
  $dau bash -c "helm install solver nebulous/nebulous-optimiser-solver \
    --set image.tag=\"main\" \
    --set tolerations[0].key=\"node-role.kubernetes.io/control-plane\" \
    --set tolerations[0].operator=\"Exists\" \
    --set tolerations[0].effect=\"NoSchedule\" \
    --set AMPL_LICENSE=\"$LICENSE_AMPL\" \
    --set application.id=\"$APPLICATION_ID\" \
    --set activemq.ACTIVEMQ_HOST=\"nebulous-activemq\" \
    --set activemq.ACTIVEMQ_PORT=\"61616\" \
    --set image.tag=\"$NEBULOUS_SCRIPTS_BRANCH\" \
    --set activemq.ACTIVEMQ_USER=\"admin\" \
    --set activemq.ACTIVEMQ_PASSWORD=\"$APP_BROKER_ADMIN_PASSWORD\"" 
else
  echo "Insalling minimal components in cluster"
  echo "Installing EMS"
  $dau bash -c 'helm install ems nebulous/ems-server \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule" \
    --set app_uuid=$APPLICATION_ID \
    --set broker_address=$CONTROL_PLANE_BROKER_ADDRESS \
    --set broker_username=$CONTROL_PLANE_BROKER_STATIC_APP_CLIENT_USER \
    --set broker_password=$CONTROL_PLANE_BROKER_STATIC_APP_CLIENT_PASSWORD \
    --set client.image.tag="ems-client-$NEBULOUS_SCRIPTS_BRANCH" \
    --set broker_port=$CONTROL_PLANE_BROKER_PORT'

  $dau bash -c 'helm install netdata netdata/netdata'
  echo "Installing  Solver"
  $dau bash -c 'helm install solver nebulous/nebulous-optimiser-solver \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule" \
    --set AMPL_LICENSE="$LICENSE_AMPL" \
    --set application.id=$APPLICATION_ID \
    --set activemq.ACTIVEMQ_USER=$CONTROL_PLANE_BROKER_STATIC_APP_CLIENT_USER \
    --set activemq.ACTIVEMQ_PASSWORD=$CONTROL_PLANE_BROKER_STATIC_APP_CLIENT_PASSWORD \
    --set activemq.ACTIVEMQ_HOST=$CONTROL_PLANE_BROKER_ADDRESS \
    --set activemq.ACTIVEMQ_PORT=$CONTROL_PLANE_BROKER_PORT \
    --set image.tag="$NEBULOUS_SCRIPTS_BRANCH"' 
fi


echo "Add volumes provisioner"
$dau bash -c "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.27/deploy/local-path-storage.yaml"  


if [ "$WORKFLOW_ENABLED" == "yes" ]; then
  echo "Workflow installation.";

  $dau bash -c 'helm install -n argo nebulous-workflow-executor nebulous/nebulous-workflow-executor --create-namespace'

  $dau bash -c "kubectl -n argo create secret docker-registry regcred --docker-server=$PRIVATE_DOCKER_REGISTRY_SERVER --docker-username=$PRIVATE_DOCKER_REGISTRY_USERNAME --docker-password=$PRIVATE_DOCKER_REGISTRY_PASSWORD --docker-email=$PRIVATE_DOCKER_REGISTRY_EMAIL"
  $dau bash -c 'kubectl -n argo patch serviceaccount default -p "{\"imagePullSecrets\": [{\"name\": \"regcred\"}]}"'

  echo "Workflow installation completed.";
fi

if [ "$SECURITY_MANAGER_ENABLED" == "yes" ]; then
  echo "Installing OPA Gatekeeper..."
  wget https://raw.githubusercontent.com/eu-nebulous/security-manager/dev/OPA-GATEKEEPER-INSTALL.sh
  chmod +x OPA-GATEKEEPER-INSTALL.sh
  ./OPA-GATEKEEPER-INSTALL.sh

  echo "Installing Security Manager..."
  $dau bash -c 'helm install security-manager nebulous/nebulous-security-manager \
    --set-file configMap.k3sConfig="$KUBECONFIG" \
    --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
    --set tolerations[0].operator="Exists" \
    --set tolerations[0].effect="NoSchedule"'
fi



# Enable and start the vela install service. Do this last to make sure message broker is ready.
sudo systemctl daemon-reload
sudo systemctl enable kubevela-installer.service
sudo systemctl start kubevela-installer.service