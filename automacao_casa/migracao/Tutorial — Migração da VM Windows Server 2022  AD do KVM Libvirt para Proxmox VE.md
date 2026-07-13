# Tutorial — Migração da VM Windows Server 2022 / AD do KVM Libvirt para Proxmox VE

## 1. Objetivo

Migrar a VM Windows Server 2022 com AD/DNS do host KVM/libvirt `dell` para o cluster Proxmox VE `proxmox-homelab`.

VM origem:

```bash
win2k22-2026-6-3
```

VM destino no Proxmox:

```bash
VMID=120
Nome: winserver-ad
```

---

## 2. Cenário identificado

```bash
Host origem: dell
Hipervisor origem: KVM/libvirt
VM origem: win2k22-2026-6-3
Disco ativo: /var/lib/libvirt/images/win2k22-2026-6-3.2026-06-05T05:56
Disco base: /var/lib/libvirt/images/win2k22-2026-6-3.qcow2
Firmware: BIOS Legacy
Disco origem: SATA/QCOW2
Rede origem: e1000e
Destino: pve-dell-novo
IP Proxmox destino: 192.168.31.11
Storage destino: local-lvm
```

---

## 3. Estratégia usada

A abordagem segura foi:

```bash
1. Exportar informações da VM original
2. Desligar a VM no KVM/libvirt
3. Gerar QCOW2 consolidado
4. Copiar imagem para o Proxmox
5. Criar VM vazia no Proxmox
6. Importar disco
7. Subir primeiro com SATA
8. Instalar drivers VirtIO
9. Adicionar disco temporário VirtIO SCSI de 1 GB
10. Validar driver VirtIO SCSI no Windows
11. Migrar disco principal de SATA para SCSI VirtIO
12. Remover disco temporário
13. Validar AD/DNS
```

---

## 4. Backup das informações da VM no host Dell

No host `dell`:

```bash
mkdir -p /root/backup-vm-win2k22-ad/{xml,info,logs}
```

```bash
virsh dumpxml win2k22-2026-6-3 > /root/backup-vm-win2k22-ad/xml/win2k22-2026-6-3.xml
virsh dominfo win2k22-2026-6-3 > /root/backup-vm-win2k22-ad/info/dominfo.txt
virsh domblklist win2k22-2026-6-3 > /root/backup-vm-win2k22-ad/info/domblklist.txt
virsh domiflist win2k22-2026-6-3 > /root/backup-vm-win2k22-ad/info/domiflist.txt
```

Validar disco da VM:

```bash
virsh domblklist win2k22-2026-6-3
```

---

## 5. Desligamento controlado da VM origem

Dentro do Windows Server:

```powershell
shutdown /s /t 0
```

No host `dell`, validar:

```bash
virsh list --all
virsh domstate win2k22-2026-6-3
```

Resultado esperado:

```bash
shut off
```

---

## 6. Gerar imagem consolidada QCOW2

Criar diretório:

```bash
mkdir -p /var/lib/libvirt/images/export-proxmox
```

Validar cadeia de snapshot/backing file:

```bash
qemu-img info --backing-chain /var/lib/libvirt/images/win2k22-2026-6-3.2026-06-05T05\:56
```

Gerar imagem consolidada:

```bash
qemu-img convert -p -O qcow2 /var/lib/libvirt/images/win2k22-2026-6-3.2026-06-05T05\:56 /var/lib/libvirt/images/export-proxmox/win2k22-ad-consolidado.qcow2
```

Validar imagem:

```bash
qemu-img info /var/lib/libvirt/images/export-proxmox/win2k22-ad-consolidado.qcow2
```

Validar se não possui backing file:

```bash
qemu-img info /var/lib/libvirt/images/export-proxmox/win2k22-ad-consolidado.qcow2 | grep -i backing
```

Resultado ideal:

```bash
sem retorno
```

---

## 7. Copiar imagem para o Proxmox

No host `dell`:

```bash
scp /var/lib/libvirt/images/export-proxmox/win2k22-ad-consolidado.qcow2 root@192.168.31.11:/root/
```

No Proxmox `pve-dell-novo`:

```bash
ls -lh /root/win2k22-ad-consolidado.qcow2
qemu-img info /root/win2k22-ad-consolidado.qcow2
```

---

## 8. Criar VM vazia no Proxmox

No `pve-dell-novo`:

```bash
VMID=120; qm create $VMID --name winserver-ad --memory 8192 --cores 4 --sockets 1 --cpu x86-64-v2-AES --bios seabios --machine q35 --net0 e1000,bridge=vmbr0 --ostype win11
```

---

## 9. Importar disco para local-lvm

```bash
VMID=120; qm importdisk $VMID /root/win2k22-ad-consolidado.qcow2 local-lvm
```

Validar:

```bash
qm config 120
```

O disco importado aparece inicialmente como:

```bash
unused0: local-lvm:vm-120-disk-0
```

---

## 10. Primeiro boot usando SATA

Anexar disco como SATA:

```bash
VMID=120; qm set $VMID --sata0 local-lvm:vm-$VMID-disk-0
```

Definir boot:

```bash
VMID=120; qm set $VMID --boot order=sata0
```

Adicionar CD-ROM vazio:

```bash
VMID=120; qm set $VMID --ide2 none,media=cdrom
```

Habilitar tablet:

```bash
VMID=120; qm set $VMID --tablet 1
```

Iniciar VM:

```bash
VMID=120; qm start $VMID
```

---

## 11. Ajuste de rede inicial

Como a placa mudou, validar IP dentro do Windows:

```powershell
ipconfig /all
```

Configuração esperada para o AD:

```bash
IP: 192.168.31.24
Máscara: 255.255.255.0
Gateway: 192.168.31.2
DNS: 127.0.0.1
```

Se precisar configurar via PowerShell:

```powershell
Get-NetAdapter
```

