# Tutorial — Fase 2 — Coleta de Logs Docker / Portainer com Grafana Alloy

## 1. Identificação do documento

| Item | Informação |
|---|---|
| Ambiente | Homelab |
| Fase | Fase 2 |
| Objetivo | Coletar logs de containers Docker/Portainer e enviar para Loki |
| Host de origem dos logs | `docker-hml.jmsalles.homelab.br` |
| IP do host Docker | `192.168.31.37` |
| Servidor central de logs | `observabilidade` |
| IP do Loki | `192.168.31.17` |
| DNS do Grafana | `logs.jmsalles.homelab.br` |
| URL do Grafana | `https://logs.jmsalles.homelab.br` |
| Endpoint Loki para ingestão | `http://192.168.31.17:3100/loki/api/v1/push` |
| Coletor | Grafana Alloy |
| Método de instalação | Docker Compose |
| Diretório base no host Docker | `/opt/alloy-docker-logs` |
| Arquivo Compose | `docker-compose.yml` |
| SELinux | Desabilitado no padrão do homelab |
| Firewall local | Desabilitado no padrão do homelab |

---

## 2. Objetivo

Implantar o **Grafana Alloy** no host Docker/Portainer para coletar logs dos containers Docker e enviá-los para o Loki central instalado na VM:

```text
observabilidade - 192.168.31.17
```

A partir desta fase, o Grafana em:

```text
https://logs.jmsalles.homelab.br
```

passará a exibir logs de containers Docker do host:

```text
docker-hml.jmsalles.homelab.br
```

Esta fase é importante porque o host Docker concentra vários serviços do homelab, como:

```text
Nginx reverse proxy
Portainer
Gitea
Nexus
Vault
MinIO
phpIPAM
Stirling PDF
Docker Registry
Outros containers auxiliares
```

---

## 3. Escopo da Fase 2

Esta fase contempla:

```text
1. Validação do Loki central
2. Validação do host Docker/Portainer
3. Criação da estrutura /opt/alloy-docker-logs
4. Criação da configuração do Alloy
5. Criação do docker-compose.yml do Alloy
6. Subida do Alloy em container
7. Coleta automática de logs dos containers Docker
8. Padronização de labels
9. Validação no Loki
10. Validação no Grafana
11. Consultas LogQL úteis
12. Operação do Alloy
13. Backup da configuração
14. Troubleshooting
```

Esta fase ainda não contempla:

```text
Coleta de logs do Kubernetes
Coleta de logs de servidores Linux sem Docker
Alertas no Grafana
Dashboards avançados
Integração com Zabbix
```

---

## 4. Arquitetura da Fase 2

