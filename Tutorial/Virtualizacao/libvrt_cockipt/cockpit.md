# 🖥️ Guia completo do **Cockpit** (somente Cockpit) — administração visual do seu host de virtualização

> Este tutorial cobre **apenas o Cockpit**: instalação, módulos oficiais, plugins úteis, configuração via **interface web**, ajustes de desempenho e manutenção — tudo feito **dentro** do Cockpit. Serve para Rocky/EL 10, mas vale para distros RHEL-like em geral.

---

## 🧩 O que é o Cockpit?

* **Painel web** para administrar seu servidor: hardware, serviços, **máquinas virtuais**, rede, storage, usuários, atualizações e desempenho.
* Acessível por navegador: `https://<IP_DO_HOST>:9090`.
* Usa **usuários do sistema** (mesmas permissões do Linux). Para gerenciar VMs, coloque seu usuário no grupo `libvirt`.

---

## 🚀 Instalação rápida (pacotes oficiais)

```bash
dnf -y install \
  cockpit cockpit-machines cockpit-storaged cockpit-networkmanager \
  cockpit-packagekit cockpit-pcp cockpit-tuned cockpit-sosreport

  Instalar o PCP (back-end de métricas) e autoconfig:

sudo dnf -y install pcp pcp-zeroconf


Ativar os serviços do PCP:

sudo systemctl enable --now pmcd pmlogger pmproxy

systemctl enable --now cockpit.socket         # inicia o servidor web
# (opcional) abrir a porta no firewall
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload

# (recomendado) ativar módulos de desempenho e tuning
systemctl enable --now pmcd pmlogger || true  # PCP (gráficos e histórico)
systemctl enable --now tuned || true
```

Entrar: `https://<IP_DO_HOST>:9090` (use um usuário local; se for gerenciar VMs, adicione ao grupo `libvirt` e faça logout/login: `usermod -aG libvirt <seu_usuario>`).

---

## 🔐 HTTPS/TLS no Cockpit (certificado próprio)

1. Tenha um **certificado válido** (por ex. Let’s Encrypt).
2. Instale no Cockpit:

```bash
mkdir -p /etc/cockpit/ws-certs.d
cat /caminho/fullchain.pem /caminho/privkey.pem > /etc/cockpit/ws-certs.d/0-seu-dominio.pem
systemctl restart cockpit
```

Dica: restrinja o acesso via **firewalld** à zona da sua LAN ou exponha apenas via **VPN**.

---

## 🧭 Tour pela interface (onde clicar)

### 🏠 **Visão geral (Dashboard)**

* **Uso de CPU/RAM/Disco**, temperatura, **sessões** e **serviços**.
* Acesso rápido ao **Terminal** embutido (shell no navegador).

### 🖥️ **Máquinas Virtuais** (módulo *cockpit-machines*)

* Criar/editar VMs, ligar/desligar, abrir console **no navegador** (VNC/SPICE).
* Selecionar **CPU model** (*host-passthrough*), **RAM**, **disco** e **rede**.
* **Armazenamento**: gerencia *pools* e *volumes* (inclui LVM, diretórios, etc).
* **Rede**: selecione a **bridge** (ex.: `br0`) para IP real da LAN.

### 🌐 **Rede** (módulo *cockpit-networkmanager*)

* Criar/editar **bridges** (ex.: `br0`), **VLANs**, IP **DHCP** ou **estático**.
* Ver e reiniciar conexões, ajustar **MTU**, DNS e rotas.

### 💽 **Armazenamento** (módulo *cockpit-storaged*)

* Visual de discos, **partições**, **LVM** (PV/VG/LV), S.M.A.R.T., **RAID**/iSCSI/NFS.
* Rodar **auto-testes S.M.A.R.T.**, ver alertas, criar volumes.

### 🔄 **Atualizações** (módulo *cockpit-packagekit*)

* Aplicar updates do sistema com 1 clique, ver histórico.

### ⚡ **Desempenho** (módulo *cockpit-pcp*)

* Gráficos de **CPU**, **memória**, **disco** (I/O), **rede** (tx/rx) em tempo real e histórico.
* Útil para detectar gargalos de VM/host sem sair do navegador.

