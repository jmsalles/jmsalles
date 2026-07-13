# Tutorial — Instalar Proxmox VE no Dell, Ingressar no Cluster e Configurar NFS Auxiliar

## 1. Objetivo

Instalar o **Proxmox VE** no Dell, adicionar o host ao cluster existente e configurar o Dell como **nó Proxmox + NFS auxiliar**.

```bash
Host: pve-dell
IP: 192.168.31.13
Cluster: proxmox-homelab
Função: Nó Proxmox + NFS auxiliar
```

---

## 2. Arquitetura

```bash
Cluster Proxmox VE: proxmox-homelab

├── pve-dell-novo       192.168.31.11
├── pve-lenovo-prova    192.168.31.12
└── pve-dell            192.168.31.13
```

Storage NFS no Dell:

```bash
/srv/nfs/proxmox
├── iso
├── templates
├── backup-temp
└── lab
```

---

## 3. Premissas

```bash
Rede: 192.168.31.0/24
Gateway: 192.168.31.2
DNS/AD: 192.168.31.24
Domínio: jmsalles.homelab.br
Cluster existente: proxmox-homelab
Nó principal atual: pve-dell-novo - 192.168.31.11
Novo nó: pve-dell - 192.168.31.13
Pendrive: Ventoy
```

---

# 4. Instalar Proxmox VE no Dell

## 4.1 Boot via Ventoy

No Dell:

```bash
Boot pelo pendrive Ventoy
Selecionar ISO do Proxmox VE
Selecionar Install Proxmox VE
```

## 4.2 Configuração da instalação

Durante a instalação:

```bash
Filesystem: ext4
Hostname: pve-dell.jmsalles.homelab.br
IP Address: 192.168.31.13
Netmask: 255.255.255.0
Gateway: 192.168.31.2
DNS Server: 192.168.31.24
Time zone: America/Sao_Paulo
```

Após finalizar, reiniciar o host.

---

# 5. Primeiro acesso ao Proxmox

Acessar:

```bash
https://192.168.31.13:8006
```

Login:

```bash
User: root
Realm: Linux PAM standard authentication
Password: senha definida na instalação
```

---

# 6. Ajustes pós-instalação

## 6.1 Validar hostname

No `pve-dell`:

```bash
hostnamectl
hostname -f
```

Resultado esperado:

```bash
pve-dell.jmsalles.homelab.br
```

---

## 6.2 Ajustar `/etc/hosts`

No `pve-dell`:

```bash
vi /etc/hosts
```

Conteúdo recomendado:

```bash
127.0.0.1 localhost.localdomain localhost
192.168.31.11 pve-dell-novo.jmsalles.homelab.br pve-dell-novo
192.168.31.12 pve-lenovo-prova.jmsalles.homelab.br pve-lenovo-prova
192.168.31.13 pve-dell.jmsalles.homelab.br pve-dell
```

Nos nós atuais `pve-dell-novo` e `pve-lenovo-prova`, adicionar também:

```bash
192.168.31.13 pve-dell.jmsalles.homelab.br pve-dell
```

---

## 6.3 Validar comunicação

No `pve-dell`:

```bash
ping -c 4 pve-dell-novo
ping -c 4 pve-lenovo-prova
ping -c 4 192.168.31.24
ping -c 4 192.168.31.2
```

Nos nós atuais:

```bash
ping -c 4 pve-dell
ping -c 4 192.168.31.13
```

---

# 7. Ajustar repositório no-subscription

No `pve-dell`:

```bash
sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null; sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/ceph.list 2>/dev/null; echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list; apt update; apt dist-upgrade -y
```

Se atualizar kernel:

```bash
reboot
```

Validar:

```bash
pveversion
```

---

# 8. Ingressar o Dell no cluster

## 8.1 Opção A — Via shell

No `pve-dell`:

```bash
pvecm add 192.168.31.11
```

Informar a senha root do `pve-dell-novo`.

Validar:

```bash
pvecm status
pvecm nodes
```

Resultado esperado:

```bash
pve-dell-novo
pve-lenovo-prova
pve-dell
```

---

## 8.2 Opção B — Via interface gráfica

No nó principal atual, acessar:

```bash
https://192.168.31.11:8006
```

Ir em:

```bash
Datacenter > Cluster
```

Clicar em:

```bash
Join Information
```

Copiar as informações exibidas.

Depois acessar o novo nó:

```bash
https://192.168.31.13:8006
```

Ir em:

```bash
Datacenter > Cluster > Join Cluster
```

Preencher:

```bash
Peer Address: 192.168.31.11
Peer Password: senha root do pve-dell-novo
Cluster Network: 192.168.31.13
```

Confirmar o ingresso.

Validar na interface:

```bash
Datacenter
```

Resultado esperado:

```bash
pve-dell-novo
pve-lenovo-prova
pve-dell
```

---

# 9. Preparar NFS no Dell

## 9.1 Criar diretórios

No `pve-dell`:

```bash
mkdir -p /srv/nfs/proxmox/{iso,templates,backup-temp,lab}
```

## 9.2 Ajustar permissões

```bash
chown -R root:root /srv/nfs/proxmox
chmod -R 755 /srv/nfs/proxmox
```

---

# 10. Instalar NFS Server

No `pve-dell`:

```bash
apt update; apt install -y nfs-kernel-server
```

Habilitar serviço:

```bash
systemctl enable --now nfs-server
systemctl status nfs-server
```

---

