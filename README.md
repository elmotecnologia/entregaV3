# KaaS on-premise: Cluster Kubernetes de Alta Disponibilidade com K3s, HAProxy, Calico e Traefik

Este projeto entrega um ambiente **Kubernetes as a Service (KaaS)** em hardware on‑premises (ou VMs), com **alta disponibilidade real**, utilizando:

- **K3s** – distribuição leve e certificada do Kubernetes.
- **HAProxy** – balanceador externo para a API (porta 6443) e para o tráfego de aplicações (HTTP/HTTPS).
- **Calico** – CNI com suporte a Network Policies e melhor desempenho.
- **Traefik** – Ingress Controller exposto via NodePort com portas fixas.

A arquitetura foi testada com failover de qualquer master sem interrupção do cluster, e com roteamento de aplicações de exemplo.

---

## Arquitetura do Ambiente

- **3 nós master** (control-plane + etcd distribuído)
- **2 nós worker**
- **1 nó HAProxy** (balanceador externo)
- Todos os nós rodam Ubuntu 24.04 LTS, em uma rede /24.

### Endereçamento IP utilizado

| Função               | IP          |
|----------------------|-------------|
| master1              | 10.10.50.30 |
| master2              | 10.10.50.31 |
| master3              | 10.10.50.32 |
| worker1              | 10.10.50.33 |
| worker2              | 10.10.50.34 |
| HAProxy              | 10.10.50.61 |
| Host de deploy (opcional) | 10.10.50.60 |

> Os IPs podem ser ajustados conforme sua realidade, mantendo a consistência nas configurações.

---

## Decisões Técnicas e Lições Aprendidas

- **Masters adicionais apontam para o IP direto do primeiro master**  
  `K3S_URL=https://10.10.50.30:6443` – **nunca** para o HAProxy.  
  *Isso garante que o cluster etcd seja realmente formado entre os três masters.*

- **HAProxy com health check TCP (porta 6443)**  
  Evita o erro `401` retornado pelo `/healthz` do Kubernetes quando usado `option httpchk`.

- **`--tls-san` inclui o IP do HAProxy e todos os IPs dos masters**  
  Necessário para que o certificado da API aceite conexões via balanceador e entre os próprios masters.

- **Desabilitação do flannel e do controlador de políticas do K3s**  
  Preparação para instalar o Calico como CNI (arquivo `/etc/rancher/k3s/config.yaml` em todos os masters).

- **Traefik exposto via NodePort com portas fixas (30080/30443)**  
  Facilita a configuração do HAProxy (frontends 80/443 → backends nos masters nessas portas).

---

## Pré‑requisitos

- 5 VMs ou servidores físicos (mínimo 2 vCPU, 2GB RAM cada).
- Ubuntu 24.04 instalado em todos os nós.
- Acesso SSH com chave pública entre o host de deploy e todos os nós.
- Portas liberadas internamente: 6443 (API), 2379/2380 (etcd), 8472 (VXLAN do Calico), 80/443 (tráfego HTTP/HTTPS).
- (Opcional) Ansible para automação – os comandos manuais estão documentados.

---

## Passo a Passo de Implantação

### 1. Preparação de todos os nós (swap, sysctl, módulos)

Execute em **todos os nós** (masters, workers e HAProxy, se aplicável):


sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
sudo modprobe br_netfilter
echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p


### 2. Instalação do HAProxy (balanceador)

No nó `10.10.50.61`:


sudo apt update && sudo apt install -y haproxy


