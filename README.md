# OSX-Linux: macOS com Aceleração Gráfica Paravirtualizada no Linux (Reims vGPU)

⚠️ **ISENÇÃO DE RESPONSABILIDADE / LEGAL DISCLAIMER**

*Este projeto foi desenvolvido com fins estritamente **educacionais, de pesquisa acadêmica, experimentação científica e testes não-comerciais** relativos à virtualização de sistemas operacionais e à paravirtualização de drivers gráficos.*

* **Sem Distribuição de Propriedade Intelectual:** Este repositório **NÃO** hospeda, armazena, compartilha ou distribui quaisquer binários proprietários, arquivos protegidos por direitos autorais, instaladores do macOS, firmwares proprietários ou chaves de segurança da Apple Inc. Todas as ferramentas utilitárias inclusas (como scripts de download de recuperação) buscam imagens de recuperação disponibilizadas publicamente e diretamente a partir dos servidores oficiais da Apple Inc.
* **Marcas Registradas:** Apple, macOS, OS X, Metal, Ventura, Sonoma e demais termos são marcas registradas de titularidade da Apple Inc., utilizadas neste repositório exclusivamente de forma nominativa para fins de identificação, estudo científico e referência tecnológica sob a doutrina de Fair Use (Uso Aceitável).
* **Termos de Serviço:** A execução de sistemas operacionais macOS em hardware que não seja de fabricação da Apple Inc. pode estar em desconformidade com os Termos de Contrato de Licença de Usuário Final (EULA) do macOS.
* **Responsabilidade do Usuário:** O usuário final é o único e exclusivo responsável por ler, entender e estar em conformidade com as leis de direitos autorais de seu país e com quaisquer termos de licença de uso de software aplicáveis antes de prosseguir com qualquer instalação gráfica.

---


Este projeto é uma distribuição pronta, leve e configurada baseada no revolucionário projeto **Reims vGPU** (de Anees Iqbal / steelbrain). Ele permite emular o macOS Ventura (ou superior) no Linux (QEMU/KVM) utilizando a sua GPU física compartilhada através de paravirtualização nativa da Apple (`AppleParavirtGPU.kext`), traduzindo chamadas gráficas do **Metal** para **Vulkan** em tempo real!

Ideal para quem quer rodar macOS fluido em máquinas modernas (como processadores Intel de 11ª a 14ª gerações, GPUs AMD ou Intel UHD 730/770) que não possuem suporte/drivers Hackintosh nativos para placas de vídeo físicas.

---

## 💻 Requisitos do Sistema

### Hardware Mínimo:
*   **Processador:** Processador Intel ou AMD com suporte a virtualização de hardware (`Intel VT-x` ou `AMD-V`) e tabelas de páginas aninhadas (`EPT` ou `NPT`).
*   **GPU:** Qualquer placa de vídeo (integrada ou dedicada) compatível com a API **Vulkan 1.2** ou superior (como Intel UHD 730+, AMD Radeon modernas ou NVIDIA).

### Sistema Hospedeiro (Host Linux):
*   Qualquer distribuição Linux moderna baseada em Arch (como Arch Linux, Omarchy, EndeavourOS) ou baseada em Ubuntu/Debian (como Ubuntu 24.04/26.04).

---

## 🚀 Instalação Automática com o Reims Manager (Recomendado)

Se você deseja economizar tempo e ter uma interface visual amigável via terminal para fazer tudo isso de forma automatizada, use o **Reims Manager**! Ele automatiza a verificação de requisitos, compilação do QEMU, downloads das imagens oficiais de recuperação, configuração do hardware (RAM, CPU, HD), inicialização nos modos corretos de forma protegida e até tarefas de reparo e atualizações.

Basta abrir o terminal na pasta raiz do projeto e executar:

```bash
chmod +x reims_manager.sh
./reims_manager.sh
```

### O que você pode fazer pelo Gerenciador:
* **`1` - Instalar Nova VM:** Escolha a versão desejada (de High Sierra ao Sequoia/Tahoe), informe o hardware desejado e o script cuidará do download, criação do disco e da inicialização estável com instruções detalhadas de formatação.
* **`2` - Iniciar VM Existente:** Escolha qual VM ligar e o seu driver de vídeo: com **Aceleração Reims vGPU (Vulkan)** acelerada por hardware ou em modo de compatibilidade básico (VMware SVGA). O script detecta automaticamente se a VM é nova e oferece iniciá-la em Modo de Captura para criar o primeiro snapshot imutável de paravirtualização.
* **`3` - Editar Configurações:** Altere as especificações de hardware (RAM, Cores de CPU e Resolução de Tela) de qualquer uma das suas VMs individualmente de forma extremamente simples.
* **`4` - Deletar VM:** Remova com segurança e limpe todo o espaço ocupado por uma VM e todos os seus snapshots.
* **`5` - Menu de Reparo:** Faça limpezas de logs e sockets temporários travados por crashes, verifique a integridade dos discos virtuais ou force a recompilação de componentes.
* **`6` - Menu de Atualizações:** Verifique se existem novos commits no repositório principal, no QEMU customizado, no OSX-KVM e também analise novas versões de crates/dependências Rust.

