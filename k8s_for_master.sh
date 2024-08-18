# setup_k8s_for_local_env.sh
# for kubeadm, this for master instance
#!/bin/bash

echo "Updating APT package index..."
apt update
echo "APT package index updated."

echo "Installing Vim and Git..."
apt install -y vim git
echo "Vim and Git installation completed."

echo "firewalld part"
sudo apt-get install -y firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld

sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

#마스터 노드일 경우
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250-10252/tcp
sudo firewall-cmd --permanent --add-port=8285/udp
sudo firewall-cmd --permanent --add-port=8472/udp
sudo firewall-cmd --reload

echo "Script execution finished."

echo "Updating and upgrading apt packages..."
sudo apt update && sudo apt upgrade -y
echo "Completed updating and upgrading apt packages."

echo "Disabling swap..."
swapoff -a
echo "Swap disabled."

echo "Commenting out the swap partition in /etc/fstab..."
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab
echo "Swap partition commented out in /etc/fstab."

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf > /dev/null
overlay
br_netfilter
EOF

echo "Loading br_netfilter module... and Load overlay module"
modprobe br_netfilter
modprobe overlay
echo "br_netfilter module loaded."


tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
echo "iptables configuration completed."

echo "Applying sysctl settings..."
sysctl --system
echo "Sysctl settings applied."

#install kubernetes packge 
echo "Installing APT transport HTTPS and other dependencies..."
sudo apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
echo "APT transport HTTPS and other dependencies installed."

# Ensure /etc/apt/keyrings directory exists
if [ ! -d /etc/apt/keyrings ]; then
	sudo mkdir -p /etc/apt/keyrings
	sudo chmod 755 /etc/apt/keyrings
fi

# Add Docker GPG key
if [ ! -f /etc/apt/keyrings/docker.gpg ]; tehn
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
fi

# Add Docker repository
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
	echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

# Update apt cache
sudo apt-get update

# Install containerd.io.package
sudo apt-get install -y containerd.io

# Generate default containerd config
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1

# Modify containerd config for SystemdCgroup
echo "Modifying containerd config for SystemdCgroup..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
echo "Containerd config modification completed."

# Restart containerd service
echo "Restarting containerd service..."
sudo systemctl restart containerd
echo "Containerd service restarted."

# Enable containerd service on boot
echo "Enabling containerd service on boot..."
sudo systemctl enable containerd
echo "Containerd service enabled."

# Ensure /etc/apt/keyrings directory exists and add Kubernetes apt-key
echo "Adding Kubernetes apt-key..."
if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null
  echo "Kubernetes apt-key added."
else
  echo "Kubernetes apt-key already exists. Skipping."
fi

# Add Kubernetes APT repository
echo "Adding Kubernetes APT repository..."
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
echo "Kubernetes APT repository added."

# Update apt cache
echo "Updating apt cache..."
sudo apt-get update
echo "APT cache updated."

# Install kubeadm, kubelet, kubectl
echo "Installing kubeadm, kubelet, kubectl..."
sudo apt-get install -y kubeadm kubelet kubectl
echo "Installation of kubeadm, kubelet, kubectl completed."

# Mark Kubernetes packages to hold version
echo "Holding Kubernetes package versions..."
sudo apt-mark hold kubelet kubeadm kubectl
echo "Kubernetes package versions held."

# Enable and start kubelet service
echo "Enabling and starting kubelet service..."
sudo systemctl enable kubelet
sudo systemctl start kubelet
echo "Kubelet service enabled and started."

# Variables (Replace with your actual values if needed)
POD_NETWORK_CIDR="192.168.0.0/16" # CNI Calico설치로 인한 고정
API_SERVER_ADDRESS="" # master instance ip addr 

echo "Initializing Kubernetes Cluster..."
kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR --apiserver-advertise-address=$API_SERVER_ADDRESS
if [ $? -eq 0 ]; then
  echo "Kubernetes Cluster initialized successfully."
else
  echo "Failed to initialize Kubernetes Cluster." >&2
  exit 1
fi

echo "Setting up kubeconfig for the user..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
echo "kubeconfig setup completed."

# Download Calico manifest
echo "Downloading Calico manifest..."
curl -o /tmp/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/calico.yaml
if [ $? -eq 0 ]; then
  echo "Calico manifest downloaded successfully."
else
  echo "Failed to download Calico manifest." >&2
  exit 1
fi

# Apply Calico network plugin
echo "Applying Calico network plugin..."
kubectl apply -f /tmp/calico.yaml
if [ $? -eq 0 ]; then
  echo "Calico network plugin applied successfully."
else
  echo "Failed to apply Calico network plugin." >&2
  exit 1
fi

echo "Script execution completed.""


