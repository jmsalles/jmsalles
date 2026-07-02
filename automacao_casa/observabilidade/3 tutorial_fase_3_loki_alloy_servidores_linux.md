# Tutorial — Fase 3 — Coleta de Logs de Servidores Linux com Grafana Alloy

## 1. Identificação do documento

| Item | Informação |
|---|---|
| Ambiente | Homelab |
| Fase | Fase 3 |
| Objetivo | Coletar logs de servidores Linux e enviar para Loki |
| Servidor central de logs | `observabilidade` |
| IP do Loki | `192.168.31.17` |
| DNS do Grafana | `logs.jmsalles.homelab.br` |
| URL do Grafana | `https://logs.jmsalles.homelab.br` |
| Endpoint Loki para ingestão | `http://192.168.31.17:3100/loki/api/v1/push` |
| Coletor | Grafana Alloy |
| Modelo de instalação | Pacote RPM com serviço systemd |
| Arquivo de configuração | `/etc/alloy/config.alloy` |
| Serviço systemd | `alloy.service` |
| Storage path padrão | `/var/lib/alloy` |
| SELinux | Desabilitado no padrão do homelab |
| Firewall local | Desabilitado no padrão do homelab |

---

## 2. Objetivo

Implantar o **Grafana Alloy** como serviço systemd nos servidores Linux do homelab para coletar logs do sistema operacional e enviar para o Loki central.

A partir desta fase, o Grafana em:

```text
https://logs.jmsalles.homelab.br
```

passará a exibir logs de servidores Linux, como:

```text
/var/log/messages
/var/log/secure
/var/log/cron
/var/log/dnf.log
/var/log/yum.log
/var/log/audit/audit.log
/var/log/k8s-backup/*.log
```

A fase 2 coletou logs de containers Docker/Portainer.  
A fase 3 coleta logs do **sistema operacional Linux**.

---

## 3. Escopo da Fase 3

Esta fase contempla:

```text
1. Instalação do Grafana Alloy via RPM
2. Configuração do Alloy como serviço systemd
3. Coleta de logs Linux via loki.source.file
4. Envio dos logs para Loki central
5. Padronização de labels para servidores Linux
6. Validação via Loki API
7. Validação via Grafana
8. Consultas LogQL úteis para Linux
9. Backup da configuração do Alloy
10. Troubleshooting
11. Script de instalação padronizado para replicação
```

Esta fase ainda não contempla:

```text
Coleta de logs de pods Kubernetes
Eventos do Kubernetes
Logs de /var/log/containers
Logs de /var/log/pods
Dashboards avançados
Alertas no Grafana
Integração com Zabbix
```

Os logs do Kubernetes ficarão para a **Fase 4**.

---

## 4. Diferença entre as fases

| Fase | Foco | Coletor | Modelo |
|---|---|---|---|
| Fase 1 | Loki + Grafana central | Alloy local | Docker Compose na VM `observabilidade` |
| Fase 2 | Docker / Portainer | Alloy container | Docker Compose no host Docker |
| Fase 3 | Servidores Linux | Alloy RPM | Serviço systemd no Linux |
| Fase 4 | Kubernetes | Alloy no cluster | DaemonSet ou Helm |

---

## 5. Arquitetura da Fase 3

```text
+-------------------------------------------------------------+
| Servidor Linux                                              |
| Exemplo: lenovo-server-linux                                |
|                                                             |
|  +----------------------+                                   |
|  | /var/log/messages    |                                   |
|  | /var/log/secure      |                                   |
|  | /var/log/cron        |                                   |
|  | /var/log/audit       |                                   |
|  +----------+-----------+                                   |
|             |                                               |
|             v                                               |
|  +----------------------+                                   |
|  | Grafana Alloy        |                                   |
|  | Serviço systemd      |                                   |
|  | /etc/alloy/config    |                                   |
|  +----------+-----------+                                   |
|             |                                               |
|             | HTTP Push                                     |
|             v                                               |
+-------------+-----------------------------------------------+
              |
              | http://192.168.31.17:3100/loki/api/v1/push
              v
+-------------------------------------------------------------+
| VM observabilidade                                          |
| IP: 192.168.31.17                                           |
|                                                             |
|  +----------------------+       +-------------------------+ |
|  | Loki                 | <---- | Grafana                 | |
|  | Porta 3100           |       | Publicado via Nginx     | |
|  +----------------------+       +-------------------------+ |
+-------------------------------------------------------------+
              ^
              |
              | https://logs.jmsalles.homelab.br
              |
+-------------+-----------------------------------------------+
| Nginx reverse proxy                                         |
+-------------------------------------------------------------+
```

---

## 6. Hosts Linux sugeridos para esta fase

Começar por um host piloto e depois replicar.