### 🧪 **Ajustes (tuned)** (módulo *cockpit-tuned*)

* Trocar perfil de energia/desempenho. Para host de virtualização use **virtual-host**.

### 📜 **Logs** e **Relatórios**

* *Jornal* (journald) com filtros, busca por serviço.
* *sosreport* para coletar diagnóstico completo em um arquivo.

---

## 🛠️ Fluxos comuns 100% pelo Cockpit

### 🌉 Criar/ajustar **bridge** (ex.: `br0`)

1. **Rede →** *Adicionar ligação* → **Bridge** → Nome: `br0`.
2. **Adicionar porta**: escolha a interface física (ex.: `enp0s31f6`).
3. IPv4: **Automático (DHCP)** ou **Manual** (IP/Gateway/DNS).
4. **Aplicar**. A `br0` passa a ter o IP; a física vira “escrava” da bridge.

### 💽 Registrar **pool de armazenamento** para VMs

1. **Máquinas Virtuais → Armazenamento → Adicionar pool**.
2. Tipo: **LVM** (se usar VG de VMs).

   * **Nome**: `vms`
   * **Grupo de Volumes**: `vg_vms`
   * **Target**: `/dev/vg_vms`
3. **Criar** e marcar **Iniciar automaticamente**.

> Criou um LV pela linha de comando? Clique **Atualizar** no pool para aparecer na lista.

### 🧰 Criar uma **VM** (GUI)

1. **Máquinas Virtuais → Criar**.
2. Fonte: **Arquivo ISO** (upload ou caminho local) **ou** URL.
3. Configure **CPU** (*host-passthrough* quando disponível), **vCPUs** (topologia coerente), **RAM**.
4. Selecione **Disco** no **pool** (ex.: `vms`), tamanho/volume.
5. **Rede**: escolha **Bridge** = `br0`, **Modelo** = *virtio*.
6. **Criar** e acompanhe a instalação no **console web**.

### 🔧 Editar **opções avançadas** da VM

* Em **Máquinas Virtuais**, clique na VM → **Editar** → ajuste CPU/NUMA, disco, rede.
* Para tunings não expostos na UI, use **Ver XML** (botão na página da VM) e aplique:

  * **Hugepages**:

    ```xml
    <memoryBacking><hugepages/></memoryBacking>
    ```
  * **I/O paralelo** (exemplo para VirtIO-SCSI):

    ```xml
    <iothreads>2</iothreads>
    <devices>
      <controller type='scsi' model='virtio-scsi'>
        <driver queues='4'/>
      </controller>
      <disk ...>
        <driver name='qemu' type='raw' cache='none' io='native' iothread='1' discard='unmap'/>
      </disk>
    </devices>
    ```

> As alterações em XML aparecem **imediatamente** no Cockpit e são persistentes.

---

## ⚙️ Otimizações de desempenho — **pelo Cockpit**

### 🔧 *tuned* (perfil do host)

* **Ajustes → Tuned →** selecione **virtual-host**.

### 📈 Desempenho (PCP)

* Certifique-se que **PCP** está *Ativo* (em *Resumo* ou *Desempenho*).
* Defina **retenção** e **coleta** conforme necessidade (pelo próprio módulo).

### 💽 Saúde do disco (storaged)

* Rode **S.M.A.R.T. short/long test** no SSD.
* Acompanhe **tempos de resposta** e **setores remapeados**.

### 🌐 Rede

* Em **Rede**, verifique **MTU**, duplex e **estatísticas** da `br0`.
* Em **VM → Console/terminal do guest**, ajuste **multiqueue** (quando aplicável).

---

## 🧰 Plugins úteis (Cockpit **apenas**)

> Estes ampliam o Cockpit **sem sair da UI**. Quando não houver RPM para EL10, use a instalação genérica indicada pelos projetos.

### 📁 **Arquivos** (*cockpit-files*) — gerenciador de arquivos web

```bash
dnf -y install nodejs npm make gettext cockpit-bridge
git clone https://github.com/cockpit-project/cockpit-files.git
cd cockpit-files
make && make install
```

* Surge no menu como **Files/Arquivos** (upload, mover, editar, permissões).

