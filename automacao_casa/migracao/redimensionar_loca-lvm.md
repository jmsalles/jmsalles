Segue um tutorial completo para **redimensionar o `data` do Proxmox**, considerando o cenário em que o `data` é um **LVM-Thin Pool** e precisa ser reduzido, por exemplo de `794G` para `500G`.

---

# Tutorial — Redimensionar o `data` do Proxmox para 500G

## 1. Objetivo

Redimensionar o volume `data` do Proxmox, usado normalmente pelo storage `local-lvm`, para o tamanho de **500G**.

No Proxmox, o volume `data` geralmente é um **LVM-Thin Pool**, utilizado para armazenar discos de VMs e containers.

Exemplo inicial:

```bash
root@pve-dell:~# lvs
```

Saída esperada antes do ajuste:

```bash
LV    VG  Attr       LSize   Pool Origin Data% Meta% Move Log Cpy%Sync Convert
data  pve twi-a-tz-- 794.30g             0.00  0.24
root  pve -wi-ao---- 96.00g
swap  pve -wi-ao---- 8.00g
```

---

# 2. Atenção importante

O `data` do Proxmox é um **thin pool**.

Ele pode ser aumentado diretamente, mas **não pode ser reduzido com `lvreduce` ou `lvresize`**.

Ao tentar reduzir diretamente, o erro esperado é:

```bash
lvreduce -y -L 500G /dev/pve/data
```

Erro:

```bash
Thin pool volumes pve/data_tdata cannot be reduced in size yet.
```

Portanto, para reduzir o `data`, o procedimento correto é:

1. Confirmar que o `local-lvm` está vazio;
2. Desabilitar temporariamente o storage;
3. Remover o thin pool atual;
4. Recriar o thin pool `data` com o novo tamanho;
5. Reabilitar o storage no Proxmox.

---

# 3. Validar se o `local-lvm` está vazio

Antes de remover o `data`, valide se não existem discos de VMs ou containers usando esse storage.

Execute:

```bash
pvesm list local-lvm
```

Se o storage estiver vazio, não deve aparecer nenhum disco importante.

Depois, valide nas configurações das VMs e containers:

```bash
grep -R "local-lvm" /etc/pve/qemu-server /etc/pve/lxc 2>/dev/null
```

Se esse comando retornar alguma VM ou CT usando `local-lvm`, **não continue**, pois o procedimento apagaria os discos dessas máquinas.

---

# 4. Validar os volumes LVM

Execute:

```bash
lvs -a -o lv_name,vg_name,lv_attr,lv_size,pool_lv,origin,data_percent,metadata_percent
```

Exemplo:

```bash
lvs -a -o lv_name,vg_name,lv_attr,lv_size,pool_lv,origin,data_percent,metadata_percent
```

Verifique se o `data` está com `Data%` zerado ou sem uso relevante.

Exemplo esperado:

```bash
LV    VG  Attr       LSize   Pool Origin Data%  Meta%
data  pve twi-a-tz-- 794.30g             0.00   0.24
root  pve -wi-ao---- 96.00g
swap  pve -wi-ao---- 8.00g
```

---

# 5. Desabilitar temporariamente o storage `local-lvm`

Para evitar uso durante o procedimento:

```bash
pvesm set local-lvm --disable 1
```

Valide o status:

```bash
pvesm status
```

---

# 6. Remover o thin pool `data` atual

Execute:

```bash
lvremove -y /dev/pve/data
```

Esse comando remove o thin pool atual.

Atenção: se houver discos de VM/CT dentro dele, eles serão apagados. Por isso a validação anterior é obrigatória.

---

# 7. Recriar o `data` com 500G

Agora recrie o thin pool com o tamanho desejado:

```bash
lvcreate -L 500G -T pve/data
```

Esse comando cria novamente o volume `data` como **LVM-Thin Pool** dentro do volume group `pve`.

---

# 8. Reabilitar o storage no Proxmox

Após recriar o `data`, reabilite o storage:

```bash
pvesm set local-lvm --disable 0
```

---

# 9. Validar o resultado

Execute:

```bash
lvs
```

O resultado esperado deve ser semelhante a:

```bash
LV    VG  Attr       LSize   Pool Origin Data% Meta% Move Log Cpy%Sync Convert
data  pve twi-a-tz-- 500.00g             0.00  0.24
root  pve -wi-ao---- 96.00g
swap  pve -wi-ao---- 8.00g
```

Valide também o espaço livre no volume group:

```bash
vgs
```

E o status dos storages do Proxmox:

```bash
pvesm status
```

---

# 10. Caso o `local-lvm` não apareça no Proxmox

Se por algum motivo o storage `local-lvm` não aparecer mais no Proxmox, recrie o cadastro com:

```bash
pvesm add lvmthin local-lvm --vgname pve --thinpool data --content images,rootdir
```

Depois valide:

```bash
pvesm status
```

---

# 11. Comandos completos do procedimento

Use somente se o `local-lvm` estiver vazio:

```bash
pvesm list local-lvm
grep -R "local-lvm" /etc/pve/qemu-server /etc/pve/lxc 2>/dev/null
lvs -a -o lv_name,vg_name,lv_attr,lv_size,pool_lv,origin,data_percent,metadata_percent
pvesm set local-lvm --disable 1
lvremove -y /dev/pve/data
lvcreate -L 500G -T pve/data
pvesm set local-lvm --disable 0
lvs
vgs
pvesm status
```

---

# 12. Observação sobre aumento do `data`

Para aumentar o `data`, o procedimento é diferente e pode ser feito diretamente com `lvextend`.

Exemplo para aumentar para `700G`:

```bash
lvextend -L 700G /dev/pve/data
```

Ou para usar todo o espaço livre do VG:

```bash
lvextend -l +100%FREE /dev/pve/data
```

Mas para **reduzir**, como no caso de `794G` para `500G`, o Proxmox/LVM não permite redução direta do thin pool. Por isso foi necessário remover e recriar o `data`.

---

# 13. Resumo final

O erro abaixo é esperado ao tentar reduzir diretamente um LVM-Thin Pool:

```bash
Thin pool volumes pve/data_tdata cannot be reduced in size yet.
```

A solução correta é:

```bash
pvesm set local-lvm --disable 1
lvremove -y /dev/pve/data
lvcreate -L 500G -T pve/data
pvesm set local-lvm --disable 0
```

Depois validar com:

```bash
lvs
vgs
pvesm status
```

Com isso, o `data` do Proxmox fica redimensionado para **500G**, e o restante do espaço retorna como livre no volume group `pve`.
