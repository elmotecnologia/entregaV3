#!/bin/bash
# menu_sdn.sh - Menu principal para gerenciamento SDN

while true; do
    echo "========================================="
    echo "   GERENCIADOR SDN - PROXMOX"
    echo "========================================="
    echo "1 - Listar VMs e próximo ID disponível"
    echo "2 - Criar nova VNet"
    echo "3 - Clonar VM para VNet"
    echo "4 - Sair"
    echo "========================================="
    read -p "Escolha uma opção: " OPTION
    
    case $OPTION in
        1) ./listar_vms.sh ;;
        2) ./criar_vnet.sh ;;
        3) ./clonar_para_vnet.sh ;;
        4) echo "Saindo..."; exit 0 ;;
        *) echo "Opção inválida!" ;;
    esac
    echo ""
    read -p "Pressione Enter para continuar..."
done

