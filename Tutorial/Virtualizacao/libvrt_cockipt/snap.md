# 📚 Guia definitivo — **Snapshots LVM (RAW) + Backup dedicado**

**Stack:** Rocky Linux 10 • KVM/libvirt • VG `vg_vms` • Bridge `br0` • Discos RAW em LVM
**Seus LVs de VMs:** `k8s-cp1(60G)`, `k8s-w1(40G)`, `k8s-w2(40G)`, `rocky10_openshift(100G)`, `vm_k8s(160G)`

> Template novo, com interface visual em Markdown, cobrindo:
> **(A)** criação de **/backup** em LVM (150 G) + `fstab` + montagem;
> **(B)** fluxo completo de **snapshots LVM**: **1) criar → 2) backup → 3) rollback → 4) remover**;
> **(C)** montagem correta do snapshot (host vs. helper VM) e correção do erro *“Can’t open blockdev”*;
> **(D)** comandos de listagem/monitoramento `lvs`;
> **(E)** exemplos reais com **seus** LVs;
> **(F)** 1-liners, dicas e troubleshooting.

---

## ✅ Pré-requisitos & checagens

### 🖥️ No **guest** (uma vez por VM) — *freeze/thaw consistente*

```bash
# Rocky/EL
sudo dnf -y install qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent
# Ubuntu/Debian
sudo apt -y install qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent
```

### 🧰 No **host**

```bash
# Libvirt ativo?
systemctl is-active libvirtd

# Espaço livre nos VGs
vgs
pvs -o+pv_used

# Mapear VM ↔ LV (ex.: vm_k8s)
virsh domblklist vm_k8s
# ex.: target sda -> source /dev/vg_vms/vm_k8s
```

---

# 💽 Parte A — **/backup** dedicado em LVM (150 G) + XFS + fstab + montagem

> Objetivo: criar `backups` (150 G) no VG **rl\_miwifi-r3600-srv**, montar em **/backup** e garantir montagem no boot.

### 0) Checar espaço

```bash
vgs rl_miwifi-r3600-srv
lvs rl_miwifi-r3600-srv
```

### 1) Criar LV (150 G)

```bash
lvcreate -L 150G -n backups rl_miwifi-r3600-srv
```

### 2) Formatar XFS (atenção aos hífens!)

```bash
mkfs.xfs /dev/rl_miwifi-r3600--srv/backups
# equivalente:
# mkfs.xfs /dev/mapper/rl_miwifi--r3600--srv-backups
```

### 3) Ponto de montagem

```bash
mkdir -p /backup
```

### 4) Adicionar ao **/etc/fstab** (recomendado **UUID**)

```bash
UUID=$(blkid -s UUID -o value /dev/mapper/rl_miwifi--r3600--srv-backups)
echo "UUID=$UUID  /backup  xfs  noatime,discard  0  0" | tee -a /etc/fstab
```

* `noatime`: menos writes de metadata.
* `discard`: TRIM online (ainda recomendo TRIM periódico abaixo).
* Para XFS, o último campo é **0**.

### 5) Recarregar systemd & montar

```bash
systemctl daemon-reload
mount -av        # ou: mount /backup
```

### 6) Validar

```bash
findmnt /backup
df -h /backup
```

### 7) TRIM periódico

```bash
systemctl enable --now fstrim.timer
fstrim -v /backup
```

> **Se já existia um LV maior (ex.: 300 G):** XFS não encolhe.
> **A)** se vazio: `umount` → `lvremove` → recrie 150 G (passos 1–7).
> **B)** se tem dados: crie `backups150`, copie com `rsync -aHAX`, `lvrename` e atualize o `fstab` (UUID).

---

## 🔎 Parte B — **Listagem e monitoramento** (sempre à mão)

```bash
# Geral: nome, VG, tamanho, origem (snap), %uso do snap, devices
lvs -a -o lv_name,vg_name,lv_size,origin,data_percent,devices | column -t

# Só seus LVs (resumo)
lvs -o lv_name,vg_name,lv_size,attr,devices vg_vms | \
  egrep 'k8s-cp1|k8s-w1|k8s-w2|rocky10_openshift|vm_k8s' | column -t

# Acompanhar snapshots em tempo real
watch -n5 'lvs -o lv_name,origin,lv_size,data_percent,devices | column -t | egrep "snap|k8s-|rocky10_openshift|vm_k8s"'
```

