# 🧭 Guia definitivo — **Criação de VMs Linux** (template novo)

**Stack:** Rocky Linux 10 • KVM/libvirt • LVM (RAW) • Bridge **`br0`** • **Text install**

> **Objetivo:** criar VMs Linux **performáticas** usando **LVM (RAW)** no VG `vg_vms`, rede em **bridge `br0`** e **instalação 100% em modo texto** (via `virt-install` + `--location` + `console=ttyS0`).
> Você verá **2 exemplos completos** (Rocky e Ubuntu) já com **`maximum` (teto)** e **`current` (ativo agora)** para **memória** e **CPU**.

---

## ✅ Pré-requisitos rápidos

* Host com `libvirtd` ativo e Cockpit opcional.
* Pool **`vms`** (LVM) apontando para **`vg_vms`**.
* Bridge **`br0`** funcional (com IP).
* ISOs no host (ex.: `/var/lib/libvirt/images/iso/`).
* Seu usuário no grupo `libvirt` (senão use `sudo`).

Checagens:

```bash
systemctl is-active libvirtd
vgs | grep vg_vms
ip -br a | egrep 'br0|enp|eth'
ls -lh /var/lib/libvirt/images/iso/
```

---

## 🧱 Passo 1 — Criar os discos **LVM (RAW)** para as VMs

> Cada VM terá um LV dedicado no **VG `vg_vms`** (melhor I/O que qcow2).

```bash
# VM A (Rocky 10)
lvcreate -L 60G -n vm_rocky10 vg_vms

# VM B (Ubuntu 24.04)
lvcreate -L 80G -n vm_ubuntu2404 vg_vms
```

> Dica: se precisar remover e recriar, **pare a VM** e **não apague o LV por engano**.

---

## 🖥️ Passo 2 — Criar VMs **(modo texto SEM VNC)**

### 🔧 Opções comuns (explicadas)

* **`--graphics none`** → sem VNC/virt-viewer.
* **`--location <ISO>`** + **`--extra-args 'inst.text console=ttyS0,115200n8'`** → Anaconda/installer no **console serial** (acessa com `virsh console`).
* **Disco**: `format=raw,bus=scsi,cache=none,io=native,discard=unmap` (máximo desempenho).
* **CPU**: `host-passthrough` (expor instruções do host ao guest).
* **`--vcpus X,maxvcpus=Y`** e **`--memory A,maxmemory=B`** → define **current** e **maximum** (teto).
* **Rede**: `--network bridge=br0,model=virtio`.

---

### 🅰️ VM A — **Rocky 10** (current < maximum)

* **CPU**: current **4**, maximum **6**
* **Memória**: current **8 GiB**, maximum **16 GiB**

```bash
virt-install \
  --name vm_rocky10 \
  --virt-type kvm \
  --osinfo detect=on,name=linux2024 \
  --memory 8192,maxmemory=16384 \
  --vcpus 4,maxvcpus=6 \
  --cpu host-passthrough,cache.mode=passthrough \
  --iothreads 2 \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/dev/vg_vms/vm_rocky10,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --network bridge=br0,model=virtio \
  --graphics none \
  --location /var/lib/libvirt/images/iso/Rocky-10.0-x86_64-minimal.iso \
  --extra-args 'inst.text console=ttyS0,115200n8' \
  --boot uefi
```

Conectar ao instalador (em outra aba):

```bash
virsh console vm_rocky10      # sair com: Ctrl+]
```

---

### 🅱️ VM B — **Ubuntu 24.04** (outro conjunto de limites)

* **CPU**: current **2**, maximum **4**
* **Memória**: current **6 GiB**, maximum **12 GiB**

```bash
virt-install \
  --name vm_ubuntu2404 \
  --virt-type kvm \
  --osinfo detect=on,name=linux2024 \
  --memory 6144,maxmemory=12288 \
  --vcpus 2,maxvcpus=4 \
  --cpu host-passthrough,cache.mode=passthrough \
  --iothreads 2 \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/dev/vg_vms/vm_ubuntu2404,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --network bridge=br0,model=virtio \
  --graphics none \
  --location /var/lib/libvirt/images/iso/ubuntu-24.04.1-live-server-amd64.iso \
  --extra-args 'console=ttyS0,115200n8' \
  --boot uefi
```

