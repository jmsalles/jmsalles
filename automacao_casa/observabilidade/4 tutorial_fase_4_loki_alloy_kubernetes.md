# Tutorial — Fase 4 — Coleta de Logs do Kubernetes com Grafana Alloy e Loki

## 1. Identificação do documento

| Item | Informação |
|---|---|
| Ambiente | Homelab |
| Fase | Fase 4 |
| Objetivo | Coletar logs de pods e eventos Kubernetes e enviar para Loki |
| Cluster | `k8s-homelab` |
| Namespace de observabilidade | `observability` |
| Release Helm | `alloy-k8s-logs` |
| Coletor | Grafana Alloy |
| Modelo de instalação | Helm chart |
| Servidor central de logs | `observabilidade` |
| IP do Loki | `192.168.31.17` |
| Endpoint Loki para ingestão | `http://192.168.31.17:3100/loki/api/v1/push` |
| Grafana | `https://logs.jmsalles.homelab.br` |
| Foco da coleta | Pods, containers, namespaces, nodes e eventos Kubernetes |
| Tipo de alteração no cluster | Criação de namespace, ServiceAccount, RBAC, ConfigMap e workload Alloy |
| Impacto esperado nas aplicações | Sem alteração nos deployments/aplicações existentes |

---

## 2. Objetivo

Implantar o **Grafana Alloy** dentro do cluster Kubernetes para coletar:

```text
Logs dos pods
Logs dos containers
Labels por namespace
Labels por pod
Labels por container
Labels por node
Eventos do Kubernetes
```

E enviar tudo para o Loki central:

```text
http://192.168.31.17:3100/loki/api/v1/push
```

A consulta será feita no Grafana:

```text
https://logs.jmsalles.homelab.br
```

---

## 3. Contexto das fases anteriores

| Fase | Resultado |
|---|---|
| Fase 1 | Loki + Grafana + Alloy local implantados na VM `observabilidade` |
| Fase 2 | Logs Docker/Portainer coletados no host `docker-hml` |
| Fase 3 | Logs Linux coletados via Alloy em servidores Linux |
| Fase 4 | Coleta de logs e eventos Kubernetes |

Nesta fase, não vamos substituir Zabbix, nem alterar aplicações, nem instalar agentes nos containers de aplicação.

O Alloy será executado como workload no cluster, usando a API do Kubernetes para coletar logs dos pods e eventos.

---

## 4. Arquitetura da Fase 4

```text
+------------------------------------------------------------------+
| Cluster Kubernetes                                               |
|                                                                  |
|  Namespace: observability                                        |
|                                                                  |
|  +-------------------------+                                     |
|  | Grafana Alloy           |                                     |
|  | alloy-k8s-logs          |                                     |
|  | ServiceAccount + RBAC   |                                     |
|  +-----------+-------------+                                     |
|              |                                                   |
|              | Kubernetes API                                    |
|              v                                                   |
|  +-------------------------+                                     |
|  | Pods / Containers       |                                     |
|  | Namespaces              |                                     |
|  | Kubernetes Events       |                                     |
|  +-----------+-------------+                                     |
|              |                                                   |
|              | HTTP push                                         |
|              v                                                   |
+--------------+---------------------------------------------------+
               |
               | http://192.168.31.17:3100/loki/api/v1/push
               v
+------------------------------------------------------------------+
| VM observabilidade                                               |
| IP: 192.168.31.17                                                |
|                                                                  |
|  +----------------------+       +-----------------------------+  |
|  | Loki                 | <---- | Grafana                     |  |
|  | Porta 3100           |       | https://logs.jmsalles...    |  |
|  +----------------------+       +-----------------------------+  |
+------------------------------------------------------------------+
```

---

## 5. Modelo escolhido

Para esta fase, usaremos o modelo:

```text
Alloy instalado no Kubernetes via Helm chart
Coleta de logs via Kubernetes API
Coleta de eventos via Kubernetes API
Envio para Loki central externo ao cluster
```

Componentes Alloy usados:

```text
loki.write
discovery.kubernetes
discovery.relabel
loki.source.kubernetes
loki.source.kubernetes_events
loki.process
```

---

## 6. Por que usar Kubernetes API nesta fase

O Alloy possui mais de uma forma de coletar logs Kubernetes.

### 6.1. Modelo A — Kubernetes API

```text
loki.source.kubernetes
```

Vantagens:

```text
Não precisa acessar /var/log/pods nos nodes
Não precisa rodar container privilegiado
Não precisa montar filesystem do node
Não exige root no container
Pode coletar logs de pods usando a API do Kubernetes
```

Desvantagem:

```text
Pode gerar mais tráfego e consumo de CPU nos kubelets, pois a leitura dos logs passa pela API.
```

### 6.2. Modelo B — Leitura de arquivos nos nodes

```text
/var/log/containers/*.log
/var/log/pods/*.log
```

Vantagens:

```text
Muito comum em ambientes grandes
Coleta local por node
Pode ser mais eficiente em volume alto
```

Desvantagens:

```text
Exige DaemonSet
Exige montagem de diretórios do host
Exige mais cuidado com permissões
Mais invasivo no node
```

### 6.3. Decisão para o homelab

Para esta fase, o modelo escolhido é:

```text
Kubernetes API com loki.source.kubernetes
```

Motivo:

```text
Menos invasivo
Mais simples para começar
Mais fácil de remover
Não exige acesso ao filesystem dos nodes
Boa opção para primeira implantação no cluster
```

---

## 7. O que esta fase altera no cluster

Esta implantação cria recursos no Kubernetes:

```text
Namespace observability
ServiceAccount do Alloy
ClusterRole/ClusterRoleBinding
ConfigMap com config.alloy
Deployment ou DaemonSet do Alloy, conforme valores do Helm chart
Service interno do Alloy
```

Esta implantação não altera:

```text
Deployments existentes
Services existentes
Ingress existentes
ConfigMaps das aplicações
Secrets das aplicações
Volumes das aplicações
Nodes
CNI
kubelet
etcd
control-plane
```

---

## 8. Pré-requisitos

### 8.1. Loki funcionando

Validar de qualquer node/host com acesso ao Loki:

```bash
curl -s http://192.168.31.17:3100/ready
```

Resultado esperado:

```text
ready
```

### 8.2. kubectl funcionando

No host de administração:

```bash
kubectl cluster-info
```

Validar nodes:

```bash
kubectl get nodes -o wide
```

Validar namespaces:

```bash
kubectl get ns
```

### 8.3. Helm instalado

Validar Helm:

```bash
helm version
```

Se não estiver instalado, instalar conforme o sistema operacional do host de administração.

Em Rocky/RHEL, exemplo genérico:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Validar:

```bash
helm version
```

---

## 9. Definir variáveis da implantação

No host de administração do cluster:

```bash
export CLUSTER_NAME="k8s-homelab"
export LOKI_URL="http://192.168.31.17:3100/loki/api/v1/push"
export NAMESPACE="observability"
export RELEASE_NAME="alloy-k8s-logs"
```

Validar:

```bash
echo "$CLUSTER_NAME"
echo "$LOKI_URL"
echo "$NAMESPACE"
echo "$RELEASE_NAME"
```

Se for outro cluster, ajustar:

```bash
export CLUSTER_NAME="k8s-prd"
```

ou:

```bash
export CLUSTER_NAME="k8s-hml"
```

---

## 10. Validar conectividade do cluster com o Loki

Antes de instalar o Alloy, validar se o cluster consegue acessar o Loki.

Criar pod temporário de teste:

```bash
kubectl run teste-loki-connect \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl:latest \
  -- curl -s http://192.168.31.17:3100/ready
```

Resultado esperado:

```text
ready
```

Se não responder, validar:

```text
Rota do cluster até 192.168.31.17
DNS/rede entre pods e rede 192.168.31.0/24
Políticas de rede, se existirem
Firewall externo, se existir
```

Como seu padrão de homelab é firewall local desabilitado, o ponto mais comum seria rota/rede.

---

## 11. Criar namespace

Criar namespace:

```bash
kubectl create namespace observability
```

Se já existir:

```bash
kubectl get namespace observability
```

Adicionar labels úteis:

```bash
kubectl label namespace observability name=observability --overwrite
kubectl label namespace observability app.kubernetes.io/part-of=observability --overwrite
```

Validar:

```bash
kubectl get ns observability --show-labels
```

---

## 12. Adicionar repositório Helm da Grafana

