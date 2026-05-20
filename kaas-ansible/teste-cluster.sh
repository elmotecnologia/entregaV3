#!/bin/bash
echo "=== VALIDAÇÃO DO VIP 10.10.20.100 ===\n"

# 1. Teste de conectividade
echo "1. Testando conectividade TCP..."
if timeout 3 telnet 10.10.20.100 6443 2>/dev/null | grep -q "Connected"; then
    echo "✅ Porta 6443 acessível no VIP"
else
    echo "❌ Porta 6443 não respondeu"
fi

# 2. Teste da API
echo -e "\n2. Testando API Kubernetes via VIP..."
if curl -k --max-time 5 https://10.10.20.100:6443/version 2>/dev/null | grep -q "gitVersion"; then
    echo "✅ API respondendo via VIP"
    curl -k -s https://10.10.20.100:6443/version | grep gitVersion
else
    echo "❌ API não respondeu via VIP"
fi

# 3. Verificar pods do kube-vip
echo -e "\n3. Status do kube-vip:"
kubectl get pods -n kube-system -l name=kube-vip-ds

# 4. Verificar leader
echo -e "\n4. Leader atual:"
LEADER=$(kubectl get endpoints -n kube-system kube-vip -o jsonpath='{.subsets[0].addresses[0].nodeName}' 2>/dev/null)
if [ -n "$LEADER" ]; then
    echo "✅ Leader: $LEADER"
else
    echo "⚠️ Não foi possível determinar o leader"
fi

# 5. Teste com kubectl
echo -e "\n5. Teste com kubectl usando VIP:"
kubectl get nodes --server=https://10.10.20.100:6443 --insecure-skip-tls-verify 2>/dev/null | head -3

echo -e "\n=== VALIDAÇÃO CONCLUÍDA ==="