---

# 🧭 Parte C — **Fluxo oficial de Snapshot LVM (RAW)**

### 🧠 Mapa mental do processo

```
[1] Criar snapshot  ──► snapshot EXISTE
        │
        ├─► [2] BACKUP lendo do snapshot ──► (opção) [4] Remover
        │
        └─► [3] ROLLBACK (merge) ──► origin volta ao estado do snapshot ──► (snap some)
```

---

## 1) 🟩 **Criação** (VM ligada, com consistência)

Ex.: **k8s-cp1 (60G)** — ajuste `-L` ao volume de escrita durante a retenção.

```bash
virsh domfsfreeze k8s-cp1
lvcreate -s -n k8s-cp1_snap_$(date +%F_%H%M) -L 10G /dev/vg_vms/k8s-cp1
virsh domfsthaw k8s-cp1

# confirmar
lvs -a -o lv_name,origin,lv_size,lv_time,data_percent | egrep 'k8s-cp1'
```

---

## 2) 🟨 **Backup** (usando o snapshot; não altera o origin)

### 2.1 Montar **no host** (quando o guest NÃO usa LVM interno)

> Monte a **partição** do snapshot, não o disco inteiro.
> **Erro “Can’t open blockdev”** ocorre quando tenta montar o disco sem `kpartx` ou LV está inativo.

```bash
SNAP=/dev/vg_vms/k8s-cp1_snap_2025-08-24_0226

# ativar & mapear partições (...p1, p2, ...)
lvchange -ay "$SNAP"
kpartx -av "$SNAP"
lsblk -f | egrep 'k8s--cp1_snap|MOUNTPOINT'

# monte a partição correta (ex.: p1) em RO
mkdir -p /mnt/snap
mount -o ro /dev/mapper/vg_vms-k8s--cp1_snap_2025--08--24_0226p1 /mnt/snap
```

**Copiar com rsync (crie o destino antes!):**

```bash
mkdir -p /backup/k8s-cp1
rsync -aHAX --numeric-ids --info=progress2 /mnt/snap/ /backup/k8s-cp1/
```

**Limpeza:**

```bash
umount /mnt/snap
kpartx -dv "$SNAP"
```

### 2.2 Guest com **LVM interno** → use **VM helper** (recomendado)

```bash
# anexar snapshot em RO à VM helper
SNAP=/dev/vg_vms/k8s-cp1_snap_2025-08-24_0226
virsh attach-disk helper_vm "$SNAP" vdb --targetbus scsi --mode readonly --live --persistent
```

Na **helper\_vm**:

```bash
sudo kpartx -av /dev/vdb
sudo pvscan; sudo vgscan; sudo vgchange -ay
lsblk -f
sudo mount -o ro /dev/mapper/<VG_DO_GUEST>-<LV_RAIZ> /mnt/snap
# ... rsync/tar/restic ...
sudo umount /mnt/snap
```

Voltar ao host:

```bash
virsh detach-disk helper_vm vdb --persistent
```

### 2.3 Cópia **bloco-a-bloco** (imagem bruta)

```bash
dd if=/dev/vg_vms/k8s-cp1_snap_2025-08-24_0226 of=/backup/k8s-cp1.img bs=16M status=progress
# ou:
qemu-img convert -p -O raw /dev/vg_vms/k8s-cp1_snap_2025-08-24_0226 /backup/k8s-cp1.img
```

**Monitore a % do snapshot:**

```bash
watch -n5 'lvs -o lv_name,origin,lv_size,data_percent | egrep "k8s-cp1"'
```

---

## 3) 🟦 **Recovery / Rollback** (voltar o origin ao estado do snapshot)

> **Requer VM desligada**; o `lvconvert --merge` aplica o snapshot no origin e **remove** o snapshot.

Ex.: **k8s-w1**

```bash
virsh shutdown k8s-w1
lvconvert --merge /dev/vg_vms/k8s-w1_snap_2025-08-24_1200
virsh start k8s-w1
```

Descobrir nome do snapshot:

```bash
lvs -a -o lv_name,origin,lv_size,lv_time | egrep 'k8s-w1'
```

---

## 4) 🟥 **Remoção/Limpeza** (quando não haverá rollback)