Adicionar repositório:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
```

Atualizar repositórios:

```bash
helm repo update
```

Validar chart disponível:

```bash
helm search repo grafana/alloy
```

---

## 13. Criar diretório de trabalho

Criar diretório local no host de administração:

```bash
mkdir -p ~/k8s-observability/alloy-k8s-logs/{values,backup}
```

Entrar no diretório:

```bash
cd ~/k8s-observability/alloy-k8s-logs
```

Validar:

```bash
pwd
ls -lah
```

---

## 14. Criar arquivo values do Helm

Criar arquivo:

```bash
vi ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

Conteúdo:

```yaml
controller:
  type: deployment
  replicas: 1

serviceAccount:
  create: true

rbac:
  create: true

alloy:
  clustering:
    enabled: false

  configMap:
    create: true
    content: |-
      logging {
        level  = "info"
        format = "logfmt"
      }

      loki.write "loki_central" {
        endpoint {
          url = "http://192.168.31.17:3100/loki/api/v1/push"
        }
      }

      discovery.kubernetes "pods" {
        role = "pod"
      }

      discovery.relabel "pod_logs" {
        targets = discovery.kubernetes.pods.targets

        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          action        = "replace"
          target_label  = "namespace"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          action        = "replace"
          target_label  = "pod"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          action        = "replace"
          target_label  = "container"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_node_name"]
          action        = "replace"
          target_label  = "node"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
          action        = "replace"
          target_label  = "app"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_label_app"]
          action        = "replace"
          target_label  = "app_label"
        }

        rule {
          source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
          action        = "replace"
          target_label  = "job"
          separator     = "/"
          replacement   = "$1"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_controller_kind"]
          action        = "replace"
          target_label  = "workload_kind"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_controller_name"]
          action        = "replace"
          target_label  = "workload_name"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_container_id"]
          action        = "replace"
          target_label  = "container_runtime"
          regex         = `^(\S+):\/\/.+$`
          replacement   = "$1"
        }
      }

      loki.source.kubernetes "pod_logs" {
        targets    = discovery.relabel.pod_logs.output
        forward_to = [loki.process.pod_logs.receiver]
      }

      loki.process "pod_logs" {
        stage.static_labels {
          values = {
            cluster = "k8s-homelab",
            env     = "homelab",
            source  = "kubernetes",
            log_type = "pod",
          }
        }

        forward_to = [loki.write.loki_central.receiver]
      }

      loki.source.kubernetes_events "cluster_events" {
        job_name   = "integrations/kubernetes/eventhandler"
        log_format = "logfmt"
        forward_to = [loki.process.cluster_events.receiver]
      }

      loki.process "cluster_events" {
        stage.static_labels {
          values = {
            cluster  = "k8s-homelab",
            env      = "homelab",
            source   = "kubernetes",
            log_type = "event",
          }
        }

        stage.labels {
          values = {
            kubernetes_cluster_events = "job",
          }
        }

        forward_to = [loki.write.loki_central.receiver]
      }

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

---

## 15. Ajustar nome do cluster no values

Se o cluster não for `k8s-homelab`, ajustar:

```bash
sed -i "s/k8s-homelab/${CLUSTER_NAME}/g" ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

Validar:

```bash
grep cluster ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

---

## 16. Explicação da configuração

### 16.1. `loki.write`

```river
loki.write "loki_central" {
  endpoint {
    url = "http://192.168.31.17:3100/loki/api/v1/push"
  }
}
```

Define o destino dos logs.

---

### 16.2. `discovery.kubernetes`

```river
discovery.kubernetes "pods" {
  role = "pod"
}
```

Descobre pods no cluster.

---

### 16.3. `discovery.relabel`

```river
discovery.relabel "pod_logs" {
  targets = discovery.kubernetes.pods.targets
  ...
}
```

Transforma metadados do Kubernetes em labels úteis para o Loki.

Labels criadas:

```text
namespace
pod
container
node
app
app_label
job
workload_kind
workload_name
container_runtime
```

---

### 16.4. `loki.source.kubernetes`

```river
loki.source.kubernetes "pod_logs" {
  targets    = discovery.relabel.pod_logs.output
  forward_to = [loki.process.pod_logs.receiver]
}
```

Coleta logs dos containers dos pods usando a API do Kubernetes.

---

### 16.5. `loki.process`

```river
loki.process "pod_logs" {
  stage.static_labels {
    values = {
      cluster = "k8s-homelab",
      env     = "homelab",
      source  = "kubernetes",
      log_type = "pod",
    }
  }

  forward_to = [loki.write.loki_central.receiver]
}
```

Adiciona labels fixas e envia para o Loki.

---

### 16.6. `loki.source.kubernetes_events`

```river
loki.source.kubernetes_events "cluster_events" {
  job_name   = "integrations/kubernetes/eventhandler"
  log_format = "logfmt"
  forward_to = [loki.process.cluster_events.receiver]
}
```

Coleta eventos do Kubernetes.

Exemplos de eventos úteis:

```text
BackOff
FailedScheduling
FailedMount
FailedPull
Unhealthy
Killing
Pulled
Created
Started
NodeNotReady
NodeReady
```

---

## 17. Fazer dry-run do Helm

Executar:

```bash
helm upgrade --install alloy-k8s-logs grafana/alloy \
  --namespace observability \
  --values ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml \
  --dry-run \
  --debug