```text
+-------------------------------------------------------------+
| Host Docker / Portainer                                     |
| docker-hml.jmsalles.homelab.br                              |
| IP: 192.168.31.37                                           |
|                                                             |
|  +---------------------+                                    |
|  | Containers Docker   |                                    |
|  | Nginx, Gitea, etc.  |                                    |
|  +----------+----------+                                    |
|             |                                               |
|             | docker.sock                                   |
|             v                                               |
|  +---------------------+                                    |
|  | Grafana Alloy       |                                    |
|  | alloy-docker-logs   |                                    |
|  +----------+----------+                                    |
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
|  +---------------------+      +--------------------------+  |
|  | Loki                | <--- | Grafana                  |  |
|  | Porta 3100          |      | Porta 3000               |  |
|  +---------------------+      +--------------------------+  |
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

## 5. Modelo escolhido

Para esta fase será usado:

```text
Alloy em container no próprio host Docker
```

O Alloy será executado com acesso somente leitura ao socket Docker:

```text
/var/run/docker.sock:/var/run/docker.sock:ro
```

Com isso, ele consegue descobrir os containers e coletar os logs gerados pelo Docker.

Não será alterado o `logging driver` dos containers existentes.

O modelo escolhido é:

```text
Alloy coleta os logs do Docker
Alloy envia para Loki central
Grafana consulta Loki
Zabbix continua responsável por monitoração operacional
```

---

## 6. Por que não usar Docker logging driver do Loki nesta fase

Existe a possibilidade de usar o plugin/logging driver do Loki diretamente no Docker. Porém, para este homelab, o modelo com Alloy é mais seguro para começar porque:

```text
Não altera o logging driver atual dos containers
Não exige recriar todos os containers existentes
Permite rollback simples
Centraliza a configuração de coleta em um único container
Permite adicionar labels e regras sem impactar os serviços
Mantém compatibilidade com docker logs
```

Portanto, nesta fase será usado:

```text
Grafana Alloy + Docker socket
```

---

## 7. Convenção de labels

As labels são fundamentais para consultar logs no Loki.

Para evitar cardinalidade alta, usaremos labels estáveis e de baixa variação.

Labels adotadas nesta fase:

| Label | Exemplo | Função |
|---|---|---|
| `env` | `homelab` | Ambiente |
| `host` | `docker-hml` | Host de origem |
| `fqdn` | `docker-hml.jmsalles.homelab.br` | Nome completo do host |
| `runtime` | `docker` | Tipo de runtime |
| `source` | `docker` | Origem do log |
| `container` | `nginx` | Nome do container |
| `service_name` | `nginx` | Nome lógico do serviço |
| `compose_project` | `nginx` | Projeto Docker Compose, quando existir |
| `compose_service` | `nginx` | Serviço Docker Compose, quando existir |
| `image` | `grafana/alloy:latest` | Imagem do container |

Não usaremos como labels principais:

```text
container_id
IP de container
timestamp
request_id
trace_id
user_id
endpoint dinâmico
```

Motivo:

```text
Esses valores podem aumentar demais a cardinalidade e prejudicar performance do Loki.
```

---

## 8. Pré-requisitos

### 8.1. Fase 1 funcionando

Antes de iniciar, validar que a stack central está funcionando:

```text
Loki em 192.168.31.17:3100
Grafana em https://logs.jmsalles.homelab.br
Datasource Loki configurado
Alloy local da VM observabilidade funcionando
```

### 8.2. Host Docker

Host desta fase:

```text
docker-hml.jmsalles.homelab.br
192.168.31.37
```

### 8.3. Acesso necessário

Você precisa ter acesso SSH ao host:

```bash
ssh jmsalles@docker-hml.jmsalles.homelab.br
```

ou:

```bash
ssh jmsalles@192.168.31.37
```

---

## 9. Acessar o host Docker

Acessar o host:

```bash
ssh jmsalles@docker-hml.jmsalles.homelab.br
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

Validar Docker:

```bash
docker version
```

Validar Docker Compose:

```bash
docker compose version
```

Validar containers ativos:

```bash
docker ps
```

---

## 10. Validar comunicação com Loki central

No host `docker-hml`, testar acesso ao Loki:

```bash
curl -s http://192.168.31.17:3100/ready
```

Resultado esperado:

```text
ready
```

Testar labels atuais:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Se o `jq` não estiver instalado:

```bash
dnf install -y jq
```

ou, em distribuições Debian/Ubuntu:

```bash
apt update
apt install -y jq
```

---

## 11. Validar Docker socket

O Alloy precisará acessar o socket Docker.

Validar se o socket existe:

```bash
ls -lh /var/run/docker.sock
```

Resultado esperado:

```text
srw-rw---- root docker /var/run/docker.sock
```

Validar se o Docker responde:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

---

## 12. Criar diretório base do Alloy

Diretório padrão desta fase:

```text
/opt/alloy-docker-logs
```

Criar estrutura:

```bash
mkdir -p /opt/alloy-docker-logs/{config,data,backup}
```

Entrar no diretório:

```bash
cd /opt/alloy-docker-logs
```

Validar:

```bash
tree -d /opt/alloy-docker-logs
```

Se o comando `tree` não existir:

```bash
dnf install -y tree
```

Estrutura esperada:

```text
/opt/alloy-docker-logs
├── backup
├── config
└── data
```

---

## 13. Criar configuração do Alloy

Criar arquivo:

```bash
vim /opt/alloy-docker-logs/config/config.alloy
```

Conteúdo:

```river
logging {
  level  = "info"
  format = "logfmt"
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

discovery.relabel "docker_logs" {
  targets = []

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "service_name"
  }

  rule {
    source_labels = ["__meta_docker_container_image"]
    target_label  = "image"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_project"]
    target_label  = "compose_project"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_service"]
    target_label  = "compose_service"
  }
}

loki.source.docker "docker_logs" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.docker.containers.targets
  labels        = {
    env     = "homelab",
    host    = "docker-hml",
    fqdn    = "docker-hml.jmsalles.homelab.br",
    runtime = "docker",
    source  = "docker",
  }
  relabel_rules = discovery.relabel.docker_logs.rules
  forward_to    = [loki.write.loki_central.receiver]
}

loki.write "loki_central" {
  endpoint {
    url = "http://192.168.31.17:3100/loki/api/v1/push"
  }
}
```

---

## 14. Explicação da configuração do Alloy

### 14.1. Logging interno do Alloy

```river
logging {
  level  = "info"
  format = "logfmt"
}
```

Define o nível de log do próprio Alloy.

---

### 14.2. Descoberta de containers Docker

```river
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}
```

Faz o Alloy conversar com o Docker Engine local usando:

```text
/var/run/docker.sock
```

Com isso, o Alloy descobre automaticamente containers existentes e futuros.

---

### 14.3. Regras de relabel

```river
discovery.relabel "docker_logs" {
  targets = []
  ...
}
```

As regras extraem metadados do Docker e transformam em labels úteis para o Loki.

Exemplo:

```text
/__meta_docker_container_name -> container
/__meta_docker_container_image -> image
```

---

### 14.4. Coleta dos logs Docker

```river
loki.source.docker "docker_logs" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.docker.containers.targets
  labels        = {
    env     = "homelab",
    host    = "docker-hml",
    fqdn    = "docker-hml.jmsalles.homelab.br",
    runtime = "docker",
    source  = "docker",
  }
  relabel_rules = discovery.relabel.docker_logs.rules
  forward_to    = [loki.write.loki_central.receiver]
}
```

Esse bloco coleta os logs dos containers Docker.

---

### 14.5. Envio para Loki central

```river
loki.write "loki_central" {
  endpoint {
    url = "http://192.168.31.17:3100/loki/api/v1/push"
  }
}
```

Esse bloco envia os logs para o Loki central em:

```text
observabilidade - 192.168.31.17
```

---

## 15. Criar docker-compose.yml do Alloy

Criar arquivo:

```bash
vim /opt/alloy-docker-logs/docker-compose.yml
```

Conteúdo:

```yaml
services:
  alloy-docker-logs:
    image: grafana/alloy:latest
    container_name: alloy-docker-logs
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    volumes:
      - /opt/alloy-docker-logs/config/config.alloy:/etc/alloy/config.alloy:ro
      - /opt/alloy-docker-logs/data:/var/lib/alloy/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
```

---

## 16. Validar docker-compose.yml

Entrar no diretório:

```bash
cd /opt/alloy-docker-logs
```

Validar sintaxe:

```bash
docker compose config
```

Se o comando exibir a configuração renderizada sem erro, o arquivo está válido.

---

## 17. Subir o Alloy

Baixar imagem:

```bash
cd /opt/alloy-docker-logs
docker compose pull
```

Subir container:

```bash
docker compose up -d
```

Validar:

```bash
docker compose ps
```

Resultado esperado:

```text
NAME                IMAGE                  STATUS
alloy-docker-logs   grafana/alloy:latest   Up
```

Validar com Docker:

```bash
docker ps | grep alloy-docker-logs
```

---

