# Documento de pós-instalação do cluster Kubernetes HML/PRD

## 1. Objetivo

Este documento descreve a estrutura recomendada para a fase de pós-instalação dos clusters Kubernetes de HML e PRD do homelab jmsalles.homelab.br.

A proposta é transformar os clusters em uma plataforma DevOps/GitOps leve, funcional e próxima de um ambiente corporativo real, utilizando:

* Argo CD para GitOps
* Gitea como Git local leve
* Gitea act_runner como runner de CI/CD
* Nexus Repository como registry e repositório de artefatos
* Vault para gestão de segredos
* ingress-nginx para publicação HTTP/HTTPS
* MetalLB para entrega de IPs LoadBalancer em ambiente bare metal
* Zabbix e Grafana já existentes para monitoramento e visualização
* Nginx reverse proxy externo para publicação dos serviços Docker

## 2. Visão geral da arquitetura

A arquitetura proposta separa os serviços centrais da plataforma dos workloads do Kubernetes.

Os serviços críticos como Git, Nexus e Vault devem rodar fora do cluster Kubernetes, preferencialmente em Docker com volumes persistentes. Isso evita que uma falha no cluster impeça o acesso ao Git, ao registry ou aos segredos necessários para recuperação do ambiente.

```text
Rede homelab jmsalles.homelab.br
|
|-- Servidor Docker externo ao cluster
|   |-- Gitea
|   |-- Gitea act_runner
|   |-- Nexus Repository
|   |-- Vault
|   |-- Nginx reverse proxy
|
|-- Zabbix existente
|-- Grafana existente
|
|-- Cluster Kubernetes HML
|   |-- MetalLB
|   |-- ingress-nginx
|   |-- Argo CD
|   |-- aplicações HML
|
|-- Cluster Kubernetes PRD
    |-- MetalLB
    |-- ingress-nginx
    |-- Argo CD
    |-- aplicações PRD
```

## 3. Decisões técnicas adotadas

| Componente                             | Decisão             |
| -------------------------------------- | ------------------- |
| Git local                              | Gitea               |
| Runner                                 | Gitea act_runner    |
| Registry                               | Nexus Repository    |
| Gestão de segredos                     | Vault               |
| GitOps                                 | Argo CD             |
| Entrada HTTP/HTTPS                     | ingress-nginx       |
| LoadBalancer bare metal                | MetalLB             |
| Monitoramento                          | Zabbix existente    |
| Dashboards                             | Grafana existente   |
| Publicação externa dos serviços Docker | Nginx reverse proxy |
| Ambiente de teste                      | Cluster HML         |
| Ambiente produtivo                     | Cluster PRD         |

## 4. Serviços fora do cluster Kubernetes

Os seguintes serviços devem rodar fora do Kubernetes, preferencialmente em Docker ou Docker Compose, em um servidor dedicado da rede homelab.

### 4.1 Gitea

O Gitea será utilizado como servidor Git local.

Funções principais:

* Hospedar repositórios Git locais
* Versionar manifests Kubernetes
* Versionar Helm values
* Versionar arquivos de infraestrutura
* Acionar workflows com Gitea Actions
* Servir como fonte de verdade para o Argo CD

DNS sugerido:

```text
git.jmsalles.homelab.br
```

Repositórios sugeridos:

```text
k8s-gitops
k8s-apps
dockerfiles
helm-charts
infra-docs
ansible-homelab
```

Estrutura sugerida para o repositório GitOps:

```text
k8s-gitops/
├── clusters/
│   ├── hml/
│   │   ├── argocd/
│   │   ├── apps/
│   │   ├── ingress/
│   │   └── namespaces/
│   └── prd/
│       ├── argocd/
│       ├── apps/
│       ├── ingress/
│       └── namespaces/
├── base/
│   ├── namespaces/
│   ├── network/
│   └── policies/
└── README.md
```

### 4.2 Gitea act_runner

O Gitea act_runner será o runner de CI/CD leve para executar workflows do Gitea Actions.

Funções principais:

* Executar pipelines
* Fazer build de imagens
* Enviar imagens para o Nexus
* Executar testes
* Atualizar manifests ou Helm values
* Apoiar o fluxo de promoção entre HML e PRD

Fluxo básico:

```text
Commit no Gitea
|
Workflow do Gitea Actions
|
Gitea act_runner executa o job
|
Build da imagem
|
Push da imagem para o Nexus
|
Atualização do manifest ou Helm values
|
Argo CD aplica no cluster
```

