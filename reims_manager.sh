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

# Função para exibir um spinner animado moderno e uma caixa de logs em tempo real enquanto um processo roda em background
show_spinner() {
    local pid=$1
    local message="$2"
    local log_file="${3:-/dev/null}"
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' # Spinner moderno de braille
    local spin_idx=0
    
    # Limpa a tela inteira uma vez antes de iniciar o loop para garantir a remoção completa do menu antigo
    clear
    
    # Esconde o cursor do terminal para evitar piscadas
    tput civis 2>/dev/null || true
    
    while kill -0 "$pid" 2>/dev/null; do
        # Posiciona o cursor no topo esquerdo e limpa do cursor até o fim da tela (evita flickers e resíduos de texto antigo)
        printf "\033[H\033[J"
        
        # Desenhar o cabeçalho estático do menu
        echo -e "${BLUE}============================================================${NC}"
        echo -e "${GREEN}      Gerenciador de VMs macOS - Reims Paravirtualização    ${NC}"
        echo -e "${BLUE}============================================================${NC}"
        echo -e ""
        
        # Desenhar o spinner e a mensagem ativa
        local char="${spinstr:$spin_idx:1}"
        spin_idx=$(( (spin_idx + 1) % ${#spinstr} ))
        echo -e "  ${BLUE}$char${NC}  ${YELLOW}$message...${NC}"
        echo -e ""
        
        # Desenhar a caixa de logs
        echo -e "  ${BLUE}┌─────────────────────[ LOGS EM TEMPO REAL ]─────────────────────┐${NC}"
        
        local lines=()
        if [ -f "$log_file" ] && [ "$log_file" != "/dev/null" ]; then
            while IFS= read -r line; do
                # Limpar retornos de carro, tabulações e caracteres de escape ANSI para manter a caixa limpa
                local clean_line=$(echo "$line" | tr -d '\r' | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | cut -c1-60)
                printf -v padded_line "%-60s" "$clean_line"
                lines+=("$padded_line")
            done < <(tail -n 8 "$log_file")
        fi
        
        # Se o log tiver menos de 8 linhas, preencher com vazias
        while [ ${#lines[@]} -lt 8 ]; do
            printf -v padded_line "%-60s" ""
            lines+=("$padded_line")
        done
        
        # Imprimir as 8 linhas de log dentro das bordas da caixa
        for line in "${lines[@]}"; do
            echo -e "  ${BLUE}│${NC}  $line  ${BLUE}│${NC}"
        done
        
        echo -e "  ${BLUE}└────────────────────────────────────────────────────────────────┘${NC}"
        
        sleep $delay
    done
    
    # Restaura o cursor do terminal
    tput cnorm 2>/dev/null || true
    
    # Aguarda o processo terminar e pega o código de saída
    wait "$pid"
    local exit_code=$?
    
    # Atualiza a tela com o resultado final posicionado no topo e limpa até o fim
    printf "\033[H\033[J"
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}      Gerenciador de VMs macOS - Reims Paravirtualização    ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo -e ""
    
    if [ $exit_code -eq 0 ]; then
        echo -e "  [${GREEN}✓${NC}]  ${GREEN}${message} - Concluído com Sucesso!${NC}"
    else
        echo -e "  [${RED}✗${NC}]  ${RED}${message} - Falhou! (Código: $exit_code)${NC}"
    fi
    echo -e ""
    
    # Desenhar caixa final
    echo -e "  ${BLUE}┌─────────────────────────[ FIM DO LOG ]─────────────────────────┐${NC}"
    local lines=()
    if [ -f "$log_file" ] && [ "$log_file" != "/dev/null" ]; then
        while IFS= read -r line; do
            local clean_line=$(echo "$line" | tr -d '\r' | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | cut -c1-60)
            printf -v padded_line "%-60s" "$clean_line"
            lines+=("$padded_line")
        done < <(tail -n 8 "$log_file")
    fi
    while [ ${#lines[@]} -lt 8 ]; do
        printf -v padded_line "%-60s" ""
        lines+=("$padded_line")
    done
    for line in "${lines[@]}"; do
        echo -e "  ${BLUE}│${NC}  $line  ${BLUE}│${NC}"
    done
    echo -e "  ${BLUE}└────────────────────────────────────────────────────────────────┘${NC}"
    echo -e ""
    
    return $exit_code
}

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
    local config_json="$SCRIPT_DIR/vm/disks/rails/$selected_vm/config.json"
    local config_file="$SCRIPT_DIR/vm/disks/rails/$selected_vm/config.sh"
    
    # Carregar valores salvos ou usar padrões seguros
    local ram="16G"
    local cores="4"
    local threads="8"
    local resolution="1920x1080"
    
    # Se o config.json não existir, mas o config.sh sim, criar o json a partir do sh
    if [ ! -f "$config_json" ] && [ -f "$config_file" ]; then
        local r=$(grep "^RAM=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "16G")
        local c=$(grep "^CPU_CORES=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "4")
        local t=$(grep "^CPU_THREADS=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "8")
        local res=$(grep "^RESOLUTION=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "1920x1080")
        python3 -c "import json; json.dump({'ram': '$r', 'cpu_cores': int('$c'), 'cpu_threads': int('$t'), 'resolution': '$res'}, open('$config_json', 'w'), indent=4)" 2>/dev/null || true
    fi

    # Se o config.json existir, ler os valores dele (fonte de verdade absoluta!)
    if [ -f "$config_json" ]; then
        ram=$(python3 -c "import json; print(json.load(open('$config_json')).get('ram', '16G'))" 2>/dev/null || echo "16G")
        cores=$(python3 -c "import json; print(json.load(open('$config_json')).get('cpu_cores', 4))" 2>/dev/null || echo "4")
        threads=$(python3 -c "import json; print(json.load(open('$config_json')).get('cpu_threads', 8))" 2>/dev/null || echo "8")
        resolution=$(python3 -c "import json; print(json.load(open('$config_json')).get('resolution', '1920x1080'))" 2>/dev/null || echo "1920x1080")
        
        # Validar e sincronizar config.sh para refletir o JSON de forma correta
        local sh_ram=$(grep "^RAM=" "$config_file" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "")
        local sh_cores=$(grep "^CPU_CORES=" "$config_file" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "")
        
        if [ "$sh_ram" != "$ram" ] || [ "$sh_cores" != "$cores" ]; then
            echo -e "${YELLOW}Alterações detectadas no config.json. Sincronizando especificações da VM...${NC}"
            echo "RAM=\"$ram\"" > "$config_file"
            echo "CPU_CORES=\"$cores\"" >> "$config_file"
            echo "CPU_THREADS=\"$threads\"" >> "$config_file"
            echo "RESOLUTION=\"$resolution\"" >> "$config_file"
        fi
    elif [ -f "$config_file" ]; then
        ram=$(grep "^RAM=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "16G")
        cores=$(grep "^CPU_CORES=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "4")
        threads=$(grep "^CPU_THREADS=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "8")
        resolution=$(grep "^RESOLUTION=" "$config_file" | cut -d= -f2 | tr -d '"' || echo "1920x1080")
    fi
    
    # Se estiver em ambiente Omarchy/Hyprland ou em desktops tradicionais (GNOME, KDE, XFCE, Cinnamon, etc. via wmctrl)
    local target_workspace=""
    local uses_hyprctl=0
    local uses_wmctrl=0
    
    if command -v hyprctl >/dev/null 2>&1; then
        uses_hyprctl=1
    elif command -v wmctrl >/dev/null 2>&1; then
        uses_wmctrl=1
    fi
    
    if [ "$uses_hyprctl" -eq 1 ] || [ "$uses_wmctrl" -eq 1 ]; then
        echo -e "\n${BLUE}[Ambiente Gráfico com Suporte a Área de Trabalho Detectado]${NC}"
        read -rp "Deseja iniciar a VM em qual Área de Trabalho Virtual? (Ex: 1-10, Enter para atual): " ws_choice
        if [[ "$ws_choice" =~ ^[0-9]+$ ]]; then
            target_workspace="$ws_choice"
            if [ "$uses_hyprctl" -eq 1 ]; then
                echo -e "${GREEN}Configurando Hyprland para abrir a VM no Workspace $ws_choice...${NC}"
                hyprctl keyword windowrulev2 "workspace $ws_choice,class:^(qemu-system-x86_64)$" >/dev/null 2>&1 || true
                hyprctl keyword windowrulev2 "workspace $ws_choice,class:^(qemu)$" >/dev/null 2>&1 || true
            elif [ "$uses_wmctrl" -eq 1 ]; then
                echo -e "${GREEN}Agendando movimento da VM para o Workspace $ws_choice via wmctrl...${NC}"
                # Move a janela do QEMU assim que ela aparecer em segundo plano (assíncrono)
                local ws_index=$((ws_choice - 1))
                if [ "$ws_index" -lt 0 ]; then ws_index=0; fi
                (
                    for i in {1..30}; do
                        sleep 0.5
                        local win_id=$(wmctrl -l 2>/dev/null | grep -iE "QEMU|reims-vgpu" | head -n 1 | cut -d' ' -f1 || true)
                        if [ -n "$win_id" ]; then
                            wmctrl -i -r "$win_id" -t "$ws_index" >/dev/null 2>&1 || true
                            break
                        fi
                    done
                ) &
            fi
        fi
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
    local config_json="$SCRIPT_DIR/vm/disks/rails/$selected_vm/config.json"
    local config_file="$SCRIPT_DIR/vm/disks/rails/$selected_vm/config.sh"
    
    # Valores atuais ou padrões
    local ram="16G"
    local cores="4"
    local resolution="1920x1080"
    
    if [ -f "$config_json" ]; then
        ram=$(python3 -c "import json; print(json.load(open('$config_json')).get('ram', '16G'))" 2>/dev/null || echo "16G")
        cores=$(python3 -c "import json; print(json.load(open('$config_json')).get('cpu_cores', 4))" 2>/dev/null || echo "4")
        resolution=$(python3 -c "import json; print(json.load(open('$config_json')).get('resolution', '1920x1080'))" 2>/dev/null || echo "1920x1080")
    elif [ -f "$config_file" ]; then
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
    
    # Salvar no JSON (fonte de verdade absoluta!)
    python3 -c "import json; json.dump({'ram': '$ram', 'cpu_cores': int('$cores'), 'cpu_threads': int('$threads'), 'resolution': '$resolution'}, open('$config_json', 'w'), indent=4)" 2>/dev/null || true
    
    # Salvar no config.sh para compatibilidade retroativa
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

install_dependencies() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}   Verificar e Instalar Dependências do Sistema${NC}"
    echo -e "${BLUE}============================================================${NC}"

    local is_interactive="${1:-true}"

    # --- Verificar SO ---
    if [ -f /etc/os-release ]; then
        OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
        echo -e "Sistema detectado: ${GREEN}$OS_NAME${NC}"
    else
        OS_NAME="Desconhecido"
        echo -e "${YELLOW}Aviso: Não foi possível determinar o sistema operacional.${NC}"
    fi

    local pacman_bin=""
    local apt_bin=""
    local dnf_bin=""

    if command -v pacman >/dev/null 2>&1; then pacman_bin="pacman"; fi
    if command -v apt-get >/dev/null 2>&1; then apt_bin="apt-get"; fi
    if command -v dnf >/dev/null 2>&1; then dnf_bin="dnf"; fi

    if [ -n "$pacman_bin" ]; then
        echo -e "Instalando dependências via ${GREEN}pacman${NC}..."
        echo -e "${YELLOW}Pode ser solicitado o acesso root (sudo) para autenticação.${NC}"
        sudo -v
        sudo pacman -S --needed --noconfirm base-devel git wget qemu-base libguestfs p7zip make python python-pip cdrtools net-tools screen meson ninja dtc libslirp llvm-libs llvm spirv-tools vulkan-headers > "$SCRIPT_DIR/pacman_install.log" 2>&1 &
        show_spinner $! "Instalando pacotes do sistema via pacman" "$SCRIPT_DIR/pacman_install.log" || {
            echo -e "${RED}Erro na instalação. Detalhes do log em pacman_install.log:${NC}"
            tail -n 15 "$SCRIPT_DIR/pacman_install.log"
        }
        
        # Configurar Rustup para UEFI no Arch
        if command -v rustup >/dev/null 2>&1; then
            echo -e "  [${GREEN}✓${NC}]  ${GREEN}Rustup detectado.${NC}"
        else
            echo -e "${YELLOW}Instalando rustup no lugar do rust do sistema para suporte UEFI...${NC}"
            sudo pacman -Rdd --noconfirm rust >/dev/null 2>&1 || true
            sudo pacman -S --noconfirm rustup >/dev/null 2>&1 || true
            rustup default stable >/dev/null 2>&1 || true
        fi
        
    elif [ -n "$dnf_bin" ]; then
        echo -e "Instalando dependências via ${GREEN}dnf${NC}..."
        echo -e "${YELLOW}Pode ser solicitado o acesso root (sudo) para autenticação.${NC}"
        sudo -v
        # Instalação das ferramentas base e de compilação do QEMU/Reims no Fedora (incluindo suporte a interface gráfica GTK/SDL)
        sudo dnf install -y qemu-kvm git wget libguestfs-tools dmg2img p7zip p7zip-plugins make python3 python3-pip genisoimage net-tools screen tesseract vim \
            meson ninja-build glib2-devel pixman-devel libslirp-devel libbpf-devel libcap-ng-devel libseccomp-devel vulkan-headers vulkan-loader-devel spirv-tools llvm llvm-devel clang \
            gtk3-devel vte291-devel SDL2-devel SDL2_image-devel libepoxy-devel mesa-libEGL-devel mesa-libgbm-devel virglrenderer-devel libdrm-devel > "$SCRIPT_DIR/dnf_install.log" 2>&1 &
        show_spinner $! "Instalando pacotes do sistema via dnf (pode levar alguns minutos)" "$SCRIPT_DIR/dnf_install.log" || {
            echo -e "${RED}Erro na instalação. Detalhes do log em dnf_install.log:${NC}"
            tail -n 15 "$SCRIPT_DIR/dnf_install.log"
        }
            
    elif [ -n "$apt_bin" ]; then
        echo -e "Instalando dependências via ${GREEN}apt-get${NC}..."
        echo -e "${YELLOW}Pode ser solicitado o acesso root (sudo) para autenticação.${NC}"
        sudo -v
        sudo apt-get update > "$SCRIPT_DIR/apt_update.log" 2>&1 &
        show_spinner $! "Atualizando os repositórios do sistema (apt update)" "$SCRIPT_DIR/apt_update.log"
        
        sudo apt-get install -y qemu-system uml-utilities virt-manager git \
            wget libguestfs-tools p7zip-full make dmg2img tesseract-ocr \
            tesseract-ocr-eng genisoimage vim net-tools screen build-essential \
            meson ninja-build libglib2.0-dev libpixman-1-dev libslirp-dev libbpf-dev libcap-ng-dev libseccomp-dev python3-pip llvm spirv-tools \
            libgtk-3-dev libsdl2-dev libvte-2.91-dev libepoxy-dev libgbm-dev > "$SCRIPT_DIR/apt_install.log" 2>&1 &
        show_spinner $! "Instalando pacotes do sistema via apt-get" "$SCRIPT_DIR/apt_install.log" || {
            echo -e "${RED}Erro na instalação. Detalhes do log em apt_install.log:${NC}"
            tail -n 15 "$SCRIPT_DIR/apt_install.log"
        }
    else
        echo -e "${YELLOW}Gerenciador de pacotes pacman, apt ou dnf não encontrado.${NC}"
        echo -e "${YELLOW}Certifique-se de que as dependências básicas (qemu, dmg2img, make, meson, ninja, libslirp, etc.) já estão instaladas.${NC}"
    fi

    # --- Configuração do Rust e UEFI Target ---
    echo -e "\n${BLUE}Verificando compilador Rust e target UEFI...${NC}"
    if ! command -v rustup >/dev/null 2>&1; then
        echo -e "${YELLOW}Rustup não encontrado no PATH.${NC}"
        if [ -f "$HOME/.cargo/env" ]; then
            echo -e "Carregando ambiente do Cargo..."
            source "$HOME/.cargo/env"
        fi
    fi

    if ! command -v rustup >/dev/null 2>&1; then
        echo -e "${YELLOW}Instalando Rust via rustup oficial...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
        fi
    fi

    if command -v rustup >/dev/null 2>&1; then
        echo -e "Adicionando target UEFI (${GREEN}x86_64-unknown-uefi${NC})..."
        rustup target add x86_64-unknown-uefi || true
        echo -e "${GREEN}Rust e target UEFI configurados com sucesso!${NC}"
    else
        echo -e "${RED}Erro: Não foi possível configurar o Rustup automaticamente. Por favor, instale o rustup e o target x86_64-unknown-uefi manualmente.${NC}"
    fi

    echo -e "\n${GREEN}Verificação de dependências concluída!${NC}"
    if [ "$is_interactive" = "true" ]; then
        if [ -d "$SCRIPT_DIR/vendor/qemu/build" ]; then
            echo -e "\n${YELLOW}Aviso: O QEMU possui uma compilação anterior em cache.${NC}"
            echo -e "Para que o suporte gráfico nativo (GTK/SDL) recém-instalado seja compilado, é necessário limpar o cache anterior."
            read -rp "Deseja limpar o cache de compilação do QEMU para forçar uma nova configuração? [S/n]: " clean_choice
            clean_choice="${clean_choice:-S}"
            if [[ "$clean_choice" =~ ^[Ss]$ ]]; then
                echo -e "Limpando diretório de compilação em vendor/qemu/build..."
                rm -rf "$SCRIPT_DIR/vendor/qemu/build"
                echo -e "${GREEN}Cache limpo com sucesso! Na próxima compilação, o QEMU será totalmente reconfigurado com suporte GTK/SDL.${NC}"
            fi
        fi
        echo ""
        read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
    fi
}

install_vm() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN}   Instalar Nova Máquina Virtual macOS com Reims vGPU${NC}"
    echo -e "${BLUE}============================================================${NC}"

    # --- Verificar SO e Gerenciador de Pacotes ---
    echo -e "\n${BLUE}[1/7] Verificando sistema operacional e dependências...${NC}"
    install_dependencies false

    # --- Compilar QEMU Interno ---
    echo -e "\n${BLUE}[2/7] Compilando e configurando o QEMU interno com suporte a Vulkan/Reims...${NC}"
    # Executa o script de compilação local
    ./scripts/qemu-build/qemu-build.sh --target x86_64 --backend vulkan > "$SCRIPT_DIR/qemu_build.log" 2>&1 &
    show_spinner $! "Compilando QEMU com suporte Reims vGPU (isso pode levar de 2 a 5 minutos)" "$SCRIPT_DIR/qemu_build.log"
    local build_res=$?

    QEMU_BIN="$SCRIPT_DIR/vendor/qemu/build/qemu-system-x86_64"
    if [ $build_res -ne 0 ] || [ ! -f "$QEMU_BIN" ]; then
        echo -e "${RED}Erro: Falha ao compilar o QEMU. Veja as últimas linhas do log em qemu_build.log:${NC}"
        tail -n 30 "$SCRIPT_DIR/qemu_build.log"
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

    # Gerenciar cache individual por versão de macOS para evitar conflitos de mídias (ex: Sonoma usando Tahoe)
    local cached_dmg="$SCRIPT_DIR/vm/disks/BaseSystem-$MAC_VERSION.dmg"
    
    # Remove mídias residuais genéricas antes do processo para garantir que a versão correta seja montada
    rm -f BaseSystem.dmg BaseSystem.img
    
    if [ -f "$cached_dmg" ]; then
        echo -e "${GREEN}Usando BaseSystem-$MAC_VERSION.dmg do cache de mídia local...${NC}"
        cp -f "$cached_dmg" BaseSystem.dmg
    elif [ -f "$SCRIPT_DIR/BaseSystem.dmg" ]; then
        # Retrocompatibilidade
        echo -e "Copiando BaseSystem.dmg existente na raiz..."
        cp -f "$SCRIPT_DIR/BaseSystem.dmg" BaseSystem.dmg
    fi

    if [ ! -f "BaseSystem.dmg" ]; then
        ./fetch-macOS-v2.py --shortname="$MAC_VERSION" > "$SCRIPT_DIR/macos_download.log" 2>&1 &
        show_spinner $! "Baixando a imagem de recuperação oficial do macOS ($MAC_VERSION)" "$SCRIPT_DIR/macos_download.log"
        # Copia para a pasta de mídias do Reims como cache para evitar downloads repetidos da mesma versão
        mkdir -p "$SCRIPT_DIR/vm/disks"
        cp -f BaseSystem.dmg "$cached_dmg"
    else
        echo -e "${GREEN}BaseSystem.dmg preparado com sucesso.${NC}"
    fi

    # Converter DMG para IMG bruta
    if command -v dmg2img >/dev/null 2>&1; then
        dmg2img -f -i BaseSystem.dmg BaseSystem.img > "$SCRIPT_DIR/dmg_convert.log" 2>&1 &
        show_spinner $! "Convertendo BaseSystem.dmg para formato cru (.img)" "$SCRIPT_DIR/dmg_convert.log"
    else
        qemu-img convert -O raw BaseSystem.dmg BaseSystem.img > "$SCRIPT_DIR/dmg_convert.log" 2>&1 &
        show_spinner $! "Convertendo BaseSystem.dmg para formato cru (.img)" "$SCRIPT_DIR/dmg_convert.log"
    fi

    # Criar o disco virtual rígido para a instalação do macOS
    rm -f mac_hdd_ng.img
    qemu-img create -f qcow2 mac_hdd_ng.img "$disk_size" > "$SCRIPT_DIR/disk_create.log" 2>&1 &
    show_spinner $! "Criando disco virtual rígido de $disk_size" "$SCRIPT_DIR/disk_create.log"

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
    local config_json="$SCRIPT_DIR/vm/disks/rails/$RAIL_NAME/config.json"
    local config_file="$SCRIPT_DIR/vm/disks/rails/$RAIL_NAME/config.sh"
    
    # Salvar no JSON (fonte de verdade absoluta!)
    python3 -c "import json; json.dump({'ram': '$ram_input', 'cpu_cores': int('$cpu_cores'), 'cpu_threads': int('$cpu_threads'), 'resolution': '1920x1080'}, open('$config_json', 'w'), indent=4)" 2>/dev/null || true
    
    # Salvar no config.sh para compatibilidade retroativa
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
                if [ -d "$SCRIPT_DIR/vendor/qemu/build" ]; then
                    read -rp "Deseja realizar uma compilação LIMPA (limpar cache do QEMU para forçar reconfiguração)? [s/N]: " clean_rebuild
                    if [[ "$clean_rebuild" =~ ^[Ss]$ ]]; then
                        echo -e "${GREEN}Limpando diretório de compilação...${NC}"
                        rm -rf "$SCRIPT_DIR/vendor/qemu/build"
                    fi
                fi
                "$SCRIPT_DIR/scripts/qemu-build/qemu-build.sh" --target x86_64 --backend vulkan > "$SCRIPT_DIR/qemu_build.log" 2>&1 &
                show_spinner $! "Compilando QEMU com suporte Reims vGPU (pode levar alguns minutos)" "$SCRIPT_DIR/qemu_build.log"
                local build_res=$?
                if [ $build_res -ne 0 ]; then
                    echo -e "${RED}Erro: Falha ao compilar o QEMU. Veja as últimas linhas do log em qemu_build.log:${NC}"
                    tail -n 25 "$SCRIPT_DIR/qemu_build.log"
                fi
                echo -e "\n${BLUE}Recompilando GOP ROM...${NC}"
                "$SCRIPT_DIR/crates/reims-vgpu-efi/scripts/reims-vgpu-efi-rom/reims-vgpu-efi-rom.sh" > "$SCRIPT_DIR/gop_build.log" 2>&1 &
                show_spinner $! "Compilando firmware UEFI GOP ROM"
                local gop_res=$?
                if [ $gop_res -ne 0 ]; then
                    echo -e "${RED}Erro: Falha ao compilar a GOP ROM. Detalhes em gop_build.log.${NC}"
                fi
                echo -e "\n${GREEN}Recompilação finalizada!${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            4)
                install_dependencies true
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
                git stash >/dev/null 2>&1
                git pull --rebase origin master > "$SCRIPT_DIR/git_pull.log" 2>&1 &
                show_spinner $! "Atualizando código do projeto via git pull" "$SCRIPT_DIR/git_pull.log"
                local pull_res=$?
                git stash pop >/dev/null 2>&1 || true
                if [ $pull_res -eq 0 ]; then
                    echo -e "${GREEN}Código do projeto atualizado com sucesso!${NC}"
                else
                    echo -e "${RED}Erro ao puxar atualizações. Veja git_pull.log ou resolva conflitos manualmente.${NC}"
                fi
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            3)
                echo -e "\n${BLUE}Atualizando e sincronizando submódulos...${NC}"
                git submodule update --init --recursive > "$SCRIPT_DIR/submodules_update.log" 2>&1 &
                show_spinner $! "Sincronizando e atualizando submódulos do Git" "$SCRIPT_DIR/submodules_update.log"
                if [ -d "$SCRIPT_DIR/osx-kvm-temp/.git" ]; then
                    git -C "$SCRIPT_DIR/osx-kvm-temp" pull --rebase > "$SCRIPT_DIR/osx_kvm_update.log" 2>&1 &
                    show_spinner $! "Atualizando repositório OSX-KVM" "$SCRIPT_DIR/osx_kvm_update.log"
                fi
                echo -e "${GREEN}Submódulos atualizados com sucesso!${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
                ;;
            4)
                echo -e "\n${BLUE}Atualizando dependências de pacotes em Rust...${NC}"
                if command -v cargo >/dev/null 2>&1; then
                    cargo update > "$SCRIPT_DIR/cargo_update.log" 2>&1 &
                    show_spinner $! "Atualizando dependências de crates Rust" "$SCRIPT_DIR/cargo_update.log"
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
        echo -e " 1) ${GREEN}Verificar e Instalar Dependências do Sistema${NC}"
        echo -e " 2) ${GREEN}Instalar Nova Máquina Virtual macOS${NC}"
        echo -e " 3) ${BLUE}Iniciar Máquina Virtual Existente${NC}"
        echo -e " 4) ${YELLOW}Editar Configurações de uma VM Existente${NC}"
        echo -e " 5) ${RED}Deletar Máquina Virtual Existente${NC}"
        echo -e " 6) ${YELLOW}Menu de Reparo & Ferramentas${NC}"
        echo -e " 7) ${BLUE}Menu de Atualizações (Check & Update)${NC}"
        echo -e " 8) Sair"
        echo -e "${BLUE}============================================================${NC}"
        read -rp "Opção (1-8): " opt
        
        case "$opt" in
            1) install_dependencies true ;;
            2) install_vm ;;
            3) start_vm ;;
            4) edit_vm ;;
            5) delete_vm ;;
            6) repair_menu ;;
            7) update_menu ;;
            8) echo -e "\nAté mais!\n"; exit 0 ;;
            *) echo -e "${RED}Opção inválida! Pressione qualquer tecla para continuar...${NC}"; read -n 1 -s ;;
        esac
    done
}

