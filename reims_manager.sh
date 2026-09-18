#!/usr/bin/env bash
#
# reims_manager.sh
#
# Gerenciador interativo de Máquinas Virtuais macOS com Reims Paravirtualização.
# Permite instalar novas VMs, iniciar as existentes e deletá-las via menu amigável.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Estilos de cores para o terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0;37m' # Sem Cor

VMS_LIST=()

list_vms() {
    VMS_LIST=()
    local rails_dir="$SCRIPT_DIR/vm/disks/rails"
    if [ ! -d "$rails_dir" ]; then
        return 1
    fi
    
    # Encontra as subpastas de forma robusta
    while IFS= read -r -d '' dir; do
        VMS_LIST+=("$(basename "$dir")")
    done < <(find "$rails_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    
    if [ ${#VMS_LIST[@]} -eq 0 ]; then
        return 1
    fi
    
    for i in "${!VMS_LIST[@]}"; do
        echo -e "  $((i+1))) ${GREEN}${VMS_LIST[i]}${NC}"
    done
    return 0
}

start_vm() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}   Iniciar Máquina Virtual macOS${NC}"
    echo -e "${BLUE}============================================================${NC}"
    
    echo -e "\nSelecione a VM desejada:"
    if ! list_vms; then
        echo -e "${YELLOW}Nenhuma VM instalada ainda (pasta 'rails' vazia ou ausente).${NC}"
        echo -e "\nUse a opção 1 do menu para instalar uma nova VM."
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
        return
    fi
    
    read -rp "Escolha a VM (1-${#VMS_LIST[@]}): " vm_choice
    if [[ ! "$vm_choice" =~ ^[0-9]+$ ]] || [ "$vm_choice" -lt 1 ] || [ "$vm_choice" -gt "${#VMS_LIST[@]}" ]; then
        echo -e "${RED}Opção inválida!${NC}"
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
        return
    fi
    
    local selected_vm="${VMS_LIST[$((vm_choice-1))]}"
    local config_file="$SCRIPT_DIR/vm/disks/rails/$selected_vm/config.sh"
    
    # Carregar valores salvos ou usar padrões seguros
    local ram="16G"
    local cores="4"
    local threads="8"
    local resolution="1920x1080"
    
    if [ -f "$config_file" ]; then
        ram=$(grep "^RAM=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "16G")
        cores=$(grep "^CPU_CORES=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "4")
        threads=$(grep "^CPU_THREADS=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "8")
        resolution=$(grep "^RESOLUTION=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "1920x1080")
    fi
    
    echo -e "\nSelecione o modo de inicialização:"
    echo "1) Reims vGPU (Aceleração Gráfica 3D via Vulkan) - [RECOMENDADO]"
    echo "2) VMware SVGA (Modo de Compatibilidade / renderização por CPU)"
    echo "3) Modo de Captura (Inicia em modo gravável para criar/atualizar o Snapshot)"
    read -rp "Escolha o modo (1-3, padrão 1): " mode_choice
    mode_choice="${mode_choice:-1}"
    
    if [ "$mode_choice" = "3" ]; then
        echo -e "\nIniciando a VM ${GREEN}$selected_vm${NC} em modo de captura de snapshot (via VMware SVGA)..."
        echo -e "${YELLOW}Importante:${NC} Faça login na VM, aguarde o sistema subir e em seguida faça um ${GREEN}Desligamento Limpo (Shut Down)${NC} pelo menu do macOS para salvar o snapshot."
        echo ""
        read -rp "Pressione [ENTER] para iniciar..."
        RAM="$ram" CPU_CORES="$cores" CPU_THREADS="$threads" RESOLUTION="$resolution" "$SCRIPT_DIR/vm/boot-x86.sh" --rail "$selected_vm" --device vmware-svga --capture || true
    else
        # Se escolher 1 ou 2, mas não houver snapshot ainda, sugerir/forçar o modo de captura!
        if [ ! -e "$SCRIPT_DIR/vm/disks/rails/$selected_vm/snapshots/current" ]; then
            echo -e "\n${YELLOW}Aviso: A VM '$selected_vm' ainda não possui nenhum snapshot base imutável!${NC}"
            echo -e "Para iniciá-la em modo interativo (opções 1 ou 2), precisamos primeiro criar o snapshot inicial."
            read -rp "Deseja iniciar a VM em modo de captura agora para gerar o snapshot? [S/n]: " cap_choice
            cap_choice="${cap_choice:-S}"
            if [[ "$cap_choice" =~ ^[Ss]$ ]]; then
                echo -e "\nIniciando a VM ${GREEN}$selected_vm${NC} em modo de captura de snapshot (via VMware SVGA)..."
                echo -e "${YELLOW}Importante:${NC} Faça login na VM e faça um ${GREEN}Desligamento Limpo (Shut Down)${NC} pelo menu do macOS para salvar o snapshot."
                echo ""
                read -rp "Pressione [ENTER] para iniciar..."
                RAM="$ram" CPU_CORES="$cores" CPU_THREADS="$threads" RESOLUTION="$resolution" "$SCRIPT_DIR/vm/boot-x86.sh" --rail "$selected_vm" --device vmware-svga --capture || true
            fi
            read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
            return
        fi

        local device_flag="reims-vgpu-pci"
        if [ "$mode_choice" = "2" ]; then
            device_flag="vmware-svga"
        fi
        
        echo -e "\nIniciando a VM ${GREEN}$selected_vm${NC} com dispositivo ${BLUE}$device_flag${NC}..."
        RAM="$ram" CPU_CORES="$cores" CPU_THREADS="$threads" RESOLUTION="$resolution" "$SCRIPT_DIR/vm/boot-x86.sh" --rail "$selected_vm" --device "$device_flag" --interactive || true
    fi
    
    echo ""
    read -n 1 -s -r -p "VM finalizada. Pressione qualquer tecla para voltar ao menu..."
}

edit_vm() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}   Editar Configurações de Máquina Virtual macOS${NC}"
    echo -e "${BLUE}============================================================${NC}"
    
    echo -e "\nSelecione a VM que deseja configurar:"
    if ! list_vms; then
        echo -e "${YELLOW}Nenhuma VM instalada para configurar.${NC}"
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
        return
    fi
    
    read -rp "Escolha a VM (1-${#VMS_LIST[@]}): " vm_choice
    if [[ ! "$vm_choice" =~ ^[0-9]+$ ]] || [ "$vm_choice" -lt 1 ] || [ "$vm_choice" -gt "${#VMS_LIST[@]}" ]; then
        echo -e "${RED}Opção inválida!${NC}"
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
        return
    fi
    
    local selected_vm="${VMS_LIST[$((vm_choice-1))]}"
    local config_file="$SCRIPT_DIR/vm/disks/rails/$selected_vm/config.sh"
    
    # Valores atuais ou padrões
    local ram="16G"
    local cores="4"
    local resolution="1920x1080"
    
    if [ -f "$config_file" ]; then
        ram=$(grep "^RAM=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "16G")
        cores=$(grep "^CPU_CORES=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "4")
        resolution=$(grep "^RESOLUTION=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "1920x1080")
    fi
    
    echo -e "\nConfigurações Atuais para ${GREEN}$selected_vm${NC}:"
    echo -e " 1) RAM: ${BLUE}$ram${NC}"
    echo -e " 2) Cores de CPU: ${BLUE}$cores${NC}"
    echo -e " 3) Resolução de Tela: ${BLUE}$resolution${NC}"
    echo -e " 4) Voltar ao menu principal"
    echo ""
    read -rp "Escolha o item que deseja editar (1-4): " edit_choice
    
    case "$edit_choice" in
        1)
            read -rp "Digite a nova quantidade de RAM (Ex: 4G, 8G, 16G, 32G): " ram_input
            if [ -n "$ram_input" ]; then
                ram="$ram_input"
            fi
            ;;
        2)
            read -rp "Digite a nova quantidade de Cores de CPU (Ex: 2, 4, 6, 8): " cores_input
            if [ -n "$cores_input" ]; then
                cores="$cores_input"
            fi
            ;;
        3)
            echo -e "\nSelecione a resolução desejada:"
            echo "1) 1920x1080 - [RECOMENDADO]"
            echo "2) 1440x900"
            echo "3) 1280x720"
            echo "4) 1024x768"
            read -rp "Escolha a resolução (1-4): " res_opt
            case "$res_opt" in
                1) resolution="1920x1080" ;;
                2) resolution="1440x900" ;;
                3) resolution="1280x720" ;;
                4) resolution="1024x768" ;;
            esac
            ;;
        *)
            return
            ;;
    esac
    
    # Salvar configurações atualizadas
    local threads=$(( cores * 2 ))
    mkdir -p "$(dirname "$config_file")"
    echo "RAM=\"$ram\"" > "$config_file"
    echo "CPU_CORES=\"$cores\"" >> "$config_file"
    echo "CPU_THREADS=\"$threads\"" >> "$config_file"
    echo "RESOLUTION=\"$resolution\"" >> "$config_file"
    
    echo -e "\n${GREEN}Configurações atualizadas com sucesso!${NC}"
    echo -e "As novas especificações serão aplicadas na próxima vez que você iniciar a VM."
    echo ""
    read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
}