```

Validar se não há erro de YAML, Helm ou template.

---

## 18. Instalar Alloy no Kubernetes

Executar:

```bash
helm upgrade --install alloy-k8s-logs grafana/alloy \
  --namespace observability \
  --values ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

Validar release:

```bash
helm list -n observability
```

Resultado esperado:

```text
alloy-k8s-logs
```

---

## 19. Validar recursos criados

Validar pods:

```bash
kubectl get pods -n observability -o wide
```

Validar deployment:

```bash
kubectl get deploy -n observability
```

Validar services:

```bash
kubectl get svc -n observability
```

Validar service account:

```bash
kubectl get sa -n observability
```

Validar configmaps:

```bash
kubectl get cm -n observability
```

Validar eventos do namespace:

```bash
kubectl get events -n observability --sort-by='.lastTimestamp'
```

---

## 20. Validar logs do Alloy

Ver logs do pod Alloy:

```bash
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=200
```

Acompanhar em tempo real:

```bash
kubectl logs -n observability -l app.kubernetes.io/name=alloy -f
```

Se houver mais de um pod:

```bash
kubectl get pods -n observability
```

Depois:

```bash
kubectl logs -n observability POD_DO_ALLOY -f
```

---

## 21. Validar conectividade do Alloy com Loki

Executar teste dentro do namespace:

```bash
kubectl run teste-loki-from-observability \
  -n observability \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl:latest \
  -- curl -s http://192.168.31.17:3100/ready
```

Resultado esperado:

```text
ready
```

---

## 22. Gerar logs de teste no Kubernetes

Criar pod temporário:

```bash
kubectl run teste-loki-k8s \
  --restart=Never \
  --image=busybox:latest \
  -- sh -c 'for i in 1 2 3 4 5; do echo "VALIDACAO FASE 4 LOKI K8S linha $i - $(date)"; sleep 2; done'
```

Ver logs pelo kubectl:

```bash
kubectl logs teste-loki-k8s
```

Aguardar alguns segundos e remover:

```bash
kubectl delete pod teste-loki-k8s
```

---

## 23. Gerar evento Kubernetes de teste

Criar um pod com imagem inexistente para gerar evento de erro:

```bash
kubectl run teste-evento-loki \
  --restart=Never \
  --image=imagem-inexistente-loki-teste:0.0.1
```

Validar eventos:

```bash
kubectl get events --sort-by='.lastTimestamp' | tail -n 20
```

Depois remover:

```bash
kubectl delete pod teste-evento-loki --ignore-not-found
```

Esse teste deve gerar eventos como:

```text
Failed
ErrImagePull
ImagePullBackOff
BackOff
```

---

## 24. Validar no Loki via API

Consultar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Consultar clusters:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/cluster/values" | jq
```

Consultar fontes:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/source/values" | jq
```

Consultar namespaces:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/namespace/values" | jq
```

Consultar pods:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/pod/values" | jq
```

Consultar containers:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
```

Resultado esperado:

```text
cluster = k8s-homelab
source = kubernetes
log_type = pod/event
namespace = default, kube-system, observability, etc.
```

---

## 25. Validar no Grafana

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
{source="kubernetes"}
```

Consulta do cluster:

```logql
{cluster="k8s-homelab"}
```

Consulta de logs de pods:

```logql
{cluster="k8s-homelab", log_type="pod"}
```

Consulta de eventos:

```logql
{cluster="k8s-homelab", log_type="event"}
```

Consulta da validação:

```logql
{cluster="k8s-homelab"} |= "VALIDACAO FASE 4"
```

---

## 26. Consultas LogQL úteis para Kubernetes