### 6.1. Host piloto recomendado

```text
lenovo-server-linux
```

Motivo:

```text
É um servidor Linux principal do homelab.
Possui serviços e logs relevantes.
É bom para validar a coleta antes de replicar para todos.
```

### 6.2. Hosts candidatos

| Host | IP | Observação |
|---|---:|---|
| `lenovo-server-linux` | `192.168.31.31` | Hypervisor/servidor principal |
| `hpi7` / `hp-i7` | `192.168.31.36` | Host físico onde roda a VM observabilidade |
| `docker-hml` | `192.168.31.37` | Já tem coleta Docker na fase 2; pode receber também coleta Linux |
| `dell` / `dell-novo` | `192.168.31.38` | Servidor Linux/homelab |
| `k8s-cp1` | Conforme ambiente | Coleta apenas de logs do SO nesta fase |
| `k8s-w1` | Conforme ambiente | Coleta apenas de logs do SO nesta fase |
| `k8s-w2` | Conforme ambiente | Coleta apenas de logs do SO nesta fase |

Observação:

```text
Nos nós Kubernetes, esta fase coleta logs do Linux.
A coleta de pods, containers do Kubernetes, namespaces e eventos ficará para a Fase 4.
```

---

## 7. Padrão de labels da Fase 3

Labels são fundamentais para consultas eficientes no Loki.

### 7.1. Labels usadas

| Label | Exemplo | Função |
|---|---|---|
| `env` | `homelab` | Ambiente |
| `source` | `linux` | Origem geral |
| `host` | `lenovo-server-linux` | Host curto |
| `fqdn` | `lenovo-server-linux.jmsalles.homelab.br` | FQDN |
| `job` | `linux-system` | Grupo de coleta |
| `log_type` | `messages` | Tipo do log |
| `role` | `linux-server` | Perfil lógico do host |

### 7.2. Labels que devem ser evitadas

Evitar usar como label:

```text
IP dinâmico
PID
timestamp
request_id
user_id
session_id
trace_id
container_id
nome de arquivo rotacionado muito variável
```

Motivo:

```text
Esses valores aumentam a cardinalidade no Loki.
Cardinalidade alta degrada consulta, indexação e consumo de recursos.
```

---

## 8. Arquivos coletados na configuração padrão

| Arquivo | Label `log_type` | Uso |
|---|---|---|
| `/var/log/messages` | `messages` | Logs gerais do sistema |
| `/var/log/secure` | `secure` | SSH, sudo, autenticação |
| `/var/log/cron` | `cron` | Execuções agendadas |
| `/var/log/dnf.log` | `dnf` | Instalação/atualização de pacotes |
| `/var/log/yum.log` | `yum` | Logs yum em sistemas compatíveis |
| `/var/log/audit/audit.log` | `audit` | Auditoria do sistema |
| `/var/log/k8s-backup/*.log` | `k8s-backup` | Backup etcd/k8s, quando existir |

Observação:

```text
Se algum arquivo não existir em determinado host, a coleta simplesmente não terá dados daquele tipo.
```

---

## 9. Decisão sobre permissões

No Linux, arquivos como:

```text
/var/log/secure
/var/log/audit/audit.log
```

normalmente possuem acesso restrito.

Para homelab, adotaremos o modelo mais simples:

```text
Executar o serviço Alloy como root.
```

Motivo:

```text
Facilita a leitura de todos os logs necessários.
Evita necessidade de ACLs em cada arquivo.
Evita problema com rotação de logs.
É coerente com o padrão atual do homelab.
```

Em ambiente corporativo, o ideal seria avaliar ACLs, grupos específicos e hardening do serviço.

---

## 10. Pré-requisitos

No host Linux onde será instalado o Alloy:

```text
Acesso SSH
Permissão sudo/root
Conectividade com 192.168.31.17:3100
DNS funcionando
Sistema Rocky/RHEL/Oracle Linux preferencialmente
SELinux/firewall seguindo padrão do homelab
```

Validar conectividade com Loki:

```bash
curl -s http://192.168.31.17:3100/ready
```

Resultado esperado:

```text
ready
```

---

# 11. Instalação manual — passo a passo

## 11.1. Acessar o host Linux

Exemplo com `lenovo-server-linux`:

```bash
ssh jmsalles@lenovo-server-linux.jmsalles.homelab.br
```

ou:

```bash
ssh jmsalles@192.168.31.31
```

Elevar para root:

```bash
sudo -i
```

Validar hostname:

```bash
hostname
hostname -f
```

Validar IP:

```bash
ip -br addr
```

Validar sistema operacional:

```bash
cat /etc/redhat-release 2>/dev/null || cat /etc/os-release
```

---

