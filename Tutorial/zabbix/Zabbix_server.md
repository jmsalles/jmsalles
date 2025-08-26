# **Guia Completo — Monitoramento com Zabbix + Grafana (VM Rocky 10 | modo texto)**

**Host padrão:** `vm-lenovoi7-zabbix`  
**IP fixo:** `192.168.31.35/24` — **Gateway:** `192.168.31.2`  
**Instalação:** sempre **modo texto** (text-mode)  
**SELinux:** **desabilitado** (permanente + kernel)  
**Discos de dados na VM:** `/dev/sdb` (Postgres) • `/dev/sdc` (Grafana)  
**Containers:** Podman (Netavark) — opção Quadlet documentada  
**Stack:** PostgreSQL 16 • Zabbix Server • Zabbix Web • Grafana  
**Grafana:** após o 1º login a troca de senha é **obrigatória** — *foi definida como* **“4796@@Eumesmo 1234567”**

---

## 1) Hypervisor (KVM/libvirt) — LVM + instalação da VM (modo texto)

### 1.1 LVs para a VM
```bash
sudo lvcreate -L 60G  -n lv_vm_lenovoi7_zbx_os   vg_vms
sudo lvcreate -L 120G -n lv_vm_lenovoi7_zbx_pg   vg_vms
sudo lvcreate -L 20G  -n lv_vm_lenovoi7_zbx_graf vg_vms
```

### 1.2 Libvirt “system”, bridge e OVMF
```bash
echo 'allow br0' | sudo tee /etc/qemu/bridge.conf
sudo systemctl restart libvirtd
export LIBVIRT_DEFAULT_URI=qemu:///system
sudo dnf -y install edk2-ovmf
```

### 1.3 Criar VM em **modo texto** (UEFI, virtio-scsi, `--location`)
```bash
sudo virt-install --connect qemu:///system \
  --name vm-lenovoi7-zabbix \
  --virt-type kvm \
  --vcpus 4 \
  --cpu host-passthrough,cache.mode=passthrough \
  --memory 8192 \
  --osinfo detect=on,name=linux2024 \
  --iothreads 2 \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/dev/vg_vms/lv_vm_lenovoi7_zbx_os,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --disk path=/dev/vg_vms/lv_vm_lenovoi7_zbx_pg,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --disk path=/dev/vg_vms/lv_vm_lenovoi7_zbx_graf,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --network bridge=br0,model=virtio \
  --graphics none \
  --location /var/lib/libvirt/images/iso/Rocky-10.0-x86_64-minimal.iso \
  --extra-args 'inst.text console=ttyS0,115200n8' \
  --boot uefi
```
> Durante a instalação **não particionar/montar** `sdb` e `sdc`.  
> Console: `sudo virsh console vm-lenovoi7-zabbix` (sair: `Ctrl+]`).

---

## 2) Pós-instalação (Rocky 10)

### 2.0 Pacotes essenciais (inclui **vim** e **autocomplete**)
```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --set-enabled crb
sudo dnf -y install vim-enhanced bash-completion git curl wget tar unzip \
  bind-utils net-tools lvm2 xfsprogs

# garantir autocomplete no bash
if [ -f /etc/profile.d/bash_completion.sh ]; then
  echo 'source /etc/profile.d/bash_completion.sh' | tee -a ~/.bashrc
fi
source ~/.bashrc
```

### 2.1 Identidade e horário
```bash
sudo hostnamectl set-hostname vm-lenovoi7-zabbix
sudo dnf -y update
sudo timedatectl set-timezone America/Sao_Paulo
sudo systemctl enable --now chronyd
```

### 2.2 IP fixo (sem derrubar sessão)
```bash
nmcli device status
sudo nmcli con mod "System ens3" ipv4.method manual \
  ipv4.addresses 192.168.31.35/24 ipv4.gateway 192.168.31.2 \
  ipv4.dns "1.1.1.1 8.8.8.8"
sudo nmcli con up "System ens3"
```

### 2.3 **Desabilitar SELinux** (runtime + permanente + kernel) e reboot
```bash
sudo dnf -y install policycoreutils libselinux-utils grubby
sudo setenforce 0 || true
sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
sudo grubby --update-kernel=ALL --args="selinux=0 enforcing=0"
grep ^SELINUX= /etc/selinux/config && cat /proc/cmdline
sudo reboot
```
Após voltar:
```bash
getenforce
sestatus || true
```

---

## 3) LVM na VM (dados em **/dev/sdb** e **/dev/sdc**)

