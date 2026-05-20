#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_info() {
    echo -e "${BLUE}[DETALHE]${NC} $1"
}

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Verificar se sshpass está instalado (se for usar senha)
check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass não está instalado."
        read -p "Deseja instalar sshpass? (s/n): " INSTALL_SSHPASS
        if [[ "$INSTALL_SSHPASS" =~ ^[Ss]$ ]]; then
            sudo apt-get update && sudo apt-get install -y sshpass
            if [ $? -eq 0 ]; then
                print_msg "sshpass instalado com sucesso!"
            else
                print_error "Falha ao instalar sshpass"
                exit 1
            fi
        else
            print_error "sshpass é necessário para autenticação por senha. Use chave SSH ou instale sshpass."
            exit 1
        fi
    fi
}

# Coletar informações do servidor Proxmox
print_header "LISTADOR DE VMIDS - PROXMOX"

# Verificar se temos configuração salva
SAVE_DIR=~/projetos/IsolamentoSDN/dbaas
if [ -d "$SAVE_DIR" ] && [ -f "$SAVE_DIR/vnet_*.conf" ]; then
    CONFIG_FILE=$(ls -t $SAVE_DIR/vnet_*.conf 2>/dev/null | head -1)
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        print_msg "Configuração carregada de: $CONFIG_FILE"
        echo "  Servidor: $PROXMOX_IP"
        echo "  Usuário: $SSH_USER"
        read -p "Usar esta configuração? (s/n): " USE_CONFIG
        if [[ "$USE_CONFIG" =~ ^[Ss]$ ]]; then
            PROXMOX_IP=${PROXMOX_IP}
            SSH_USER=${SSH_USER}
        else
            unset PROXMOX_IP SSH_USER
        fi
    fi
fi

