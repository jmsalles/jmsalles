
---

# Guia de Implantação do **AWX** no Kubernetes (AWX Operator) — **StorageClass RWO + Projetos via Git**

> Identidade “Guia”: texto limpo, comandos sempre em blocos `bash`, edições com `vim`, âncoras no Sumário e assinatura no final. Sem CSS.

---

## 🎯 Resumo

Instalação do **AWX** via **AWX Operator** em um cluster Kubernetes que possui uma **StorageClass RWO (ex.: `vmware-sc`) marcada como *default***.
A UI será exposta via **Ingress NGINX** com **TLS**, e **todos os projetos serão consumidos via Git**, sem PVC dedicado de `projects`.

Fluxo: pré-checagens → operator com **tag pinada** → secrets (`admin` / `SECRET_KEY`) → TLS/DNS → CR do AWX (Ingress + Git) → verificação/ajustes → backup/restore → upgrade → troubleshooting.

---

## 🧭 Sumário

* [Pré-requisitos e premissas](#prérequisitos-e-premissas)
* [Checagens do cluster](#checagens-do-cluster)
* [Namespace e contexto](#namespace-e-contexto)
* [Instalar o AWX Operator (tag fixa)](#instalar-o-awx-operator-tag-fixa)
* [Criar Secrets (admin e SECRET_KEY)](#criar-secrets-admin-e-secret_key)
* [TLS e DNS para o Ingress](#tls-e-dns-para-o-ingress)
* [Implantar o AWX (Ingress + projetos via Git)](#implantar-o-awx-ingress--projetos-via-git)
* [Verificações pós-deploy](#verificações-pósdeploy)
* [Backup & Restore (CRDs)](#backup--restore-crds)
* [Upgrade seguro](#upgrade-seguro)
* [Desinstalação](#desinstalação)
* [Troubleshooting rápido](#troubleshooting-rápido)
* [Checklist final](#checklist-final)

---

## Pré-requisitos e premissas

* Cluster Kubernetes saudável (1+ nós) com **Ingress Controller NGINX** acessível (`LoadBalancer`/MetalLB ou `NodePort`).
* **StorageClass RWO** dinâmica (ex.: `vmware-sc`) marcada como ***default*** no cluster.
* `kubectl` apontando para o cluster, com usuário autorizado a criar CRDs e recursos no namespace `awx`.
* Projetos do AWX serão **sempre consumidos via Git** (SCM), sem necessidade de PVC dedicado de `projects`.

---

## Checagens do cluster

Listar nós e versões:

```bash
kubectl get nodes -o wide
kubectl version --short
```

Verificar as StorageClasses (a `*` indica a default, que será RWO):

```bash
kubectl get storageclass
```

Verificar o Ingress NGINX (ajuste o namespace se for diferente):

```bash
kubectl get ingressclass
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
```

---

## Namespace e contexto

Criar o namespace `awx` e fixar o contexto atual nele:

```bash
kubectl create namespace awx
kubectl config set-context --current --namespace=awx
```

---

## Instalar o AWX Operator (tag fixa)

Sempre fixe a versão do operator para evitar surpresas em produção. Exemplo usando a tag `2.9.0`.

Clonar o repositório do operator:

```bash
cd ~
git clone https://github.com/ansible/awx-operator.git
cd awx-operator
git fetch --tags
git checkout tags/2.9.0
```

Editar o arquivo `kustomization.yaml` com `vim`:

```bash
vim kustomization.yaml
```

Conteúdo sugerido:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.9.0
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.9.0
namespace: awx
```

Aplicar o operator no cluster:

```bash
kubectl apply -k .
kubectl get pods -n awx
```

Aguardar até o pod `awx-operator-controller-manager` ficar em **Running**.

---

## Criar Secrets (admin e `SECRET_KEY`)

Definir a senha do usuário `admin`:

```bash
ADMIN_PASS='TroqueEstaSenhaSuperForte!'
kubectl create secret generic awx-admin-password \
  --from-literal=password="$ADMIN_PASS" -n awx
```

Gerar a `SECRET_KEY` usada pelo Django (mínimo 32 caracteres):

```bash
SECRET_KEY="$(openssl rand -base64 48 | tr -d '\n')"
kubectl create secret generic awx-secret-key \
  --from-literal=secret_key="$SECRET_KEY" -n awx
```

Sem essa `SECRET_KEY`, o pod `awx-web` entra em `CrashLoopBackOff` com erro de Django.

---

## TLS e DNS para o Ingress

Exemplo usando o FQDN `awx.seulab.local` (ajuste para o domínio do seu ambiente).

Gerar um certificado autoassinado (para produção, preferir `cert-manager` + ACME):

```bash
openssl req -x509 -nodes -days 825 -newkey rsa:4096 \
  -keyout awx.key -out awx.crt -subj "/CN=awx.seulab.local"
```

Criar o Secret de TLS no namespace `awx`:

```bash
kubectl create secret tls awx-tls --key awx.key --cert awx.crt -n awx
```

No DNS (ou `/etc/hosts` em lab), apontar `awx.seulab.local` para o **EXTERNAL-IP** do Service `ingress-nginx-controller`.

---

## Implantar o AWX (Ingress + projetos via Git)

Aqui será criado o recurso `AWX` principal, já integrado com Ingress NGINX e usando **apenas Git** para projetos (sem PVC de `projects`).

Criar o arquivo `awx.yml`:

```bash
vim awx.yml
```

Conteúdo sugerido:

```yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: ClusterIP
  ingress_type: ingress
  ingress_class_name: nginx

  # Host e TLS no Ingress
  hostname: awx.seulab.local
  ingress_tls_secret: awx-tls

  # Anotações do NGINX (string multilinha)
  ingress_annotations: |
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/enable-websocket: "true"

  # Credenciais e SECRET_KEY
  admin_user: admin
  admin_password_secret: awx-admin-password
  secret_key_secret: awx-secret-key

  # Projetos SEM PVC (tudo via Git/SCM)
  projects_persistence: false

  # Extra: injeta SECRET_KEY também via env (cinto e suspensório)
  extra_env:
    - name: SECRET_KEY
      valueFrom:
        secretKeyRef:
          name: awx-secret-key
          key: secret_key

  # Tuning básico de recursos (ajuste conforme seu cluster)
  web_resource_requirements:
    requests:
      cpu: 250m
      memory: "512Mi"
    limits:
      cpu: "2"
      memory: "3Gi"

  task_resource_requirements:
    requests:
      cpu: 500m
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "4Gi"

  ee_resource_requirements:
    requests:
      cpu: 250m
      memory: "512Mi"
    limits:
      cpu: "2"
      memory: "2Gi"
```

Aplicar o CR do AWX e acompanhar os recursos:

```bash
kubectl apply -f awx.yml
kubectl get pods,svc,ingress,pvc -n awx -w
```

Situação esperada:

* `awx-postgres-13-0` em **Running**
* `awx-web-...` em **Running / 3/3 Ready**
* `awx-task-...` em **Running / 4/4 Ready**
* `svc/awx-service` criado e com endpoints
* `ingress/awx` (ou nome similar) com host `awx.seulab.local`

Nenhum PVC de `projects` será criado, pois `projects_persistence` está em `false`.

---

## Verificações pós-deploy

Verificar endpoints do Service principal:

```bash
kubectl -n awx get endpoints awx-service -o wide
```

Se estiver vazio ou com endpoints `NotReady`, o Ingress retornará `503`.

Testar acesso interno ao Service (sem TLS, dentro do cluster):

```bash
kubectl -n awx run curl --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -lc 'wget -S -O- http://awx-service 2>&1 | head -n1'
```

Testar via Ingress usando o IP externo:

```bash
curl -skI https://<EXTERNAL-IP> -H 'Host: awx.seulab.local' | head -n1
```

No navegador, acessar:

```text
https://awx.seulab.local/
```

Credenciais iniciais:

```text
Usuário: admin
Senha: (a definida no Secret awx-admin-password)
```

Na UI, ajustar:

```text
Settings → System → Base URL = https://awx.seulab.local
```

---

## Backup & Restore (CRDs)

Mesmo em ambiente com SC apenas RWO, é possível usar um PVC RWO para os backups.

### PVC de backup

Criar o arquivo `awx-backup-pvc.yml`:

```bash
vim awx-backup-pvc.yml
```

Conteúdo:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: awx-backup-pvc
  namespace: awx
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

Aplicar:

```bash
kubectl apply -f awx-backup-pvc.yml
kubectl -n awx get pvc
```

### Backup

Criar o arquivo `awx-backup.yml`:

```bash
vim awx-backup.yml
```

Conteúdo:

```yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWXBackup
metadata:
  name: awx-backup
  namespace: awx
spec:
  deployment_name: awx
  backup_pvc: awx-backup-pvc
  no_log: false
```

Aplicar e acompanhar:

```bash
kubectl apply -f awx-backup.yml
kubectl -n awx get jobs
```

### Restore

Criar o arquivo `awx-restore.yml`:

```bash
vim awx-restore.yml
```

Conteúdo:

```yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWXRestore
metadata:
  name: awx-restore
  namespace: awx
spec:
  deployment_name: awx
  backup_pvc: awx-backup-pvc
```

Aplicar:

```bash
kubectl apply -f awx-restore.yml
kubectl -n awx get pods -w
```

---

## Upgrade seguro

1. Realizar backup (`AWXBackup`) e garantir que o job completou com sucesso.
2. Atualizar a **tag** do operator no `kustomization.yaml` (por exemplo, de `2.9.0` para outra versão testada).
3. Reaplicar o kustomize:

```bash
cd ~/awx-operator
kubectl apply -k .
```

4. Reaplicar o `awx.yml` (o operator vai reconciliar a nova versão).
5. Monitorar o processo:

```bash
kubectl -n awx logs -f deploy/awx-operator-controller-manager -c awx-manager
kubectl -n awx get pods -w
```

---

## Desinstalação

Remover apenas o AWX (mantendo operator e PVCs):

```bash
kubectl -n awx delete awx awx
kubectl -n awx get pvc
```

Remover tudo (AWX, operator e namespace):

```bash
kubectl -n awx delete awx awx --ignore-not-found
cd ~/awx-operator
kubectl delete -k .
kubectl delete namespace awx
```

Atenção à `reclaimPolicy` da StorageClass: PVs podem ser removidos automaticamente ao deletar o namespace.

---

## Troubleshooting rápido

**Ingress retornando 503**

```bash
kubectl -n awx get endpoints awx-service -o wide
```

Se não houver endpoints ou estiverem `NotReady`, verificar os pods `awx-web`:

```bash
kubectl -n awx get pods
kubectl -n awx logs deploy/awx-web
```

**Erro `SECRET_KEY must not be empty`**

Verificar o Secret e o conteúdo:

```bash
kubectl -n awx get secret awx-secret-key -o jsonpath='{.data.secret_key}' | base64 --decode; echo
```

Se necessário, ajustar o CR via patch:

```bash
kubectl -n awx patch awx awx --type merge -p '{
  "spec": {
    "secret_key_secret": "awx-secret-key",
    "extra_env": [
      {
        "name": "SECRET_KEY",
        "valueFrom": {
          "secretKeyRef": {
            "name": "awx-secret-key",
            "key": "secret_key"
          }
        }
      }
    ]
  }
}'
kubectl -n awx delete pod -l app.kubernetes.io/name=awx-web
```

**PVC de backup em Pending**

```bash
kubectl -n awx describe pvc awx-backup-pvc
kubectl get storageclass
```

Confirmar se a StorageClass default suporta criação automática de volumes RWO.

**Problemas de memória ou CPU**

Ajustar os blocos `*_resource_requirements` no `awx.yml` e recriar os pods:

```bash
kubectl -n awx delete pod -l app.kubernetes.io/name=awx-web
kubectl -n awx delete pod -l app.kubernetes.io/name=awx-task
```

**Base URL e redirects estranhos**

Conferir em:

```text
Settings → System → Base URL
```

Garantir que está em `https://awx.seulab.local`.

---

## Checklist final

* [ ] StorageClass **RWO** configurada e marcada como **default**
* [ ] `ingress-nginx` acessível (LoadBalancer/MetalLB ou NodePort)
* [ ] Namespace `awx` criado e contexto do `kubectl` ajustado
* [ ] AWX Operator aplicado com **tag pinada**
* [ ] Secrets `awx-admin-password` e `awx-secret-key` criados no namespace `awx`
* [ ] `awx.yml` aplicado com:

  * [ ] `projects_persistence: false` (projetos via Git/SCM)
  * [ ] Ingress NGINX configurado (host, TLS e anotações)
* [ ] `awx-web` em **3/3 Ready**, `awx-task` em **4/4 Ready**, `awx-service` com endpoints
* [ ] UI acessível em `https://awx.seulab.local` (admin / senha configurada)
* [ ] Base URL configurada em **Settings → System**
* [ ] PVC de backup criado (`awx-backup-pvc`) e backup testado (`AWXBackup`)
* [ ] Procedimento de upgrade documentado e validado em ambiente controlado

---

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles](https://github.com/jmsalles)