### 4.3 Nexus Repository

O Nexus será utilizado como registry e repositório central de artefatos.

Funções principais:

* Registry Docker privado
* Cache/proxy do Docker Hub
* Repositório de Helm Charts
* Repositório raw para scripts, pacotes e arquivos
* Futuro proxy de pacotes RPM, se necessário

DNS sugerido:

```text
nexus.jmsalles.homelab.br
```

Repositórios sugeridos no Nexus:

| Nome          | Tipo   | Uso                              |
| ------------- | ------ | -------------------------------- |
| docker-hosted | hosted | imagens próprias                 |
| docker-proxy  | proxy  | cache do Docker Hub              |
| docker-group  | group  | endpoint único para pull         |
| helm-hosted   | hosted | Helm Charts próprios             |
| raw-hosted    | hosted | arquivos diversos                |
| yum-proxy     | proxy  | cache de pacotes RPM, uso futuro |

Fluxo de imagem:

```text
act_runner
|
Build da imagem
|
Push para docker-hosted
|
Kubernetes faz pull pelo docker-group
```

Exemplo de padrão de imagem:

```text
nexus.jmsalles.homelab.br:5000/apps/nginx-demo:1.0.0
nexus.jmsalles.homelab.br:5000/apps/api-hml:0.1.0
nexus.jmsalles.homelab.br:5000/apps/api-prd:1.0.0
```

### 4.4 Vault

O Vault será utilizado para gestão centralizada de segredos.

Funções principais:

* Armazenar senhas
* Armazenar tokens
* Armazenar credenciais de aplicações
* Armazenar credenciais de banco de dados
* Integrar futuramente com Kubernetes Auth
* Evitar secrets fixos em YAML, Git ou Helm values

DNS sugerido:

```text
vault.jmsalles.homelab.br
```

Cuidados importantes:

* Não utilizar Vault em modo dev
* Utilizar volume persistente
* Fazer backup do storage
* Documentar o processo de init e unseal
* Proteger o acesso por HTTPS
* Criar policies por aplicação
* Evitar guardar root token em arquivos de texto sem proteção

Estrutura lógica sugerida no Vault:

```text
kv/
├── hml/
│   ├── apps/
│   │   ├── app-demo/
│   │   └── teampass/
│   └── infra/
│       ├── nexus/
│       └── argocd/
└── prd/
    ├── apps/
    │   ├── app-demo/
    │   └── teampass/
    └── infra/
        ├── nexus/
        └── argocd/
```

### 4.5 Nginx reverse proxy externo

O Nginx reverse proxy externo será responsável por publicar os serviços Docker da rede homelab.

Serviços publicados:

```text
git.jmsalles.homelab.br
nexus.jmsalles.homelab.br
vault.jmsalles.homelab.br
```

Esse Nginx fica fora do cluster Kubernetes e não substitui o ingress-nginx do cluster. Ele é usado apenas para os serviços Docker externos.

## 5. Serviços dentro do cluster Kubernetes

### 5.1 MetalLB

O MetalLB já está sendo utilizado para entregar IPs do tipo LoadBalancer em ambiente bare metal.

Função:

```text
Permitir que serviços Kubernetes do tipo LoadBalancer recebam IPs da rede local.
```

Exemplo de pool com dois IPs:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.31.43-192.168.31.44
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool
```

Validação:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl get svc -A | grep LoadBalancer
```

### 5.2 ingress-nginx

O ingress-nginx já está sendo utilizado como controlador de entrada HTTP/HTTPS para as aplicações no cluster.

Função:

```text
Receber tráfego HTTP/HTTPS e encaminhar para os Services internos do Kubernetes.
```

DNS sugeridos:

```text
argocd-hml.jmsalles.homelab.br
argocd-prd.jmsalles.homelab.br
app-hml.jmsalles.homelab.br
app-prd.jmsalles.homelab.br
```

Validação:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingress -A
kubectl describe ingress -A
```

### 5.3 Argo CD

O Argo CD será responsável pelo deploy GitOps das aplicações e componentes do cluster.

Funções principais:

* Sincronizar o estado do cluster com o Git
* Aplicar manifests Kubernetes
* Aplicar Helm Charts
* Controlar drift de configuração
* Permitir rollback
* Centralizar a visão de deploys

DNS sugeridos:

```text
argocd-hml.jmsalles.homelab.br
argocd-prd.jmsalles.homelab.br
```

Namespaces:

```bash
kubectl create namespace argocd
```

Validação:

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
kubectl get ingress -n argocd
kubectl get applications -n argocd
```

