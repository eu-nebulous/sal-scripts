
echo "Master start script"
WIREGUARD_VPN_IP=`ip a | grep wg | grep inet | awk '{print $2}' | cut -d'/' -f1`;
echo "WIREGUARD_VPN_IP=$WIREGUARD_VPN_IP";

sudo kubeadm init --apiserver-advertise-address ${WIREGUARD_VPN_IP} --service-cidr 10.96.0.0/16 --pod-network-cidr 10.244.0.0/16

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


#sudo -H -u ubuntu kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml;
sudo -H -u ubuntu bash -c 'helm repo add cilium https://helm.cilium.io/ && helm repo update'
sudo -H -u ubuntu bash -c 'helm install cilium cilium/cilium --namespace kube-system --set encryption.enabled=true --set encryption.type=wireguard'

echo "Setting KubeVela..."
sudo -H -u ubuntu bash -c 'helm repo add kubevela https://kubevela.github.io/charts && helm repo update'
sudo -H -u ubuntu bash -c 'nohup helm install --create-namespace -n vela-system kubevela kubevela/vela-core --version 1.8.2 > /home/ubuntu/vela.txt 2>&1 &'

sudo -H -u ubuntu bash -c 'helm repo add nebulous https://jmarchel7bulls.github.io/helm-charts/'

sudo -H -u ubuntu bash -c 'helm repo add netdata https://netdata.github.io/helmchart/'

sudo -H -u ubuntu bash -c 'helm repo update'

echo "Starting EMS"
  sudo -H -E -u ubuntu bash -c 'helm install ems nebulous/ems-server \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule" \
  --set app_uuid=$APPLICATION_ID \
  --set broker_address=158.37.63.86 \
  --set image.tag="2024-apr-nebulous" \
  --set broker_port=32754'


sudo -H -u ubuntu bash -c 'helm install netdata netdata/netdata'

echo "Starting Solver"
sudo -H -E -u ubuntu bash -c 'helm install solver nebulous/nebulous-optimiser-solver \
  --set tolerations[0].key="node-role.kubernetes.io/control-plane" \
  --set tolerations[0].operator="Exists" \
  --set tolerations[0].effect="NoSchedule" \
  --set amplLicense.keyValue="NjYxZTQzNDQ5ODE2NDczZWIzNDIwNDc2NzZlZjI5Mzc1MjQ0MDUyMGM3MzczYzI5MTg1ODBjNWFmNzBmMzZiN2U3YWYxNzZjYTY2NjQyYTZjMWYzYzFiNjQwNmFlYTgxMTRiZjhhNDg5ZjQ0OGJjZGIyYTc2MDYzNzNiMjNiMTdjNWQ4ZjlhMjg2MjcyYzg4ZjIxOWZjZWZjMTY0MzIxMmU2ZWFjZTY5M2EzMDliYjNlMzBkN2UzNTI3MjA3OTgxZTBhMjNhNWNkOGIzYjcyOGUwZTc2ZWJiZDQwMjNhZTZiNGJkZmFiYmY1MDdkZTJlODM0M2UyNmNjNDc4NjlhNjQ0ZmZkODYxZmQzNjE0ZmVmYTJkYmZhNzI0YmMyODU3MTFmM2Q1Zjg3M2IyOTk0ODViZGNlOTBiYTRlNzc1YjQwMjI1MTI3MzIzNTBlYzZhNjExOGI4NjkyNmUwMDhjNjg1OTQwNjAyYjA5NzhlYzAxMjlmY2Q4NzM0ZDhjNGM2NDIwYmQ4MzE4OWU0NWM0MTk1ZWE4MzMxMzI0NjE4ZjBjN2RlYTViMTk0MTQ0MTJjN2MzMTNiOTIzMmQ4MTVlMGIxZDYzZjYxY2M0MWM1MzIzMDdkOTBiYjkwMWMyYTM0NTZhMWU0MGQ0OTkzOTAxMWEwMTIwMjEwYzNkYWE1YjNlN2YzZTk4ZGNhMDRmZTgyNDA3ZDc4MzQ0NGIzODcwMGU1MzdlNGJkOWI3MmY3MGY1NDQwZGM4YmE1OWE5MjU1YzJlMWM0OGRmYWM2ZTAwNmE5MGZkMzI1ODYwYzVkMzFkNDRlZTBhNTZjZTJlNTM2OWM3MTMzOTE4NWNhZjAxMWIxNzY2NGE3YTRjNWRhZjM5MjMxM2Q4YWUxODdmZTI0NzY2M2JmYjI2MDIwMGFjNGIyN2JmNGI0NDIzNTYxMzE1MmJlZDQxODMzYTZlOWViNTE1YjBjMjNiNjkzMmRhNjE2MmQ3OTE0OWY4NTE1MTdiYTgwNDY4MjAzMzcwODA0YjYyZmZi" \
  --set application.id=$APPLICATION_ID \
  --set activemq.ACTIVEMQ_HOST=158.37.63.86 \
  --set activemq.ACTIVEMQ_PORT=32754'