Crie o arquivo `/etc/haproxy/haproxy.cfg` conforme o conteúdo fornecido na seção [Configuração do HAProxy](#configuração-do-haproxy). Em seguida:


sudo haproxy -f /etc/haproxy/haproxy.cfg -c
sudo systemctl enable --now haproxy


### 3. Instalação do primeiro master (master1)


curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.27.4+k3s1 sh -s - server \
  --cluster-init \
  --disable servicelb \
  --disable traefik \
  --tls-san 10.10.50.61 \
  --tls-san 10.10.50.30 \
  --tls-san 10.10.50.31 \
  --tls-san 10.10.50.32 \
  --write-kubeconfig-mode 644


Salve o token do cluster (será usado nos próximos nós):


sudo cat /var/lib/rancher/k3s/server/node-token


### 4. Instalação dos masters adicionais (master2 e master3)

Em **master2 (10.10.50.31)** e **master3 (10.10.50.32)** , execute (substitua `TOKEN` pelo valor obtido acima):


TOKEN="seu_token_aqui"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.27.4+k3s1 \
  K3S_URL=https://10.10.50.30:6443 \
  K3S_TOKEN=$TOKEN \
  sh -s - server \
  --disable servicelb \
  --disable traefik \
  --tls-san 10.10.50.61 \
  --tls-san 10.10.50.30 \
  --tls-san 10.10.50.31 \
  --tls-san 10.10.50.32


### 5. Instalação dos workers

Em cada worker (10.10.50.33 e 10.10.50.34):


TOKEN="seu_token_aqui"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.27.4+k3s1 \
  K3S_URL=https://10.10.50.61:6443 \
  K3S_TOKEN=$TOKEN \
  sh -s - agent


> Os workers podem apontar para o HAProxy (ou diretamente para qualquer master).

### 6. Configurar kubeconfig local

No seu host de administração (ex.: master1), copie o kubeconfig para seu usuário:


mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config


Edite `~/.kube/config` e altere `server: https://127.0.0.1:6443` para `server: https://10.10.50.61:6443`.

### 7. Desabilitar flannel e policy padrão (preparar para Calico)

Em **todos os masters**, crie o arquivo `/etc/rancher/k3s/config.yaml`:

yaml
disable-network-policy: true
flannel-backend: none


Reinicie o K3s em cada master:


sudo systemctl restart k3s


Aguarde alguns segundos. Os nodes ficarão `NotReady` até a instalação do Calico (normal).

### 8. Instalar Calico CNI

Aplique os manifests (em qualquer master com kubectl funcional):


kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/custom-resources.yaml


Acompanhe a instalação:


watch kubectl get pods -n calico-system


Quando todos os pods estiverem `Running`, os nodes voltarão ao estado `Ready`.

### 9. Instalar Traefik como Ingress Controller

Crie um arquivo `traefik-values.yaml`:

yaml
service:
  enabled: true
  type: NodePort
  nodePorts:
    web:
      port: 80
      nodePort: 30080
    websecure:
      port: 443
      nodePort: 30443


Adicione o repositório Helm e instale:


helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik --namespace traefik --create-namespace -f traefik-values.yaml


Se o serviço aparecer como `LoadBalancer` (com portas aleatórias), edite-o manualmente:


kubectl edit svc -n traefik traefik
# Altere type: LoadBalancer → type: NodePort
# Adicione nodePort: 30080 e nodePort: 30443 nos respectivos ports


Verifique:


kubectl get svc -n traefik traefik


Saída esperada: `80:30080/TCP,443:30443/TCP`.

### 10. Configurar HAProxy para Ingress (portas 80 e 443)

Adicione os frontends/backends para HTTP e HTTPS no `/etc/haproxy/haproxy.cfg` (conforme modelo abaixo). Recarregue o HAProxy:


sudo haproxy -f /etc/haproxy/haproxy.cfg -c
sudo systemctl reload haproxy


---

## Arquivos de Configuração

### Configuração completa do HAProxy (`haproxy.cfg`)

haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend kubernetes-api
    bind *:6443
    mode tcp
    default_backend kubernetes-apiservers

backend kubernetes-apiservers
    mode tcp
    balance roundrobin
    server cp1 10.10.50.30:6443 check fall 3 rise 2
    server cp2 10.10.50.31:6443 check fall 3 rise 2
    server cp3 10.10.50.32:6443 check fall 3 rise 2

frontend http-in
    bind *:80
    mode tcp
    default_backend traefik-http

backend traefik-http
    mode tcp
    balance roundrobin
    server master1 10.10.50.30:30080 check fall 3 rise 2
    server master2 10.10.50.31:30080 check fall 3 rise 2
    server master3 10.10.50.32:30080 check fall 3 rise 2

frontend https-in
    bind *:443
    mode tcp
    default_backend traefik-https

backend traefik-https
    mode tcp
    balance roundrobin
    server master1 10.10.50.30:30443 check fall 3 rise 2
    server master2 10.10.50.31:30443 check fall 3 rise 2
    server master3 10.10.50.32:30443 check fall 3 rise 2

frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy?stats
    stats refresh 10s
    stats auth admin:3lm0T3cn0l0gia


### Configuração do K3s para desabilitar flannel (`/etc/rancher/k3s/config.yaml`)

yaml
disable-network-policy: true
flannel-backend: none


---

## Testes de Validação

### Cluster e API


kubectl get nodes
kubectl get pods -A
curl -k https://10.10.50.61:6443/healthz


### Failover de master

Em um terminal: `watch kubectl get nodes`  
Em outro: `sudo systemctl stop k3s` no master1.  
O cluster deve continuar respondendo via HAProxy.

### Ingress de exemplo


kubectl create deployment whoami --image=traefik/whoami
kubectl expose deployment whoami --port=80
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
spec:
  rules:
  - host: whoami.local
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: whoami
            port:
              number: 80
EOF


Teste:


curl -H "Host: whoami.local" http://10.10.50.61


Saída deve mostrar os detalhes do pod `whoami`.

---

## Erros Comuns e Soluções

- **Masters adicionais não formam etcd** → Verifique se `K3S_URL` aponta para o IP direto do primeiro master (não para o HAProxy).
- **HAProxy com health check 401** → Use apenas `check` (TCP), sem `option httpchk`.
- **Nós ficam `NotReady` após desabilitar flannel** → Instale o Calico imediatamente.
- **Serviço Traefik não aceita NodePort fixo** → Edite o serviço manualmente ou crie um NodePort separado.
- **`kubectl` sem `sudo` não funciona** → Copie o kubeconfig do K3s para `~/.kube/config` e ajuste o `server` para o IP do HAProxy.

---

## Próximos Passos (Opcionais)

- **HTTPS com Let's Encrypt**: Instalar cert-manager e configurar ingress com TLS.
- **Storage persistente**: Longhorn, Rook/Ceph ou local-path-provisioner.
- **Monitoramento**: Prometheus + Grafana (kube-prometheus-stack).
- **Backup do etcd**: Snapshots automáticos com `k3s etcd-snapshot`.
- **Dashboard**: Kubernetes Dashboard ou Lens.

---

## Links úteis

- [Documentação oficial do K3s](https://docs.k3s.io)
- [Calico para K3s](https://docs.tigera.io/calico/latest/getting-started/kubernetes/k3s/quickstart)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
- [HAProxy Documentation](https://www.haproxy.com/documentation/haproxy-configuration-manual/)

---

## Licença

Este projeto é distribuído sob a licença MIT. Sinta-se livre para usar, modificar e distribuir.

---

**Desenvolvido por [Emerson Domingues Câmara]**  
🔗 [LinkedIn]www.linkedin.com/in/emersondcamara
) • [YouTube](https://www.youtube.com/@emersondcamara) • [GitHub](https://github.com/elmotecnologia)
