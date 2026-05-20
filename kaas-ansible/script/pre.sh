# 1. Atualizar sistema
sudo apt update && sudo apt upgrade -y

# 2. Instalar pacotes básicos
sudo apt install -y curl wget net-tools jq apt-transport-https ca-certificates gnupg lsb-release

# 3. Desabilitar swap (requerido para Kubernetes)
sudo swapoff -a && sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 4. Carregar módulos do kernel
sudo modprobe br_netfilter && sudo modprobe overlay

# 5. Configurar sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 6. Configurar hostnames (ajuste para cada nó)
sudo hostnamectl set-hostname master1   # No master1 (10.10.20.60)
sudo hostnamectl set-hostname master2   # No master2 (10.10.20.61)
sudo hostnamectl set-hostname master3   # No master3 (10.10.20.62)
sudo hostnamectl set-hostname worker1   # No worker1 (10.10.20.63)
sudo hostnamectl set-hostname worker2   # No worker2 (10.10.20.64)

# 7. Atualizar /etc/hosts em todos os nós
cat <<EOF | sudo tee -a /etc/hosts
10.10.20.60 master1
10.10.20.61 master2
10.10.20.62 master3
10.10.20.63 worker1
10.10.20.64 worker2
EOF