delete_vm() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${RED}   Deletar Máquina Virtual macOS${NC}"
    echo -e "${BLUE}============================================================${NC}"
    
    echo -e "\nSelecione a VM que deseja excluir:"
    if ! list_vms; then
        echo -e "${YELLOW}Nenhuma VM instalada para deletar.${NC}"
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
        return
    fi
    
    read -rp "Escolha a VM (1-${#VMS_LIST[@]}): " vm_choice
    if [[ ! "$vm_choice" =~ ^[0-9]+$ ]] || [ "$vm_choice" -lt 1 ] || [ "$vm_choice" -gt "${#VMS_LIST[@]}" ]; then
        echo -e "${RED}Opção inválida!${NC}"
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
        return
    fi
    
    local selected_vm="${VMS_LIST[$((vm_choice-1))]}"
    
    echo -e "\n${RED}PERIGO: Você está prestes a excluir permanentemente a VM '${selected_vm}' e todos os seus snapshots!${NC}"
    read -rp "Tem certeza de que deseja prosseguir? Digite 'SIM' para confirmar: " confirm
    
    if [ "$confirm" = "SIM" ]; then
        echo -e "Excluindo VM '${selected_vm}'..."
        rm -rf "$SCRIPT_DIR/vm/disks/rails/${selected_vm}"
        echo -e "${GREEN}VM '${selected_vm}' excluída com sucesso!${NC}"
    else
        echo -e "${YELLOW}Operação cancelada.${NC}"
    fi
    echo ""
    read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
}