---

## 🛠️ Instalação Manual (Passo a Passo)

Antes de compilar, instale os compiladores, gerenciadores de build e ferramentas de firmware exigidas pelo QEMU e pelo Reims vGPU.

### No Arch Linux / Omarchy / EndeavourOS:

1.  **Instale os utilitários de compilação e dependências de rede/disco:**
    ```bash
    sudo pacman -S --noconfirm base-devel git meson ninja dtc libslirp qemu-img llvm-libs llvm spirv-tools vulkan-headers
    ```

2.  **Instale o gerenciador de pacotes do Rust (Rustup) para o UEFI target:**
    O compilador padrão do Arch não traz suporte a compilação UEFI. Substitua o `rust` padrão pelo `rustup`:
    ```bash
    sudo pacman -Rdd --noconfirm rust
    sudo pacman -S --noconfirm rustup
    rustup default stable
    rustup target add x86_64-unknown-uefi
    ```

3.  **Instale o conversor de imagens da Apple (AUR):**
    ```bash
    yay -S --noconfirm dmg2img
    ```

### No Ubuntu / Debian / Pop!_OS:

1.  **Instale as dependências básicas de compilação do QEMU:**
    ```bash
    sudo apt update
    sudo apt install -y build-essential git meson ninja-build libglib2.0-dev libpixman-1-dev libslirp-dev libbpf-dev libcap-ng-dev libseccomp-dev python3-pip llvm spirv-tools dmg2img qemu-utils
    ```

2.  **Instale o Rust via Rustup e adicione o alvo UEFI:**
    ```bash
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup target add x86_64-unknown-uefi
    ```

---

## 🚀 Passo a Passo de Preparação e Execução

### Passo 1: Clonar o Repositório e Compilar o QEMU + Reims
Clone este repositório garantindo que os submódulos (o QEMU patchado) sejam baixados e, em seguida, compile o motor:

```bash
# Garantir que todos os submódulos foram baixados
git submodule update --init --recursive

# Compilar o QEMU com o backend Vulkan (levará de 2 a 6 minutos)
./scripts/qemu-build/qemu-build.sh --target x86_64 --backend vulkan
```

### Passo 2: Baixar o Instalador do macOS Ventura (13)
O macOS Ventura é a versão recomendada para máxima estabilidade no Reims vGPU. Execute o nosso script automatizado para baixá-lo diretamente da Apple:

```bash
# Executar o assistente de download
./vm/download-macos-helper.sh
```
1.  Digite **`y`** para abrir o utilitário oficial.
2.  Digite o número correspondente à opção **`macOS Ventura (13)`** e pressione Enter.
3.  O download de aproximadamente 840 MB será iniciado.
4.  Após a conclusão, converta a imagem baixada para o formato raw do QEMU rodando:
    ```bash
    dmg2img BaseSystem.dmg vm/disks/BaseSystem.img
    ```

### Passo 3: Configurar os Firmwares UEFI e o Bootloader OpenCore
Para que a sua máquina virtual possa se inicializar, execute o nosso script que traz as configurações prontas da comunidade do OSX-KVM:

```bash
# Baixar o OpenCore e os firmwares UEFI automaticamente
./vm/setup-firmware.sh
```

### Passo 4: Criar o Disco Rígido Virtual (HD de 128 GB)
Crie o disco virtual dinâmico onde o macOS será instalado:

```bash
qemu-img create -f qcow2 vm/disks/macos.img 128G
```

---

## 🖥️ Inicializando a Instalação

Agora que todos os arquivos estão perfeitamente no lugar, inicie a emulação interativa para passar pelo processo de instalação gráfica:

```bash
./vm/boot-x86.sh --device vmware-svga --interactive --capture
```

*Nota: Usamos `--device vmware-svga` para carregar a janela gráfica GTK clássica do QEMU na sua tela do Linux, permitindo que você veja as etapas iniciais de instalação antes da aceleração gráfica carregar.*

### 🛠️ O que fazer dentro da janela gráfica do QEMU:

1.  **Selecione o boot de recuperação:** No menu preto do OpenCore, use as setas do teclado e selecione **"macOS Base System (external)"** e pressione Enter.
2.  **Formatar o Disco Virtual:**
    *   Assim que a tela de recuperação abrir, abra o **Utilitário de Disco** (Disk Utility).
    *   No topo esquerdo, clique no menu "Visualizar" (View) -> **"Mostrar Todos os Dispositivos"** (Show All Devices).
    *   Selecione o disco rígido virtual de 128 GB (geralmente nomeado como **QEMU HARDDISK Media** ou de tamanho **137,44 GB**).
    *   Clique em **Apagar** (Erase) no menu superior e preencha:
        *   **Nome:** `Macintosh HD`
        *   **Formato:** **APFS**
        *   **Esquema:** **Mapa de Partição GUID**
    *   Clique em Apagar. O processo leva 1 segundo. Feche o Utilitário de Disco.
