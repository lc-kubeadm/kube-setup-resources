#!/bin/bash

KUBELET_VERSION="1.13.2-00"
KUBEADM_VERSION="1.13.2-00"
KUBECTL_VERSION="1.13.2-00"
DOCKER_VERSION="18.06.1~ce~3-0~ubuntu"


echo " ------------------ Kubeadm kubernetes installer ----------------"
echo " ------------------ installer for Worker node    ----------------"

apt-mark unhold kubelet kubeadm docker-ce

#apt purge kubelet kubeadm kubectl docker-ce

apt-get update && apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update


apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common -y

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

apt-key fingerprint 0EBFCD88

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"


apt-get update
apt-get install  kubelet=$KUBELET_VERSION kubeadm=$KUBEADM_VERSION docker-ce=$DOCKER_VERSION
apt install kubectl=$KUBECTL_VERSION && apt-mark hold kubectl

apt-mark hold kubelet kubeadm  docker-ce
echo " ------------------ Kubeadm kubernetes installer | Finised  ----------------"

echo " ------------------ Initiating Kubernetes Cluster Main Master  ----------------"

kubeadm init --config /home/ubuntu/kubeadm-config.yaml

set -e

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

IP=`ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}'`
IPCLUSTER=$IP:6443;echo "kubeadm join --token $(kubeadm token list | sed '1d' | head -1| awk '{print $1}') $IPCLUSTER --discovery-token-ca-cert-hash sha256:$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}')" > Join-token.txt

echo " ------------------ Installing the Weave CNI plugin ----------------"

kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

echo " ------------------ Installing the Dashboard ----------------"

kubectl apply -f kubernetes-dashboard.yaml

echo " ------------------ Extracting the Dashboard Login Certificates ----------------"

grep 'client-certificate-data' ~/.kube/config | head -n 1 | awk '{print $2}' | base64 -d >> kubecfg.crt
grep 'client-key-data' ~/.kube/config | head -n 1 | awk '{print $2}' | base64 -d >> kubecfg.key

openssl pkcs12 -export -clcerts -inkey kubecfg.key -in kubecfg.crt -out kubecfg.p12 -name "kubernetes-client"


echo " ------------------ Creating a Dashboard User ----------------"

cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF

cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') > login_token


echo " ------------------ Dashboard user login Token is saved at /home/ubuntu/login_token ----------------"