# Coletar informações do Proxmox se não tiver ou se optou por não usar
if [ -z "$PROXMOX_IP" ]; then
    while true; do
        read -p "Digite o IP do servidor Proxmox (ex: 192.168.2.200): " PROXMOX_IP
        if [[ $PROXMOX_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            print_error "IP inválido!"
        fi
    done
fi

if [ -z "$SSH_USER" ]; then
    read -p "Digite o usuário SSH (padrão: root): " SSH_USER
    SSH_USER=${SSH_USER:-root}
fi

# Escolher método de autenticação
echo ""
echo "Método de autenticação:"
echo "1 - Usar senha"
echo "2 - Usar chave SSH"
read -p "Escolha (1/2 - padrão: 2): " AUTH_METHOD
AUTH_METHOD=${AUTH_METHOD:-2}

if [ "$AUTH_METHOD" -eq 1 ]; then
    read -sp "Digite a senha SSH: " SSH_PASS
    echo ""
    check_sshpass
    SSH_CMD="sshpass -p '$SSH_PASS' ssh -o StrictHostKeyChecking=no $SSH_USER@$PROXMOX_IP"
else
    SSH_CMD="ssh -o StrictHostKeyChecking=no $SSH_USER@$PROXMOX_IP"
fi

# Testar conexão SSH
print_msg "Testando conexão SSH..."
if ! $SSH_CMD "echo 'Conexão OK'" > /dev/null 2>&1; then
    print_error "Não foi possível conectar ao servidor Proxmox."
    print_info "Verifique IP, usuário e método de autenticação."
    exit 1
fi
print_msg "Conexão SSH estabelecida!"

echo ""

# Buscar todas as VMs
print_header "LISTANDO VMs DO SERVIDOR"

# Comando para listar todas as VMs com seus IDs, nomes e status
VM_LIST=$($SSH_CMD "qm list" 2>/dev/null | tail -n +2)

if [ -z "$VM_LIST" ]; then
    print_warning "Nenhuma VM encontrada no servidor!"
    exit 1
fi

# Contar total de VMs
TOTAL_VMS=$(echo "$VM_LIST" | wc -l)
print_msg "Total de VMs encontradas: $TOTAL_VMS"
echo ""

# Listar as 10 últimas VMs (ordenadas por ID decrescente)
print_header "ÚLTIMAS 10 VMs CRIADAS (por VMID)"

echo -e "${CYAN}VMID     NOME                                STATUS${NC}"
echo -e "${CYAN}----     ----                                ------${NC}"

# Ordenar por VMID (coluna 1) decrescente e pegar as 10 primeiras
echo "$VM_LIST" | sort -k1 -n -r | head -10 | while read line; do
    VMID=$(echo $line | awk '{print $1}')
    NAME=$(echo $line | awk '{print $2}')
    STATUS=$(echo $line | awk '{print $3}')
    
    # Cor para status
    if [ "$STATUS" == "running" ]; then
        STATUS_COLOR="${GREEN}running${NC}"
    elif [ "$STATUS" == "stopped" ]; then
        STATUS_COLOR="${YELLOW}stopped${NC}"
    else
        STATUS_COLOR="${RED}${STATUS}${NC}"
    fi
    
    printf "%-8s %-35s ${STATUS_COLOR}\n" "$VMID" "$NAME"
done

echo ""

# Listar todas as VMs (opcional)
read -p "Deseja ver todas as VMs? (s/n): " SHOW_ALL
if [[ "$SHOW_ALL" =~ ^[Ss]$ ]]; then
    print_header "TODAS AS VMs DO SERVIDOR"
    echo -e "${CYAN}VMID     NOME                                STATUS${NC}"
    echo -e "${CYAN}----     ----                                ------${NC}"
    
    echo "$VM_LIST" | sort -k1 -n | while read line; do
        VMID=$(echo $line | awk '{print $1}')
        NAME=$(echo $line | awk '{print $2}')
        STATUS=$(echo $line | awk '{print $3}')
        
        if [ "$STATUS" == "running" ]; then
            STATUS_COLOR="${GREEN}running${NC}"
        elif [ "$STATUS" == "stopped" ]; then
            STATUS_COLOR="${YELLOW}stopped${NC}"
        else
            STATUS_COLOR="${RED}${STATUS}${NC}"
        fi
        
        printf "%-8s %-35s ${STATUS_COLOR}\n" "$VMID" "$NAME"
    done
    echo ""
fi

# Sugerir próximo VMID disponível
print_header "PRÓXIMO VMID DISPONÍVEL"

# Extrair todos os VMIDs e encontrar o maior
MAX_VMID=$(echo "$VM_LIST" | awk '{print $1}' | sort -n | tail -1)
MIN_VMID=$(echo "$VM_LIST" | awk '{print $1}' | sort -n | head -1)

# Encontrar gaps (IDs faltando)
ALL_VMIDS=$(echo "$VM_LIST" | awk '{print $1}' | sort -n)
SUGGESTED_VMID=$((MAX_VMID + 1))

# Verificar se há gaps menores que o max+1
PREVIOUS=0
for vmid in $ALL_VMIDS; do
    if [ $((vmid - PREVIOUS)) -gt 1 ]; then
        SUGGESTED_VMID=$((PREVIOUS + 1))
        break
    fi
    PREVIOUS=$vmid
done

print_msg "Menor VMID em uso: $MIN_VMID"
print_msg "Maior VMID em uso: $MAX_VMID"
echo ""
print_msg "💡 **Próximo VMID sugerido: $SUGGESTED_VMID**"
print_info "Baseado no maior ID + 1 ou primeiro gap encontrado"

# Verificar se o ID 100 (template) está em uso
if echo "$ALL_VMIDS" | grep -q "^100$"; then
    print_info "VMID 100 (template) está em uso ✓"
else
    print_warning "VMID 100 (template) NÃO encontrado! Verifique se o template existe."
fi

echo ""

# Estatísticas adicionais
print_header "ESTATÍSTICAS DAS VMs"

# Contar VMs por status
RUNNING=$(echo "$VM_LIST" | grep -c "running")
STOPPED=$(echo "$VM_LIST" | grep -c "stopped")
OTHER=$((TOTAL_VMS - RUNNING - STOPPED))

echo -e "${GREEN}Em execução:${NC} $RUNNING"
echo -e "${YELLOW}Paradas:${NC} $STOPPED"
echo -e "${RED}Outros status:${NC} $OTHER"

# Opção para salvar em arquivo
echo ""
read -p "Deseja salvar esta lista em um arquivo? (s/n): " SAVE_LIST
if [[ "$SAVE_LIST" =~ ^[Ss]$ ]]; then
    SAVE_FILE="${SAVE_DIR}/vms_list_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$SAVE_DIR"
    
    {
        echo "Lista de VMs do Proxmox - $(date)"
        echo "Servidor: $PROXMOX_IP"
        echo "Total de VMs: $TOTAL_VMS"
        echo ""
        echo "VMID     NOME                                STATUS"
        echo "----     ----                                ------"
        echo "$VM_LIST" | sort -k1 -n | while read line; do
            VMID=$(echo $line | awk '{print $1}')
            NAME=$(echo $line | awk '{print $2}')
            STATUS=$(echo $line | awk '{print $3}')
            printf "%-8s %-35s %s\n" "$VMID" "$NAME" "$STATUS"
        done
        echo ""
        echo "Próximo VMID sugerido: $SUGGESTED_VMID"
    } > "$SAVE_FILE"
    
    print_msg "Lista salva em: $SAVE_FILE"
fi

# Integração com o script de clone (opcional)
echo ""
read -p "Deseja clonar uma nova VM usando o ID sugerido? (s/n): " CLONE_NOW
if [[ "$CLONE_NOW" =~ ^[Ss]$ ]]; then
    print_info "Iniciando script de clonagem..."
    if [ -f "${SAVE_DIR}/clonar_para_vnet.sh" ]; then
        # Passar o ID sugerido como parâmetro
        ${SAVE_DIR}/clonar_para_vnet.sh --vmid $SUGGESTED_VMID
    else
        print_error "Script de clonagem não encontrado em: ${SAVE_DIR}/clonar_para_vnet.sh"
    fi
fi

echo ""
print_msg "Consulta concluída!"