### 26.1. Todos os logs Kubernetes

```logql
{source="kubernetes"}
```

### 26.2. Logs por cluster

```logql
{cluster="k8s-homelab"}
```

### 26.3. Logs por namespace

```logql
{cluster="k8s-homelab", namespace="default"}
```

```logql
{cluster="k8s-homelab", namespace="kube-system"}
```

```logql
{cluster="k8s-homelab", namespace="observability"}
```

### 26.4. Logs por pod

```logql
{cluster="k8s-homelab", pod="NOME_DO_POD"}
```

### 26.5. Logs por container

```logql
{cluster="k8s-homelab", container="NOME_DO_CONTAINER"}
```

### 26.6. Logs por node

```logql
{cluster="k8s-homelab", node="NOME_DO_NODE"}
```

### 26.7. Erros gerais

```logql
{cluster="k8s-homelab"} |= "error"
```

### 26.8. Falhas gerais

```logql
{cluster="k8s-homelab"} |= "failed"
```

### 26.9. CrashLoopBackOff

```logql
{cluster="k8s-homelab"} |= "CrashLoopBackOff"
```

### 26.10. ImagePullBackOff

```logql
{cluster="k8s-homelab"} |= "ImagePullBackOff"
```

### 26.11. ErrImagePull

```logql
{cluster="k8s-homelab"} |= "ErrImagePull"
```

### 26.12. FailedScheduling

```logql
{cluster="k8s-homelab", log_type="event"} |= "FailedScheduling"
```

### 26.13. FailedMount

```logql
{cluster="k8s-homelab", log_type="event"} |= "FailedMount"
```

### 26.14. BackOff

```logql
{cluster="k8s-homelab", log_type="event"} |= "BackOff"
```

### 26.15. kube-system

```logql
{cluster="k8s-homelab", namespace="kube-system"}
```

### 26.16. Etcd

```logql
{cluster="k8s-homelab", pod=~".*etcd.*"}
```

### 26.17. CoreDNS

```logql
{cluster="k8s-homelab", pod=~".*coredns.*"}
```

### 26.18. Ingress

```logql
{cluster="k8s-homelab", pod=~".*ingress.*"}
```

### 26.19. MetalLB

```logql
{cluster="k8s-homelab", namespace=~".*metallb.*|metallb-system"}
```

### 26.20. ArgoCD

```logql
{cluster="k8s-homelab", namespace=~".*argocd.*"}
```

---

## 27. Consultas para investigação rápida

### 27.1. Ver tudo que falhou nos últimos minutos

```logql
{cluster="k8s-homelab"} |~ "(?i)failed|error|exception|backoff"
```

### 27.2. Problemas de imagem

```logql
{cluster="k8s-homelab"} |~ "ImagePullBackOff|ErrImagePull|pull access denied|not found"
```

### 27.3. Problemas de volume

```logql
{cluster="k8s-homelab"} |~ "FailedMount|MountVolume|Unable to attach|volume"
```

### 27.4. Problemas de scheduler

```logql
{cluster="k8s-homelab", log_type="event"} |= "FailedScheduling"
```

### 27.5. Problemas de readiness/liveness

```logql
{cluster="k8s-homelab"} |~ "Readiness probe failed|Liveness probe failed|Unhealthy"
```

---

## 28. Conferir cardinalidade

Consultar labels:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/labels" | jq
```

Consultar namespaces:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/namespace/values" | jq
```

Consultar pods:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/pod/values" | jq
```

Consultar containers:

```bash
curl -s "http://192.168.31.17:3100/loki/api/v1/label/container/values" | jq
```

Observação:

```text
A label pod pode crescer conforme pods são recriados.
Em homelab isso é aceitável no início.
Em ambiente maior, avaliar reduzir labels muito variáveis.
```

---

## 29. Operação do Alloy no Kubernetes

### 29.1. Ver release

```bash
helm list -n observability
```

### 29.2. Ver values aplicados

```bash
helm get values alloy-k8s-logs -n observability
```

### 29.3. Ver manifesto renderizado

```bash
helm get manifest alloy-k8s-logs -n observability
```

### 29.4. Ver pods

```bash
kubectl get pods -n observability -o wide
```

### 29.5. Ver logs do Alloy

```bash
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=200
```

### 29.6. Reiniciar Alloy

```bash
kubectl rollout restart deployment -n observability
```

Se o nome exato do deployment for necessário:

```bash
kubectl get deploy -n observability
```

Depois:

```bash
kubectl rollout restart deployment/NOME_DO_DEPLOYMENT -n observability
```

### 29.7. Acompanhar rollout

```bash
kubectl rollout status deployment -n observability
```

Ou com nome:

```bash
kubectl rollout status deployment/NOME_DO_DEPLOYMENT -n observability
```

---

## 30. Atualizar configuração

Editar o arquivo values:

```bash
vi ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

Aplicar:

```bash
helm upgrade alloy-k8s-logs grafana/alloy \
  --namespace observability \
  --values ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

Validar:

```bash
kubectl get pods -n observability
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=100
```

---

## 31. Backup da configuração

Criar script local no host de administração:

```bash
vi ~/k8s-observability/alloy-k8s-logs/backup/backup-alloy-k8s-logs.sh
```

Conteúdo:

```bash
#!/bin/bash

DATA=$(date +%F_%H-%M-%S)
BASE="$HOME/k8s-observability/alloy-k8s-logs"
DESTINO="${BASE}/backup"
ARQUIVO="${DESTINO}/alloy-k8s-logs-${DATA}.tar.gz"

mkdir -p "$DESTINO"

tar -czf "$ARQUIVO" \
  "${BASE}/values"

helm get values alloy-k8s-logs -n observability > "${DESTINO}/helm-values-${DATA}.yml" 2>/dev/null || true
helm get manifest alloy-k8s-logs -n observability > "${DESTINO}/helm-manifest-${DATA}.yml" 2>/dev/null || true

find "$DESTINO" -type f -name "alloy-k8s-logs-*.tar.gz" -mtime +30 -delete
find "$DESTINO" -type f -name "helm-values-*.yml" -mtime +30 -delete
find "$DESTINO" -type f -name "helm-manifest-*.yml" -mtime +30 -delete

echo "Backup criado: $ARQUIVO"
```

Permissão:

```bash
chmod +x ~/k8s-observability/alloy-k8s-logs/backup/backup-alloy-k8s-logs.sh
```

Executar:

```bash
~/k8s-observability/alloy-k8s-logs/backup/backup-alloy-k8s-logs.sh
```

Validar:

```bash
ls -lh ~/k8s-observability/alloy-k8s-logs/backup
```

---

## 32. Rollback

### 32.1. Rollback via Helm

Listar histórico:

```bash
helm history alloy-k8s-logs -n observability
```

Rollback para uma revisão anterior:

```bash
helm rollback alloy-k8s-logs NUMERO_DA_REVISAO -n observability
```

Validar:

```bash
kubectl get pods -n observability
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=100
```

---

### 32.2. Rollback usando arquivo values anterior

Aplicar values anterior:

```bash
helm upgrade alloy-k8s-logs grafana/alloy \
  --namespace observability \
  --values CAMINHO_DO_VALUES_ANTERIOR.yml
```

Validar:

```bash
helm list -n observability
kubectl get pods -n observability
```

---

## 33. Desinstalação

Se for necessário remover a Fase 4:

```bash
helm uninstall alloy-k8s-logs -n observability
```

Validar:

```bash
helm list -n observability
kubectl get all -n observability
```

Se o namespace `observability` não for usado por mais nada:

```bash
kubectl delete namespace observability
```

Atenção:

```text
Só delete o namespace se tiver certeza de que não há outros componentes nele.
```

---

## 34. Troubleshooting

### 34.1. Pod do Alloy não sobe

Ver pods:

```bash
kubectl get pods -n observability -o wide
```

Descrever pod:

```bash
kubectl describe pod -n observability NOME_DO_POD
```

Ver eventos:

```bash
kubectl get events -n observability --sort-by='.lastTimestamp'
```

---

### 34.2. Erro de configuração no Alloy

Ver logs:

```bash
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=200
```

Validar values:

```bash
helm get values alloy-k8s-logs -n observability
```

Renderizar localmente:

```bash
helm template alloy-k8s-logs grafana/alloy \
  --namespace observability \
  --values ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

---

### 34.3. Alloy sobe, mas não envia logs

Validar conectividade com Loki:

```bash
kubectl run teste-loki \
  -n observability \
  --rm -it \
  --restart=Never \
  --image=curlimages/curl:latest \
  -- curl -s http://192.168.31.17:3100/ready
```

Ver logs do Alloy:

```bash
kubectl logs -n observability -l app.kubernetes.io/name=alloy -f
```

Gerar log de teste:

```bash
kubectl run teste-loki-k8s \
  --restart=Never \
  --image=busybox:latest \
  -- sh -c 'echo "TESTE ENVIO LOKI K8S - $(date)"; sleep 5'
```

Consultar no Grafana:

```logql
{source="kubernetes"} |= "TESTE ENVIO LOKI K8S"
```

---

### 34.4. Eventos não aparecem

Gerar evento com imagem inexistente:

```bash
kubectl run teste-evento-loki \
  --restart=Never \
  --image=imagem-inexistente-loki-teste:0.0.1
```

Ver eventos:

```bash
kubectl get events --sort-by='.lastTimestamp' | tail -n 20
```

Consultar no Grafana:

```logql
{source="kubernetes", log_type="event"} |= "ErrImagePull"
```

Remover:

```bash
kubectl delete pod teste-evento-loki --ignore-not-found
```

---

### 34.5. Permissão RBAC insuficiente

Ver logs:

```bash
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=200
```

Procurar mensagens como:

```text
forbidden
cannot list resource
cannot watch resource
```

Validar RBAC:

```bash
kubectl get clusterrole | grep -i alloy
kubectl get clusterrolebinding | grep -i alloy
kubectl get sa -n observability
```

Descrever ClusterRoleBinding:

```bash
kubectl describe clusterrolebinding NOME_DO_BINDING
```

---

### 34.6. Logs de pods aparecem, mas sem label de namespace/pod/container

Validar configuração `discovery.relabel`:

```bash
helm get values alloy-k8s-logs -n observability
```

Procurar regras:

```text
target_label = "namespace"
target_label = "pod"
target_label = "container"
target_label = "node"
```

Depois aplicar novamente:

```bash
helm upgrade alloy-k8s-logs grafana/alloy \
  --namespace observability \
  --values ~/k8s-observability/alloy-k8s-logs/values/values-alloy-k8s-logs.yml
```

---

## 35. Validação final da Fase 4

Executar:

```bash
kubectl get pods -n observability -o wide
helm list -n observability
curl -s http://192.168.31.17:3100/ready
```

Gerar log:

```bash
kubectl run validacao-final-fase4 \
  --restart=Never \
  --image=busybox:latest \
  -- sh -c 'echo "VALIDACAO FINAL FASE 4 KUBERNETES LOGS - $(date)"; sleep 5'
```

Ver pelo kubectl:

```bash
kubectl logs validacao-final-fase4
```

Consultar no Grafana:

```logql
{source="kubernetes"} |= "VALIDACAO FINAL FASE 4"
```

Remover pod:

```bash
kubectl delete pod validacao-final-fase4 --ignore-not-found
```

Validar eventos:

```bash
kubectl run validacao-evento-fase4 \
  --restart=Never \
  --image=imagem-inexistente-validacao-fase4:0.0.1
```

Consultar no Grafana:

```logql
{source="kubernetes", log_type="event"} |~ "ErrImagePull|ImagePullBackOff|BackOff"
```

Remover:

```bash
kubectl delete pod validacao-evento-fase4 --ignore-not-found
```

---

## 36. Estado final esperado

Ao final desta fase:

```text
Namespace observability criado
Release Helm alloy-k8s-logs instalado
Alloy rodando no cluster
Logs de pods chegando no Loki
Eventos Kubernetes chegando no Loki
Grafana exibindo logs por cluster, namespace, pod, container e node
Endpoint Loki usado: http://192.168.31.17:3100/loki/api/v1/push
Aplicações existentes sem alteração
```

---

## 37. Próximas fases

Após validar a Fase 4:

```text
Fase 5 - Dashboards iniciais no Grafana
Fase 6 - Alertas básicos baseados em logs
Fase 7 - Integração operacional com Zabbix
Fase 8 - Ajuste de retenção e volume de logs
Fase 9 - Avaliação de armazenamento em MinIO/S3 para Loki
```

---

## 38. Referências oficiais usadas como base técnica

```text
Grafana Alloy — Collect Kubernetes logs:
https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/

Grafana Alloy — Configure on Kubernetes:
https://grafana.com/docs/alloy/latest/configure/kubernetes/

Grafana Alloy — loki.source.kubernetes:
https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.kubernetes/

Grafana Alloy — loki.source.kubernetes_events:
https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.kubernetes_events/
```