Modelo recomendado:

```text
Gitea
|
Repositório k8s-gitops
|
Argo CD
|
Cluster HML/PRD
```

Fluxo GitOps:

```text
Alteração no Git
|
Argo CD detecta diferença
|
Aplicação fica OutOfSync
|
Sincronização manual ou automática
|
Cluster é atualizado
```

## 6. Namespaces recomendados

Namespaces base:

```bash
kubectl create namespace argocd
kubectl create namespace apps-hml
kubectl create namespace apps-prd
kubectl create namespace monitoring
kubectl create namespace tools
```

Namespaces já existentes ou esperados:

```bash
kubectl get ns
```

Estrutura sugerida:

| Namespace      | Uso                          |
| -------------- | ---------------------------- |
| argocd         | Argo CD                      |
| ingress-nginx  | ingress-nginx                |
| metallb-system | MetalLB                      |
| apps-hml       | aplicações de homologação    |
| apps-prd       | aplicações de produção       |
| monitoring     | integrações de monitoramento |
| tools          | ferramentas auxiliares       |

## 7. Integração com Zabbix

Como o Zabbix já existe na rede, não é necessário instalar outro Zabbix dentro do cluster.

O ideal é integrar o cluster ao Zabbix existente.

Itens recomendados para monitorar:

```text
Status dos nodes
CPU dos nodes
Memória dos nodes
Disco dos nodes
Status do kubelet
Status do container runtime
Pods em CrashLoopBackOff
Pods Pending
Pods Evicted
PVC com pouco espaço
Ingress indisponível
MetalLB sem IP disponível
Argo CD indisponível
Argo CD OutOfSync
Nexus indisponível
Vault indisponível
Gitea indisponível
Runner com falha
```

Comandos úteis para validação manual:

```bash
kubectl get nodes -o wide
kubectl top nodes
kubectl top pods -A
kubectl get pods -A
kubectl get pvc -A
kubectl get events -A --sort-by=.lastTimestamp
```

Serviços externos que também devem ser monitorados pelo Zabbix:

```text
git.jmsalles.homelab.br
nexus.jmsalles.homelab.br
vault.jmsalles.homelab.br
argocd-hml.jmsalles.homelab.br
argocd-prd.jmsalles.homelab.br
```

## 8. Integração com Grafana

Como o Grafana já está rodando na rede, ele deve ser reaproveitado.

Existem dois caminhos:

### 8.1 Usar o Grafana com datasource Prometheus

Nesse cenário, instala-se Prometheus dentro do cluster e o Grafana externo consulta o Prometheus.

Fluxo:

```text
Cluster Kubernetes
|
Prometheus coleta métricas
|
Grafana externo consulta Prometheus
|
Dashboards exibem o estado do cluster
```

### 8.2 Usar o Grafana com datasource Zabbix

Nesse cenário, o Grafana exibe informações vindas do Zabbix.

Fluxo:

```text
Zabbix coleta disponibilidade e métricas
|
Grafana consulta Zabbix
|
Dashboards exibem visão consolidada
```

Minha recomendação:

```text
Manter o Zabbix como ferramenta principal de alerta.
Usar o Grafana como camada visual.
Adicionar Prometheus no cluster futuramente, se quiser dashboards Kubernetes mais completos.
```

## 9. Fluxo de CI/CD recomendado

Fluxo com Gitea, act_runner, Nexus e Argo CD:

```text
1. Código é enviado para o Gitea
2. Workflow do Gitea Actions é acionado
3. act_runner executa o pipeline
4. Pipeline faz build da imagem
5. Pipeline envia a imagem para o Nexus
6. Pipeline atualiza o manifest ou Helm values no repositório GitOps
7. Argo CD detecta a alteração
8. Argo CD aplica no cluster HML
9. Após validação, a alteração é promovida para PRD
```

Exemplo conceitual de pipeline:

```yaml
name: build-and-push

on:
  push:
    branches:
      - main

jobs:
  build:
    runs-on: docker

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login no Nexus
        run: |
          echo "$NEXUS_PASSWORD" | docker login nexus.jmsalles.homelab.br:5000 -u "$NEXUS_USER" --password-stdin

      - name: Build da imagem
        run: |
          docker build -t nexus.jmsalles.homelab.br:5000/apps/app-demo:${GITHUB_SHA} .

      - name: Push da imagem
        run: |
          docker push nexus.jmsalles.homelab.br:5000/apps/app-demo:${GITHUB_SHA}
```

Observação:

As variáveis NEXUS_USER e NEXUS_PASSWORD não devem ser gravadas diretamente no repositório. Elas devem ser armazenadas com segurança no Gitea ou futuramente integradas ao Vault.

## 10. Fluxo de promoção HML para PRD

A promoção entre ambientes deve ser controlada.

Modelo recomendado:

```text
Branch develop
|
Deploy em HML
|
Validação
|
Merge para main ou criação de tag
|
Deploy em PRD
```

Estrutura sugerida:

```text
clusters/
├── hml/
│   └── apps/
│       └── app-demo/
│           └── values.yaml
└── prd/
    └── apps/
        └── app-demo/
            └── values.yaml
```

Exemplo:

```yaml
image:
  repository: nexus.jmsalles.homelab.br:5000/apps/app-demo
  tag: "1.0.0"
```

No HML, pode usar tags mais frequentes:

```text
0.1.0
0.1.1
develop-123
```

No PRD, usar tags controladas:

```text
1.0.0
1.0.1
1.1.0
```

## 11. Segurança mínima recomendada

Boas práticas iniciais:

```text
Não usar senha em YAML
Não usar secrets em ConfigMap
Não usar tag latest em PRD
Não permitir deploy manual fora do GitOps
Separar HML e PRD
Usar usuários diferentes para serviços
Usar volumes persistentes nos serviços Docker
Manter backup do Gitea, Nexus e Vault
Usar HTTPS nos serviços principais
```

Serviços que devem ter backup obrigatório:

```text
Gitea
Nexus
Vault
Argo CD
Manifests GitOps
Volumes das aplicações
```

## 12. Backup recomendado

Primeira fase:

```text
Backup dos volumes Docker do Gitea
Backup dos volumes Docker do Nexus
Backup dos volumes Docker do Vault
Backup dos repositórios Git
Backup dos manifests Kubernetes
```

Segunda fase:

```text
Velero para backup do cluster
MinIO ou NAS como destino
Backup dos namespaces críticos
Backup dos PVCs
```

Itens críticos:

```text
/var/lib/docker/volumes/gitea
/var/lib/docker/volumes/nexus
/var/lib/docker/volumes/vault
```

Exemplo de diretório de backup:

```bash
mkdir -p /backup/homelab/gitea
mkdir -p /backup/homelab/nexus
mkdir -p /backup/homelab/vault
mkdir -p /backup/homelab/kubernetes
```

## 13. Ordem de implantação recomendada

A implantação deve ser feita em fases.

### Fase 1: base Docker externa

Instalar e validar:

```text
Gitea
Gitea act_runner
Nexus
Vault
Nginx reverse proxy
```

Validar DNS:

```bash
ping git.jmsalles.homelab.br
ping nexus.jmsalles.homelab.br
ping vault.jmsalles.homelab.br
```

Validar acesso HTTP/HTTPS:

```bash
curl -I http://git.jmsalles.homelab.br
curl -I http://nexus.jmsalles.homelab.br
curl -I http://vault.jmsalles.homelab.br
```

### Fase 2: base Kubernetes

Validar componentes existentes:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

Validar MetalLB:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

