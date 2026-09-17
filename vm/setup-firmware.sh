#!/usr/bin/env bash
#
# vm/setup-firmware.sh
# Automatizador para baixar e configurar o OpenCore e os firmwares OVMF.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISKS_DIR="$REPO_ROOT/vm/disks"
OVMF_DIR="$REPO_ROOT/vm/ovmf"

echo "========================================================="
echo " macOS Firmware & Bootloader Configurator"
echo "========================================================="

# Criar pastas caso não existam
mkdir -p "$DISKS_DIR/rails" "$DISKS_DIR/run" "$OVMF_DIR"

echo "[setup] Clonando temporariamente o repositório OSX-KVM..."
TEMP_DIR="/tmp/OSX-KVM-TEMP"
rm -rf "$TEMP_DIR"
git clone --depth 1 https://github.com/kholia/OSX-KVM.git "$TEMP_DIR"

echo "[setup] Copiando bootloader OpenCore..."
cp "$TEMP_DIR/OpenCore/OpenCore.qcow2" "$DISKS_DIR/OpenCore.qcow2"

echo "[setup] Copiando firmwares UEFI (OVMF)..."
cp "$TEMP_DIR/OVMF_CODE_4M.fd" "$OVMF_DIR/OVMF_CODE_4M.fd"
# Copia todas as resoluções de tela disponíveis para maior flexibilidade
cp "$TEMP_DIR"/OVMF_VARS-*.fd "$OVMF_DIR/"

echo "[setup] Limpando arquivos temporários..."
rm -rf "$TEMP_DIR"

echo "[setup] Criando o link simbólico da Rail padrão (macos-13)..."
mkdir -p "$DISKS_DIR/rails/macos-13"
ln -sfn macos-13 "$DISKS_DIR/rails/current"

echo "========================================================="
echo " 🎉 Configuração concluída com sucesso!"
echo " Arquivos prontos:"
echo " - $DISKS_DIR/OpenCore.qcow2"
echo " - $OVMF_DIR/OVMF_CODE_4M.fd"
echo " - $OVMF_DIR/OVMF_VARS-1920x1080.fd"
echo "========================================================="