## 18. Ver logs do Alloy

Ver logs:

```bash
cd /opt/alloy-docker-logs
docker compose logs -f alloy-docker-logs
```

Resultado esperado:

```text
Alloy started
component healthy
loki.source.docker
loki.write
```

Para sair:

```text
CTRL + C
```

---

## 19. Validar interface local do Alloy

O Alloy expõe uma interface local na porta:

```text
12345
```

Validar porta:

```bash
ss -lntp | grep 12345
```

Testar localmente:

```bash
curl -s http://127.0.0.1:12345/-/healthy
```

Resultado esperado:

```text
Alloy is healthy
```

Se quiser acessar pelo navegador:

```text
http://docker-hml.jmsalles.homelab.br:12345
```

No homelab, como firewall está desabilitado, o acesso deve funcionar. Caso futuramente o firewall seja habilitado, liberar a porta somente para administração.

---

## 20. Gerar logs de teste em containers

### 20.1. Teste simples com container temporário

Executar:

```bash
docker run --rm --name teste-loki-docker alpine sh -c 'echo "TESTE LOKI DOCKER HML - $(date)"'
```

Esse container irá executar, gerar uma linha de log e sair.

---

### 20.2. Teste com container temporário com vários logs

Executar:

```bash
docker run --rm --name teste-loki-loop alpine sh -c 'for i in $(seq 1 5); do echo "TESTE LOKI LOOP DOCKER HML linha $i - $(date)"; sleep 1; done'
```

---

### 20.3. Teste com log de erro proposital

Executar:

```bash
docker run --rm --name teste-loki-error alpine sh -c 'echo "ERROR TESTE CONTROLADO LOKI DOCKER HML - $(date)"'
```

---

## 21. Validar no Loki via API

No host `docker-hml`, consultar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Validar valores de `host`:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/host/values" | jq
```

Resultado esperado:

```json
[
  "docker-hml",
  "observabilidade"
]
```

Validar valores de `runtime`:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/runtime/values" | jq
```

Resultado esperado:

```json
[
  "docker"
]
```

Validar valores de `source`:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/source/values" | jq
```

Resultado esperado:

```json
[
  "docker",
  "linux"
]
```

Validar containers:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
```

Deve aparecer uma lista contendo containers como:

```text
nginx
portainer
gitea
nexus
vault
minio
phpipam
alloy-docker-logs
```

Os nomes podem variar conforme o nome real dos containers no seu host.

---

## 22. Validar no Grafana

Acessar:

```text
https://logs.jmsalles.homelab.br
```

Ir em:

```text
Explore
Data source: Loki
```

Consulta inicial:

```logql
{host="docker-hml"}
```

Se aparecerem logs, a fase 2 está funcionando.

---

## 23. Consultas LogQL úteis

### 23.1. Todos os logs do host Docker

```logql
{host="docker-hml"}
```

### 23.2. Todos os logs Docker

```logql
{runtime="docker"}
```

### 23.3. Logs por container

Exemplo Nginx:

```logql
{host="docker-hml", container="nginx"}
```

Exemplo Portainer:

```logql
{host="docker-hml", container=~".*portainer.*"}
```

Exemplo Gitea:

```logql
{host="docker-hml", container=~".*gitea.*"}
```

Exemplo Nexus:

```logql
{host="docker-hml", container=~".*nexus.*"}
```

Exemplo Vault:

```logql
{host="docker-hml", container=~".*vault.*"}
```

Exemplo MinIO:

```logql
{host="docker-hml", container=~".*minio.*"}
```

Exemplo phpIPAM:

```logql
{host="docker-hml", container=~".*php.*|.*ipam.*"}
```

Exemplo Stirling PDF:

```logql
{host="docker-hml", container=~".*stirling.*|.*pdf.*"}
```

---

## 24. Consultas para troubleshooting operacional

### 24.1. Buscar erros gerais

```logql
{host="docker-hml"} |= "error"
```

### 24.2. Buscar ERROR maiúsculo