install_vm() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}   Instalar Nova Máquina Virtual macOS com Reims vGPU${NC}"
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

    QEMU_BIN="$SCRIPT_DIR/vendor/qemu/build/qemu-system-x86_64"
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

    # Se o usuário digitou apenas números (ex: 128, 256), adicionamos o "G" automaticamente para evitar que o qemu-img crie o disco em bytes
    if [[ "$disk_size" =~ ^[0-9]+$ ]]; then
        disk_size="${disk_size}G"
    fi

    echo -e "\nConfiguração final:"
    echo -e "- RAM: ${GREEN}${ram_input} (${allocated_ram_mb} MiB)${NC}"
    echo -e "- CPU: ${GREEN}${cpu_cores} Cores, ${cpu_threads} Threads${NC}"
    echo -e "- Disco: ${GREEN}${disk_size}${NC}"

    # --- Baixar e Preparar Mídia de Instalação ---
    echo -e "\n${BLUE}[4/7] Baixando a imagem de recuperação do macOS...${NC}"

    # Se a pasta osx-kvm-temp não existir ou estiver vazia/sem o script de fetch, clonar
    if [ ! -f "$SCRIPT_DIR/osx-kvm-temp/fetch-macOS-v2.py" ]; then
        echo -e "${YELLOW}osx-kvm-temp vazio ou ausente. Clonando OSX-KVM do GitHub...${NC}"
        rm -rf "$SCRIPT_DIR/osx-kvm-temp"
        git clone --depth 1 https://github.com/kholia/OSX-KVM.git "$SCRIPT_DIR/osx-kvm-temp"
    fi

    cd "$SCRIPT_DIR/osx-kvm-temp"

    # Se já houver um BaseSystem.dmg na raiz, trazemos para cá para economizar download
    if [ -f "$SCRIPT_DIR/BaseSystem.dmg" ] && [ ! -f "BaseSystem.dmg" ]; then
        echo -e "Copiando BaseSystem.dmg existente na raiz..."
        cp "$SCRIPT_DIR/BaseSystem.dmg" .
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
    echo -e "\n${BLUE}[5/7] Iniciar a Máquina Virtual de Instalação...${NC}"
    echo -e "${YELLOW}ATENÇÃO:${NC}"
    echo "1. A janela do QEMU se abrirá na sua tela."
    echo "2. No menu superior esquerdo do Disk Utility, mude a visualização para 'Show All Devices' / 'Mostrar Todos os Dispositivos'."
    echo "3. Identifique o disco vazio de $disk_size na barra lateral (NÃO selecione os discos pequenos de 150MB do OpenCore ou de 3GB do Instalador)."
    echo "4. Selecione esse disco de $disk_size, clique em 'Erase' / 'Apagar' no topo, configure:"
    echo "   - Nome: Macintosh HD"
    echo "   - Formato: APFS"
    echo "   - Esquema (Scheme): GUID Partition Map"
    echo "5. Feche o Disk Utility, selecione 'Reinstall macOS' / 'Reinstalar macOS' e prossiga com a instalação."
    echo "6. O sistema irá reiniciar algumas vezes durante o processo. Mantenha a VM aberta."
    echo "7. Assim que a instalação terminar e você chegar ao Desktop do macOS, DESLIGUE (Shut Down) o macOS de forma limpa pelo menu  para concluir o processo."
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
    cd "$SCRIPT_DIR"

    # --- Importar para o Sistema de Reims Paravirtualização ---
    echo -e "\n${BLUE}[6/7] Importando sistema para Reims Paravirtualização...${NC}"
    mkdir -p "$SCRIPT_DIR/vm/disks/rails/$RAIL_NAME" "$SCRIPT_DIR/vm/ovmf"

    echo -e "Salvando configurações iniciais da VM..."
    local config_file="$SCRIPT_DIR/vm/disks/rails/$RAIL_NAME/config.sh"
    echo "RAM=\"$ram_input\"" > "$config_file"
    echo "CPU_CORES=\"$cpu_cores\"" >> "$config_file"
    echo "CPU_THREADS=\"$cpu_threads\"" >> "$config_file"
    echo "RESOLUTION=\"1920x1080\"" >> "$config_file"

    echo -e "Copiando bootloader OpenCore..."
    cp -f "$SCRIPT_DIR/osx-kvm-temp/OpenCore/OpenCore.qcow2" "$SCRIPT_DIR/vm/disks/OpenCore.qcow2"

    echo -e "Copiando firmwares UEFI (OVMF)..."
    cp -f "$SCRIPT_DIR/osx-kvm-temp/OVMF_CODE_4M.fd" "$SCRIPT_DIR/vm/ovmf/OVMF_CODE_4M.fd"
    cp -f "$SCRIPT_DIR"/osx-kvm-temp/OVMF_VARS-*.fd "$SCRIPT_DIR/vm/ovmf/"

    echo -e "Movendo disco rígido para o diretório padrão..."
    mv -f "$SCRIPT_DIR/osx-kvm-temp/mac_hdd_ng.img" "$SCRIPT_DIR/vm/disks/macos.img"

    # --- Criar o Snapshot Base da Paravirtualização ---
    echo -e "\n${BLUE}[7/7] Gerando Snapshot Base para Paravirtualização...${NC}"
    echo -e "Estaremos subindo o macOS mais uma vez."
    echo -e "${YELLOW}Importante:${NC} Apenas realize o login ou certifique-se de que o sistema subiu e em seguida faça um ${GREEN}Desligamento Limpo (Shut Down)${NC} pelo menu do macOS."
    echo -e "Isso criará o snapshot 'base' de paravirtualização imutável necessário para habilitar Reims vGPU."
    read -rp "Pressione [ENTER] para iniciar o processo de captura do snapshot..."

    # Invoca o script do projeto no modo capture para gerar o snapshot base imutável
    "$SCRIPT_DIR/vm/boot-x86.sh" --rail "$RAIL_NAME" --device vmware-svga --capture

    echo -e "\n${GREEN}============================================================${NC}"
    echo -e "${GREEN}   Instalação e Paravirtualização Configurados com Sucesso!   ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "\nAgora você tem uma trilha de paravirtualização pronta para uso interativo."
    echo -e "Você pode iniciar o macOS com aceleração paravirtualizada Reims vGPU a qualquer momento rodando:"
    echo -e "\n   ${BLUE}./vm/boot-x86.sh --rail $RAIL_NAME --device reims-vgpu-pci --interactive${NC}"
    echo -e "Ou caso prefira a estabilidade máxima com renderização de CPU:"
    echo -e "\n   ${BLUE}./vm/boot-x86.sh --rail $RAIL_NAME --device vmware-svga --interactive${NC}"
    echo -e "\nAproveite!\n"
    
    read -n 1 -s -r -p "Instalação concluída. Pressione qualquer tecla para voltar ao menu..."
}

