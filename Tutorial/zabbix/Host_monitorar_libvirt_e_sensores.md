# **Guia — Monitorar o host i7lenovo no Zabbix (Plano B: libvirt sem collectd)**

**Servidor Zabbix/Web**: `http://192.168.31.35`  
**Host a monitorar**: `i7lenovo` (hypervisor com libvirt/KVM)  
**Agente**: Zabbix **Agent 2**  
**Sensores**: S.M.A.R.T. (discos) + `templates_sensores` (CPU/FAN/voltagens)  
**Libvirt**: **Plano B** — coletor *bushvin/zabbix-kvm-res* (sem collectd)

---

## 0) Premissas
- Você já tem o Zabbix Server/Web operando (7.x).  
- No host **i7lenovo** você tem acesso root via shell.  
- SELinux: se estiver *enforcing* e der bloqueio no acesso ao libvirt/smartctl, considere **desabilitar** ou criar exceções (este guia assume ambiente permissivo).

---

## 1) Repositório Zabbix 7.4 (EL10) e Agent 2
**No i7lenovo:**
```bash
# habilitar Zabbix repo 7.4 (EL10)
sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.4/stable/alma/10/x86_64/zabbix-release-latest-7.4.el10.noarch.rpm || \
sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.4/release/alma/10/noarch/zabbix-release-latest-7.4.el10.noarch.rpm

sudo dnf clean all && sudo dnf makecache
sudo dnf -y install zabbix-agent2
```

Configurar o Agent 2 apontando para o seu Zabbix (`192.168.31.35`) e usando **o hostname do próprio host** automaticamente:
```bash
HN="$(hostname -s)"   # use 'hostname -f' se quiser FQDN
sudo sed -i -E \
  -e "s|^#?Server=.*|Server=192.168.31.35|" \
  -e "s|^#?ServerActive=.*|ServerActive=192.168.31.35|" \
  -e "s|^#?Hostname=.*|Hostname=${HN}|" \
  /etc/zabbix/zabbix_agent2.conf
grep -q '^Hostname=' /etc/zabbix/zabbix_agent2.conf || echo "Hostname=${HN}" | sudo tee -a /etc/zabbix/zabbix_agent2.conf

sudo systemctl enable --now zabbix-agent2
```

**Vincular template base (UI):**  
- **Dados coletados → Hosts → (i7lenovo) → Templates → Link templates →** `Linux by Zabbix agent` → **Salvar**.  

---

## 2) Discos S.M.A.R.T. (temperatura/saúde)
Instalar `smartmontools` e configurar o **plugin SMART** do Agent 2 com **sintaxe correta**:
```bash
sudo dnf -y install smartmontools
sudo install -d /etc/zabbix/zabbix_agent2.d/plugins.d

# sem cabeçalhos e sem 'Enable' (não existe);
# use APENAS as chaves abaixo:
sudo tee /etc/zabbix/zabbix_agent2.d/plugins.d/smart.conf >/dev/null <<'EOF'
Plugins.Smart.Path=/usr/sbin/smartctl
Plugins.Smart.Timeout=10
EOF

# (se o agent roda como 'zabbix' e o smartctl exigir privilégio, habilite sudo sem senha só para esse binário)
# echo 'zabbix ALL=(ALL) NOPASSWD:/usr/sbin/smartctl' | sudo tee /etc/sudoers.d/zabbix-smartctl

sudo systemctl restart zabbix-agent2
```

**Vincular template (UI):**  
- **Dados coletados → Templates → Import** (botão no topo direito), se precisar importar.  
- **No host i7lenovo → Templates → Link templates →** `SMART by Zabbix agent 2` → **Salvar**.

**Checks rápidos:**
```bash
sudo /usr/sbin/smartctl --version
sudo /usr/sbin/smartctl --scan
journalctl -u zabbix-agent2 -e | tail -n 50
```

---

## 3) Sensores de CPU/FAN/Voltagens — `templates_sensores`
Usaremos o projeto **zabbix-sensors** (script `sensors.py` lendo **/sys**).

```bash
sudo dnf -y install git python3

cd /opt && sudo git clone https://github.com/blind-oracle/zabbix-sensors.git
cd /opt/zabbix-sensors

# instalar o script (o arquivo correto é sensors.py — não existe pasta scripts/)
sudo install -m 0755 sensors.py /usr/local/bin/zabbix-sensors.py

# instalar UserParameters para o agent2
sudo install -d /etc/zabbix/zabbix_agent2.d
sudo install -m 0644 sensors.conf /etc/zabbix/zabbix_agent2.d/zabbix-sensors.conf

# ajustar o conf para python3 + caminho do script instalado
sudo sed -i -E \
  -e 's#/usr/bin/python([0-9])?#/usr/bin/python3#g' \
  -e 's#[[:space:]](\.\/)?sensors\.py# /usr/local/bin/zabbix-sensors.py#g' \
  -e 's#/opt/zabbix-sensors/sensors\.py#/usr/local/bin/zabbix-sensors.py#g' \
  /etc/zabbix/zabbix_agent2.d/zabbix-sensors.conf

# garantir inclusão de *.conf (caso seu agent2.conf não tenha)
grep -E '^Include=' /etc/zabbix/zabbix_agent2.conf || echo 'Include=/etc/zabbix/zabbix_agent2.d/*.conf' | sudo tee -a /etc/zabbix/zabbix_agent2.conf

sudo systemctl restart zabbix-agent2
```