Exemplo:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.31.24 -PrefixLength 24 -DefaultGateway 192.168.31.2
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1,192.168.31.24
```

---

## 12. Instalar drivers VirtIO

No Proxmox:

```bash
cd /var/lib/vz/template/iso
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
```

Anexar ISO VirtIO:

```bash
VMID=120; qm set $VMID --ide2 local:iso/virtio-win.iso,media=cdrom
```

Dentro do Windows, executar:

```bash
virtio-win-guest-tools.exe
```

Reiniciar a VM.

---

## 13. Alterar rede para VirtIO

Desligar VM:

```bash
VMID=120; qm shutdown $VMID
```

Alterar placa de rede:

```bash
VMID=120; qm set $VMID --net0 virtio,bridge=vmbr0
```

Ligar:

```bash
VMID=120; qm start $VMID
```

Validar novamente o IP no Windows:

```powershell
ipconfig /all
```

---

## 14. Habilitar QEMU Guest Agent

No Proxmox:

```bash
VMID=120; qm set $VMID --agent enabled=1
```

Reiniciar VM:

```bash
VMID=120; qm reboot $VMID
```

Validar:

```bash
VMID=120; qm agent $VMID ping
```

---

## 15. Preparar migração do disco principal para VirtIO SCSI

Adicionar controlador SCSI VirtIO e disco temporário de 1 GB:

```bash
VMID=120; qm set $VMID --scsihw virtio-scsi-single --scsi1 local-lvm:1,discard=on,iothread=1
```

Ligar a VM:

```bash
VMID=120; qm start $VMID
```

Dentro do Windows, validar no Device Manager:

```bash
Red Hat VirtIO SCSI pass-through controller
Red Hat VirtIO Ethernet Adapter
```

No Disk Management, o disco temporário aparece como:

```bash
Disk 1
Unknown
Offline
1.00 GB
Unallocated
```

Não precisa inicializar nem formatar esse disco. Ele serve apenas para forçar o Windows a carregar o driver VirtIO SCSI.

---

## 16. Migrar disco principal de SATA para VirtIO SCSI

Desligar VM:

```bash
VMID=120; qm shutdown $VMID
```

Se necessário:

```bash
VMID=120; qm stop $VMID
```

Remover disco SATA da configuração:

```bash
VMID=120; qm set $VMID --delete sata0
```

Adicionar disco principal como SCSI VirtIO:

```bash
VMID=120; qm set $VMID --scsihw virtio-scsi-single --scsi0 local-lvm:vm-$VMID-disk-0,discard=on,iothread=1
```

Ajustar boot:

```bash
VMID=120; qm set $VMID --boot order=scsi0
```

Ligar VM:

```bash
VMID=120; qm start $VMID
```

Validar que o Windows inicia normalmente.

---

## 17. Remover disco temporário de 1 GB

Após validar que o Windows subiu com o disco principal em `scsi0`, desligar a VM:

```bash
VMID=120; qm shutdown $VMID
```

Remover disco temporário:

```bash
VMID=120; qm set $VMID --delete scsi1
```

Fazer rescan:

```bash
VMID=120; qm rescan
```

Se aparecer como disco não utilizado na interface, remover pelo Proxmox em:

```bash
VM 120 > Hardware > Unused Disk > Remove
```

Ligar novamente:

```bash
VMID=120; qm start $VMID
```

---

## 18. Configuração final esperada da VM

Validar:

```bash
qm config 120
```

Configuração esperada:

```bash
agent: enabled=1
bios: seabios
boot: order=scsi0
cores: 4
cpu: x86-64-v2-AES
ide2: local:iso/virtio-win.iso,media=cdrom
machine: pc-q35-11.0
memory: 8192
name: winserver-ad
net0: virtio=MAC,bridge=vmbr0
ostype: win11
scsi0: local-lvm:vm-120-disk-0,discard=on,iothread=1,size=150G
scsihw: virtio-scsi-single
sockets: 1
tablet: 1
```

---

## 19. Validação do Active Directory e DNS

Dentro do Windows:

```powershell
dcdiag
dcdiag /test:dns
netdom query fsmo
Get-Service ADWS,DNS,NTDS,KDC,Netlogon
```

Validar DNS:

```powershell
nslookup jmsalles.homelab.br 127.0.0.1
nslookup winserver.jmsalles.homelab.br 127.0.0.1
```

---

## 20. Validação a partir de outro host Linux

Exemplo no `docker-hml-lenovo-i5`:

```bash
ping -c 4 192.168.31.24
nslookup jmsalles.homelab.br 192.168.31.24
nslookup winserver.jmsalles.homelab.br 192.168.31.24
```

Testar portas:

```bash
nc -vz 192.168.31.24 53
nc -vz 192.168.31.24 88
nc -vz 192.168.31.24 389
nc -vz 192.168.31.24 445
```

---

## 21. Plano de rollback

Se ocorrer falha crítica antes da validação final:

No Proxmox:

```bash
VMID=120; qm stop $VMID
```

No host Dell antigo:

```bash
virsh start win2k22-2026-6-3
```

Regra principal:

```bash
Nunca deixar a VM antiga e a VM nova ligadas ao mesmo tempo.
```

---

## 22. Checklist final

```bash
[ ] XML da VM original salvo
[ ] Disco consolidado gerado
[ ] Imagem copiada para o Proxmox
[ ] VM 120 criada
[ ] Disco importado em local-lvm
[ ] Primeiro boot realizado com SATA
[ ] Drivers VirtIO instalados
[ ] Rede alterada para VirtIO
[ ] QEMU Guest Agent habilitado
[ ] Disco temporário de 1 GB adicionado
[ ] VirtIO SCSI reconhecido no Windows
[ ] Disco principal migrado para scsi0
[ ] Disco temporário removido
[ ] Windows Server iniciado com sucesso
[ ] AD validado
[ ] DNS validado
[ ] Testes externos OK
```

---

## 23. Resultado final

```bash
Cluster: proxmox-homelab

├── pve-dell-novo
├── pve-lenovo-prova
└── VM 120 - winserver-ad
    ├── Windows Server 2022
    ├── Active Directory
    ├── DNS
    ├── IP: 192.168.31.24
    ├── Disco: VirtIO SCSI
    ├── Rede: VirtIO
    └── QEMU Guest Agent: enabled
```

Com essa etapa concluída, o próximo passo será validar por alguns dias e depois preparar o Dell físico antigo para instalação do Proxmox VE e entrada no cluster.
