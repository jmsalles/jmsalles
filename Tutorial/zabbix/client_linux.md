Boa Jeferson 👌 — você quer automatizar a configuração do **Zabbix Agent 2** usando o **hostname da própria máquina** e editar o arquivo `zabbix_agent2.conf` via `sed`.

Aqui vai o passo a passo:

---

# 📘 Instalação e Configuração Automática – Zabbix Agent 2 no Rocky 10

## 🔹 1. Instalar repositório e agente

```bash
sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.4/release/rhel/10/noarch/zabbix-release-latest.el10.noarch.rpm
sudo dnf clean all
sudo dnf install -y zabbix-agent2
```

---

## 🔹 2. Definir variáveis

Aqui você define o **servidor Zabbix** e pega o **hostname da máquina automaticamente**:

```bash
ZBX_SERVER="192.168.31.35"
HOSTNAME=$(hostname -s)
```

* `hostname -s` → pega apenas o nome curto (ex: `vm-lenovoi7-zabbix`).
* Se quiser o FQDN, troque para `hostname -f`.

---

## 🔹 3. Editar `zabbix_agent2.conf` com `sed`

```bash
sudo sed -i "s/^Server=.*/Server=${ZBX_SERVER}/" /etc/zabbix/zabbix_agent2.conf
sudo sed -i "s/^ServerActive=.*/ServerActive=${ZBX_SERVER}/" /etc/zabbix/zabbix_agent2.conf
sudo sed -i "s/^Hostname=.*/Hostname=${HOSTNAME}/" /etc/zabbix/zabbix_agent2.conf
```

🔍 Explicação:

* `s/^Server=.*/Server=.../` → substitui a linha `Server=` pelo valor da variável.
* Faz o mesmo para `ServerActive` e `Hostname`.

---

## 🔹 4. Ativar e iniciar o agente

```bash
sudo systemctl enable --now zabbix-agent2
sudo systemctl status zabbix-agent2
```

---

## 🔹 5. Ajustar firewall

```bash
sudo firewall-cmd --permanent --add-port=10050/tcp
sudo firewall-cmd --reload
```

---

## 🔹 6. Testar comunicação

Do servidor Zabbix, rode:

```bash
zabbix_get -s <IP_DO_CLIENTE> -k agent.ping
```

Se retornar `1`, a conexão está OK ✅.

---

👉 Quer que eu prepare um **script único** (`install_zabbix_agent2.sh`) que já faça tudo isso de uma vez (instala, configura com variáveis e sobe o serviço), para você só rodar no Rocky 10?
