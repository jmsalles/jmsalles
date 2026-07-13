# Tutorial — Adicionar Storage NFS no Cluster Proxmox

## 1. Objetivo

Adicionar um storage NFS compartilhado ao cluster Proxmox `proxmox-homelab`, permitindo que os nós do cluster acessem o mesmo diretório remoto para uso com ISOs, templates, backups temporários ou VMs de laboratório.

Neste exemplo, o NFS está no host:

```bash
Servidor NFS: pve-dell
IP: 192.168.31.13
```

Exports NFS:

```bash
/srv/nfs/proxmox/iso
/srv/nfs/proxmox/templates
/srv/nfs/proxmox/backup-temp
/srv/nfs/proxmox/lab
```

---

## 2. Arquitetura

```bash
Cluster Proxmox VE: proxmox-homelab

├── pve-dell-novo       192.168.31.11
├── pve-lenovo-prova    192.168.31.12
└── pve-dell            192.168.31.13
    └── NFS auxiliar
        ├── /srv/nfs/proxmox/iso
        ├── /srv/nfs/proxmox/templates
        ├── /srv/nfs/proxmox/backup-temp
        └── /srv/nfs/proxmox/lab
```

---

## 3. Premissas

```bash
Rede: 192.168.31.0/24
Cluster: proxmox-homelab
Servidor NFS: 192.168.31.13
NFS Server: nfs-kernel-server
Nós autorizados: 192.168.31.0/24
```

---

# 4. Validar exports no servidor NFS

No servidor NFS `pve-dell`:

```bash
exportfs -v
```

Resultado esperado:

```bash
/srv/nfs/proxmox/iso
/srv/nfs/proxmox/templates
/srv/nfs/proxmox/backup-temp
/srv/nfs/proxmox/lab
```

Validar serviço:

```bash
systemctl status nfs-server
```

Caso precise aplicar novamente:

```bash
exportfs -ra
```

---

# 5. Testar acesso NFS a partir de outro nó

Em outro nó do cluster, por exemplo `pve-dell-novo`:

```bash
showmount -e 192.168.31.13
```

Resultado esperado:

```bash
Export list for 192.168.31.13:
/srv/nfs/proxmox/iso          192.168.31.0/24
/srv/nfs/proxmox/templates    192.168.31.0/24
/srv/nfs/proxmox/backup-temp  192.168.31.0/24
/srv/nfs/proxmox/lab          192.168.31.0/24
```

---

# 6. Método 1 — Adicionar Storage NFS via Interface Gráfica

Acessar a interface do Proxmox:

```bash
https://192.168.31.11:8006
```

Ir em:

```bash
Datacenter > Storage > Add > NFS
```

---

## 6.1 Adicionar storage para ISOs

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

## 6.2 Adicionar storage para templates LXC

Ir novamente em:

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

## 6.3 Adicionar storage para backups temporários

Ir novamente em:

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

## 6.4 Adicionar storage para laboratório

Ir novamente em:

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

# 7. Método 2 — Adicionar Storage NFS via Shell

Executar em qualquer nó do cluster.

## 7.1 Adicionar NFS para ISOs

```bash
pvesm add nfs nfs-dell-iso --server 192.168.31.13 --export /srv/nfs/proxmox/iso --content iso --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

---

## 7.2 Adicionar NFS para templates LXC

```bash
pvesm add nfs nfs-dell-templates --server 192.168.31.13 --export /srv/nfs/proxmox/templates --content vztmpl --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

---

## 7.3 Adicionar NFS para backups temporários

```bash
pvesm add nfs nfs-dell-backup-temp --server 192.168.31.13 --export /srv/nfs/proxmox/backup-temp --content backup --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

---

## 7.4 Adicionar NFS para laboratório

```bash
pvesm add nfs nfs-dell-lab --server 192.168.31.13 --export /srv/nfs/proxmox/lab --content images,rootdir --nodes pve-dell,pve-dell-novo,pve-lenovo-prova
```

---

# 8. Validar storage no cluster

Em qualquer nó:

```bash
pvesm status
```

Resultado esperado:

```bash
Name                    Type     Status
nfs-dell-iso            nfs      active
nfs-dell-templates      nfs      active
nfs-dell-backup-temp    nfs      active
nfs-dell-lab            nfs      active
```

Também é possível validar pela interface:

```bash
Datacenter > Storage
```

---

# 9. Teste de gravação

Executar em qualquer nó do cluster:

```bash
touch /mnt/pve/nfs-dell-iso/teste-nfs.txt
ls -lh /mnt/pve/nfs-dell-iso/teste-nfs.txt
rm -f /mnt/pve/nfs-dell-iso/teste-nfs.txt
```

Validar no servidor NFS `pve-dell`:

```bash
ls -lh /srv/nfs/proxmox/iso
```

---

# 10. Exemplo de uso

## 10.1 Copiar ISO para o storage NFS

```bash
cp -av /var/lib/vz/template/iso/virtio-win.iso /mnt/pve/nfs-dell-iso/
```

Validar:

```bash
ls -lh /mnt/pve/nfs-dell-iso/
```

Depois conferir pela interface:

```bash
Datacenter > Storage > nfs-dell-iso > ISO Images
```

---

# 11. Cuidados importantes

Usar esse NFS auxiliar para:

```bash
ISOs
Templates
Backups temporários
VMs de laboratório
Arquivos de migração
Exportação/importação
```

Evitar usar para:

```bash
AD principal
Zabbix principal
Nexus pesado
Banco de dados
VMs críticas com muito I/O
```

---

# 12. Checklist final

```bash
[ ] NFS Server ativo no pve-dell
[ ] exportfs -v mostra os exports
[ ] showmount -e 192.168.31.13 funciona a partir de outro nó
[ ] Storage nfs-dell-iso adicionado
[ ] Storage nfs-dell-templates adicionado
[ ] Storage nfs-dell-backup-temp adicionado
[ ] Storage nfs-dell-lab adicionado
[ ] pvesm status mostra os storages como active
[ ] Teste de gravação realizado com sucesso
```

---

# 13. Resultado esperado

```bash
Cluster: proxmox-homelab

├── pve-dell-novo       192.168.31.11
├── pve-lenovo-prova    192.168.31.12
└── pve-dell            192.168.31.13
    └── NFS auxiliar
        ├── nfs-dell-iso
        ├── nfs-dell-templates
        ├── nfs-dell-backup-temp
        └── nfs-dell-lab
```