## 11.2. Validar conectividade com Loki

```bash
curl -s http://192.168.31.17:3100/ready
```

Resultado esperado:

```text
ready
```

Se não retornar `ready`, testar rota:

```bash
ping -c 3 192.168.31.17
```

Testar porta:

```bash
curl -v http://192.168.31.17:3100/ready
```

---

## 11.3. Instalar pacotes básicos

```bash
dnf install -y wget curl jq vim tar gzip dnf-plugins-core
```

Validar:

```bash
which wget
which curl
which jq
```

---

## 11.4. Adicionar repositório Grafana

Importar chave GPG:

```bash
wget -q -O /tmp/grafana-gpg.key https://rpm.grafana.com/gpg.key
rpm --import /tmp/grafana-gpg.key
```

Criar repositório:

```bash
cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
```

Atualizar cache:

```bash
dnf makecache
```

Validar repo:

```bash
dnf repolist | grep -i grafana
```

---

## 11.5. Instalar Grafana Alloy

```bash
dnf install -y alloy
```

Validar pacote:

```bash
rpm -qa | grep alloy
```

Validar binário:

```bash
which alloy
```

Validar versão:

```bash
alloy --version
```

---

## 11.6. Verificar serviço systemd

```bash
systemctl status alloy --no-pager
```

Caso ainda não esteja habilitado:

```bash
systemctl enable alloy
```

Não iniciar ainda. Primeiro vamos configurar.

---

## 11.7. Criar backup da configuração original

```bash
cp -a /etc/alloy/config.alloy /etc/alloy/config.alloy.bkp.$(date +%F_%H-%M-%S)
```

Validar:

```bash
ls -lh /etc/alloy/
```

---

## 11.8. Configurar Alloy para escutar na rede

Por padrão, a UI/endpoint local do Alloy pode ficar restrita.

No homelab, vamos expor na porta:

```text
12345
```

Editar arquivo de ambiente em sistemas RHEL/Rocky:

```bash
cp -a /etc/sysconfig/alloy /etc/sysconfig/alloy.bkp.$(date +%F_%H-%M-%S)
```

Configurar `CUSTOM_ARGS`:

```bash
if grep -q '^CUSTOM_ARGS=' /etc/sysconfig/alloy; then
  sed -i 's|^CUSTOM_ARGS=.*|CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"|' /etc/sysconfig/alloy
else
  echo 'CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"' >> /etc/sysconfig/alloy
fi
```

Validar:

```bash
grep CUSTOM_ARGS /etc/sysconfig/alloy
```

Resultado esperado:

```text
CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"
```

---

## 11.9. Executar Alloy como root

Criar override systemd:

```bash
mkdir -p /etc/systemd/system/alloy.service.d
```

Criar arquivo:

```bash
cat > /etc/systemd/system/alloy.service.d/override.conf << 'EOF'
[Service]
User=root
Group=root
EOF
```

Recarregar systemd:

```bash
systemctl daemon-reload
```

Validar unit completa:

```bash
systemctl cat alloy
```

---

## 11.10. Criar configuração principal do Alloy

Capturar hostname automaticamente:

```bash
HOST_SHORT="$(hostname -s)"
HOST_FQDN="$(hostname -f 2>/dev/null || hostname -s)"
```

Exibir:

```bash
echo "$HOST_SHORT"
echo "$HOST_FQDN"
```

Criar configuração:

```bash
cat > /etc/alloy/config.alloy << EOF
logging {
  level  = "info"
  format = "logfmt"
}

loki.source.file "linux_system_logs" {
  targets = [
    {
      "__path__" = "/var/log/messages",
      "job" = "linux-system",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "messages",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/secure",
      "job" = "linux-security",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "secure",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/cron",
      "job" = "linux-cron",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "cron",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/dnf.log",
      "job" = "linux-packages",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "dnf",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/yum.log",
      "job" = "linux-packages",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "yum",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/audit/audit.log",
      "job" = "linux-audit",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "audit",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/k8s-backup/*.log",
      "__path_exclude__" = "/var/log/k8s-backup/*.{gz,zip,bak,old}",
      "job" = "k8s-backup",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "k8s-backup",
      "role" = "linux-server",
    },
  ]

  forward_to    = [loki.process.linux_common.receiver]
  tail_from_end = true

  file_match {
    enabled     = true
    sync_period = "10s"
  }
}

loki.process "linux_common" {
  stage.static_labels {
    values = {
      env    = "homelab",
      source = "linux",
    }
  }

  forward_to = [loki.write.loki_central.receiver]
}

loki.write "loki_central" {
  endpoint {
    url = "http://192.168.31.17:3100/loki/api/v1/push"
  }
}
EOF
```

---

## 11.11. Explicação da configuração

