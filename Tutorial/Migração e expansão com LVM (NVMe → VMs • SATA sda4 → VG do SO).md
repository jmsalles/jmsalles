# 🚀 Migração e expansão com LVM (NVMe → VMs • SATA sda4 → VG do SO)

> **O que vamos fazer, em alto nível**
>
> 1. Preparar o **NVMe de 1 TB** para LVM e **adicioná-lo ao VG `vg_vms`**.
> 2. **Mover** todos os dados das VMs que hoje estão na **`/dev/sda4`** (SATA) para o **NVMe** (**`pvmove` online**, sem downtime).
> 3. Em vez de “descartar” a `sda4`, vamos **reaproveitá-la**:
>
>    * **remover `/dev/sda4` do `vg_vms`** (libera o PV),
>    * **adicioná-la ao VG do sistema** `rl_miwifi-r3600-srv`,
>    * **estender o LV de raiz** `rl_miwifi--r3600--srv-root` **até 250 GiB** (crescimento **online**).
>
> Tudo com **verificações**, **planos de rollback** e dicas de desempenho.
> Esse fluxo é seguro e pode ser feito **com VMs ligadas**; ainda assim, **prefira janela de baixo I/O e nobreak**.

---

## 🧭 Mapa visual (antes → depois)

```
ANTES
  vg_vms -> PV: /dev/sda4 (≈289 GiB)                 [VMs]
  rl_miwifi-r3600-srv -> PV: /dev/sda3 (≈170 GiB)    [/, /boot, swap]

DEPOIS
  vg_vms -> PV: /dev/nvme0n1p1 (≈931 GiB)            [VMs]
  rl_miwifi-r3600-srv -> PVs: /dev/sda3 + /dev/sda4  [/, /boot, swap]
                                    \
                                     -> LV root = 250 GiB (XFS)
```

---

## ✅ Pré-cheques rápidos

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
vgs
pvs -o+pv_used
lvs -o+devices
# (opcional) TRIM semanal ligado?
systemctl is-enabled fstrim.timer || true
```

> Confirme que:
> • `vg_vms` usa **/dev/sda4**;
> • `nvme0n1` está livre;
> • VG do SO chama-se **rl\_miwifi-r3600-srv** e o LV raiz é **rl\_miwifi--r3600--srv-root** (XFS).

---

## 1) 🧱 Preparar o **NVMe** para LVM

> Se o NVMe já tem uma partição LVM, **pule para o passo 2**.

```bash
dnf -y install gdisk
sgdisk -Z /dev/nvme0n1                               # (opcional) zera rótulos antigos
sgdisk -n 1:0:0 -t 1:8E00 -c 1:pv_vms_nvme /dev/nvme0n1
partprobe /dev/nvme0n1
lsblk -o NAME,SIZE,TYPE,PARTTYPE /dev/nvme0n1        # verifique nvme0n1p1 com tipo 8e00
```

---

## 2) ➕ Tornar o NVMe PV e **estender** o `vg_vms`

```bash
pvcreate /dev/nvme0n1p1
vgextend vg_vms /dev/nvme0n1p1
vgs
pvs -o+pv_used
```

> Agora o `vg_vms` tem espaço no NVMe para receber tudo que está em `/dev/sda4`.

---

## 3) 🔁 **Migrar** dados do SATA → NVMe (**online**)

```bash
# Mostra progresso a cada 10s, verboso
pvmove -i 10 -v /dev/sda4 /dev/nvme0n1p1
```

Acompanhe em outra sessão:

```bash
lvs -o+devices           # ao final, não deve mais aparecer /dev/sda4
pvs -o+pv_used
```

> **Dicas**
>
> * Pode levar tempo; evite operações pesadas nas VMs.
> * Para abortar (se necessário): `pvmove --abort` (os dados ficam onde já estavam).

---

## 4) 🔄 Reaproveitar a **/dev/sda4** no **VG do SO**

> Agora que a `sda4` está vazia no `vg_vms`, vamos **liberá-la**, **adicionar ao VG do SO** e **crescer o `/`**.

### 4.1) **Soltar** a `sda4` do `vg_vms`

```bash
vgreduce vg_vms /dev/sda4
pvs
vgs
```

> Obs.: **Não** rode `pvremove` — vamos reaproveitar o PV em outro VG.

### 4.2) **Anexar** a `sda4` ao VG do SO

```bash
vgextend rl_miwifi-r3600-srv /dev/sda4
vgs
pvs -o+pv_used
```

> Agora o VG **rl\_miwifi-r3600-srv** tem **/dev/sda3 + /dev/sda4**.
> Isso garante **extents livres** para aumentar o LV raiz.

---

## 5) ⬆️ **Estender** o LV raiz para **250 GiB** (XFS, online)

> Caminhos equivalentes do LV raiz (use um):
> • `/dev/rl_miwifi-r3600--srv/root`
> • `/dev/mapper/rl_miwifi--r3600--srv-root`

### 5.1) Ver o tamanho atual e espaço livre no VG

```bash
lvs /dev/rl_miwifi-r3600--srv/root
vgs rl_miwifi-r3600-srv
```

### 5.2) Crescer para **250 GiB**

```bash
# cresce LV e filesystem (XFS) de uma vez; se o -r falhar, veja a 5.3
lvextend -r -L 250G /dev/rl_miwifi-r3600--srv/root
```

### 5.3) (Plano B) Crescer em duas etapas

```bash
lvextend -L 250G /dev/rl_miwifi-r3600--srv/root
xfs_growfs /                                   # dentro do host (/, XFS)
```

### 5.4) Conferir

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'root|sda'
df -hT /
lvs /dev/rl_miwifi-r3600--srv/root
```