```logql
{host="docker-hml"} |= "ERROR"
```

### 24.3. Buscar falhas

```logql
{host="docker-hml"} |= "failed"
```

### 24.4. Buscar exceptions

```logql
{host="docker-hml"} |= "Exception"
```

### 24.5. Buscar timeout

```logql
{host="docker-hml"} |= "timeout"
```

### 24.6. Buscar conexão recusada

```logql
{host="docker-hml"} |= "connection refused"
```

### 24.7. Buscar problema de permissão

```logql
{host="docker-hml"} |= "permission denied"
```

---

## 25. Consultas específicas por serviço

### 25.1. Nginx reverse proxy

Erros 500:

```logql
{host="docker-hml", container=~".*nginx.*"} |= "500"
```

Erros 502:

```logql
{host="docker-hml", container=~".*nginx.*"} |= "502"
```

Erros 504:

```logql
{host="docker-hml", container=~".*nginx.*"} |= "504"
```

Upstream:

```logql
{host="docker-hml", container=~".*nginx.*"} |= "upstream"
```

Host específico:

```logql
{host="docker-hml", container=~".*nginx.*"} |= "logs.jmsalles.homelab.br"
```

---

### 25.2. Portainer

Todos os logs do Portainer:

```logql
{host="docker-hml", container=~".*portainer.*"}
```

Falhas:

```logql
{host="docker-hml", container=~".*portainer.*"} |= "error"
```

---

### 25.3. Gitea

Todos os logs do Gitea:

```logql
{host="docker-hml", container=~".*gitea.*"}
```

Erros:

```logql
{host="docker-hml", container=~".*gitea.*"} |= "error"
```

Problemas de banco:

```logql
{host="docker-hml", container=~".*gitea.*"} |= "database"
```

---

### 25.4. Nexus

Todos os logs do Nexus:

```logql
{host="docker-hml", container=~".*nexus.*"}
```

Erros:

```logql
{host="docker-hml", container=~".*nexus.*"} |= "ERROR"
```

Problemas de repositório:

```logql
{host="docker-hml", container=~".*nexus.*"} |= "repository"
```

---

### 25.5. Vault

Todos os logs do Vault:

```logql
{host="docker-hml", container=~".*vault.*"}
```

Estado sealed:

```logql
{host="docker-hml", container=~".*vault.*"} |= "sealed"
```

Erros:

```logql
{host="docker-hml", container=~".*vault.*"} |= "error"
```

---

### 25.6. MinIO

Todos os logs do MinIO:

```logql
{host="docker-hml", container=~".*minio.*"}
```

Erros:

```logql
{host="docker-hml", container=~".*minio.*"} |= "error"
```

Disco:

```logql
{host="docker-hml", container=~".*minio.*"} |= "disk"
```

---

### 25.7. phpIPAM

Todos os logs relacionados:

```logql
{host="docker-hml", container=~".*php.*|.*ipam.*|.*apache.*"}
```

Erros PHP:

```logql
{host="docker-hml", container=~".*php.*|.*ipam.*|.*apache.*"} |= "PHP"
```

Erros de conexão:

```logql
{host="docker-hml", container=~".*php.*|.*ipam.*|.*apache.*"} |= "connection"
```

---

## 26. Boas práticas de consulta no Grafana

Ao consultar logs no Grafana:

```text
1. Primeiro selecione um intervalo curto de tempo
2. Use labels específicas
3. Depois aplique filtros de texto
4. Use regex somente quando necessário
```

Exemplo melhor:

```logql
{host="docker-hml", container=~".*nginx.*"} |= "502"
```

Exemplo menos eficiente:

```logql
{host="docker-hml"} |~ ".*502.*"
```

---

## 27. Verificar cardinalidade das labels

Consultar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Consultar valores da label `container`:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
```

Consultar valores da label `image`:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/image/values" | jq
```

Se aparecerem muitas labels ou valores extremamente dinâmicos, revisar a configuração para reduzir cardinalidade.

