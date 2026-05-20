sudo tee /etc/rancher/k3s/config.yaml <<EOF
token: "MeuTokenSuperSeguroK3s2024"
tls-san:
  - 10.10.20.100
  - master1
  - master2
  - master3
cluster-init: true
disable:
  - servicelb
  - traefik
write-kubeconfig-mode: "644"
EOF