> **Importante:** XFS **não diminui**; só cresce. Tenha certeza do alvo **250 GiB**.

---

## 6) 🧷 Garantir boot tranquilo (initramfs)

> Como o LV raiz agora usa extents que podem estar em **sda4**, é prudente **regenerar o initramfs** para incluir qualquer dependência nova.

```bash
dracut -f   # regenera o initramfs do kernel atual
```

(Em seguida, teste um reboot de manutenção.)

---

## 7) 🧹 Pós-tarefas & qualidade de vida

* **TRIM/Discard** (SSD/NVMe):

  ```bash
  # LVM já deve ter issue_discards=1; garanta TRIM periódico:
  systemctl enable --now fstrim.timer
  fstrim -v /
  ```
* **Cockpit / libvirt** (para ver o novo espaço das VMs):

  ```bash
  virsh pool-refresh vms
  virsh pool-info vms
  ```
* **Relatórios**:

  ```bash
  lvs -o+devices
  vgs
  pvs -o+pv_used
  ```

---

## 🔁 Rollback / cenários especiais

* **Precisou voltar a sda4 para `vg_vms`**:
  `vgreduce rl_miwifi-r3600-srv /dev/sda4 && vgextend vg_vms /dev/sda4`
  (só faça se **não** houver extents do LV raiz ocupando a sda4; verifique com `lvs -o+devices`).

* **Faltou espaço no NVMe durante o `pvmove`**:
  Mova **LV por LV** em vez de tudo:
  `pvmove -n <LV> /dev/sda4 /dev/nvme0n1p1`

* **`lvextend -r` falhou com XFS**:
  Use a **5.3** (separar LV e `xfs_growfs`), que é a forma “canônica”.

---

## 🧪 Checklist final

* [ ] `pvmove` de `/dev/sda4` → `/dev/nvme0n1p1` concluído (sem `/dev/sda4` em `lvs -o+devices`).
* [ ] `vgreduce vg_vms /dev/sda4` feito.
* [ ] `vgextend rl_miwifi-r3600-srv /dev/sda4` feito.
* [ ] `lvextend -r -L 250G /dev/rl_miwifi-r3600--srv/root` OK.
* [ ] `df -hT /` mostra **≈250 GiB**.
* [ ] `dracut -f` executado.
* [ ] TRIM periódico ligado (`fstrim.timer` ativo).

---

### 💡 Dicas de performance

* Para o **pool das VMs** (agora no NVMe):
  use **RAW em LVM**, **cache=none**, **io=native**, **virtio-scsi** com filas e **iothreads** (você já está nessa linha 😉).
* Mantenha o **Cockpit/PCP** ligados para ver **I/O** durante o `pvmove` e evitar gargalos.

---

Se quiser, eu empacoto **todos os comandos** acima num **script único** que:

1. faz as validações,
2. executa `pvmove` com barra de progresso,
3. realoca a `sda4` para o VG do SO,
4. cresce o `/` para 250 GiB,
5. e imprime um **relatório final**.