---

## 28. Operação do Alloy

### 28.1. Ver status

```bash
cd /opt/alloy-docker-logs
docker compose ps
```

### 28.2. Parar

```bash
cd /opt/alloy-docker-logs
docker compose down
```

### 28.3. Subir

```bash
cd /opt/alloy-docker-logs
docker compose up -d
```

### 28.4. Reiniciar

```bash
cd /opt/alloy-docker-logs
docker compose restart
```

### 28.5. Ver logs

```bash
cd /opt/alloy-docker-logs
docker compose logs -f alloy-docker-logs
```

### 28.6. Atualizar imagem

```bash
cd /opt/alloy-docker-logs
docker compose pull
docker compose up -d
```

---

## 29. Backup da configuração

### 29.1. Criar script

Criar arquivo:

```bash
vim /usr/local/sbin/backup-alloy-docker-logs.sh
```

Conteúdo:

```bash
#!/bin/bash

DATA=$(date +%F_%H-%M-%S)
DESTINO="/opt/alloy-docker-logs/backup"
ARQUIVO="${DESTINO}/alloy-docker-logs-config-${DATA}.tar.gz"
LOG="/var/log/backup-alloy-docker-logs.log"

mkdir -p "$DESTINO"

echo "[$(date '+%F %T')] Iniciando backup da configuracao do Alloy Docker Logs" >> "$LOG"

tar -czf "$ARQUIVO" \
  /opt/alloy-docker-logs/docker-compose.yml \
  /opt/alloy-docker-logs/config

if [ $? -eq 0 ]; then
  echo "[$(date '+%F %T')] Backup criado com sucesso: $ARQUIVO" >> "$LOG"
else
  echo "[$(date '+%F %T')] ERRO ao criar backup" >> "$LOG"
  exit 1
fi

find "$DESTINO" -type f -name "alloy-docker-logs-config-*.tar.gz" -mtime +30 -delete

echo "[$(date '+%F %T')] Rotina finalizada" >> "$LOG"
```

### 29.2. Dar permissão

```bash
chmod +x /usr/local/sbin/backup-alloy-docker-logs.sh
```

### 29.3. Testar backup

```bash
/usr/local/sbin/backup-alloy-docker-logs.sh
```

### 29.4. Validar backup

```bash
ls -lh /opt/alloy-docker-logs/backup
```

### 29.5. Validar log

```bash
tail -n 50 /var/log/backup-alloy-docker-logs.log
```

### 29.6. Agendar no cron

Editar crontab:

```bash
crontab -e
```

Adicionar:

```cron
20 1 * * * /usr/local/sbin/backup-alloy-docker-logs.sh >> /var/log/backup-alloy-docker-logs.log 2>&1
```

Validar:

```bash
crontab -l
```

---

## 30. Rollback

Caso a configuração quebre o Alloy, seguir este procedimento.

### 30.1. Parar container

```bash
cd /opt/alloy-docker-logs
docker compose down
```

### 30.2. Listar backups

```bash
ls -lh /opt/alloy-docker-logs/backup
```

### 30.3. Restaurar backup

Exemplo:

```bash
tar -xzf /opt/alloy-docker-logs/backup/alloy-docker-logs-config-YYYY-MM-DD_HH-MM-SS.tar.gz -C /
```

### 30.4. Subir novamente

```bash
cd /opt/alloy-docker-logs
docker compose up -d
```

### 30.5. Validar

```bash
docker compose ps
docker compose logs --tail=100 alloy-docker-logs
```

---

## 31. Troubleshooting

### 31.1. Alloy não sobe

Ver logs:

```bash
cd /opt/alloy-docker-logs
docker compose logs alloy-docker-logs
```

Validar sintaxe do Compose:

```bash
docker compose config
```

Validar arquivo do Alloy:

```bash
cat /opt/alloy-docker-logs/config/config.alloy
```

---