### 📤 **Compartilhamentos** (*cockpit-file-sharing*) — SMB/NFS pela UI

```bash
dnf -y install cockpit-bridge coreutils attr findutils hostname iproute \
           glibc-common systemd nfs-utils samba samba-common-tools make
git clone https://github.com/45Drives/cockpit-file-sharing.git
cd cockpit-file-sharing
make && make install
systemctl enable --now smb
firewall-cmd --add-service=samba --permanent; firewall-cmd --reload
```

* Gerencie shares **SMB/NFS** em **File Sharing** no Cockpit.

### 👥 **Identidades** (*cockpit-identities*) — usuários/grupos/senha Samba

```bash
cd /tmp
curl -LO https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12_generic.zip
unzip cockpit-identities_0.1.12_generic.zip
cd cockpit-identities_0.1.12_generic
make install
```

* Aparece como **Identidades/Identities** no menu.
* Crie usuários/grupos e defina **senha Samba** (usa `smbpasswd` por baixo).

> **Remoção** de plugins (se precisar):
> `rm -rf /usr/local/share/cockpit/cockpit-files /usr/local/share/cockpit/cockpit-file-sharing /usr/local/share/cockpit/cockpit-identities`

---

## 🔍 Monitoramento e manutenção — dentro do Cockpit

* **Resumo/Desempenho (PCP)**: CPU, memória, **I/O de disco**, rede; veja tendências e picos.
* **Logs**: *Jornal* com filtro por serviço (ex.: `libvirtd`, `cockpit`, `sshd`).
* **Serviços**: iniciar/parar/reiniciar, **habilitar no boot**, ver dependências.
* **Atualizações**: aplicar patches agendando sua janela de manutenção.
* **Relatórios**: *sosreport* para suporte (gera um tarball com diagnóstico).

---

## ✅ Checklists (só Cockpit)

**Criar VM nova (GUI)**

1. **Armazenamento →** confirme o pool (ex.: `vms`) e espaço livre.
2. **Máquinas Virtuais → Criar** → selecione **ISO** e **pool**.
3. CPU: **host-passthrough**, topologia correta; RAM conforme carga.
4. Rede: **Bridge** = `br0`, **Modelo** = *virtio*.
5. Instale o SO pelo **console web**.
6. Depois, em **Editar** → ajuste **disco** (VirtIO-SCSI, `cache=none`), redes, etc.

**Publicar pasta por SMB (GUI)**

1. **Identities**: crie usuário e **senha Samba**.
2. **File Sharing**: adicione **Share** (path, permissões, ACL).
3. Teste acesso a `\\<IP_DO_HOST>\<share>`.

**Saúde do host**

1. **Desempenho**: confira gráficos e latência de I/O.
2. **Armazenamento**: S.M.A.R.T. e uso de LVM.
3. **Atualizações**: mantenha o sistema em dia.

---

## 🧯 Troubleshooting (focado no Cockpit)

* **Sem acesso à UI**: verifique se `cockpit.socket` está *Ativo* na página de **Serviços** ou rode `systemctl status cockpit` no **Terminal** do Cockpit.
* **Certificado inválido**: instale em `/etc/cockpit/ws-certs.d/` e reinicie o Cockpit.
* **“Máquinas Virtuais” vazio**: confirme que o serviço **libvirtd** está *Ativo* em **Serviços** e que seu usuário pertence a `libvirt`.
* **Pool/volume não aparece**: em **Armazenamento → pool** clique **Atualizar** (ou reabra a página).
* **Bridge sem IP**: ajuste **Rede → br0** para **DHCP** ou configure IP estático corretamente (Gateway/DNS).
* **Console da VM não abre**: verifique se a VM tem vídeo VNC/SPICE habilitado ou use **Console** textual se o guest suportar.

---

### 🎯 Conclusão

Com o **Cockpit** e os módulos/plugins acima, você administra **tudo** do seu host de virtualização **pelo navegador**: rede (bridge), storage (LVM), **VMs**, desempenho (PCP), atualizações e até **compartilhamentos** e **usuários** — sem sair da UI.
Se quiser, te monto um **script único** que instala e habilita todos os módulos/plugins de Cockpit e aplica as configurações básicas de forma automatizada.