```bash
sudo pvcreate /dev/sdb /dev/sdc
sudo vgcreate vg_zbx /dev/sdb /dev/sdc
sudo lvcreate -n lv_pg -L 120G vg_zbx
sudo lvcreate -n lv_grafana -L 20G vg_zbx

sudo mkfs.xfs /dev/vg_zbx/lv_pg
sudo mkfs.xfs /dev/vg_zbx/lv_grafana
sudo mkdir -p /srv/postgres /srv/grafana
sudo blkid
sudo vim /etc/fstab
```
Entradas (trocar pelos **UUIDs**):
```
UUID=<UUID_lv_pg>    /srv/postgres xfs defaults,noatime 0 2
UUID=<UUID_lv_graf>  /srv/grafana  xfs defaults,noatime 0 2
```
Montar:
```bash
sudo systemctl daemon-reload
sudo mount -a && df -h
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

---

## 4) Podman + Netavark + diretórios
```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --set-enabled crb
sudo dnf -y install podman netavark aardvark-dns fuse-overlayfs slirp4netns
podman --version

sudo mkdir -p /etc/containers/systemd
sudo mkdir -p /etc/zabbix /var/log/zabbix
sudo mkdir -p /srv/postgres /srv/grafana

# variáveis do banco (senha atualizada)
sudo tee /etc/zabbix/db.env >/dev/null <<'EOF'
POSTGRES_USER=zabbix
POSTGRES_PASSWORD=4796@@Eumesmo1234567
POSTGRES_DB=zabbix
EOF
```

---

## 5) (Opcional) Quadlet `.network`
```bash
sudo tee /etc/containers/systemd/zbxnet.network >/dev/null <<'EOF'
[Unit]
Description=Podman network zbxnet
[Network]
NetworkName=zbxnet
Driver=bridge
EOF
sudo systemctl daemon-reload
sudo systemctl start zbxnet-network.service
```

---

## 6) Serviços — Zabbix & Grafana

### 6B — **Recomendado**: `podman run` + `systemd generate`
```bash
# rede (se já existir, ok)
sudo podman network create zbxnet || true

# PostgreSQL
sudo podman run -d --name pg-zbx --network zbxnet \
  -p 127.0.0.1:5432:5432 \
  --env-file /etc/zabbix/db.env -e TZ=America/Sao_Paulo \
  -v /srv/postgres:/var/lib/postgresql/data \
  postgres:16

# Zabbix Server
sudo mkdir -p /var/log/zabbix
sudo podman run -d --name zbx-server --network zbxnet \
  -p 10051:10051 \
  -e DB_SERVER_HOST=pg-zbx \
  --env-file /etc/zabbix/db.env \
  -e TZ=America_Sao_Paulo \
  -v /var/log/zabbix:/var/log/zabbix \
  zabbix/zabbix-server-pgsql:alpine-latest

# (se necessário) inicializar schema e reiniciar
sudo podman run --rm --network zbxnet \
  --env-file /etc/zabbix/db.env \
  zabbix/zabbix-server-pgsql:alpine-latest \
  sh -lc 'zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | psql -h pg-zbx -U "$POSTGRES_USER" "$POSTGRES_DB"'
sudo podman restart zbx-server

# Zabbix Web (apontando para o server, evita localhost:10051)
sudo podman run -d --name zbx-web --network zbxnet \
  -p 80:8080 \
  -e DB_SERVER_HOST=pg-zbx \
  --env-file /etc/zabbix/db.env \
  -e PHP_TZ=America/Sao_Paulo \
  -e ZBX_SERVER_HOST=zbx-server \
  -e ZBX_SERVER_PORT=10051 \
  -e ZBX_SERVER_NAME="Zabbix vm-lenovoi7-zabbix" \
  zabbix/zabbix-web-nginx-pgsql:alpine-latest

# Grafana (permite escrita como UID 472)
sudo mkdir -p /srv/grafana && sudo chown -R 472:472 /srv/grafana && sudo chmod 775 /srv/grafana
sudo podman run -d --name grafana --network zbxnet \
  -p 3000:3000 \
  -e GF_INSTALL_PLUGINS=alexanderzobnin-zabbix-app \
  -e TZ=America_Sao_Paulo \
  -v /srv/grafana:/var/lib/grafana \
  --user 472:472 \
  grafana/grafana:latest
```

**Persistência no boot (um por vez):**
```bash
sudo podman generate systemd --files --new --name pg-zbx
sudo podman generate systemd --files --new --name zbx-server
sudo podman generate systemd --files --new --name zbx-web
sudo podman generate systemd --files --new --name grafana
sudo mv container-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now container-pg-zbx.service container-zbx-server.service container-zbx-web.service container-grafana.service
```

---

## 7) Firewall & Acesso
```bash
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-port=3000/tcp --permanent
sudo firewall-cmd --add-port=10051/tcp --permanent
sudo firewall-cmd --reload
```
- **Zabbix Web:** `http://192.168.31.35/` (Admin/zabbix → trocar)  
- **Grafana:** `http://192.168.31.35:3000/` (admin/admin → **troca obrigatória**; já foi definida como “4796@@Eumesmo 1234567”)

