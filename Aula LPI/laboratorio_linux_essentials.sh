#!/usr/bin/env bash
# Laboratorio seguro para a aula "Linux do zero: primeiros passos na linha de comando"
# Execute como usuario comum. Nao precisa de sudo.
set -euo pipefail

cd "$HOME"
mkdir -p aula-linux-essentials
cd aula-linux-essentials
pwd
ls -la

mkdir -p documentos logs
touch anotacoes.txt
echo "Primeira aula de Linux Essentials" > anotacoes.txt
cat anotacoes.txt
ls -l

cp anotacoes.txt documentos/anotacoes-copia.txt
mv documentos/anotacoes-copia.txt documentos/anotacoes-final.txt
ls documentos
rm documentos/anotacoes-final.txt

cd "$HOME"
mkdir -p treino-terminal
cd treino-terminal
touch resumo.txt
echo "Aprendi pwd, ls e cd" > resumo.txt
mkdir -p evidencias
cp resumo.txt evidencias/resumo-copia.txt
ls -R
