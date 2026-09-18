#!/usr/bin/env bash
#
# install_all_osx.sh
#
# Automatizador completo de requisitos, compilação de QEMU, download do instalador macOS,
# configuração de hardware virtual (RAM, Disco, CPUs) e preparação do sistema para paravirtualização.
#

set -euo pipefail

# Estilos de cores para o terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0;37m' # Sem Cor

echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}   Instalador Automatizado do macOS com Reims Paravirtualização ${NC}"
echo -e "${BLUE}============================================================${NC}"

# --- Verificar SO e Gerenciador de Pacotes ---
echo -e "\n${BLUE}[1/7] Verificando sistema operacional e dependências...${NC}"
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
    echo -e "Sistema detectado: ${GREEN}$OS_NAME${NC}"
else
    echo -e "${YELLOW}Aviso: Não foi possível determinar o sistema operacional. Assumindo baseado em Linux/Arch.${NC}"
fi

# Instalação de pacotes via pacman (Arch/Omarchy) ou apt (Debian/Ubuntu)
if command -v pacman >/dev/null 2>&1; then
    echo -e "Instalando dependências via ${GREEN}pacman${NC}..."
    echo -e "${YELLOW}Pode ser solicitado o acesso root (sudo) para instalar os pacotes.${NC}"
    sudo pacman -S --needed --noconfirm qemu-base git wget libguestfs dmg2img p7zip make python python-pip cdrtools net-tools screen || true
elif command -v apt-get >/dev/null 2>&1; then
    echo -e "Instalando dependências via ${GREEN}apt-get${NC}..."
    echo -e "${YELLOW}Pode ser solicitado o acesso root (sudo) para instalar os pacotes.${NC}"
    sudo apt-get update
    sudo apt-get install -y qemu-system uml-utilities virt-manager git \
        wget libguestfs-tools p7zip-full make dmg2img tesseract-ocr \
        tesseract-ocr-eng genisoimage vim net-tools screen
else
    echo -e "${YELLOW}Gerenciador de pacotes pacman/apt não encontrado. Certifique-se de que dependências básicas como dmg2img, qemu e make já estão instaladas.${NC}"
fi

# --- Compilar QEMU Interno ---
echo -e "\n${BLUE}[2/7] Compilando e configurando o QEMU interno com suporte a Vulkan/Reims...${NC}"
# Executa o script de compilação local
./scripts/qemu-build/qemu-build.sh --target x86_64 --backend vulkan

QEMU_BIN="/home/elizeu/Projects/osx-linux/vendor/qemu/build/qemu-system-x86_64"
if [ ! -f "$QEMU_BIN" ]; then
    echo -e "${RED}Erro: Falha ao compilar o QEMU em $QEMU_BIN. Abortando.${NC}"
    exit 1
fi
echo -e "${GREEN}QEMU compilado com sucesso em: $QEMU_BIN${NC}"

# --- Obter Configurações do Usuário ---
echo -e "\n${BLUE}[3/7] Configuração da Máquina Virtual macOS${NC}"

# Escolha da versão do macOS
echo -e "Selecione a versão do macOS desejada:"
echo "1) High Sierra (10.13)"
echo "2) Mojave (10.14)"
echo "3) Catalina (10.15)"
echo "4) Big Sur (11.7)"
echo "5) Monterey (12.6)"
echo "6) Ventura (13)"
echo "7) Sonoma (14) - [RECOMENDADO]"
echo "8) Sequoia (15)"
echo "9) Tahoe (26)"
read -rp "Escolha a versão (1-9, padrão 7): " mac_choice
mac_choice="${mac_choice:-7}"

