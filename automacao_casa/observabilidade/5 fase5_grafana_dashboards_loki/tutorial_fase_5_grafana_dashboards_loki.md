# Tutorial — Fase 5 — Dashboards Iniciais no Grafana para Loki

## 1. Identificação do documento

| Item | Informação |
|---|---|
| Ambiente | Homelab |
| Fase | Fase 5 |
| Objetivo | Criar dashboards iniciais no Grafana para análise dos logs centralizados |
| Grafana | `https://logs.jmsalles.homelab.br` |
| Loki | `http://192.168.31.17:3100` |
| VM central | `observabilidade` |
| Diretório da stack | `/opt/observability` |
| Datasource | `Loki` |
| Datasource UID recomendado | `Loki` |
| Método principal | Provisionamento por arquivos JSON |
| Método alternativo | Importação manual via interface do Grafana |
| Dashboards criados | Overview, Linux, Docker/Portainer e Kubernetes |

---

## 2. Objetivo

Criar dashboards iniciais no Grafana para facilitar a investigação operacional dos logs coletados nas fases anteriores:

```text
Fase 1 - Loki + Grafana + Alloy local
Fase 2 - Logs Docker / Portainer
Fase 3 - Logs de servidores Linux
Fase 4 - Logs e eventos Kubernetes
```

A partir desta fase, o acesso principal será:

```text
https://logs.jmsalles.homelab.br
```

Os dashboards serão organizados em uma pasta do Grafana chamada:

```text
Homelab - Logs
```

---

## 3. Escopo da Fase 5

Esta fase contempla:

```text
1. Padronização do datasource Loki com uid fixo
2. Criação de diretório de provisionamento de dashboards
3. Criação do provider de dashboards
4. Importação/provisionamento de dashboards JSON
5. Dashboard Loki Overview
6. Dashboard Linux Servers
7. Dashboard Docker / Portainer
8. Dashboard Kubernetes
9. Consultas LogQL usadas nos painéis
10. Validação dos dashboards
11. Troubleshooting
12. Backup dos dashboards
```

Esta fase ainda não contempla:

```text
Alertas avançados
Notificações por e-mail/Telegram/Slack
Integração com Zabbix
Provisionamento de alert rules
Dashboard de métricas Prometheus
Tempo/Traces
```

Esses itens ficam para as próximas fases.

---

## 4. Arquitetura da Fase 5

```text
+--------------------------------------------------------------+
| Usuário                                                      |
| Navegador                                                    |
+-------------------------------+------------------------------+
                                |
                                | https://logs.jmsalles.homelab.br
                                v
+--------------------------------------------------------------+
| Nginx Reverse Proxy                                          |
+-------------------------------+------------------------------+
                                |
                                | http://192.168.31.17:3000
                                v
+--------------------------------------------------------------+
| VM observabilidade                                           |
|                                                              |
|  +----------------------+      +---------------------------+ |
|  | Grafana              | ---> | Loki                      | |
|  | Dashboards           |      | Logs centralizados        | |
|  +----------------------+      +---------------------------+ |
|                                                              |
|  Dashboards provisionados em:                                |
|  /opt/observability/grafana/provisioning/dashboards          |
+--------------------------------------------------------------+
```

---

## 5. Dashboards planejados

| Dashboard | Finalidade |
|---|---|
| `Loki — Overview Homelab` | Visão geral de logs, erros e fontes |
| `Loki — Linux Servers` | Logs Linux, SSH, sudo, cron, audit e backup |
| `Loki — Docker / Portainer` | Logs de containers Docker, Nginx, Portainer e serviços |
| `Loki — Kubernetes` | Logs de pods, namespaces, containers, nodes e eventos |

---

## 6. Conceitos usados

### 6.1. Datasource UID

O Grafana gera um UID interno para cada datasource. Para dashboards provisionados por arquivo, é melhor padronizar o UID:

```text
Loki
```

Assim os dashboards JSON conseguem apontar sempre para o mesmo datasource.

### 6.2. Provisionamento de dashboards

O Grafana permite provisionar dashboards por arquivos em diretórios locais. Como sua stack já monta:

```text
/opt/observability/grafana/provisioning
```

em:

```text
/etc/grafana/provisioning
```

dentro do container, usaremos essa estrutura para criar dashboards versionáveis.