> **Sem DHCP?** adicione a `--extra-args` um IP fixo, por exemplo:
> `ip=192.168.31.240::192.168.31.1:255.255.255.0:vmA:ens3:none nameserver=1.1.1.1`

---

## 🧩 Passo 3 — Pós-instalação dentro da VM

```bash
# Rocky/EL:
sudo dnf -y install qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent
# Ubuntu/Debian:
sudo apt -y install qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent
```

> Isso habilita IP/estatísticas e **freeze/thaw** (para snapshots LVM consistentes).

---

## 🧠 *current* × *maximum* — ajustar depois (hot-plug)

> Você já definiu os tetos ao criar as VMs. Se quiser **mudar em runtime**:

### Memória (até o teto)

```bash
# aumentar "current" agora e persistir
virsh setmem vm_rocky10 12G --live
virsh setmem vm_rocky10 12G --config
```

### vCPU (até o teto)

```bash
virsh setvcpus vm_rocky10 6 --live
virsh setvcpus vm_rocky10 6 --config
```

### Elevar **o teto** (maximum) depois

> Geralmente com a VM **desligada**:

```bash
virsh shutdown vm_rocky10
virsh setmaxmem vm_rocky10 24G --config
virsh setvcpus vm_rocky10 8 --maximum --config
virsh start vm_rocky10
```

---

## 🔁 Autostart (iniciar VM no boot do host)

```bash
systemctl enable --now libvirtd
virsh autostart vm_rocky10
virsh autostart vm_ubuntu2404
virsh dominfo vm_rocky10 | egrep 'Name|Autostart|Persistent'
```

*(Opcional)* religar todas que estavam ligadas antes do shutdown:

```bash
systemctl enable --now libvirt-guests
sed -i 's/^#\?ON_BOOT=.*/ON_BOOT=start/; s/^#\?ON_SHUTDOWN=.*/ON_SHUTDOWN=shutdown/; s/^#\?START_DELAY=.*/START_DELAY=10/' /etc/sysconfig/libvirt-guests
systemctl restart libvirt-guests
```

---

## 🧪 Verificações úteis

```bash
virsh list --all
virsh dominfo vm_rocky10
virsh domifaddr vm_rocky10
virsh domblklist vm_rocky10
```

---

## 🧯 Erros comuns (e correção rápida)

* **“disco já está sendo usado por outro convidado”**
  → a VM já existe. Reinstale sem recriar disco:

  ```bash
  virsh destroy vm_k8s 2>/dev/null || true
  virt-install --name vm_k8s --reinstall --graphics none \
    --location /var/lib/libvirt/images/iso/Rocky-10.0-x86_64-minimal.iso \
    --extra-args 'inst.text console=ttyS0,115200n8' --boot uefi
  ```

  *(ou `virsh undefine --nvram` para recriar do zero e repetir o comando completo)*

* **Console não mostra instalador**
  → garanta `--graphics none` e `--extra-args '... console=ttyS0,115200n8'`, e conecte com `virsh console <VM>`.

---

## ✅ Checklist final

* [ ] LVs criados no **`vg_vms`** (um por VM).
* [ ] VMs criadas com **`--graphics none`** e **`console=ttyS0`**.
* [ ] **CPU**/**Memória**: `current` e `maximum` definidos como planejado.
* [ ] Disco **RAW/LVM** com **virtio-scsi + cache=none + io=native + discard=unmap**.
* [ ] **qemu-guest-agent** instalado no guest.
* [ ] **Autostart** configurado (se desejado).

Pronto! Você tem um fluxo **limpo, repetível e rápido** para criar VMs Linux em **LVM (RAW)**, com **instalação texto** e controle fino de **`current`** e **`maximum`** em **CPU/RAM**.