### 11.11.1. Coleta por arquivo

```river
loki.source.file "linux_system_logs"
```

Esse componente lê arquivos locais e encaminha as linhas para outros componentes Loki.

### 11.11.2. `tail_from_end = true`

```river
tail_from_end = true
```

Faz o Alloy começar a ler do final do arquivo quando não existir posição salva.

Motivo:

```text
Evita enviar todo o histórico antigo de /var/log/messages e /var/log/secure no primeiro start.
```

### 11.11.3. `file_match`

```river
file_match {
  enabled     = true
  sync_period = "10s"
}
```

Permite descoberta de arquivos, especialmente útil em paths com glob, como:

```text
/var/log/k8s-backup/*.log
```

### 11.11.4. Labels estáticas

```river
env    = "homelab"
source = "linux"
```

Labels comuns para todos os logs Linux.

### 11.11.5. Loki central

```river
url = "http://192.168.31.17:3100/loki/api/v1/push"
```

Destino final dos logs.

---

## 11.12. Validar configuração

Exibir arquivo:

```bash
cat /etc/alloy/config.alloy
```

Validar serviço:

```bash
systemctl daemon-reload
```

Iniciar Alloy:

```bash
systemctl enable --now alloy
```

Validar status:

```bash
systemctl status alloy --no-pager
```

Ver logs:

```bash
journalctl -u alloy -n 100 --no-pager
```

Acompanhar logs:

```bash
journalctl -u alloy -f
```

---

## 11.13. Validar porta do Alloy

```bash
ss -lntp | grep 12345
```

Resultado esperado:

```text
0.0.0.0:12345
```

Testar health local:

```bash
curl -s http://127.0.0.1:12345/-/healthy
```

Resultado esperado:

```text
Alloy is healthy
```

Testar pela rede a partir de outro host:

```bash
curl -s http://NOME_OU_IP_DO_HOST:12345/-/healthy
```

---

## 11.14. Gerar log de teste

Gerar evento no syslog:

```bash
logger "VALIDACAO FASE 3 LOKI LINUX - ${HOST_SHORT} - $(date)"
```

Validar se entrou no `/var/log/messages`:

```bash
tail -n 20 /var/log/messages
```

---

## 11.15. Validar no Loki via API

Consultar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Consultar hosts:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/host/values" | jq
```

Consultar tipos de log:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/log_type/values" | jq
```

Esperado aparecer:

```text
messages
secure
cron
dnf
yum
audit
k8s-backup
```

Nem todos aparecem imediatamente. Somente aparecem quando houver log recebido daquele tipo.

---

## 11.16. Validar no Grafana

Acessar:

```text
https://logs.jmsalles.homelab.br
```

Ir em:

```text
Explore
Data source: Loki
```

Consulta:

```logql
{source="linux"}
```

Consulta por host:

```logql
{host="lenovo-server-linux"}
```

Consulta da validação:

```logql
{source="linux"} |= "VALIDACAO FASE 3"
```

---

# 12. Script padronizado de instalação

Este script automatiza a instalação e configuração do Alloy Linux Logs.

## 12.1. Criar script

No host Linux alvo:

```bash
vim /usr/local/sbin/install-alloy-linux-logs-homelab.sh
```

Conteúdo:

```bash
#!/bin/bash

set -e

LOKI_URL="http://192.168.31.17:3100/loki/api/v1/push"
ALLOY_LISTEN="0.0.0.0:12345"
HOST_SHORT="$(hostname -s)"
HOST_FQDN="$(hostname -f 2>/dev/null || hostname -s)"
DATA="$(date +%F_%H-%M-%S)"

echo "============================================================"
echo " Instalacao Grafana Alloy - Linux Logs"
echo " Host: ${HOST_SHORT}"
echo " FQDN: ${HOST_FQDN}"
echo " Loki: ${LOKI_URL}"
echo "============================================================"

echo "[1/10] Instalando pacotes basicos"
dnf install -y wget curl jq vim tar gzip dnf-plugins-core

echo "[2/10] Configurando repositorio Grafana"
wget -q -O /tmp/grafana-gpg.key https://rpm.grafana.com/gpg.key
rpm --import /tmp/grafana-gpg.key

cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

dnf makecache

echo "[3/10] Instalando Alloy"
dnf install -y alloy

echo "[4/10] Backup da configuracao original"
mkdir -p /opt/backup-alloy-linux-logs
cp -a /etc/alloy/config.alloy "/opt/backup-alloy-linux-logs/config.alloy.original.${DATA}" || true
cp -a /etc/sysconfig/alloy "/opt/backup-alloy-linux-logs/sysconfig.alloy.original.${DATA}" || true

echo "[5/10] Configurando CUSTOM_ARGS"
if grep -q '^CUSTOM_ARGS=' /etc/sysconfig/alloy; then
  sed -i "s|^CUSTOM_ARGS=.*|CUSTOM_ARGS="--server.http.listen-addr=${ALLOY_LISTEN}"|" /etc/sysconfig/alloy
else
  echo "CUSTOM_ARGS="--server.http.listen-addr=${ALLOY_LISTEN}"" >> /etc/sysconfig/alloy
fi

echo "[6/10] Configurando Alloy para executar como root"
mkdir -p /etc/systemd/system/alloy.service.d

cat > /etc/systemd/system/alloy.service.d/override.conf << 'EOF'
[Service]
User=root
Group=root
EOF

echo "[7/10] Criando configuracao /etc/alloy/config.alloy"
cat > /etc/alloy/config.alloy << EOF
logging {
  level  = "info"
  format = "logfmt"
}

loki.source.file "linux_system_logs" {
  targets = [
    {
      "__path__" = "/var/log/messages",
      "job" = "linux-system",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "messages",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/secure",
      "job" = "linux-security",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "secure",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/cron",
      "job" = "linux-cron",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "cron",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/dnf.log",
      "job" = "linux-packages",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "dnf",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/yum.log",
      "job" = "linux-packages",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "yum",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/audit/audit.log",
      "job" = "linux-audit",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "audit",
      "role" = "linux-server",
    },
    {
      "__path__" = "/var/log/k8s-backup/*.log",
      "__path_exclude__" = "/var/log/k8s-backup/*.{gz,zip,bak,old}",
      "job" = "k8s-backup",
      "host" = "${HOST_SHORT}",
      "fqdn" = "${HOST_FQDN}",
      "log_type" = "k8s-backup",
      "role" = "linux-server",
    },
  ]

  forward_to    = [loki.process.linux_common.receiver]
  tail_from_end = true

  file_match {
    enabled     = true
    sync_period = "10s"
  }
}

loki.process "linux_common" {
  stage.static_labels {
    values = {
      env    = "homelab",
      source = "linux",
    }
  }

  forward_to = [loki.write.loki_central.receiver]
}

loki.write "loki_central" {
  endpoint {
    url = "${LOKI_URL}"
  }
}
EOF

echo "[8/10] Recarregando systemd"
systemctl daemon-reload

echo "[9/10] Habilitando e iniciando Alloy"
systemctl enable --now alloy
systemctl restart alloy

echo "[10/10] Validando servico"
systemctl status alloy --no-pager || true

echo "Gerando log de teste"
logger "VALIDACAO FASE 3 LOKI LINUX - ${HOST_SHORT} - ${DATA}"

echo "Validando Loki"
curl -s http://192.168.31.17:3100/ready || true

echo
echo "============================================================"
echo " Instalacao concluida"
echo " Host: ${HOST_SHORT}"
echo " Teste no Grafana:"
echo " {host="${HOST_SHORT}"} |= "VALIDACAO FASE 3""
echo "============================================================"
```

## 12.2. Permissão

```bash
chmod +x /usr/local/sbin/install-alloy-linux-logs-homelab.sh
```

## 12.3. Executar

```bash
/usr/local/sbin/install-alloy-linux-logs-homelab.sh
```

## 12.4. Validar

```bash
systemctl status alloy --no-pager
journalctl -u alloy -n 100 --no-pager
curl -s http://127.0.0.1:12345/-/healthy
```

No Grafana:

```logql
{source="linux"} |= "VALIDACAO FASE 3"
```

---

# 13. Configuração opcional — coleta do journal/systemd

## 13.1. Quando usar

A coleta via journal é útil para investigar serviços systemd como:

```text
sshd
docker
containerd
kubelet
crond
chronyd
NetworkManager
nginx
libvirtd
```

Porém, pode gerar duplicidade se o mesmo evento também estiver em `/var/log/messages`.

Minha recomendação:

```text
Primeiro use coleta por arquivo.
Depois habilite journal somente nos hosts onde fizer sentido.
```

---

## 13.2. Adicionar grupo para Alloy

Se o Alloy não estiver rodando como root, ele precisa de permissões para ler o journal.

Como neste tutorial usamos `User=root`, esta etapa não é obrigatória.

Mas, se quiser usar o usuário `alloy`, validar grupos:

```bash
getent group systemd-journal
getent group adm
```

Adicionar:

```bash
usermod -aG systemd-journal alloy
```

Se o grupo `adm` existir:

```bash
usermod -aG adm alloy
```

Reiniciar:

```bash
systemctl restart alloy
```

---

## 13.3. Exemplo de bloco journal

Adicionar ao `/etc/alloy/config.alloy` antes do `loki.write`:

```river
loki.relabel "journal_units" {
  forward_to = []

  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
}

loki.source.journal "systemd" {
  forward_to    = [loki.process.journal_common.receiver]
  relabel_rules = loki.relabel.journal_units.rules
  labels = {
    job      = "linux-journal",
    host     = "NOME_DO_HOST",
    fqdn     = "FQDN_DO_HOST",
    log_type = "journal",
    role     = "linux-server",
  }
  max_age = "1h"
}

loki.process "journal_common" {
  stage.static_labels {
    values = {
      env    = "homelab",
      source = "journal",
    }
  }

  forward_to = [loki.write.loki_central.receiver]
}
```

Substituir:

```text
NOME_DO_HOST
FQDN_DO_HOST
```

Depois:

```bash
systemctl restart alloy
journalctl -u alloy -n 100 --no-pager
```

Consultar no Grafana:

```logql
{source="journal"}
```

Consultar unidade específica:

```logql
{source="journal", unit="sshd.service"}
```

---

# 14. Consultas LogQL úteis — Linux

## 14.1. Todos os logs Linux

```logql
{source="linux"}
```

## 14.2. Logs de um host específico

```logql
{host="lenovo-server-linux"}
```

## 14.3. Logs de autenticação

```logql
{source="linux", log_type="secure"}
```

## 14.4. Falha de senha SSH

```logql
{source="linux", log_type="secure"} |= "Failed password"
```

## 14.5. Login aceito SSH

```logql
{source="linux", log_type="secure"} |= "Accepted password"
```

ou:

```logql
{source="linux", log_type="secure"} |= "Accepted publickey"
```

## 14.6. Uso de sudo

```logql
{source="linux", log_type="secure"} |= "sudo"
```

## 14.7. Erros gerais

```logql
{source="linux"} |= "error"
```

## 14.8. Falhas gerais

```logql
{source="linux"} |= "failed"
```

## 14.9. Kernel

```logql
{source="linux", log_type="messages"} |= "kernel"
```

## 14.10. OOM Killer

```logql
{source="linux"} |= "Out of memory"
```

ou:

```logql
{source="linux"} |= "oom-kill"
```

## 14.11. Disco

```logql
{source="linux"} |= "disk"
```

## 14.12. Filesystem

```logql
{source="linux"} |= "filesystem"
```

## 14.13. Cron

```logql
{source="linux", log_type="cron"}
```

## 14.14. Backup etcd/k8s

```logql
{source="linux", log_type="k8s-backup"}
```

Buscar erro no backup:

```logql
{source="linux", log_type="k8s-backup"} |= "ERRO"
```

Buscar snapshot:

```logql
{source="linux", log_type="k8s-backup"} |= "snapshot"
```

## 14.15. DNF

```logql
{source="linux", log_type="dnf"}
```

Buscar atualização:

```logql
{source="linux", log_type="dnf"} |= "Upgraded"
```

## 14.16. Audit

```logql
{source="linux", log_type="audit"}
```

Buscar negação:

```logql
{source="linux", log_type="audit"} |= "denied"
```

---

# 15. Consultas por host do homelab

## 15.1. Lenovo server Linux

```logql
{host="lenovo-server-linux"}
```

## 15.2. HP i7

```logql
{host=~"hpi7|hp-i7"}
```

## 15.3. Docker HML — logs Linux

```logql
{host="docker-hml", source="linux"}
```

## 15.4. Docker HML — logs Docker da Fase 2

```logql
{host="docker-hml", source="docker"}
```

## 15.5. Kubernetes control-plane — logs Linux

```logql
{host=~".*cp.*|.*master.*", source="linux"}
```

## 15.6. Kubernetes workers — logs Linux

```logql
{host=~".*w.*|.*worker.*", source="linux"}
```

---

# 16. Boas práticas de consulta no Grafana

Ao consultar logs:

```text
1. Primeiro selecione um intervalo curto no Grafana
2. Use labels específicas
3. Depois filtre por texto
4. Evite regex muito aberta
5. Evite consultar muitos dias sem necessidade
```

Exemplo melhor:

```logql
{host="lenovo-server-linux", log_type="secure"} |= "sudo"
```

Exemplo menos eficiente:

```logql
{source="linux"} |~ ".*sudo.*"
```

---

# 17. Verificar labels disponíveis

Consultar via API:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Consultar hosts:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/host/values" | jq
```

Consultar tipos de logs:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/log_type/values" | jq
```