### 31.2. Erro de acesso ao Docker socket

Validar socket:

```bash
ls -lh /var/run/docker.sock
```

Validar se o socket está montado no container:

```bash
docker exec -it alloy-docker-logs ls -lh /var/run/docker.sock
```

Ver logs:

```bash
docker logs alloy-docker-logs
```

Se houver erro de permissão, como estamos em homelab, uma alternativa é executar temporariamente com usuário root, que normalmente já é o padrão do container.

---

### 31.3. Alloy sobe, mas não envia logs

Validar conectividade com Loki:

```bash
curl -s http://192.168.31.17:3100/ready
```

Validar endpoint de push:

```bash
curl -s http://192.168.31.17:3100/loki/api/v1/labels | jq
```

Ver logs do Alloy:

```bash
cd /opt/alloy-docker-logs
docker compose logs -f alloy-docker-logs
```

Gerar log de teste:

```bash
docker run --rm --name teste-loki-docker alpine sh -c 'echo "TESTE LOKI DOCKER HML - $(date)"'
```

Consultar no Grafana:

```logql
{host="docker-hml"} |= "TESTE LOKI DOCKER HML"
```

---

### 31.4. Logs aparecem no Loki, mas não no Grafana

Validar datasource do Grafana:

```text
Grafana > Connections > Data sources > Loki > Save & test
```

Validar consulta mais ampla:

```logql
{host="docker-hml"}
```

Ajustar o intervalo de tempo no canto superior direito do Grafana para:

```text
Last 15 minutes
Last 1 hour
Last 6 hours
```

---

### 31.5. Labels de container não aparecem

Validar valores:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
```

Se não aparecer `container`, revisar este bloco:

```river
discovery.relabel "docker_logs" {
  targets = []

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
}
```

Depois reiniciar:

```bash
cd /opt/alloy-docker-logs
docker compose restart
```

---

## 32. Validação final da Fase 2

Executar no host `docker-hml`:

```bash
hostname
hostname -f
docker ps
cd /opt/alloy-docker-logs
docker compose ps
curl -s http://192.168.31.17:3100/ready
```

Gerar log de teste:

```bash
docker run --rm --name validacao-fase2-loki alpine sh -c 'echo "VALIDACAO FASE 2 LOKI DOCKER HML - $(date)"'
```

Validar no Grafana:

```logql
{host="docker-hml"} |= "VALIDACAO FASE 2"
```

Validar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/host/values" | jq
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
```

Resultado esperado:

```text
Logs do docker-hml chegando no Loki
Labels host/container/runtime/source disponíveis
Grafana exibindo logs dos containers Docker
```

---

## 33. Estado final esperado

Ao final da Fase 2:

```text
Alloy rodando no docker-hml
Logs dos containers Docker sendo enviados ao Loki central
Grafana exibindo logs por host, container e serviço
Endpoint Loki usado diretamente: http://192.168.31.17:3100/loki/api/v1/push
Nenhuma alteração no logging driver dos containers existentes
Backup da configuração criado
```

---

## 34. Próximas fases

Após validar esta fase, seguir para:

```text
Fase 3 - Coleta de logs dos servidores Linux
Fase 4 - Coleta de logs do Kubernetes
Fase 5 - Dashboards iniciais no Grafana
Fase 6 - Alertas básicos de logs
Fase 7 - Integração operacional com Zabbix
```

---

## 35. Referências oficiais usadas como base técnica

```text
Grafana Alloy - loki.source.docker:
https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/

Grafana Alloy - discovery.docker:
https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.docker/

Grafana Alloy - discovery.relabel:
https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.relabel/

Grafana Alloy - Monitor Docker containers:
https://grafana.com/docs/alloy/latest/monitor/monitor-docker-containers/

Grafana Loki - Cardinality:
https://grafana.com/docs/loki/latest/get-started/labels/cardinality/

Grafana Loki - Query best practices:
https://grafana.com/docs/loki/latest/query/bp-query/
```
