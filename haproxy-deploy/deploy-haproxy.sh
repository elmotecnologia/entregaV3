#!/bin/bash

# Configurações
HAPROXY_HOST="10.10.50.30"
SSH_USER="root"                 # ou um user com permissão sudo
CONFIG_FILE="haproxy.cfg"       # arquivo que será copiado
REMOTE_PATH="/etc/haproxy/haproxy.cfg"

# 1. Copiar a configuração (ajuste os IPs dos CPs antes!)
scp "$CONFIG_FILE" "$SSH_USER@$HAPROXY_HOST:$REMOTE_PATH"

# 2. Testar a sintaxe remotamente
ssh "$SSH_USER@$HAPROXY_HOST" "haproxy -f $REMOTE_PATH -c"

if [ $? -eq 0 ]; then
    echo "Configuração válida. Recarregando HAProxy..."
    ssh "$SSH_USER@$HAPROXY_HOST" "systemctl reload haproxy"
else
    echo "ERRO: configuração inválida. Nada foi recarregado."
    exit 1
fi