Consultar jobs:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/job/values" | jq
```

---

# 18. Operação do Alloy

## 18.1. Status

```bash
systemctl status alloy --no-pager
```

## 18.2. Iniciar

```bash
systemctl start alloy
```

## 18.3. Parar

```bash
systemctl stop alloy
```

## 18.4. Reiniciar

```bash
systemctl restart alloy
```

## 18.5. Recarregar configuração

```bash
systemctl reload alloy
```

Se o reload falhar, usar:

```bash
systemctl restart alloy
```

## 18.6. Logs do serviço

```bash
journalctl -u alloy -n 100 --no-pager
```

Acompanhar em tempo real:

```bash
journalctl -u alloy -f
```

## 18.7. Ver unit completa

```bash
systemctl cat alloy
```

## 18.8. Validar endpoint local

```bash
curl -s http://127.0.0.1:12345/-/healthy
```

---

# 19. Atualização do Alloy

Atualizar pacote:

```bash
dnf update -y alloy
```

Reiniciar:

```bash
systemctl restart alloy
```

Validar:

```bash
alloy --version
systemctl status alloy --no-pager
```

---

# 20. Backup da configuração

## 20.1. Criar script

```bash
vim /usr/local/sbin/backup-alloy-linux-logs.sh
```

Conteúdo:

```bash
#!/bin/bash

DATA=$(date +%F_%H-%M-%S)
DESTINO="/opt/backup-alloy-linux-logs"
ARQUIVO="${DESTINO}/alloy-linux-logs-config-${DATA}.tar.gz"
LOG="/var/log/backup-alloy-linux-logs.log"

mkdir -p "$DESTINO"

echo "[$(date '+%F %T')] Iniciando backup da configuracao do Alloy Linux Logs" >> "$LOG"

tar -czf "$ARQUIVO"   /etc/alloy   /etc/sysconfig/alloy   /etc/systemd/system/alloy.service.d 2>> "$LOG"

if [ $? -eq 0 ]; then
  echo "[$(date '+%F %T')] Backup criado com sucesso: $ARQUIVO" >> "$LOG"
else
  echo "[$(date '+%F %T')] ERRO ao criar backup" >> "$LOG"
  exit 1
fi

find "$DESTINO" -type f -name "alloy-linux-logs-config-*.tar.gz" -mtime +30 -delete

echo "[$(date '+%F %T')] Rotina finalizada" >> "$LOG"
```

## 20.2. Permissão

```bash
chmod +x /usr/local/sbin/backup-alloy-linux-logs.sh
```

## 20.3. Testar

```bash
/usr/local/sbin/backup-alloy-linux-logs.sh
```

## 20.4. Validar

```bash
ls -lh /opt/backup-alloy-linux-logs
tail -n 50 /var/log/backup-alloy-linux-logs.log
```

## 20.5. Agendar cron

Editar:

```bash
crontab -e
```

Adicionar:

```cron
25 1 * * * /usr/local/sbin/backup-alloy-linux-logs.sh >> /var/log/backup-alloy-linux-logs.log 2>&1
```

Validar:

```bash
crontab -l
```

---

# 21. Rollback

## 21.1. Parar Alloy

```bash
systemctl stop alloy
```

## 21.2. Listar backups

```bash
ls -lh /opt/backup-alloy-linux-logs
```

## 21.3. Restaurar backup

Exemplo:

```bash
tar -xzf /opt/backup-alloy-linux-logs/alloy-linux-logs-config-YYYY-MM-DD_HH-MM-SS.tar.gz -C /
```

## 21.4. Recarregar systemd

```bash
systemctl daemon-reload
```

## 21.5. Subir Alloy

```bash
systemctl start alloy
```

## 21.6. Validar

```bash
systemctl status alloy --no-pager
journalctl -u alloy -n 100 --no-pager
```

---

# 22. Remoção do Alloy

Se for necessário remover:

```bash
systemctl stop alloy
systemctl disable alloy
dnf remove -y alloy
```

Remover arquivos, se desejado:

```bash
rm -rf /etc/alloy
rm -rf /var/lib/alloy
rm -rf /etc/systemd/system/alloy.service.d
systemctl daemon-reload
```

---

# 23. Troubleshooting

## 23.1. Alloy não inicia

Validar status:

```bash
systemctl status alloy --no-pager
```

Ver logs:

```bash
journalctl -u alloy -n 200 --no-pager
```

Validar configuração:

```bash
cat /etc/alloy/config.alloy
```

Ver unit:

```bash
systemctl cat alloy
```

---

## 23.2. Erro de sintaxe no config.alloy

Ver logs:

```bash
journalctl -u alloy -n 100 --no-pager
```

Normalmente o log indica a linha com problema.

Corrigir:

```bash
vim /etc/alloy/config.alloy
```

Reiniciar:

```bash
systemctl restart alloy
```

---

## 23.3. Alloy inicia, mas não envia logs

Validar Loki:

```bash
curl -s http://192.168.31.17:3100/ready
```

Validar rede:

```bash
ping -c 3 192.168.31.17
```

Validar porta:

```bash
curl -v http://192.168.31.17:3100/ready
```

Ver logs do Alloy:

```bash
journalctl -u alloy -f
```

Gerar log:

```bash
logger "TESTE ENVIO LOKI LINUX $(date)"
```

Consultar no Grafana:

```logql
{source="linux"} |= "TESTE ENVIO LOKI"
```

---

## 23.4. Logs de `/var/log/secure` não aparecem

Validar arquivo:

```bash
ls -lh /var/log/secure
tail -n 20 /var/log/secure
```

Validar se Alloy roda como root:

```bash
ps -ef | grep alloy | grep -v grep
```

Ver unit:

```bash
systemctl cat alloy
```

Esperado encontrar:

```text
User=root
Group=root
```

Se não estiver, recriar override:

```bash
mkdir -p /etc/systemd/system/alloy.service.d