### 6.3. LogQL

Os painéis usam consultas LogQL com labels como:

```text
env
source
host
runtime
container
cluster
namespace
pod
node
log_type
```

Exemplo:

```logql
{source="linux", log_type="secure"} |= "sudo"
```

---

## 7. Validar fase anterior

Antes de criar dashboards, validar se já existem logs das fases anteriores.

Acessar o Grafana:

```text
https://logs.jmsalles.homelab.br
```

Ir em:

```text
Explore
Data source: Loki
```

Testar:

```logql
{env="homelab"}
```

Linux:

```logql
{source="linux"}
```

Docker:

```logql
{source="docker"}
```

Kubernetes:

```logql
{source="kubernetes"}
```

Se algum deles não retornar dados, validar a fase correspondente.

---

# 8. Ajustar datasource Loki com UID fixo

## 8.1. Acessar a VM observabilidade

```bash
ssh jmsalles@192.168.31.17
sudo -i
cd /opt/observability
```

## 8.2. Fazer backup do datasource atual

```bash
mkdir -p /opt/observability/backup/fase5
```

```bash
cp -a /opt/observability/grafana/provisioning/datasources/loki.yml \
  /opt/observability/backup/fase5/loki.yml.bkp.$(date +%F_%H-%M-%S)
```

## 8.3. Atualizar datasource com UID fixo

Editar:

```bash
vim /opt/observability/grafana/provisioning/datasources/loki.yml
```

Conteúdo recomendado:

```yaml
apiVersion: 1

datasources:
  - name: Loki
    uid: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
    editable: true
```

Validar:

```bash
cat /opt/observability/grafana/provisioning/datasources/loki.yml
```

## 8.4. Reiniciar Grafana

```bash
cd /opt/observability
docker compose restart grafana
```

Validar:

```bash
docker compose ps
docker compose logs --tail=100 grafana
```

Acessar:

```text
https://logs.jmsalles.homelab.br
```

Ir em:

```text
Connections
Data sources
Loki
Save & test
```

Resultado esperado:

```text
Data source connected and labels found
```

---

# 9. Criar estrutura de dashboards

Criar diretórios:

```bash
mkdir -p /opt/observability/grafana/provisioning/dashboards/json
```

Validar:

```bash
tree -d /opt/observability/grafana/provisioning
```

Estrutura esperada:

```text
/opt/observability/grafana/provisioning
├── dashboards
│   └── json
└── datasources
```

---

# 10. Criar provider de dashboards

Criar arquivo:

```bash
vim /opt/observability/grafana/provisioning/dashboards/dashboards.yml
```

Conteúdo:

```yaml
apiVersion: 1

providers:
  - name: 'JMSalles Homelab Loki'
    orgId: 1
    folder: 'Homelab - Logs'
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards/json
```

Explicação:

| Campo | Função |
|---|---|
| `folder` | Pasta onde os dashboards aparecerão no Grafana |
| `type: file` | Dashboards serão lidos de arquivos JSON |
| `editable: true` | Permite editar pela interface |
| `updateIntervalSeconds` | Intervalo de leitura dos arquivos |

---

# 11. Copiar dashboards JSON

Copiar os arquivos JSON fornecidos junto com este tutorial para:

```text
/opt/observability/grafana/provisioning/dashboards/json
```

Arquivos:

```text
loki_overview_homelab.json
loki_linux_servers_homelab.json
loki_docker_portainer_homelab.json
loki_kubernetes_homelab.json
```

Exemplo usando `scp` a partir da sua estação:

```bash
scp loki_*.json jmsalles@192.168.31.17:/tmp/
```

Na VM:

```bash
sudo -i
cp /tmp/loki_*.json /opt/observability/grafana/provisioning/dashboards/json/
```

Ajustar permissões:

```bash
chown -R 472:472 /opt/observability/grafana/provisioning/dashboards
```

Validar:

```bash
ls -lh /opt/observability/grafana/provisioning/dashboards/json
```

---

# 12. Reiniciar Grafana para carregar dashboards

```bash
cd /opt/observability
docker compose restart grafana
```

Validar logs:

```bash
docker compose logs --tail=200 grafana
```

Procurar mensagens relacionadas a provisioning:

```bash
docker compose logs grafana | grep -i provisioning
```