```bash
lvremove -f /dev/vg_vms/k8s-cp1_snap_2025-08-24_0226
lvs -a -o lv_name,origin,lv_size | egrep 'snap|k8s-|rocky10_openshift|vm_k8s'
```

---

# 🧪 Parte D — Exemplos rápidos (com seus nomes)

### 📦 `vm_k8s (160G)` — snapshot + helper VM

```bash
virsh domfsfreeze vm_k8s
lvcreate -s -n vm_k8s_snap_$(date +%F_%H%M) -L 16G /dev/vg_vms/vm_k8s
virsh domfsthaw vm_k8s

virsh attach-disk helper_vm /dev/vg_vms/vm_k8s_snap_2025-08-24_1200 vdb \
  --targetbus scsi --mode readonly --live --persistent
# (backup dentro da helper)
virsh detach-disk helper_vm vdb --persistent
lvremove -f /dev/vg_vms/vm_k8s_snap_2025-08-24_1200
```

### 🗂️ `rocky10_openshift (100G)` — snapshot + restic

```bash
virsh domfsfreeze rocky10_openshift
lvcreate -s -n rocky10_openshift_snap_$(date +%F_%H%M) -L 12G /dev/vg_vms/rocky10_openshift
virsh domfsthaw rocky10_openshift

restic -r /backup/restic backup /dev/vg_vms/rocky10_openshift_snap_2025-08-24_1200
lvremove -f /dev/vg_vms/rocky10_openshift_snap_2025-08-24_1200
```

### 🔁 `k8s-w2 (40G)` — rollback

```bash
virsh shutdown k8s-w2
lvconvert --merge /dev/vg_vms/k8s-w2_snap_2025-08-24_1200
virsh start k8s-w2
```

---

# ⚡ Parte E — 1-liners (rápidos)

**Criar (1):**

```bash
VM=k8s-cp1; virsh domfsfreeze $VM; lvcreate -s -n ${VM}_snap_$(date +%F_%H%M) -L 10G /dev/vg_vms/$VM; virsh domfsthaw $VM
```

**Backup (2) — host (sem LVM interno):**

```bash
SNAP=/dev/vg_vms/k8s-cp1_snap_2025-08-24_0226; lvchange -ay $SNAP; kpartx -av $SNAP; \
mkdir -p /backup/k8s-cp1; mount -o ro /dev/mapper/vg_vms-k8s--cp1_snap_2025--08--24_0226p1 /mnt/snap; \
rsync -aHAX --numeric-ids --info=progress2 /mnt/snap/ /backup/k8s-cp1/
```

**Rollback (3):**

```bash
VM=k8s-w1; virsh shutdown $VM; lvconvert --merge /dev/vg_vms/${VM}_snap_2025-08-24_1200; virsh start $VM
```

**Remover (4):**

```bash
lvremove -f /dev/vg_vms/k8s-cp1_snap_2025-08-24_0226
```

---

## 🛡️ Boas práticas

* Dimensione o snapshot (`-L`) conforme **escritas previstas**; monitore `data_percent` e evite chegar a **100%** (snap quebra).
* **Poucos snapshots simultâneos** ⇒ menor overhead.
* **Retenção curta** para LVM snaps; para longo prazo, copie para **/backup** (LV dedicado).
* **Freeze/Thaw** sempre que possível para consistência de app/FS.

---

## 🧯 Troubleshooting

**“Can’t open blockdev” ao montar**
→ Ative LV (`lvchange -ay`), crie partições com `kpartx -av` e **monte a partição** (…`p1`).
Se LVM interno no guest, use **helper VM** e `vgchange -ay`.

**Editou o `fstab` e `mount -a` alertou sobre systemd**
→ `systemctl daemon-reload` → `mount -av`.

**Rsync falhou “No such file or directory”**
→ Crie o diretório destino (`mkdir -p /backup/<vm>`) antes de rodar o `rsync`.

**Snapshot quebrou (100%)**
→ `lvremove -f <snap>` e refaça **maior**.

---

Pronto! Este tutorial integra **todas** as seções: **/backup em LVM (150 G)**, `fstab` + `daemon-reload`, **fluxo 1→2→3→4**, montagem correta (host vs helper), **lvs** para monitorar e **exemplos** com as suas VMs.