---

## 8) Backup (dump diário)
```bash
sudo mkdir -p /backup/zabbix
sudo crontab -e
```
Adicionar:
```
0 2 * * * podman exec pg-zbx pg_dump -U zabbix -d zabbix | gzip > /backup/zabbix/zbx-$(date +\%F).sql.gz
```
> *Item 9.2 (snapshot LVM) removido.*

---

## 9) Agente Zabbix **nativo** (sem container)

**Repositório para EL10 (Alma 10 — compatível com Rocky 10)**  
- **LTS 7.0:**
```bash
sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/10/x86_64/zabbix-release-7.0-7.el10.noarch.rpm
```
- **Atual 7.4:**
```bash
sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.4/release/alma/10/noarch/zabbix-release-latest-7.4.el10.noarch.rpm
```
Depois:
```bash
sudo dnf clean all && sudo dnf makecache
sudo dnf -y install zabbix-agent2
```
Configurar e iniciar:
```bash
sudo sed -i \
  -e 's/^Server=.*/Server=192.168.31.35/' \
  -e 's/^ServerActive=.*/ServerActive=192.168.31.35/' \
  -e 's/^Hostname=.*/Hostname=vm-lenovoi7-zabbix/' \
  /etc/zabbix/zabbix_agent2.conf

sudo firewall-cmd --add-port=10050/tcp --permanent
sudo firewall-cmd --reload
sudo systemctl enable --now zabbix-agent2
```

Cadastrar no Zabbix (GUI):
- **Configuration → Hosts → Create host**
- Host name: `vm-lenovoi7-zabbix`
- Interface Agent: `192.168.31.35:10050`
- Template: `Linux by Zabbix agent`

---

## 10) Checklist rápido
```bash
hostnamectl && ip a
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT && df -h && vgs && lvs
podman ps
systemctl --type=service | egrep 'container-(pg-zbx|zbx-server|zbx-web|grafana)'
```

---

## 11) Troubleshooting rápido
- **Dashboard “localhost:10051 refused”** → recriar `zbx-web` com `ZBX_SERVER_HOST=zbx-server`.
- **“Database error” no Zabbix Web** → criar schema e reiniciar `zbx-server`/`zbx-web`.
- **Grafana cai (Exit 1)** → `chown -R 472:472 /srv/grafana && chmod 775 /srv/grafana` e recriar/`restart`.
- **Agente não instala (repo)** → usar RPMs “alma/10” acima.

---

_© Template Lenovo i7 — `vm-lenovoi7-zabbix` — revisão: agora._


---

## 13) Criar hosts pela **interface web** (Zabbix 7.x)

> Você estava em **Inventário → Inventário do host** — ali não cria host.  
> No Zabbix 7.x, a criação fica em **Dados coletados**.

### Passo a passo
1. No menu lateral, clique em **Dados coletados** → **Hosts**.  
   (Atalho: `http://192.168.31.35/zabbix.php?action=host.list`)
2. Clique em **Criar host** (canto superior direito).  
   (Atalho direto: `http://192.168.31.35/zabbix.php?action=host.edit`)
3. Preencha:
   - **Nome do host:** `vm-lenovoi7-zabbix` *(deve bater com `Hostname=` do agent2)*
   - **Grupo(s):** escolha um (ex.: *Linux servers*) ou crie um novo
   - **Interfaces → Adicionar → Agent:**
     - **IP:** `192.168.31.35`
     - **Porta:** `10050`
     - **Conectar a:** **IP**
     - (Deixe “Monitored by proxy” desmarcado)
   - **Templates → Selecionar:** `Linux by Zabbix agent`  
     > Se preferir somente checagens *ativas*, use `Linux by Zabbix agent active`.
4. **Salvar**. Em ~1–2 minutos a disponibilidade deve ficar **verde**.

### Verificações rápidas
```bash
# No host Rocky (agente)
sudo systemctl status zabbix-agent2 --no-pager
ss -lntp | grep 10050 || true

# Do container do servidor, testar porta
sudo podman exec -it zbx-server sh -lc 'nc -zv 192.168.31.35 10050 || true'
```

### SNMP / dispositivos de rede
- Em **Interfaces**, adicione **SNMP** com o IP do equipamento (porta 161).  
- Em **Templates**, associe por exemplo `Template Net SNMP` (ou templates específicos do fabricante).  
- Configure a *community* SNMP v2 ou usuário/credenciais SNMP v3 conforme seu ambiente.

