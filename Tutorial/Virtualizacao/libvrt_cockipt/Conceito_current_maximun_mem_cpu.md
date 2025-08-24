# 🧠 **current** vs **maximum** em VMs KVM/libvirt (Cockpit)

*Guia visual e prático em Markdown*

> **Ideia-chave:**
> **maximum** é o **teto permitido** (limite superior) de CPU/memória da VM.
> **current** é **quanto a VM tem ativo agora**.
> Você pode **aumentar/diminuir o *current*** (até o *maximum*) **ao vivo**, se o guest suportar hot-plug. Para **elevar o *maximum***, quase sempre é preciso **desligar** a VM.

---

## 📌 TL;DR (cartões rápidos)

* 🧮 **Memória**

  * **maximum** = `<memory>` → teto de RAM permitida
  * **current**  = `<currentMemory>` → RAM ativa agora
  * **Hot-plug**: precisa **virtio-balloon**/**virtio-mem** no guest.

* ⚙️ **vCPU**

  * **maximum** = `<vcpu>` (e/ou `--maximum`) → teto de vCPUs
  * **current**  = atributo `current="N"` em `<vcpu>` → vCPUs ativas
  * **Hot-plug**: depende do SO convidado (Linux moderno: ok; Windows: Pro/Enterprise/Server).

---

## 🧭 Mapa mental

```
     ┌───────────────────────────────────┐  ← maximum (teto)
     │                                   │
     │        recursos disponíveis       │
     │         (podem crescer)           │
     │        ▲                          │
     │        │ current (agora)          │
     └────────┴──────────────────────────┘
```

---

## 🧠 Memória: *current* × *maximum*

### 📖 Conceitos

* **`<memory>` (maximum):** quanto **a VM pode ter no máximo**.
* **`<currentMemory>` (current):** quanto **está alocado agora**.
* **Aumentar/diminuir `current`** pode ser **online** (balloon/hot-plug).
* **Elevar `maximum`** geralmente **pede VM desligada**.

### 🔧 Requisitos para ajuste **online**

* Guest com **virtio-balloon** (para ajustar *current*) ou **virtio-mem** (hot-plug granular).
* Kernel/SO com suporte a **memory hotplug**.
* Em hosts com **hugepages dedicadas**, o balloon **não devolve** páginas fixas; prefira **virtio-mem** para crescer.

### 🧾 XML mínimo (exemplo)

```xml
<memory unit='GiB'>16</memory>          <!-- maximum -->
<currentMemory unit='GiB'>8</currentMemory>  <!-- current -->
<devices>
  <memballoon model='virtio'/>          <!-- virtio-balloon -->
</devices>
```

### 🖥️ Cockpit (onde clicar)

**Virtual machines → (VM) → Editar → Memory**

* *Maximum memory* = teto
* *Current allocation* = ativa agora

> Se o botão de aplicar online não aparecer, faça **Stop → Edit → Start** após mudar o maximum.

### 🧪 Exemplos práticos (CLI)

```bash
# Ver estado
virsh dominfo <vm>

# Crescer current (ao vivo, até o teto)
virsh setmem <vm> 12G --live
# Persistir para o próximo boot
virsh setmem <vm> 12G --config

# Elevar o máximo (VM parada, persiste)
virsh setmaxmem <vm> 24G --config
# Depois suba a VM e ajuste o current se desejar
```

---

## ⚙️ vCPU: *current* × *maximum*

### 📖 Conceitos

* **`<vcpu>` (maximum):** **teto** de vCPUs.
* **`<vcpu current="N">` (current):** **ativas agora**.
* **Hot-add/Hot-remove** de vCPU: depende do **guest** (Linux: ok; Windows: edições Pro/Enterprise/Server).

### 🧾 XML mínimo (exemplo)

```xml
<vcpu placement='static' current='4'>8</vcpu>  <!-- current=4, maximum=8 -->
<cpu mode='host-passthrough'>                   <!-- melhor desempenho -->
  <topology sockets='1' cores='4' threads='2'/> <!-- ex.: 8 vCPU = 1x4x2 -->
</cpu>
```

> **Regra de ouro da topologia:** `vcpus = sockets × cores × threads`.
> Ex.: 6 vCPU = `sockets=1, cores=3, threads=2`.

### 🖥️ Cockpit (onde clicar)

**Virtual machines → (VM) → Editar → CPUs**

* *Maximum* (teto) e *Current* (ativas). Ajuste a topologia se precisar.

### 🧪 Exemplos práticos (CLI)

```bash
# Ver estado
virsh dominfo <vm>

# Ativar mais vCPUs ao vivo (até o teto)
virsh setvcpus <vm> 6 --live

# Persistir para o próximo boot
virsh setvcpus <vm> 6 --config

# Elevar o teto (geralmente com a VM desligada)
virsh setvcpus <vm> 10 --maximum --config
```

---

## 🗂️ Tabela de referência rápida

| Ação                        | Pode ser **online**? | Requer **guest suporte**? | Notas                               |
| --------------------------- | :------------------: | :-----------------------: | ----------------------------------- |
| Aumentar **current memory** |           ✅          |   ✅ (balloon/virtio-mem)  | Até o **maximum**                   |
| Diminuir **current memory** |           ✅          |        ✅ (balloon)        | Nem todo guest reduz imediatamente  |
| Elevar **maximum memory**   |           ⛔          |             —             | Desligar VM; editar `<memory>`      |
| Aumentar **current vCPU**   |           ✅          |             ✅             | Até o **maximum**                   |
| Diminuir **current vCPU**   |          ☑️          |             ✅             | Alguns guests pedem reboot/serviços |
| Elevar **maximum vCPU**     |           ⛔          |             —             | Normalmente com a VM desligada      |

---

## 🧷 Boas práticas & pegadinhas

* **Planeje o *maximum***: deixe folga (ex.: teto 16 GiB para operar entre 8–12 GiB).
* **host-passthrough** na CPU → melhor desempenho.
* **NUMA/Pinagem**: só se necessário; comece simples.
* **Hugepages**: ganho em cargas pesadas; lembre-se do efeito sobre balloon.
* **Windows**: hot-add de CPU/memória depende da edição/licenciamento.
* **Monitoramento**: acompanhe em **Cockpit → Desempenho (PCP)** durante hot-add.

---

## 🛠️ Exemplos completos

### 1) *Memory*: 8 GiB → 12 GiB agora; teto 16 GiB

```bash
# conferir
virsh dominfo <vm>

# elevar current (ao vivo)
virsh setmem <vm> 12G --live
# persistir no próximo boot
virsh setmem <vm> 12G --config
```

### 2) *Memory*: elevar o teto 16 GiB → 24 GiB

```bash
virsh shutdown <vm>
virsh setmaxmem <vm> 24G --config
virsh start <vm>
# opcional: subir current
virsh setmem <vm> 16G --live --config
```

### 3) *vCPU*: de 4 ativas (teto 8) para 6 ativas

```bash
virsh setvcpus <vm> 6 --live
virsh setvcpus <vm> 6 --config
```

### 4) *vCPU*: elevar teto 8 → 10

```bash
virsh shutdown <vm>
virsh setvcpus <vm> 10 --maximum --config
virsh start <vm>
```

---

## 🧪 Verificação e diagnóstico

```bash
# Estado geral
virsh dominfo <vm>

# XML dos campos relevantes
virsh dumpxml <vm> | sed -n '/<memory/,/<\/memory>/p'
virsh dumpxml <vm> | sed -n '/<vcpu/,/<\/vcpu>/p'
virsh dumpxml <vm> | sed -n '/<memballoon/,/\/>/p'
```

**Se não mudar online:**

* Falta **virtio-balloon/virtio-mem**?
* Guest **não** suporta hot-plug?
* Em Cockpit, tente **“Acesso administrativo”** (elevação) antes de aplicar.

---

## 🎯 Resumo final

* **maximum** = **limite superior permitido** (definido no XML; usualmente requer **VM desligada** para aumentar).
* **current** = **alocação ativa agora** (pode ajustar **online** com suporte do guest).
* Use o Cockpit para ajustes simples e **virsh** para configurações finas/automatização.

---

### 🧩 Mini-checklist (antes de mexer online)

* [ ] Guest com **virtio-balloon**/**virtio-mem** (memória)
* [ ] Edição do **CPU mode** = `host-passthrough` (desempenho)
* [ ] **Acesso administrativo** no Cockpit ou **sudo** no shell
* [ ] Monitor **PCP** aberto para ver impacto (CPU/RAM/I/O)

---

Se quiser, eu gero um **snippet de XML** pronto para a sua VM (com balloon, host-passthrough e topologia ajustada), e os **comandos `virsh`** exatos para o cenário que você escolher.