---

# 13. Validar dashboards no Grafana

Acessar:

```text
https://logs.jmsalles.homelab.br
```

Ir em:

```text
Dashboards
Browse
Homelab - Logs
```

Devem aparecer:

```text
Loki — Overview Homelab
Loki — Linux Servers
Loki — Docker / Portainer
Loki — Kubernetes
```

---

# 14. Dashboard 1 — Loki Overview Homelab

## 14.1. Objetivo

Fornecer visão geral dos logs do homelab.

## 14.2. Painéis sugeridos

```text
Total de linhas de log
Total de erros/falhas
Total de logs Linux
Total de logs Docker/Kubernetes
Volume por source
Erros por source
Top hosts por volume
Top fontes com erro/falha
Últimos erros/falhas
```

## 14.3. Consultas principais

Total de linhas:

```logql
sum(count_over_time({env="homelab"}[$__range]))
```

Erros/falhas:

```logql
sum(count_over_time({env="homelab"} |~ "(?i)error|failed|exception|backoff|timeout" [$__range]))
```

Volume por origem:

```logql
sum by (source) (count_over_time({env="homelab"}[$__interval]))
```

Erros por origem:

```logql
sum by (source) (count_over_time({env="homelab"} |~ "(?i)error|failed|exception|backoff|timeout" [$__interval]))
```

Top hosts:

```logql
topk(10, sum by (host) (count_over_time({env="homelab"}[$__range])))
```

Últimos erros/falhas:

```logql
{env="homelab"} |~ "(?i)error|failed|exception|backoff|timeout"
```

---

# 15. Dashboard 2 — Loki Linux Servers

## 15.1. Objetivo

Monitorar logs de servidores Linux coletados na Fase 3.

## 15.2. Painéis sugeridos

```text
Total Linux
Falhas SSH
Uso de sudo
Erros Linux
Logs por tipo
Falhas/erros por host
Logs de segurança
Logs gerais do sistema
Backup Kubernetes/etcd
Erros Linux recentes
```

## 15.3. Consultas principais

Todos os logs Linux:

```logql
{source="linux"}
```

Logs por host:

```logql
{source="linux", host=~"$host"}
```

Falhas SSH:

```logql
{source="linux", log_type="secure"} |= "Failed password"
```

Uso de sudo:

```logql
{source="linux", log_type="secure"} |= "sudo"
```

Backup Kubernetes/etcd:

```logql
{source="linux", log_type="k8s-backup"}
```

Erros Linux:

```logql
{source="linux"} |~ "(?i)error|failed|denied|timeout|exception"
```

---

# 16. Dashboard 3 — Loki Docker / Portainer

## 16.1. Objetivo

Monitorar logs de containers Docker/Portainer coletados na Fase 2.

## 16.2. Painéis sugeridos

```text
Total Docker
Erros Docker
Nginx 5xx
Volume por container
Erros por container
Logs por container
Nginx Reverse Proxy
Portainer
```

## 16.3. Consultas principais

Todos os logs Docker:

```logql
{source="docker"}
```

Logs por host Docker:

```logql
{source="docker", host=~"$host"}
```

Logs por container:

```logql
{source="docker", host=~"$host", container=~"$container"}
```

Erros Docker:

```logql
{source="docker"} |~ "(?i)error|failed|exception|timeout"
```

Nginx reverse proxy:

```logql
{source="docker", container=~".*nginx.*"}
```

Nginx 5xx:

```logql
{source="docker", container=~".*nginx.*"} |~ " 5[0-9][0-9] "
```

Portainer:

```logql
{source="docker", container=~".*portainer.*"}
```

---

# 17. Dashboard 4 — Loki Kubernetes

## 17.1. Objetivo

Monitorar logs de pods e eventos Kubernetes coletados na Fase 4.

## 17.2. Painéis sugeridos

```text
Total Kubernetes
Eventos Kubernetes
Erros Kubernetes
Volume por namespace
Problemas por namespace
Logs de pods
Eventos Kubernetes
Problemas Kubernetes
```

## 17.3. Consultas principais

Todos os logs Kubernetes:

```logql
{source="kubernetes"}
```

Logs por cluster:

```logql
{source="kubernetes", cluster=~"$cluster"}
```

Logs por namespace:

```logql
{source="kubernetes", cluster=~"$cluster", namespace=~"$namespace"}
```

Logs por pod:

```logql
{source="kubernetes", cluster=~"$cluster", namespace=~"$namespace", pod=~"$pod"}
```

Eventos Kubernetes:

```logql
{source="kubernetes", log_type="event"}
```

Problemas Kubernetes:

```logql
{source="kubernetes"} |~ "(?i)failed|error|backoff|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|FailedMount|FailedScheduling|Unhealthy"
```

ImagePullBackOff:

```logql
{source="kubernetes"} |= "ImagePullBackOff"
```

FailedScheduling:

```logql
{source="kubernetes", log_type="event"} |= "FailedScheduling"
```

FailedMount:

```logql
{source="kubernetes", log_type="event"} |= "FailedMount"
```

---

# 18. Método alternativo — importar pela interface

Caso não queira provisionar por arquivo, é possível importar manualmente.

No Grafana:

```text
Dashboards
New
Import
Upload dashboard JSON file
```

Selecionar um dos arquivos:

```text
loki_overview_homelab.json
loki_linux_servers_homelab.json
loki_docker_portainer_homelab.json
loki_kubernetes_homelab.json
```

Selecionar datasource:

```text
Loki
```

Salvar.

---

# 19. Boas práticas para dashboards Loki

## 19.1. Usar intervalo curto

Para investigação operacional, usar inicialmente:

```text
Last 15 minutes
Last 1 hour
Last 6 hours
```

Evitar abrir painéis com períodos muito grandes sem necessidade.

## 19.2. Evitar refresh muito agressivo

Recomendações:

```text
Produção/homelab normal: 1m ou 5m
Investigação ativa: 30s temporariamente
Histórico: refresh desligado
```

Refresh muito baixo aumenta carga no Grafana, Loki e navegador.

## 19.3. Usar labels antes de texto

Melhor:

```logql
{source="kubernetes", namespace="kube-system"} |= "error"
```

Pior:

```logql
{env="homelab"} |~ ".*kube-system.*error.*"
```

## 19.4. Evitar regex muito ampla

Melhor:

```logql
{source="docker", container=~".*nginx.*"} |= "502"
```

Pior:

```logql
{env="homelab"} |~ ".*502.*"
```

---

# 20. Backup dos dashboards

## 20.1. Criar script

Na VM observabilidade:

```bash
vim /usr/local/sbin/backup-grafana-dashboards.sh
```

Conteúdo:

```bash
#!/bin/bash

DATA=$(date +%F_%H-%M-%S)
DESTINO="/opt/observability/backup/dashboards"
ARQUIVO="${DESTINO}/grafana-dashboards-${DATA}.tar.gz"
LOG="/var/log/backup-grafana-dashboards.log"

mkdir -p "$DESTINO"

echo "[$(date '+%F %T')] Iniciando backup dos dashboards Grafana" >> "$LOG"

tar -czf "$ARQUIVO" \
  /opt/observability/grafana/provisioning/dashboards \
  /opt/observability/grafana/provisioning/datasources 2>> "$LOG"

if [ $? -eq 0 ]; then
  echo "[$(date '+%F %T')] Backup criado com sucesso: $ARQUIVO" >> "$LOG"
else
  echo "[$(date '+%F %T')] ERRO ao criar backup" >> "$LOG"
  exit 1
fi

find "$DESTINO" -type f -name "grafana-dashboards-*.tar.gz" -mtime +30 -delete

echo "[$(date '+%F %T')] Rotina finalizada" >> "$LOG"
```

Permissão:

```bash
chmod +x /usr/local/sbin/backup-grafana-dashboards.sh
```

Testar:

```bash
/usr/local/sbin/backup-grafana-dashboards.sh
```

Validar:

```bash
ls -lh /opt/observability/backup/dashboards
tail -n 50 /var/log/backup-grafana-dashboards.log
```

Agendar:

```bash
crontab -e
```

Adicionar:

```cron
30 1 * * * /usr/local/sbin/backup-grafana-dashboards.sh >> /var/log/backup-grafana-dashboards.log 2>&1
```

---

# 21. Rollback

## 21.1. Parar Grafana

```bash
cd /opt/observability
docker compose stop grafana
```

## 21.2. Restaurar backup

