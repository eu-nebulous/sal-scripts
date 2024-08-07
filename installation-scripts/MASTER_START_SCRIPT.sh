#!/bin/bash
echo "Master start script"

sudo kubeadm init --pod-network-cidr 10.244.0.0/16

echo "HOME: $(pwd), USERE: $(id -u -n)"
mkdir -p ~/.kube && sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config
id -u ubuntu &> /dev/null

if [[ $? -eq 0 ]]
then
    #USER ubuntu is found
    mkdir -p /home/ubuntu/.kube && sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config && sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config
else
    echo "User Ubuntu is not found"
fi


sudo -H -u ubuntu kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml;

echo "Setting KubeVela..."
sudo -H -u ubuntu bash -c 'helm repo add kubevela https://kubevela.github.io/charts && helm repo update'
sudo -H -u ubuntu bash -c 'nohup vela install --version 1.9.11 > /home/ubuntu/vela.txt 2>&1 &'

sudo -H -u ubuntu bash -c 'helm repo add nebulous https://eu-nebulous.github.io/helm-charts/'

sudo -H -u ubuntu bash -c 'helm repo add netdata https://netdata.github.io/helmchart/'

sudo -H -u ubuntu bash -c 'helm repo update'

echo "Starting EMS"
  sudo -H -E -u ubuntu bash -c 'helm install ems nebulous/ems-server \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule" \
  --set app_uuid=$APPLICATION_ID \
  --set broker_address=$BROKER_IP \
  --set image.tag="2024-apr-nebulous" \
  --set broker_port=$BROKER_PORT'


sudo -H -u ubuntu bash -c 'helm install netdata netdata/netdata'

echo "Starting Solver"
sudo -H -E -u ubuntu bash -c 'helm install solver nebulous/nebulous-optimiser-solver \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule" \
  --set amplLicense.keyValue="$LICENSE_AMPL" \
  --set application.id=$APPLICATION_ID \
  --set activemq.ACTIVEMQ_HOST=$BROKER_IP \
  --set activemq.ACTIVEMQ_PORT=$BROKER_PORT'