**Vincular template (UI):**  
- **Dados coletados → Templates → Import** (botão no topo direito) → importe `template_sensors_6.4.xml` do repositório clonado.  
- **No host i7lenovo → Templates → Link templates →** `templates_sensores` → **Salvar**.

**Checks rápidos:**
```bash
python3 /usr/local/bin/zabbix-sensors.py -h || true
sudo -u zabbix python3 /usr/local/bin/zabbix-sensors.py -h || true
journalctl -u zabbix-agent2 -e | tail -n 50
```

---

## 4) Libvirt/KVM — **Plano B (sem collectd): bushvin/zabbix-kvm-res**
Coletor em Python usando `libvirt`, expondo métricas por **UserParameters** no Agent 2.

### 4.1) Instalação e permissões
```bash
sudo dnf -y install libvirt-client python3-libvirt git

cd /opt && sudo git clone https://github.com/bushvin/zabbix-kvm-res.git

# instalar coletor + UserParameters
sudo install -m 0755 /opt/zabbix-kvm-res/bin/zabbix-libvirt-res.py /usr/local/bin/zabbix-libvirt-res.py
sudo install -m 0644 /opt/zabbix-kvm-res/zabbix_agentd.conf/libvirt.conf /etc/zabbix/zabbix_agent2.d/libvirt.conf

# garantir que o caminho do script no conf aponta para /usr/local/bin
sudo sed -i 's#/opt/zabbix-kvm-res/bin/zabbix-libvirt-res.py#/usr/local/bin/zabbix-libvirt-res.py#g' \
  /etc/zabbix/zabbix_agent2.d/libvirt.conf

# dar acesso ao libvirt para o usuário 'zabbix' (socket qemu:///system)
sudo usermod -aG libvirt zabbix

# reiniciar serviços
sudo systemctl restart libvirtd
sudo systemctl restart zabbix-agent2
```

**Teste de acesso ao libvirt como zabbix:**
```bash
sudo -u zabbix virsh -c qemu:///system list --all || echo "permission denied? verifique grupo libvirt e SELinux"
```

### 4.2) Templates e vinculação (UI)
- **Dados coletados → Templates → Import** → importe **`/opt/zabbix-kvm-res/zbx_templates/zabbix_libvirt-4.xml`**.  
- **No host i7lenovo → Templates → Link templates →** selecione o template importado → **Salvar**.

**Ver as chaves instaladas e testar via zabbix_get:**
```bash
grep -n '^UserParameter' /etc/zabbix/zabbix_agent2.d/libvirt.conf

# exemplo de discovery (ajuste o IP se o agent escuta em outro):
zabbix_get -s 192.168.31.35 -k 'libvirt.domains.discovery' || true
```

---

## 5) Checks finais & Troubleshooting
**Na UI:** *Dados coletados → Hosts → i7lenovo → Latest data*  
- Você deve ver: itens de **SO**, **SMART** (por disco), **templates_sensores** (CPU/FAN), e **libvirt** (máquinas virtuais).

**Linhas de comando úteis:**
```bash
# Agent 2
sudo systemctl status zabbix-agent2 --no-pager
journalctl -u zabbix-agent2 -e | tail -n 80

# Libvirt
sudo -u zabbix virsh -c qemu:///system list --all

# SMART
sudo /usr/sbin/smartctl --scan
```

**Erros comuns:**
- `Cannot read configuration: ... smart.conf: missing assignment operator`  
  → Remova cabeçalhos tipo `[Plugins.Smart]`; use **apenas** `Plugins.Smart.Path=/usr/sbin/smartctl` e `Plugins.Smart.Timeout=10`.
- `unknown parameter Plugins.Smart.Enable`  
  → A opção **Enable** **não existe** no plugin SMART do Agent 2.
- `permission denied` ao `virsh` como `zabbix`  
  → Falta o grupo `libvirt` para o usuário *zabbix* ou SELinux bloqueando.
- `templates_sensores` sem dados  
  → Confira o caminho do `zabbix-sensors.py` no conf, Python 3 e permissões de leitura em `/sys`.

---

_© Template Lenovo i7 — `vm-lenovoi7-zabbix` — revisão: agora._
