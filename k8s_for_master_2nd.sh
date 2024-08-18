#!/bin/bash

# 환경 변수 설정 (필요시 secrets.yml에서 읽어오거나 환경 변수로 설정)
PRIVATE_KEY_FILE="path_to_private_key"
MASTER_PRIVATE_IP="your_master_private_ip"

# 모든 호스트에 공통적으로 수행할 작업
# apt 캐시 업데이트 및 모든 패키지 업그레이드
apt-get update
apt-get upgrade -y

# 스왑 비활성화
swapoff -a

# /etc/fstab에서 스왑 파티션 주석 처리
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab

# containerd.conf 생성 및 커널 모듈 로드
cat <<EOF > /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 네트워크 설정
cat <<EOF > /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# Kubernetes 및 containerd를 위한 필수 패키지 설치
apt-get install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Docker GPG 키 추가 및 Docker 리포지토리 설정
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

apt-get update

# containerd 설치 및 설정
apt-get install -y containerd.io

containerd config default | tee /etc/containerd/config.toml > /dev/null 2>&1

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# Kubernetes apt-key 추가 및 리포지토리 설정
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update

# Kubernetes 패키지 설치 및 버전 고정
apt-get install -y kubeadm kubelet kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
systemctl start kubelet

# 마스터 노드에서만 실행할 작업
if [ "$HOSTNAME" = "your_master_hostname" ]; then
    # Kubernetes 클러스터 초기화
    kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address="${MASTER_PRIVATE_IP}"

    # kubeconfig 설정
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    # Calico 네트워크 플러그인 다운로드 및 적용
    curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
    kubectl apply -f calico.yaml
fi

# worker_config.yml 관련 작업은 별도로 스크립트화해야 합니다.