# Verificar se o submódulo QEMU está inicializado e populado
check_submodules() {
    local qemu_dir="$SCRIPT_DIR/vendor/qemu"
    # Se a pasta do QEMU não existir, estiver vazia, ou não tiver o arquivo configure do QEMU
    if [ ! -d "$qemu_dir" ] || [ ! -f "$qemu_dir/configure" ]; then
        echo -e "${YELLOW}Aviso: O submódulo QEMU não está inicializado ou está incompleto.${NC}"
        echo -e "Para que o Reims funcione, precisamos baixar o código-fonte do QEMU (cerca de 150-200MB)."
        read -rp "Deseja inicializar e baixar o submódulo QEMU automaticamente agora? [S/n]: " sub_choice
        sub_choice="${sub_choice:-S}"
        if [[ "$sub_choice" =~ ^[Ss]$ ]]; then
            echo -e "\n${BLUE}Inicializando e atualizando submódulos do Git (QEMU)...${NC}"
            if command -v git >/dev/null 2>&1; then
                cd "$SCRIPT_DIR"
                git submodule update --init --recursive > "$SCRIPT_DIR/submodules_update.log" 2>&1 &
                show_spinner $! "Baixando o código-fonte do QEMU via Git submodules (cerca de 150-200MB)"
                local sub_res=$?
                if [ $sub_res -eq 0 ]; then
                    echo -e "${GREEN}Submódulos populados com sucesso!${NC}"
                else
                    echo -e "${RED}Erro ao baixar submódulos. Detalhes em submodules_update.log.${NC}"
                fi
            else
                echo -e "${RED}Erro: Comando 'git' não encontrado! Por favor, instale o git e inicialize os submódulos manualmente.${NC}"
                read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
            fi
        else
            echo -e "${RED}Aviso: Sem o código-fonte do QEMU, você não conseguirá compilar ou instalar as VMs macOS.${NC}"
            read -n 1 -s -r -p "Pressione qualquer tecla para continuar..."
        fi
    fi
}

# Inicia a verificação de submódulos e o Menu Principal
check_submodules
main_menu
