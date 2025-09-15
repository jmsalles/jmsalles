Perfeito, Jeferson 👌
Vou montar o tutorial completo no **seu template fixo em Markdown** — cobrindo a migração da VM `vm-lenovoi7-zabbix` do host antigo (discos LVM) para o novo host (discos em arquivos qcow2/raw) e já incluindo a criação da **bridge `br0`**.

---

# 🖥️ Tutorial de Migração da VM `vm-lenovoi7-zabbix`

---

## 📌 Resumo

Este guia documenta o processo de **migração da VM `vm-lenovoi7-zabbix`** de um host com discos LVM para um novo host com discos em arquivo (`qcow2`), incluindo a criação e configuração da **bridge `br0`** para acesso de rede.

---

## 📑 Sumário

* [1. Pré-requisitos](#1-pré-requisitos)
* [2. Exportar discos da VM (host origem)](#2-exportar-discos-da-vm-host-origem)
* [3. Copiar discos para o novo host](#3-copiar-discos-para-o-novo-host)
* [4. Ajustar XML da VM](#4-ajustar-xml-da-vm)
* [5. Criar e configurar bridge `br0`](#5-criar-e-configurar-bridge-br0)
* [6. Importar VM no novo host](#6-importar-vm-no-novo-host)
* [7. Validar funcionamento](#7-validar-funcionamento)
* [8. Checklist final](#8-checklist-final)

---

## 1. Pré-requisitos

* Acesso root ou sudo nos dois hosts.
* Pacote `qemu-kvm` e `libvirt` instalados.
* Rede já definida: IP fixo do novo host `192.168.31.36/24` com gateway `192.168.31.1`.

---

## 2. Exportar discos da VM (host origem)

Listar discos usados:

```bash
sudo virsh domblklist vm-lenovoi7-zabbix
```

Converter volumes LVM para arquivos qcow2:

```bash
sudo qemu-img convert -p -f raw -O qcow2 /dev/vg_vms/lv_vm_lenovoi7_zbx_os   /tmp/vm-lenovoi7-zabbix_os.qcow2
sudo qemu-img convert -p -f raw -O qcow2 /dev/vg_vms/lv_vm_lenovoi7_zbx_pg   /tmp/vm-lenovoi7-zabbix_pg.qcow2
sudo qemu-img convert -p -f raw -O qcow2 /dev/vg_vms/lv_vm_lenovoi7-zbx_graf /tmp/vm-lenovoi7-zabbix_graf.qcow2
```

Exportar XML:

```bash
sudo virsh dumpxml vm-lenovoi7-zabbix > vm-lenovoi7-zabbix.xml
```

---

## 3. Copiar discos para o novo host

```bash
rsync -avh --progress /tmp/vm-lenovoi7-zabbix_* jmsalles@192.168.31.36:/mnt/vms/
```

---

## 4. Ajustar XML da VM

No arquivo `vm-lenovoi7-zabbix.xml`, alterar discos de `block` → `file`:

Exemplo:

```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none' io='native'/>
  <source file='/mnt/vms/vm-lenovoi7-zabbix_os.qcow2'/>
  <target dev='sda' bus='scsi'/>
</disk>
```

Fazer o mesmo para `sdb` e `sdc`.

Trocar interface de rede de:

```xml
<source bridge='br0'/>
```

(Mantém igual, pois vamos criar a `br0` no destino).

---

## 5. Criar e configurar bridge `br0`

### 5.1 Remover configs antigas (se existirem)

```bash
nmcli con del br0 || true
nmcli con del bridge-slave-eno1 || true
```

### 5.2 Criar bridge com IP fixo

```bash
nmcli con add type bridge ifname br0 con-name br0 ipv4.method manual \
  ipv4.addresses 192.168.31.36/24 ipv4.gateway 192.168.31.1 ipv4.dns 192.168.31.1 ipv6.method ignore
```

### 5.3 Adicionar `eno1` como slave

```bash
nmcli con add type bridge-slave ifname eno1 con-name br0-slave-eno1 master br0
```

### 5.4 Subir conexões

```bash
nmcli con up br0-slave-eno1
nmcli con up br0
```

---

## 6. Importar VM no novo host

```bash
sudo virsh define /tmp/vm-lenovoi7-zabbix.xml
sudo virsh start vm-lenovoi7-zabbix
```

---

## 7. Validar funcionamento

### No host

```bash
ip addr show br0
ping -c 3 192.168.31.1
ping -c 3 8.8.8.8
```

### Dentro da VM

```bash
ip addr
ping -c 3 192.168.31.1
ping -c 3 8.8.8.8
```

---

## 8. Checklist final ✅

* [ ] `br0` com IP fixo ativo.
* [ ] `eno1` como slave, sem IP.
* [ ] VM importada e iniciada.
* [ ] Discos apontando para `/mnt/vms`.
* [ ] VM com acesso de rede interno e externo.
* [ ] Configuração persistente após reboot.

---

✍️

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)

---

👉 Quer que eu já te entregue também um **script automatizado** (`migrar_vm_lenovoi7_zabbix.sh`) que faça todos esses passos (converter, copiar, criar XML, configurar br0, importar a VM) de forma semi-automática?