3.  **Instalar o macOS:**
    *   Selecione **"Reinstalar o macOS Ventura"**, aceite os termos, selecione a partição `Macintosh HD` que você acabou de criar e clique em Instalar.
    *   A máquina virtual irá reiniciar sozinha algumas vezes. Isso é normal! Apenas aguarde ela terminar toda a configuração até exibir o Assistente de Configuração do Usuário do macOS.

---

## 🌟 Salvando o seu Snapshot e Uso Diário

### Ativando a SSH no macOS (Muito Importante!)
Assim que terminar de criar o seu usuário no macOS e estiver na área de trabalho:
1.  Vá em **Ajustes do Sistema** (System Settings) -> **Geral** (General) -> **Compartilhamento** (Sharing).
2.  Ative a opção **Sessão Remota** (Remote Login) / SSH.
3.  Desligue a máquina virtual pelo menu Maçã -> Desligar (Shut Down).

### Captura do Snapshot
Como você utilizou o parâmetro `--capture`, o script de boot detectará que a máquina foi desligada corretamente após a instalação e salvará todo o estado do seu sistema em um **Snapshot imutável de recuperação** sob `vm/disks/rails/macos-13/snapshots/`. 

### Executando no Dia a Dia com Aceleração Total
A partir de agora, você não precisa mais da flag de captura ou de instalação. Para abrir o seu macOS com aceleração gráfica total e renderização de altíssimo desempenho, use:

```bash
./vm/boot-x86.sh --interactive
```

Qualquer modificação temporária ou travamento que aconteça na VM será descartado automaticamente ao fechar o QEMU, garantindo que o seu sistema permaneça com 100% de integridade e velocidade sempre!

---

## 🐞 Solução de Problemas comuns

### 1. `KVM not available (/dev/kvm)`
O seu usuário do Linux precisa de permissões para acessar os recursos de aceleração de hardware KVM:
```bash
sudo usermod -aG kvm $USER
```
*(Reinicie o seu computador ou refaça o login para que a alteração tenha efeito).*

### 2. `llvm-dis` ou `spirv-val` não encontrados no PATH
O Reims vGPU precisa dessas ferramentas para decodificar e validar os Shaders gráficos traduzidos.
*   No Arch: `sudo pacman -S llvm spirv-tools`
*   No Ubuntu: `sudo apt install llvm spirv-tools`

### 3. Falha de compilação da ROM UEFI (`core` crate missing)
Você está usando o compilador `rust` nativo da distribuição que não possui suporte a builds UEFI. Siga a seção de requisitos acima e mude para o **`rustup`**, adicionando o target `x86_64-unknown-uefi`.

---

## 🤝 Agradecimentos e Créditos

Este projeto é uma consolidação de esforços e inovações de desenvolvedores e comunidades incríveis da cena de virtualização e Hackintosh. Gostaríamos de prestar os devidos agradecimentos e créditos aos projetos originais sem os quais este trabalho não seria possível:

1.  **[reims-vgpu](https://github.com/steelbrain/reims-vgpu) (por Anees Iqbal / @steelbrain):**
    O coração deste ecossistema. É o projeto de código aberto em Rust que desenvolve a tecnologia inovadora de paravirtualização de GPU (vGPU) para o macOS sob QEMU/KVM, traduzindo chamadas Metal para Vulkan. Nossa eterna admiração e agradecimento ao seu criador por seu trabalho técnico genial e espírito open-source.

2.  **[metal2vulkan](https://github.com/steelbrain/metal2vulkan) (por Anees Iqbal / @steelbrain):**
    A espetacular biblioteca responsável pela tradução estática e dinâmica de instruções gráficas e Shaders Metal do macOS diretamente em instruções Vulkan/SPIR-V interpretáveis por placas de vídeo modernas no Linux.

3.  **[OSX-KVM](https://github.com/kholia/OSX-KVM) (por Dhiru Kholia / @kholia):**
    O projeto pioneiro que tornou a virtualização do macOS viável, de alto desempenho e acessível no ecossistema KVM/QEMU do Linux. Usamos seus scripts excelentes para download da mídia oficial de recuperação da Apple, estrutura do bootloader OpenCore e os firmwares UEFI/OVMF.

4.  **[KVM-Opencore](https://github.com/thenickdude/KVM-Opencore) (por @thenickdude e @Leoyzen):**
    O trabalho genial e incansável de customizar e portar o OpenCore Bootloader de forma que ele consiga se comunicar com as especificidades do QEMU/KVM de forma idêntica a um firmware de Mac real, permitindo inicializar versões modernas do macOS.

5.  **[OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) (por Acidanthera / vit9696):**
    O bootloader de código aberto mais avançado e completo do mundo, essencial para inicializar o sistema operacional e injetar os patches e kexts necessários para o macOS rodar de forma idêntica a um Mac real.

6.  **Comunidade Hackintosh e Virtualização (Universo Hackintosh & Gabriel Luchina):**
    Aos criadores de conteúdo, moderadores e entusiastas brasileiros que testam, depuram e traduzem conceitos técnicos de altíssima complexidade em materiais simples, acessíveis e automatizados para toda a comunidade.