Validar ingress-nginx:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingress -A
```

### Fase 3: Argo CD

Instalar e validar Argo CD no HML primeiro.

```bash
kubectl create namespace argocd
kubectl get pods -n argocd
kubectl get svc -n argocd
```

Depois criar o Ingress:

```bash
kubectl get ingress -n argocd
```

Após validação em HML, repetir no PRD.

### Fase 4: GitOps

Criar repositório GitOps no Gitea.

```text
k8s-gitops
```

Cadastrar o repositório no Argo CD.

Criar aplicações por ambiente:

```text
apps-hml
apps-prd
```

### Fase 5: CI/CD com Gitea act_runner

Criar primeiro pipeline simples:

```text
checkout
build
push para Nexus
```

Depois evoluir para:

```text
build
scan
push
atualização de manifest
deploy via Argo CD
```

### Fase 6: integração com monitoramento

Adicionar no Zabbix:

```text
Nodes Kubernetes
URLs dos serviços
Argo CD
Nexus
Vault
Gitea
Runner
ingress-nginx
MetalLB
```

Adicionar no Grafana:

```text
Dashboard de disponibilidade
Dashboard de cluster
Dashboard de aplicações
Dashboard de consumo dos mini PCs
```

## 14. Checklist pós-instalação

### 14.1 Docker externo

| Item                             | Status   |
| -------------------------------- | -------- |
| Gitea instalado                  | Pendente |
| Gitea com volume persistente     | Pendente |
| Gitea act_runner instalado       | Pendente |
| Nexus instalado                  | Pendente |
| Nexus com volume persistente     | Pendente |
| Vault instalado fora do modo dev | Pendente |
| Vault com volume persistente     | Pendente |
| Nginx reverse proxy configurado  | Pendente |
| DNS interno configurado          | Pendente |
| Backup dos volumes configurado   | Pendente |

### 14.2 Kubernetes

| Item                             | Status   |
| -------------------------------- | -------- |
| Cluster HML ativo                | Pendente |
| Cluster PRD ativo                | Pendente |
| MetalLB funcionando              | Pendente |
| ingress-nginx funcionando        | Pendente |
| Argo CD HML instalado            | Pendente |
| Argo CD PRD instalado            | Pendente |
| Repositório GitOps conectado     | Pendente |
| Aplicação teste publicada        | Pendente |
| Pull de imagem do Nexus validado | Pendente |

### 14.3 Monitoramento

| Item                              | Status   |
| --------------------------------- | -------- |
| Zabbix monitorando nodes          | Pendente |
| Zabbix monitorando URLs           | Pendente |
| Zabbix monitorando Gitea          | Pendente |
| Zabbix monitorando Nexus          | Pendente |
| Zabbix monitorando Vault          | Pendente |
| Grafana com dashboard do ambiente | Pendente |

## 15. Modelo final esperado

Ao final da pós-instalação, o ambiente deverá operar no seguinte modelo:

```text
Gitea
|
Workflow com act_runner
|
Build da imagem
|
Push para Nexus
|
Manifest versionado no GitOps
|
Argo CD sincroniza
|
Kubernetes publica via ingress-nginx
|
MetalLB entrega IP
|
Zabbix monitora
|
Grafana exibe dashboards
|
Vault centraliza segredos
```

## 16. Resumo da arquitetura final

| Camada          | Ferramenta         |
| --------------- | ------------------ |
| Código-fonte    | Gitea              |
| CI/CD           | Gitea act_runner   |
| Registry        | Nexus              |
| Segredos        | Vault              |
| GitOps          | Argo CD            |
| Deploy          | Kubernetes         |
| Entrada         | ingress-nginx      |
| IP LoadBalancer | MetalLB            |
| Monitoramento   | Zabbix             |
| Visualização    | Grafana            |
| Proxy externo   | Nginx              |
| Backup futuro   | Velero + MinIO/NAS |

## 17. Próximos passos recomendados

A ordem recomendada para execução é:

```text
1. Subir Gitea em Docker
2. Subir Nexus em Docker
3. Subir Vault em Docker sem modo dev
4. Configurar Nginx reverse proxy
5. Criar DNS interno para Git, Nexus e Vault
6. Instalar Argo CD no HML
7. Conectar Argo CD ao Gitea
8. Criar aplicação teste
9. Configurar act_runner
10. Criar pipeline de build e push para Nexus
11. Publicar aplicação teste no HML
12. Integrar com Zabbix
13. Criar dashboard no Grafana
14. Replicar fluxo para PRD
```

## 18. Observações finais

Essa estrutura é leve, organizada e adequada para um homelab com características profissionais.

A decisão de usar Gitea no lugar de GitLab CE reduz bastante o consumo de CPU e memória. O Nexus atende bem como registry e repositório de artefatos. O Vault adiciona uma camada importante de segurança. O Argo CD garante o modelo GitOps. O Zabbix e o Grafana existentes evitam duplicidade de ferramentas e reaproveitam a estrutura já disponível na rede.

O ambiente fica preparado para evoluir futuramente com:

```text
Velero
MinIO
Trivy
Kyverno
Loki
Prometheus
cert-manager
External Secrets Operator
```

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles
