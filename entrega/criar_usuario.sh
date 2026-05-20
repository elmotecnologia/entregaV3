#!/bin/bash

# CONFIGURAÇÕES
PROXMOX_HOST="192.168.2.200"
PROXMOX_USER="root"
STORAGE_ID="local-lvm"

# Processar parâmetros
CLIENT_NAME=""

if [ $# -gt 0 ]; then
    CLIENT_NAME="$1"
    echo "Cliente: $CLIENT_NAME"
else
    read -p "Digite o Nome do Cliente: " CLIENT_NAME
fi

[ -z "$CLIENT_NAME" ] && echo "Nome não pode ser vazio!" && exit 1

# Variáveis
USER_FULL="$CLIENT_NAME@pve"
POOL_ID="Pool_$CLIENT_NAME"
PASS=$(openssl rand -base64 15)
DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')

# Criar diretório de log do cliente
LOG_DIR="/home/elmotecnologia/projetos/entregaV2/clientes/$CLIENT_NAME"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provisionamento_$(date +%Y%m%d_%H%M%S).log"

echo "--- Executando Deploy Remoto em $PROXMOX_HOST ---"

ssh -T $PROXMOX_USER@$PROXMOX_HOST << EOF
    pvesh create /access/users --userid "$USER_FULL" --password "$PASS" --comment "Cliente $USER_FULL"
    pvesh create /pools --poolid "$POOL_ID"
    pvesh set /access/acl --path "/pool/$POOL_ID" --roles PVEVMAdmin --users "$USER_FULL"
    pvesh set /access/acl --path "/storage/$STORAGE_ID" --roles PVEDatastoreUser --users "$USER_FULL"
    pvesh set /access/acl --path "/sdn" --roles PVESDNUser --users "$USER_FULL" 2>/dev/null || \
    pvesh set /access/acl --path "/" --roles PVESDNUser --users "$USER_FULL"
EOF

if [ $? -eq 0 ]; then
    echo "--------------------------------------------------------"
    echo "PROVISIONAMENTO CONCLUÍDO!"
    echo "USUÁRIO: $USER_FULL"
    echo "SENHA:   $PASS"
    echo "POOL:    $POOL_ID"
    echo "LOG:     $LOG_FILE"
    echo "--------------------------------------------------------"
    
    # Salvar no arquivo de log
    cat > "$LOG_FILE" << EOF
Data: $DATA_HORA
Cliente: $CLIENT_NAME
Usuário: $USER_FULL
Pool: $POOL_ID
Senha: $PASS
Status: SUCESSO
EOF

    # Saída para o estado global
    echo "###STATE_OUTPUT###"
    echo "USER_ID=$USER_FULL"
    echo "PASSWORD=$PASS"
    echo "POOL_ID=$POOL_ID"
    echo "###STATE_OUTPUT_END###"
else
    echo "ERRO no provisionamento!"
    exit 1
fi