# 11. Configurar exports NFS

Editar:

```bash
vi /etc/exports
```

Adicionar:

```bash
/srv/nfs/proxmox/iso          192.168.31.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/proxmox/templates    192.168.31.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/proxmox/backup-temp  192.168.31.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/proxmox/lab          192.168.31.0/24(rw,sync,no_subtree_check,no_root_squash)
```

Aplicar:

```bash
exportfs -ra
exportfs -v
```

---

# 12. Testar NFS

Em outro nó Proxmox:

```bash
showmount -e 192.168.31.13
```

Resultado esperado:

```bash
/srv/nfs/proxmox/iso
/srv/nfs/proxmox/templates
/srv/nfs/proxmox/backup-temp
/srv/nfs/proxmox/lab
```

---

# 13. Adicionar NFS ao cluster Proxmox

## 13.1 Opção A — Via shell

Executar em qualquer nó do cluster.

### Storage para ISOs

```bash
pvesm add nfs nfs-dell-iso --server 192.168.31.13 --export /srv/nfs/proxmox/iso --content iso --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

### Storage para templates

```bash
pvesm add nfs nfs-dell-templates --server 192.168.31.13 --export /srv/nfs/proxmox/templates --content vztmpl --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

### Storage para backups temporários

```bash
pvesm add nfs nfs-dell-backup-temp --server 192.168.31.13 --export /srv/nfs/proxmox/backup-temp --content backup --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

### Storage para laboratório

```bash
pvesm add nfs nfs-dell-lab --server 192.168.31.13 --export /srv/nfs/proxmox/lab --content images,rootdir --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

Validar:

```bash
pvesm status
```

---

## 13.2 Opção B — Via interface gráfica

Acessar:

```bash
https://192.168.31.11:8006
```

Ir em:

```bash
Datacenter > Storage > Add > NFS
```

### NFS para ISOs

Preencher:

```bash
ID: nfs-dell-iso
Server: 192.168.31.13
Export: /srv/nfs/proxmox/iso
Content: ISO image
Nodes: pve-dell, pve-dell-novo, pve-lenovo-prova
```

Clicar em:

```bash
Add
```

---

### NFS para templates

```bash
Datacenter > Storage > Add > NFS
```

Preencher:

```bash
ID: nfs-dell-templates
Server: 192.168.31.13
Export: /srv/nfs/proxmox/templates
Content: Container template
Nodes: pve-dell, pve-dell-novo, pve-lenovo-prova
```

Clicar em:

```bash
Add
```

---

### NFS para backups temporários

```bash
Datacenter > Storage > Add > NFS
```

Preencher:

```bash
ID: nfs-dell-backup-temp
Server: 192.168.31.13
Export: /srv/nfs/proxmox/backup-temp
Content: VZDump backup file
Nodes: pve-dell, pve-dell-novo, pve-lenovo-prova
```

Clicar em:

```bash
Add
```

---

### NFS para laboratório

```bash
Datacenter > Storage > Add > NFS
```

Preencher:

```bash
ID: nfs-dell-lab
Server: 192.168.31.13
Export: /srv/nfs/proxmox/lab
Content: Disk image, Container
Nodes: pve-dell, pve-dell-novo, pve-lenovo-prova
```

Clicar em:

```bash
Add
```

---

# 14. Teste de gravação no NFS

Em qualquer nó do cluster:

```bash
touch /mnt/pve/nfs-dell-iso/teste-nfs.txt
ls -lh /mnt/pve/nfs-dell-iso/teste-nfs.txt
rm -f /mnt/pve/nfs-dell-iso/teste-nfs.txt
```

No `pve-dell`:

```bash
ls -lh /srv/nfs/proxmox/iso
```

---

# 15. Validar storages no cluster

Em qualquer nó:

```bash
pvesm status
```

Resultado esperado:

```bash
nfs-dell-iso
nfs-dell-templates
nfs-dell-backup-temp
nfs-dell-lab
```

---

# 16. Uso recomendado do NFS auxiliar

Usar para:

```bash
ISOs
Templates
Backups temporários
VMs de laboratório
Arquivos de migração
Exportação/importação
```

Evitar para:

```bash
AD principal
Zabbix principal
Nexus pesado
Banco de dados
VMs críticas com muito I/O
```

---

# 17. Checklist final

```bash
[ ] Proxmox VE instalado no Dell
[ ] Hostname pve-dell configurado
[ ] IP 192.168.31.13 configurado
[ ] Gateway 192.168.31.2 configurado
[ ] DNS 192.168.31.24 configurado
[ ] /etc/hosts ajustado nos três nós
[ ] Repositório no-subscription configurado
[ ] pve-dell ingressado no cluster
[ ] Cluster mostra três nós
[ ] Diretórios NFS criados
[ ] nfs-kernel-server instalado
[ ] /etc/exports configurado
[ ] exportfs -v OK
[ ] showmount -e 192.168.31.13 OK
[ ] Storages NFS adicionados ao Proxmox
[ ] Teste de gravação no NFS OK
```

---

# 18. Resultado esperado

```bash
Cluster: proxmox-homelab

├── pve-dell-novo       192.168.31.11
├── pve-lenovo-prova    192.168.31.12
└── pve-dell            192.168.31.13
    ├── local
    ├── local-lvm
    └── NFS auxiliar
        ├── nfs-dell-iso
        ├── nfs-dell-templates
        ├── nfs-dell-backup-temp
        └── nfs-dell-lab
```
