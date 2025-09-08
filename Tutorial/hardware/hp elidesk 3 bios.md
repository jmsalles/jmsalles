
Perfeito, Jeferson 👌
Vou montar um **guia completo em Markdown** no seu template (formato guia, com explicações + comandos em blocos `bash` onde couber), cobrindo **todas as telas da BIOS do HP EliteDesk 800 G3 i7** que você me mandou.

---

# 🖥️ Guia de Configuração da BIOS – HP EliteDesk 800 G3 i7

## 📌 Resumo

Este guia documenta todas as opções relevantes da BIOS do **HP EliteDesk 800 G3 i7**, explicando a função de cada configuração e recomendando os melhores ajustes para uso em **laboratório de virtualização (VMs, containers, Proxmox/KVM/VMware)**.

---

## 📑 Sumário

* [Opções do Sistema](#opções-do-sistema)
* [Dispositivos Incorporados](#dispositivos-incorporados)
* [Portas USB e SATA](#portas-usb-e-sata)
* [Gestão de Energia](#gestão-de-energia)
* [Intel AMT / ME](#intel-amt--me)
* [Checklist Final](#checklist-final)

---

## ⚙️ Opções do Sistema

Tela: **Avançado → Opções do Sistema**

| Opção                                             | Função                                                    | Recomendado                                      |
| ------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------ |
| **Configure Storage Controller for Intel Optane** | Ativa suporte a **Intel Optane Memory** (cache de disco). | ❌ Desativar (você já usa SSD NVMe, não precisa). |
| **Turbo-Boost**                                   | Aumenta frequência da CPU em cargas pesadas.              | ✅ Ativar                                         |
| **Hyperthreading**                                | Ativa threads lógicas extras da CPU.                      | ✅ Ativar                                         |
| **Multi-processor**                               | Usa todos os núcleos disponíveis.                         | ✅ Ativar                                         |
| **Virtualization Technology (VT-x)**              | Habilita virtualização Intel.                             | ✅ Ativar                                         |
| **Virtualization for Directed I/O (VT-d)**        | Suporte a passthrough de dispositivos PCI/USB.            | ✅ Ativar                                         |
| **M.2 SSD**                                       | Suporte a discos NVMe M.2.                                | ✅ Ativar                                         |
| **M.2 WLAN/BT**                                   | Suporte ao módulo Wi-Fi/Bluetooth.                        | Opcional                                         |
| **Permitir interrupção PCIe/PCI SERR#**           | Controle de interrupções PCIe.                            | ✅ Ativar (seguro).                               |

---

## 🔌 Dispositivos Incorporados

Tela: **Avançado → Embedded Device Options**

| Opção                                | Função                            | Recomendado                              |
| ------------------------------------ | --------------------------------- | ---------------------------------------- |
| **Controlador LAN incorporado**      | Placa de rede onboard.            | ✅ Ativar                                 |
| **Reativação por LAN (Wake on LAN)** | Permite ligar o PC remotamente.   | Opcional                                 |
| **Tamanho da memória de vídeo**      | RAM reservada para GPU integrada. | 32 MB (para lab é suficiente).           |
| **Dispositivo de áudio**             | Ativa/desativa o áudio onboard.   | ✅ Ativar (ou ❌ se não usar).             |
| **Alto-falantes internos**           | Habilita speaker interno.         | Opcional                                 |
| **Velocidade mínima da ventoinha**   | Define fan mínima em idle.        | 50% (pode ajustar conforme temperatura). |
| **M.2 USB / Bluetooth**              | Suporte a módulo combo.           | Opcional                                 |

---

## 🔌 Portas USB e SATA

Tela: **Avançado → Portas**

| Opção                             | Função                                           | Recomendado        |
| --------------------------------- | ------------------------------------------------ | ------------------ |
| **SATA1**                         | Ativa porta SATA principal.                      | ✅ Ativar           |
| **USB Frontais / Traseiras**      | Ativa/desativa cada porta física.                | ✅ Ativar todas     |
| **Carregamento via USB/USB-C**    | Permite carregar celular/tablet mesmo desligado. | Opcional           |
| **Restrição de dispositivos USB** | Limita uso de USB.                               | **Permitir todos** |
| **Firmware USB Type-C**           | Permite atualização do controlador USB-C.        | ✅ Ativar           |

---

## ⚡ Gestão de Energia

Tela: **Avançado → Power Management**

| Opção                                       | Função                                  | Recomendado                         |
| ------------------------------------------- | --------------------------------------- | ----------------------------------- |
| **Gerenciamento de Energia em Execução**    | Economia de energia mesmo em uso.       | ✅ Ativar                            |
| **Estados de energia em espera expandidos** | C-states profundos da CPU.              | ❌ Desativar (priorizar desempenho). |
| **Economia Máxima de Energia S5**           | Reduz consumo em estado desligado (S5). | ✅ Ativar (se não usar Wake on LAN). |
| **Gestão de energia SATA**                  | Desliga discos SATA inativos.           | ✅ Ativar                            |
| **Gestão de energia PCIe**                  | ASPM (economia PCIe).                   | ❌ Desativar (melhor latência).      |
| **Ligar através do teclado**                | Power-on via teclado.                   | Opcional                            |
| **LEDs em suspensão**                       | Ajusta piscada de LED em sleep.         | Opcional                            |

---

## 🖧 Intel AMT / ME

Tela: **Avançado → AMT/ME Configuration**

| Opção                       | Função                                 | Recomendado                                   |
| --------------------------- | -------------------------------------- | --------------------------------------------- |
| **Active Management (AMT)** | Intel vPro/AMT (gerenciamento remoto). | ❌ Desativar (se não usar em lab corporativo). |
| **USB Key Provisioning**    | Provisionar AMT via pen drive.         | ❌ Desativar                                   |
| **USB Redirection Support** | Redirecionar dispositivos USB via AMT. | ❌ Desativar                                   |
| **Unconfigure AMT**         | Reseta config AMT.                     | "Do Not Apply"                                |
| **SOL Terminal Mode**       | Padrão de emulação serial.             | ANSI                                          |
| **Show Unconfigure Prompt** | Confirma antes de resetar AMT.         | ✅ Ativar                                      |
| **Verbose Boot Messages**   | Mostra logs extras do ME.              | ❌ Desativar                                   |
| **Watchdog Timer**          | Reinicia se travar.                    | ❌ Desativar (opcional se quiser auto-reboot). |
| **CIRA Timeout**            | Timeout de conexão remota.             | Sem impacto (se AMT off).                     |

---

## ✅ Checklist Final

Para o **HP EliteDesk 800 G3 i7 (32 GB RAM, SSD/NVMe, lab de virtualização)**:

* [x] **Turbo Boost, Hyperthreading, Multi-core** → Ativos
* [x] **VT-x + VT-d** → Ativos (virtualização completa)
* [x] **LAN onboard** → Ativa
* [x] **Áudio** → Ativo (ou off se não usar)
* [x] **USB/SATA** → Todas portas ativas, restrição = "Permitir todos"
* [x] **Gestão energia** → PCIe ASPM OFF, C-States profundos OFF, SATA PM ON
* [x] **AMT/ME** → Desativado (a não ser que vá usar vPro)

---

## 📚 Referências rápidas

Checar virtualização no Linux:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
```

Checar no Windows:

```bash
systeminfo | find "Virtualization"
```

---

✍️
Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)

---

