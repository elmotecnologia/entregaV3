#!/bin/bash
#
# 1. Adiciona todos os arquivos da pasta ao "stage" do Git
git add .

# 2. Faz o seu primeiro commit (salva o estado atual dos arquivos)
git commit -m "Primeiro commit: Estrutura inicial do projeto"

# 3. (Opcional, mas altamente recomendado) Muda o nome da branch de 'master' para 'main'
git branch -m main

# 4. Agora sim, cria o repositório no GitHub e envia tudo!
gh repo create entregaV3 --public --source=. --push