cat > /etc/systemd/system/alloy.service.d/override.conf << 'EOF'
[Service]
User=root
Group=root
EOF

systemctl daemon-reload
systemctl restart alloy
```

---

## 23.5. Logs de audit não aparecem

Validar arquivo:

```bash
ls -lh /var/log/audit/audit.log
tail -n 20 /var/log/audit/audit.log
```

Validar se auditd está ativo:

```bash
systemctl status auditd --no-pager
```

Gerar evento simples:

```bash
sudo -l >/dev/null 2>&1
```

Consultar:

```logql
{source="linux", log_type="audit"}
```

---

## 23.6. Alloy não mostra UI na porta 12345

Validar porta:

```bash
ss -lntp | grep 12345
```

Validar `/etc/sysconfig/alloy`:

```bash
cat /etc/sysconfig/alloy
```

Esperado:

```text
CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"
```

Reiniciar:

```bash
systemctl restart alloy
```

---

## 23.7. Muitos logs antigos foram enviados

A configuração usa:

```river
tail_from_end = true
```

Isso evita envio histórico quando não existe posição.

Porém, se o Alloy já havia criado posição antiga, pode continuar daquela posição.

Para resetar posições:

```bash
systemctl stop alloy
rm -rf /var/lib/alloy
systemctl start alloy
```

Atenção:

```text
Isso faz o Alloy perder o controle de posição dos arquivos monitorados.
Com tail_from_end=true, ele deve voltar a acompanhar do final dos arquivos.
```

---

# 24. Validação final da Fase 3

Em cada host Linux:

```bash
hostname
hostname -f
systemctl status alloy --no-pager
curl -s http://127.0.0.1:12345/-/healthy
curl -s http://192.168.31.17:3100/ready
```

Gerar log:

```bash
logger "VALIDACAO FINAL FASE 3 LINUX LOGS - $(hostname -s) - $(date)"
```

No Grafana:

```logql
{source="linux"} |= "VALIDACAO FINAL FASE 3"
```

Validar labels via API:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/host/values" | jq
curl -s "http://192.168.31.17:3100/loki/api/v1/label/log_type/values" | jq
```

Resultado esperado:

```text
Host Linux aparece na label host
Logs aparecem no Grafana
Tipos messages/secure/cron/dnf/audit aparecem conforme geração de logs
Alloy saudável em 127.0.0.1:12345
```

---

# 25. Ordem recomendada de implantação

Implantar nesta ordem:

```text
1. lenovo-server-linux
2. hpi7 / hp-i7
3. docker-hml
4. dell / dell-novo
5. k8s-cp1
6. k8s-w1
7. k8s-w2
```

Observação:

```text
Nos hosts Kubernetes, nesta fase coletar apenas logs Linux.
Logs de pods e eventos Kubernetes ficam para a Fase 4.
```

---

# 26. Próximas fases

Após validar a Fase 3:

```text
Fase 4 - Coleta de logs do Kubernetes
Fase 5 - Dashboards iniciais no Grafana
Fase 6 - Alertas básicos de logs
Fase 7 - Integração operacional com Zabbix
```

---

# 27. Referências oficiais usadas como base técnica

```text
Grafana Alloy - Install on Linux:
https://grafana.com/docs/alloy/latest/set-up/install/linux/

Grafana Alloy - Configure on Linux:
https://grafana.com/docs/alloy/latest/configure/linux/

Grafana Alloy - loki.source.file:
https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.file/

Grafana Alloy - local.file_match:
https://grafana.com/docs/alloy/latest/reference/components/local/local.file_match/

Grafana Alloy - loki.source.journal:
https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/

Grafana Loki - Labels cardinality:
https://grafana.com/docs/loki/latest/get-started/labels/cardinality/

Grafana Loki - Query best practices:
https://grafana.com/docs/loki/latest/query/bp-query/
```
