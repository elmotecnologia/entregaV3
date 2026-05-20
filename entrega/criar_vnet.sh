#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
print_msg() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ATENÇÃO]${NC} $1"
}

# Função para validar IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Função para validar CIDR
validate_cidr() {
    local cidr=$1
    if [[ $cidr =~ ^[0-9]{1,2}$ ]] && [ $cidr -ge 0 ] && [ $cidr -le 32 ]; then
        return 0
    else
        return 1
    fi
}

# Função para validar VLAN ID
validate_vlan() {
    local vlan=$1
    if [[ $vlan =~ ^[0-9]+$ ]] && [ $vlan -ge 1 ] && [ $vlan -le 4094 ]; then
        return 0
    else
        return 1
    fi
}

# Função para validar nome (apenas letras, números e hífen)
validate_name() {
    local name=$1
    if [[ $name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Coletar informações do servidor Proxmox
echo "========================================="
echo "   CRIADOR DE VNET - PROXMOX SDN"
echo "========================================="
echo ""

while true; do
    read -p "Digite o IP do servidor Proxmox (ex: 192.168.2.200): " PROXMOX_IP
    if validate_ip "$PROXMOX_IP"; then
        break
    else
        print_error "IP inválido! Digite um IP válido (ex: 192.168.2.200)"
    fi
done

read -p "Digite o usuário SSH (padrão: root): " SSH_USER
SSH_USER=${SSH_USER:-root}

read -sp "Digite a senha SSH (ou pressione Enter se usar chave SSH): " SSH_PASS
echo ""
if [ -n "$SSH_PASS" ]; then
    SSH_CMD="sshpass -p '$SSH_PASS' ssh -o StrictHostKeyChecking=no $SSH_USER@$PROXMOX_IP"
else
    SSH_CMD="ssh -o StrictHostKeyChecking=no $SSH_USER@$PROXMOX_IP"
fi

# Testar conexão SSH
print_msg "Testando conexão SSH..."
if ! $SSH_CMD "echo 'Conexão OK'" > /dev/null 2>&1; then
    print_error "Não foi possível conectar ao servidor Proxmox. Verifique IP, usuário e senha/chave SSH."
    exit 1
fi
print_msg "Conexão SSH estabelecida com sucesso!"

echo ""
echo "========================================="
echo "   CONFIGURAÇÃO DA ZONA"
echo "========================================="

read -p "Nome da zona (padrão: DBaaS): " ZONE_NAME
ZONE_NAME=${ZONE_NAME:-DBaaS}

read -p "Bridge de rede (padrão: vmbr1): " BRIDGE
BRIDGE=${BRIDGE:-vmbr1}

read -p "IPAM (padrão: pve): " IPAM
IPAM=${IPAM:-pve}

echo ""
echo "========================================="
echo "   CONFIGURAÇÃO DA VNET"
echo "========================================="

while true; do
    read -p "Nome da VNet (ex: cliente1, hragem, produção): " VNET_NAME
    if validate_name "$VNET_NAME"; then
        break
    else
        print_error "Nome inválido! Use apenas letras, números, hífen ou underscore."
    fi
done

while true; do
    read -p "VLAN TAG (1-4094): " VLAN_TAG
    if validate_vlan "$VLAN_TAG"; then
        break
    else
        print_error "VLAN TAG inválida! Use um número entre 1 e 4094."
    fi
done

read -p "Isolar portas? (s/n - padrão: s): " ISOLATE_PORTS
if [[ "$ISOLATE_PORTS" =~ ^[SsNn]$ ]]; then
    if [[ "$ISOLATE_PORTS" =~ ^[Ss]$ ]]; then
        ISOLATE=1
    else
        ISOLATE=0
    fi
else
    ISOLATE=1
fi

echo ""
echo "========================================="
echo "   CONFIGURAÇÃO DA SUB-REDE"
echo "========================================="

while true; do
    read -p "Rede (ex: 10.0.101.0): " SUBNET_IP
    if validate_ip "$SUBNET_IP"; then
        break
    else
        print_error "IP de rede inválido!"
    fi
done

while true; do
    read -p "Máscara CIDR (0-32): " CIDR
    if validate_cidr "$CIDR"; then
        break
    else
        print_error "CIDR inválido! Use um número entre 0 e 32."
    fi
done

SUBNET="$SUBNET_IP/$CIDR"

while true; do
    read -p "Gateway (ex: 10.0.101.1): " GATEWAY
    if validate_ip "$GATEWAY"; then
        break
    else
        print_error "Gateway inválido!"
    fi
done

read -p "Ativar SNAT para acesso à internet? (s/n - padrão: s): " ENABLE_SNAT
if [[ "$ENABLE_SNAT" =~ ^[SsNn]$ ]]; then
    if [[ "$ENABLE_SNAT" =~ ^[Ss]$ ]]; then
        SNAT=1
    else
        SNAT=0
    fi
else
    SNAT=1
fi

echo ""
echo "========================================="
echo "   RESUMO DA CONFIGURAÇÃO"
echo "========================================="
echo "Servidor Proxmox: $PROXMOX_IP"
echo "Usuário SSH: $SSH_USER"
echo "Zona: $ZONE_NAME"
echo "Bridge: $BRIDGE"
echo "IPAM: $IPAM"
echo "VNet: $VNET_NAME"
echo "VLAN TAG: $VLAN_TAG"
echo "Isolar Portas: $([ $ISOLATE -eq 1 ] && echo 'Sim' || echo 'Não')"
echo "Sub-rede: $SUBNET"
echo "Gateway: $GATEWAY"
echo "SNAT: $([ $SNAT -eq 1 ] && echo 'Sim' || echo 'Não')"
echo ""

read -p "Confirmar criação? (s/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    print_warning "Operação cancelada pelo usuário."
    exit 0
fi

echo ""
print_msg "Iniciando criação da VNet..."

# 1. Criar/Verificar a zona
print_msg "Criando/Verificando zona $ZONE_NAME..."
$SSH_CMD "pvesh get /cluster/sdn/zones/$ZONE_NAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    $SSH_CMD "pvesh create /cluster/sdn/zones --type vlan --zone $ZONE_NAME --bridge $BRIDGE --ipam $IPAM"
    if [ $? -eq 0 ]; then
        print_msg "Zona $ZONE_NAME criada com sucesso!"
    else
        print_error "Falha ao criar zona $ZONE_NAME"
        exit 1
    fi
else
    print_msg "Zona $ZONE_NAME já existe, continuando..."
fi

# 2. Criar a VNet
print_msg "Criando VNet $VNET_NAME..."
$SSH_CMD "pvesh create /cluster/sdn/vnets --vnet $VNET_NAME --zone $ZONE_NAME --tag $VLAN_TAG --isolate-ports $ISOLATE"
if [ $? -eq 0 ]; then
    print_msg "VNet $VNET_NAME criada com sucesso!"
else
    print_error "Falha ao criar VNet $VNET_NAME"
    exit 1
fi

# 3. Criar a sub-rede
print_msg "Criando sub-rede $SUBNET..."
if [ $SNAT -eq 1 ]; then
    $SSH_CMD "pvesh create /cluster/sdn/vnets/$VNET_NAME/subnets --subnet $SUBNET --gateway $GATEWAY --type subnet --snat 1"
else
    $SSH_CMD "pvesh create /cluster/sdn/vnets/$VNET_NAME/subnets --subnet $SUBNET --gateway $GATEWAY --type subnet"
fi

if [ $? -eq 0 ]; then
    print_msg "Sub-rede criada com sucesso!"
else
    print_error "Falha ao criar sub-rede"
    exit 1
fi

# 4. Aplicar a configuração
print_msg "Aplicando configuração SDN..."
$SSH_CMD "pvesh set /cluster/sdn"
if [ $? -eq 0 ]; then
    print_msg "Configuração aplicada com sucesso!"
else
    print_error "Falha ao aplicar configuração"
    exit 1
fi

echo ""
echo "========================================="
echo -e "${GREEN}✅ VNET CRIADA COM SUCESSO!${NC}"
echo "========================================="
echo "Resumo da criação:"
echo "- Zona: $ZONE_NAME"
echo "- VNet: $VNET_NAME (VLAN: $VLAN_TAG)"
echo "- Sub-rede: $SUBNET (Gateway: $GATEWAY)"
echo "- SNAT: $([ $SNAT -eq 1 ] && echo 'Ativado' || echo 'Desativado')"
echo "- Isolamento de portas: $([ $ISOLATE -eq 1 ] && echo 'Ativado' || echo 'Desativado')"
echo "========================================="

# Opcional: Salvar configuração em arquivo
read -p "Salvar esta configuração em um arquivo? (s/n): " SAVE_CONFIG
if [[ "$SAVE_CONFIG" =~ ^[Ss]$ ]]; then
    CONFIG_FILE="vnet_${VNET_NAME}_$(date +%Y%m%d_%H%M%S).conf"
    cat > "$CONFIG_FILE" << EOF
# Configuração VNet - $VNET_NAME
# Criado em: $(date)

PROXMOX_IP="$PROXMOX_IP"
SSH_USER="$SSH_USER"
ZONE_NAME="$ZONE_NAME"
BRIDGE="$BRIDGE"
IPAM="$IPAM"
VNET_NAME="$VNET_NAME"
VLAN_TAG="$VLAN_TAG"
ISOLATE="$ISOLATE"
SUBNET="$SUBNET"
GATEWAY="$GATEWAY"
SNAT="$SNAT"
EOF
    print_msg "Configuração salva em: $CONFIG_FILE"

# Após criar a VNet, salvar no estado global
# Adicione estas linhas no final do script criar_vnet.sh, antes do exit

# Salvar informações da VNet para o estado global
if [ -n "$VNET_NAME" ]; then
    # Criar arquivo de estado para o orquestrador
    mkdir -p /home/elmotecnologia/projetos/deploy-automacao/.state
    cat > /home/elmotecnologia/projetos/deploy-automacao/.state/vnet_info.json << EOF
{
  "vnet_name": "$VNET_NAME",
  "vlan_id": $VLAN_TAG,
  "bridge": "$VNET_NAME",
  "subnet": "$SUBNET",
  "gateway": "$GATEWAY"
}
EOF
    echo "✅ Informações da VNet salvas para integração"

fi
fi