# Mapear escolha para shortname e trilha (rail)
case "$mac_choice" in
    1) MAC_VERSION="highsierra"; RAIL_NAME="macos-10-13" ;;
    2) MAC_VERSION="mojave"; RAIL_NAME="macos-10-14" ;;
    3) MAC_VERSION="catalina"; RAIL_NAME="macos-10-15" ;;
    4) MAC_VERSION="bigsur"; RAIL_NAME="macos-11" ;;
    5) MAC_VERSION="monterey"; RAIL_NAME="macos-12" ;;
    6) MAC_VERSION="ventura"; RAIL_NAME="macos-13" ;;
    7) MAC_VERSION="sonoma"; RAIL_NAME="macos-14" ;;
    8) MAC_VERSION="sequoia"; RAIL_NAME="macos-15" ;;
    9) MAC_VERSION="tahoe"; RAIL_NAME="macos-26" ;;
    *) MAC_VERSION="sonoma"; RAIL_NAME="macos-14" ;;
esac

echo -e "Versão selecionada: ${GREEN}$MAC_VERSION${NC} | Trilha de Snapshot: ${GREEN}$RAIL_NAME${NC}"

# Memória RAM
read -rp "Quantidade de RAM (Ex: 4G, 8G, 16G - padrão 16G): " ram_input
ram_input="${ram_input:-16G}"
# Converter G para megabytes se necessário
if [[ "$ram_input" =~ ^([0-9]+)G$ ]]; then
    allocated_ram_mb=$(( ${BASH_REMATCH[1]} * 1024 ))
else
    allocated_ram_mb=16384
fi

# Núcleos de CPU
read -rp "Quantidade de Cores de CPU (padrão 4): " cpu_cores
cpu_cores="${cpu_cores:-4}"
cpu_threads=$(( cpu_cores * 2 ))

# Tamanho do Disco Rígido
read -rp "Tamanho do Disco Rígido Virtual (Ex: 128G, 256G - padrão 256G): " disk_size
disk_size="${disk_size:-256G}"

echo -e "\nConfiguração final:"
echo -e "- RAM: ${GREEN}${ram_input} (${allocated_ram_mb} MiB)${NC}"
echo -e "- CPU: ${GREEN}${cpu_cores} Cores, ${cpu_threads} Threads${NC}"
echo -e "- Disco: ${GREEN}${disk_size}${NC}"

# --- Baixar e Preparar Mídia de Instalação ---
echo -e "\n${BLUE}[4/7] Baixando a imagem de recuperação do macOS...${NC}"
cd osx-kvm-temp

# Se já houver um BaseSystem.dmg na raiz, trazemos para cá para economizar download
if [ -f "../BaseSystem.dmg" ] && [ ! -f "BaseSystem.dmg" ]; then
    echo -e "Copiando BaseSystem.dmg existente na raiz..."
    cp ../BaseSystem.dmg .
fi

if [ ! -f "BaseSystem.dmg" ]; then
    echo -e "Iniciando download da imagem de recuperação..."
    ./fetch-macOS-v2.py --shortname="$MAC_VERSION"
else
    echo -e "${GREEN}BaseSystem.dmg já existe. Pulando download.${NC}"
fi

# Converter DMG para IMG bruta
echo -e "Convertendo BaseSystem.dmg para formato cru (.img)..."
if command -v dmg2img >/dev/null 2>&1; then
    dmg2img -f -i BaseSystem.dmg BaseSystem.img
else
    echo -e "dmg2img não encontrado. Usando qemu-img para conversão..."
    qemu-img convert -O raw BaseSystem.dmg BaseSystem.img
fi

# Criar o disco virtual rígido para a instalação do macOS
echo -e "Criando disco virtual rígido de $disk_size..."
rm -f mac_hdd_ng.img
qemu-img create -f qcow2 mac_hdd_ng.img "$disk_size"

# --- Iniciar a Instalação com Interface Gráfica ---
echo -e "\n${BLUE}[5/7] Iniciando a Máquina Virtual de Instalação...${NC}"
echo -e "${YELLOW}ATENÇÃO:${NC}"
echo "1. A janela do QEMU se abrirá na sua tela."
echo "2. Selecione 'Disk Utility' / 'Utilitário de Disco' e formate o disco de 256GB em formato APFS com o nome 'Macintosh HD'."
echo "3. Feche o Disk Utility, selecione 'Reinstall macOS' e continue a instalação."
echo "4. O sistema irá reiniciar algumas vezes no instalador. Mantenha a VM aberta."
echo "5. Assim que a instalação terminar e você chegar ao Desktop, DESLIGUE (Shut Down) o macOS de forma limpa."
echo "--------------------------------------------------------"
read -rp "Pressione [ENTER] para iniciar a VM do instalador..."

MY_OPTIONS="+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"

# Rodando o QEMU compilado localmente
$QEMU_BIN \
  -enable-kvm -m "$allocated_ram_mb" \
  -cpu Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,"$MY_OPTIONS" \
  -machine q35 \
  -device qemu-xhci,id=xhci \
  -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 \
  -smp "$cpu_threads",cores="$cpu_cores",sockets=1 \
  -device usb-ehci,id=ehci \
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" \
  -drive if=pflash,format=raw,readonly=on,file="./OVMF_CODE_4M.fd" \
  -drive if=pflash,format=raw,file="./OVMF_VARS-1920x1080.fd" \
  -smbios type=2 \
  -device ich9-intel-hda -device hda-duplex \
  -device ich9-ahci,id=sata \
  -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="./OpenCore/OpenCore.qcow2" \
  -device ide-hd,bus=sata.2,drive=OpenCoreBoot \
  -device ide-hd,bus=sata.3,drive=InstallMedia \
  -drive id=InstallMedia,if=none,file="./BaseSystem.img",format=raw \
  -drive id=MacHDD,if=none,file="./mac_hdd_ng.img",format=qcow2 \
  -device ide-hd,bus=sata.4,drive=MacHDD \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27 \
  -monitor stdio \
  -device vmware-svga || true

# Retornar ao diretório raiz
cd ..

# --- Importar para o Sistema de Reims Paravirtualização ---
echo -e "\n${BLUE}[6/7] Importando sistema para Reims Paravirtualização...${NC}"
mkdir -p "vm/disks/rails/$RAIL_NAME"

echo -e "Movendo disco rígido para o diretório padrão..."
mv -f osx-kvm-temp/mac_hdd_ng.img vm/disks/macos.img

# --- Criar o Snapshot Base da Paravirtualização ---
echo -e "\n${BLUE}[7/7] Gerando Snapshot Base para Paravirtualização...${NC}"
echo -e "Estaremos subindo o macOS mais uma vez."
echo -e "${YELLOW}Importante:${NC} Apenas realize o login ou certifique-se de que o sistema subiu e em seguida faça um ${GREEN}Desligamento Limpo (Shut Down)${NC} pelo menu do macOS."
echo -e "Isso criará o snapshot 'base' de paravirtualização imutável necessário para habilitar Reims vGPU."
read -rp "Pressione [ENTER] para iniciar o processo de captura do snapshot..."

# Invoca o script do projeto no modo capture para gerar o snapshot base imutável
./vm/boot-x86.sh --rail "$RAIL_NAME" --capture

echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}   Instalação e Paravirtualização Configurados com Sucesso!   ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "\nAgora você tem uma trilha de paravirtualização pronta para uso interativo."
echo -e "Você pode iniciar o macOS com aceleração paravirtualizada Reims vGPU a qualquer momento rodando:"
echo -e "\n   ${BLUE}./vm/boot-x86.sh --rail $RAIL_NAME --device reims-vgpu-pci --interactive${NC}"
echo -e "Ou caso prefira a estabilidade máxima com renderização de CPU:"
echo -e "\n   ${BLUE}./vm/boot-x86.sh --rail $RAIL_NAME --device vmware-svga --interactive${NC}"
echo -e "\nAproveite!"