repair_menu() {
    while true; do
        clear
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${YELLOW}                 Menu de Reparo & Ferramentas               ${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo -e "Escolha uma ferramenta:"
        echo -e " 1) ${GREEN}Limpar arquivos temporários (logs, sockets, travas de run)${NC}"
        echo -e " 2) ${BLUE}Verificar integridade do disco de uma VM${NC}"
        echo -e " 3) ${YELLOW}Recompilar QEMU Interno e GOP ROM${NC}"
        echo -e " 4) ${BLUE}Verificar e reinstalar dependências do sistema${NC}"
        echo -e " 5) Voltar ao Menu Principal"
        echo -e "${BLUE}============================================================${NC}"
        read -rp "Opção (1-5): " opt
        
        case "$opt" in
            1)
                echo -e "\n${BLUE}Limpando arquivos temporários em vm/disks/run/...${NC}"
                rm -rf "$SCRIPT_DIR/vm/disks/run"/* || true
                echo -e "${GREEN}Limpeza concluída!${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            2)
                clear
                echo -e "${BLUE}============================================================${NC}"
                echo -e "${GREEN}   Verificar Integridade de Disco${NC}"
                echo -e "${BLUE}============================================================${NC}"
                echo -e "\nSelecione a VM para analisar os discos:"
                if list_vms; then
                    read -rp "Escolha a VM (1-${#VMS_LIST[@]}): " vm_choice
                    if [[ "$vm_choice" =~ ^[0-9]+$ ]] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le "${#VMS_LIST[@]}" ]; then
                        local selected_vm="${VMS_LIST[$((vm_choice-1))]}"
                        local snap_dir="$SCRIPT_DIR/vm/disks/rails/$selected_vm/snapshots"
                        echo -e "\nAnalisando discos da VM '$selected_vm'..."
                        if [ -d "$snap_dir" ]; then
                            find "$snap_dir" -type f -name "*.img" -o -name "*.qcow2" | while read -r disk; do
                                echo -e "\nVerificando disco: ${BLUE}$(basename "$disk")${NC}"
                                qemu-img check "$disk" || true
                            done
                        else
                            echo -e "${YELLOW}Esta VM ainda não possui snapshots para verificar.${NC}"
                        fi
                    else
                        echo -e "${RED}Opção inválida!${NC}"
                    fi
                else
                    echo -e "${YELLOW}Nenhuma VM instalada para verificar.${NC}"
                fi
                echo ""
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            3)
                echo -e "\n${BLUE}Recompilando QEMU...${NC}"
                "$SCRIPT_DIR/scripts/qemu-build/qemu-build.sh" --target x86_64 --backend vulkan || true
                echo -e "\n${BLUE}Recompilando GOP ROM...${NC}"
                "$SCRIPT_DIR/crates/reims-vgpu-efi/scripts/reims-vgpu-efi-rom/reims-vgpu-efi-rom.sh" || true
                echo -e "\n${GREEN}Recompilação finalizada!${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            4)
                echo -e "\n${BLUE}Verificando dependências de sistema...${NC}"
                if command -v pacman >/dev/null 2>&1; then
                    sudo pacman -S --needed --noconfirm qemu-base git wget libguestfs dmg2img p7zip make python python-pip cdrtools net-tools screen || true
                elif command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update
                    sudo apt-get install -y qemu-system uml-utilities virt-manager git \
                        wget libguestfs-tools p7zip-full make dmg2img tesseract-ocr \
                        tesseract-ocr-eng genisoimage vim net-tools screen || true
                else
                    echo -e "${RED}Nenhum gerenciador de pacotes suportado encontrado.${NC}"
                fi
                echo -e "\n${GREEN}Verificação de dependências concluída!${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                read -n 1 -s
                ;;
        esac
    done
}

check_updates() {
    echo -e "\n${BLUE}Verificando atualizações nos repositórios...${NC}"
    
    # 1. Verificar repositório principal
    echo -e "\n[1/4] Verificando repositório principal (osx-linux)..."
    if git fetch origin master >/dev/null 2>&1; then
        local behind_commits=$(git log HEAD..origin/master --oneline)
        if [ -n "$behind_commits" ]; then
            echo -e "${YELLOW}Existem novos commits no repositório remoto!${NC}"
            echo "$behind_commits" | sed 's/^/  /'
        else
            echo -e "${GREEN}O repositório principal está totalmente atualizado.${NC}"
        fi
    else
        echo -e "${RED}Erro ao conectar ao servidor do GitHub para verificar o repositório principal.${NC}"
    fi
    
    # 2. Verificar submódulo QEMU
    echo -e "\n[2/4] Verificando submódulo QEMU (vendor/qemu)..."
    if [ -d "$SCRIPT_DIR/vendor/qemu/.git" ]; then
        if git -C "$SCRIPT_DIR/vendor/qemu" fetch origin >/dev/null 2>&1; then
            local sub_branch=$(git -C "$SCRIPT_DIR/vendor/qemu" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "host-reims-vgpu-vmapple")
            local sub_behind=$(git -C "$SCRIPT_DIR/vendor/qemu" log HEAD..origin/"$sub_branch" --oneline 2>/dev/null || true)
            if [ -n "$sub_behind" ]; then
                echo -e "${YELLOW}Existem novas correções disponíveis para o QEMU em 'origin/$sub_branch'!${NC}"
                echo "$sub_behind" | head -n 5 | sed 's/^/  /'
            else
                echo -e "${GREEN}O submódulo QEMU está atualizado.${NC}"
            fi
        else
            echo -e "${RED}Erro ao verificar atualizações do QEMU.${NC}"
        fi
    else
        echo -e "${YELLOW}Submódulo QEMU ainda não inicializado.${NC}"
    fi
    
    # 3. Verificar OSX-KVM
    echo -e "\n[3/4] Verificando repositório OSX-KVM (osx-kvm-temp)..."
    if [ -d "$SCRIPT_DIR/osx-kvm-temp/.git" ]; then
        if git -C "$SCRIPT_DIR/osx-kvm-temp" fetch origin >/dev/null 2>&1; then
            local kvm_behind=$(git -C "$SCRIPT_DIR/osx-kvm-temp" log HEAD..origin/master --oneline 2>/dev/null || true)
            if [ -n "$kvm_behind" ]; then
                echo -e "${YELLOW}Existem novas atualizações no OSX-KVM remoto!${NC}"
                echo "$kvm_behind" | head -n 5 | sed 's/^/  /'
            else
                echo -e "${GREEN}O repositório OSX-KVM está atualizado.${NC}"
            fi
        else
            echo -e "${RED}Erro ao verificar atualizações do OSX-KVM.${NC}"
        fi
    else
        echo -e "${YELLOW}Pasta osx-kvm-temp ainda não inicializada.${NC}"
    fi
    
    # 4. Verificar pacotes Cargo (Rust)
    echo -e "\n[4/4] Verificando atualizações de pacotes/crates em Rust..."
    if command -v cargo >/dev/null 2>&1; then
        echo -e "Analisando pacotes de crates externas (pode demorar alguns segundos)..."
        local cargo_updates=$(cargo update --dry-run 2>&1 | grep -E "Updating|Removing" || true)
        if [ -n "$cargo_updates" ]; then
            echo -e "${YELLOW}Existem pacotes Rust com atualizações disponíveis nas dependências!${NC}"
            echo "$cargo_updates" | head -n 10 | sed 's/^/  /'
        else
            echo -e "${GREEN}Todas as dependências Rust estão atualizadas.${NC}"
        fi
    else
        echo -e "${RED}Comando cargo não encontrado no sistema.${NC}"
    fi
}

update_menu() {
    while true; do
        clear
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${YELLOW}                 Menu de Atualizações                       ${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo -e "Escolha uma opção:"
        echo -e " 1) ${BLUE}Verificar se existem atualizações disponíveis (Check)${NC}"
        echo -e " 2) ${GREEN}Atualizar Código do Projeto (git pull / rebase)${NC}"
        echo -e " 3) ${GREEN}Sincronizar e Atualizar Submódulos (QEMU & OSX-KVM)${NC}"
        echo -e " 4) ${GREEN}Atualizar Dependências de Crates Rust (cargo update)${NC}"
        echo -e " 5) Voltar ao Menu Principal"
        echo -e "${BLUE}============================================================${NC}"
        read -rp "Opção (1-5): " opt
        
        case "$opt" in
            1)
                check_updates
                echo ""
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            2)
                echo -e "\n${BLUE}Buscando atualizações de código do projeto...${NC}"
                git stash
                if git pull --rebase origin master; then
                    echo -e "${GREEN}Código do projeto atualizado com sucesso!${NC}"
                else
                    echo -e "${RED}Erro ao puxar atualizações. Resolva os conflitos no Git manualmente.${NC}"
                fi
                git stash pop || true
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            3)
                echo -e "\n${BLUE}Atualizando e sincronizando submódulos...${NC}"
                git submodule update --init --recursive
                if [ -d "$SCRIPT_DIR/osx-kvm-temp/.git" ]; then
                    echo -e "Atualizando repositório OSX-KVM em osx-kvm-temp..."
                    git -C "$SCRIPT_DIR/osx-kvm-temp" pull --rebase || true
                fi
                echo -e "${GREEN}Submódulos atualizados com sucesso!${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            4)
                echo -e "\n${BLUE}Atualizando dependências de pacotes em Rust...${NC}"
                if command -v cargo >/dev/null 2>&1; then
                    cargo update
                    echo -e "${GREEN}Pacotes de crates Rust atualizados com sucesso!${NC}"
                else
                    echo -e "${RED}Comando cargo não encontrado.${NC}"
                fi
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                read -n 1 -s
                ;;
        esac
    done
}

main_menu() {
    while true; do
        clear
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${GREEN}      Gerenciador de VMs macOS - Reims Paravirtualização    ${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo -e "Escolha uma opção:"
        echo -e " 1) ${GREEN}Instalar Nova Máquina Virtual macOS${NC}"
        echo -e " 2) ${BLUE}Iniciar Máquina Virtual Existente${NC}"
        echo -e " 3) ${YELLOW}Editar Configurações de uma VM Existente${NC}"
        echo -e " 4) ${RED}Deletar Máquina Virtual Existente${NC}"
        echo -e " 5) ${YELLOW}Menu de Reparo & Ferramentas${NC}"
        echo -e " 6) ${BLUE}Menu de Atualizações (Check & Update)${NC}"
        echo -e " 7) Sair"
        echo -e "${BLUE}============================================================${NC}"
        read -rp "Opção (1-7): " opt
        
        case "$opt" in
            1) install_vm ;;
            2) start_vm ;;
            3) edit_vm ;;
            4) delete_vm ;;
            5) repair_menu ;;
            6) update_menu ;;
            7) echo -e "\nAté mais!\n"; exit 0 ;;
            *) echo -e "${RED}Opção inválida! Pressione qualquer tecla para continuar...${NC}"; read -n 1 -s ;;
        esac
    done
}

# Inicia o Menu Principal
main_menu