Exemplo:

```bash
tar -xzf /opt/observability/backup/dashboards/grafana-dashboards-YYYY-MM-DD_HH-MM-SS.tar.gz -C /
```

## 21.3. Subir Grafana

```bash
cd /opt/observability
docker compose start grafana
```

Validar:

```bash
docker compose logs --tail=100 grafana
```

---

# 22. Troubleshooting

## 22.1. Dashboards não aparecem

Validar diretório:

```bash
ls -lh /opt/observability/grafana/provisioning/dashboards
ls -lh /opt/observability/grafana/provisioning/dashboards/json
```

Validar provider:

```bash
cat /opt/observability/grafana/provisioning/dashboards/dashboards.yml
```

Ver logs:

```bash
cd /opt/observability
docker compose logs grafana | grep -i dashboard
docker compose logs grafana | grep -i provisioning
```

Reiniciar:

```bash
docker compose restart grafana
```

## 22.2. Painéis mostram erro de datasource

Validar datasource:

```bash
cat /opt/observability/grafana/provisioning/datasources/loki.yml
```

Esperado:

```yaml
uid: Loki
```

No Grafana:

```text
Connections
Data sources
Loki
Save & test
```

## 22.3. Painéis vazios

Verificar se há dados:

```logql
{env="homelab"}
```

Depois testar por origem:

```logql
{source="linux"}
{source="docker"}
{source="kubernetes"}
```

Ajustar intervalo de tempo para:

```text
Last 6 hours
Last 24 hours
```

## 22.4. Dashboard lento

Reduzir intervalo:

```text
Last 15 minutes
Last 1 hour
```

Remover refresh agressivo:

```text
Refresh: 1m ou 5m
```

Evitar filtros muito amplos:

```logql
{env="homelab"} |~ ".*error.*"
```

Preferir:

```logql
{source="linux", host="lenovo-server-linux"} |= "error"
```

## 22.5. Variáveis não carregam

Validar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Validar valores:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/source/values" | jq
curl -s "http://192.168.31.17:3100/loki/api/v1/label/host/values" | jq
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
curl -s "http://192.168.31.17:3100/loki/api/v1/label/namespace/values" | jq
```

Se a label não existe, o painel/variável não conseguirá filtrar por ela.

---

# 23. Validação final da Fase 5

No Grafana, validar a pasta:

```text
Dashboards
Browse
Homelab - Logs
```

Validar os dashboards:

```text
Loki — Overview Homelab
Loki — Linux Servers
Loki — Docker / Portainer
Loki — Kubernetes
```

Validar queries:

```logql
{env="homelab"}
{source="linux"}
{source="docker"}
{source="kubernetes"}
```

Gerar logs de teste se necessário.

Linux:

```bash
logger "VALIDACAO FASE 5 DASHBOARD LINUX - $(date)"
```

Docker:

```bash
docker run --rm --name validacao-fase5-dashboard alpine sh -c 'echo "VALIDACAO FASE 5 DASHBOARD DOCKER - $(date)"'
```

Kubernetes:

```bash
kubectl run validacao-fase5-dashboard \
  --restart=Never \
  --image=busybox:latest \
  -- sh -c 'echo "VALIDACAO FASE 5 DASHBOARD K8S - $(date)"; sleep 5'
```

Consultar:

```logql
{env="homelab"} |= "VALIDACAO FASE 5"
```

---

# 24. Próximas fases

Após validar a Fase 5:

```text
Fase 6 - Alertas básicos baseados em logs
Fase 7 - Integração operacional com Zabbix
Fase 8 - Ajuste fino de retenção e volume
Fase 9 - Avaliação de armazenamento em MinIO/S3 para Loki
```

---

# 25. Referências oficiais usadas como base técnica

```text
Grafana Dashboards:
https://grafana.com/docs/grafana/latest/dashboards/

Grafana Dashboard troubleshooting:
https://grafana.com/docs/grafana/latest/dashboards/troubleshoot-dashboards/

Grafana Loki LogQL:
https://grafana.com/docs/loki/latest/query/

Grafana Loki Query examples:
https://grafana.com/docs/loki/latest/query/query_examples/

Grafana Loki query troubleshooting:
https://grafana.com/docs/loki/latest/query/troubleshoot-query/
```
