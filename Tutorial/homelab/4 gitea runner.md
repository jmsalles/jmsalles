# Guia de instalação e integração do Gitea Runner no homelab JMSalles

## 1. Objetivo

Este documento descreve o procedimento completo para instalação, configuração e integração do **Gitea Runner** no homelab `jmsalles.homelab.br`.

O Gitea Runner será utilizado para executar pipelines do **Gitea Actions**, permitindo futuramente automatizar processos como:

* Build de imagens Docker
* Push de imagens para Nexus Registry
* Deploy em ambiente Docker HML
* Integração com Kubernetes HML/PRD
* Integração com Argo CD
* Integração com Vault
* Fluxos GitOps

Este tutorial contempla apenas a instalação e integração do runner com o Gitea.

Os jobs, workflows e a aplicação `app-hello-homelab` serão tratados em documento separado.

---

## 2. Visão geral da arquitetura

A instalação será realizada no servidor Docker HML.

```text
Gitea
|
| HTTPS
|
git.jmsalles.homelab.br
|
Gitea Runner
|
Docker HML
|
Execução futura de pipelines
```

Fluxo de comunicação:

```text
Gitea Runner
|
| HTTPS
|
git.jmsalles.homelab.br
|
Gitea
```

Como o Gitea utiliza certificado assinado pela CA interna do homelab, o runner precisa confiar na CA:

```text
JMSalles Homelab Root CA
|
Certificado wildcard *.jmsalles.homelab.br
|
git.jmsalles.homelab.br
```

---

## 3. Padrões adotados

| Item                      | Valor                               |
| ------------------------- | ----------------------------------- |
| Servidor                  | Docker HML                          |
| Host                      | `docker-hml-lenovo-i5`              |
| Caminho base              | `/home/jmsalles/gitea-runner`       |
| URL do Gitea              | `https://git.jmsalles.homelab.br`   |
| Nome do runner            | `gitea-runner-docker-hml-01`        |
| Imagem base               | `docker.io/gitea/act_runner:latest` |
| Imagem local customizada  | `local/gitea-act-runner:homelab-ca` |
| Arquivo Docker Compose    | `docker-compose.yml`                |
| Arquivo de configuração   | `config.yaml`                       |
| Arquivo de variáveis      | `.env`                              |
| CA interna                | `jmsalles-homelab-rootCA.crt`       |
| Diretório de dados        | `/home/jmsalles/gitea-runner/data`  |
| Diretório de certificados | `/home/jmsalles/gitea-runner/certs` |

---

## 4. Pré-requisitos

Antes de iniciar, valide se o Docker está instalado e funcional.

```bash
docker --version
```

```bash
docker compose version
```

```bash
docker ps
```

Valide se o serviço Docker está ativo.

```bash
systemctl status docker
```

Caso esteja parado, inicie o serviço.

```bash
systemctl enable --now docker
```

Valide a resolução DNS do Gitea.

```bash
nslookup git.jmsalles.homelab.br
```

Teste o acesso HTTPS ao Gitea.

```bash
curl -k -I https://git.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

ou:

```text
HTTP/2 200
```

---

## 5. Criar estrutura de diretórios

Crie a estrutura base do runner.

```bash
mkdir -p /home/jmsalles/gitea-runner/{data,certs}
```

Ajuste o dono dos diretórios.

```bash
chown -R jmsalles:jmsalles /home/jmsalles/gitea-runner
```

Acesse o diretório.

```bash
cd /home/jmsalles/gitea-runner
```

Valide a estrutura.

```bash
ls -lah /home/jmsalles/gitea-runner
```

Resultado esperado:

```text
certs
data
```

---

## 6. Copiar a CA interna do homelab

Copie a CA raiz usada pelo Nginx/Gitea para o diretório do runner.

```bash
cp -v /home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.crt /home/jmsalles/gitea-runner/certs/
```

Ajuste a permissão.

```bash
chmod 644 /home/jmsalles/gitea-runner/certs/jmsalles-homelab-rootCA.crt
```

Valide.

```bash
ls -lah /home/jmsalles/gitea-runner/certs/
```

Resultado esperado:

```text
jmsalles-homelab-rootCA.crt
```

---

## 7. Criar Dockerfile customizado do runner

Como o Gitea usa certificado assinado pela CA interna do homelab, será criada uma imagem local do `act_runner` já confiando nessa CA.

Crie o arquivo.

```bash
vim /home/jmsalles/gitea-runner/Dockerfile
```

Conteúdo:

```Dockerfile
FROM docker.io/gitea/act_runner:latest

USER root

COPY certs/jmsalles-homelab-rootCA.crt /usr/local/share/ca-certificates/jmsalles-homelab-rootCA.crt

RUN if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache ca-certificates openssl; \
    fi && \
    if command -v update-ca-certificates >/dev/null 2>&1; then \
      update-ca-certificates; \
    fi && \
    ls -lah /etc/ssl/certs/ca-certificates.crt
```

---

## 8. Gerar o arquivo config.yaml inicial

Gere o arquivo base de configuração do runner.

```bash
docker run --entrypoint="" --rm docker.io/gitea/act_runner:latest act_runner generate-config > /home/jmsalles/gitea-runner/config.yaml
```

Valide se o arquivo foi criado.

```bash
ls -lah /home/jmsalles/gitea-runner/config.yaml
```

---

## 9. Ajustar o config.yaml

Edite o arquivo.

```bash
vim /home/jmsalles/gitea-runner/config.yaml
```

Ajuste o bloco `runner`.

```yaml
runner:
  file: /data/.runner
  capacity: 1
  envs:
    SSL_CERT_FILE: /etc/ssl/certs/ca-certificates.crt
    SSL_CERT_DIR: /etc/ssl/certs
    NODE_EXTRA_CA_CERTS: /certs/jmsalles-homelab-rootCA.crt
  timeout: 3h
  shutdown_timeout: 0s
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - ubuntu-latest:docker://node:20-bookworm
    - ubuntu-22.04:docker://node:20-bookworm
    - docker-hml:docker://docker:27-cli
```

Ajuste o bloco `container`.

```yaml
container:
  network: ""
  privileged: false
  options: "-v /home/jmsalles/gitea-runner/certs:/certs:ro -e GIT_SSL_CAINFO=/certs/jmsalles-homelab-rootCA.crt -e NODE_EXTRA_CA_CERTS=/certs/jmsalles-homelab-rootCA.crt"
  workdir_parent:
  valid_volumes:
    - /home/jmsalles/gitea-runner/certs
```

Observação importante:

Não adicione manualmente o socket Docker no campo `container.options`.

Não use:

```text
-v /var/run/docker.sock:/var/run/docker.sock
```

Esse socket já é tratado pelo runner durante a criação dos containers de job. Adicionar manualmente pode causar erro de montagem duplicada:

```text
Duplicate mount point: /var/run/docker.sock
```

---

## 10. Criar o arquivo .env

Crie o arquivo de variáveis.

```bash
vim /home/jmsalles/gitea-runner/.env
```

Conteúdo inicial:

```env
GITEA_INSTANCE_URL=https://git.jmsalles.homelab.br
GITEA_RUNNER_REGISTRATION_TOKEN=COLE_AQUI_O_TOKEN_DO_GITEA
GITEA_RUNNER_NAME=gitea-runner-docker-hml-01
```

Ajuste a permissão.

```bash
chmod 600 /home/jmsalles/gitea-runner/.env
```

Valide.

```bash
ls -lah /home/jmsalles/gitea-runner/.env
```

---

## 11. Gerar token de registro no Gitea

Acesse o Gitea pelo navegador.

```text
https://git.jmsalles.homelab.br
```

Acesse o caminho:

```text
Administração do site
Ações
Runners
Criar novo Runner
```

Copie o token de registro gerado pelo Gitea.

Edite o `.env`.

```bash
vim /home/jmsalles/gitea-runner/.env
```

Substitua:

```env
GITEA_RUNNER_REGISTRATION_TOKEN=COLE_AQUI_O_TOKEN_DO_GITEA
```

pelo token real gerado no Gitea.

---

## 12. Criar o docker-compose.yml

Crie o arquivo Docker Compose.

```bash
vim /home/jmsalles/gitea-runner/docker-compose.yml
```

Conteúdo:

```yaml
services:
  gitea-runner:
    build:
      context: .
      dockerfile: Dockerfile
    image: local/gitea-act-runner:homelab-ca
    container_name: gitea-runner
    restart: unless-stopped
    env_file:
      - .env
    environment:
      CONFIG_FILE: /config.yaml
      SSL_CERT_FILE: /etc/ssl/certs/ca-certificates.crt
      SSL_CERT_DIR: /etc/ssl/certs
      NODE_EXTRA_CA_CERTS: /certs/jmsalles-homelab-rootCA.crt
    volumes:
      - ./config.yaml:/config.yaml
      - ./data:/data
      - ./certs:/certs:ro
      - /var/run/docker.sock:/var/run/docker.sock
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

---

## 13. Build da imagem customizada

Acesse o diretório do runner.

```bash
cd /home/jmsalles/gitea-runner
```

Faça o build da imagem local.

```bash
docker compose build --no-cache
```

Valide se a imagem foi criada.

```bash
docker images | grep gitea-act-runner
```

Resultado esperado:

```text
local/gitea-act-runner   homelab-ca
```

---

## 14. Subir o Gitea Runner

Suba o container.

```bash
docker compose up -d
```

Valide.

```bash
docker compose ps
```

Acompanhe os logs.

```bash
docker compose logs -f
```

Resultado esperado no primeiro registro:

```text
Registering runner
Successfully pinged the Gitea instance server
Runner registered successfully.
SUCCESS
Starting runner daemon
runner: gitea-runner-docker-hml-01
```

---

## 15. Validar se o runner está registrado

No Gitea, acesse:

```text
Administração do site
Ações
Runners
```

O runner deve aparecer com o nome:

```text
gitea-runner-docker-hml-01
```

Com as labels:

```text
ubuntu-latest
ubuntu-22.04
docker-hml
```

E com a versão:

```text
v0.6.1
```

---

## 16. Validar persistência do registro

Após o registro, o arquivo `.runner` deve ser criado no diretório de dados.

```bash
ls -lah /home/jmsalles/gitea-runner/data/
```

Resultado esperado:

```text
.runner
```

Esse arquivo mantém o runner registrado no Gitea.

---

## 17. Remover token do .env após registro

Após o runner registrar com sucesso, remova o token do `.env`.

Edite:

```bash
vim /home/jmsalles/gitea-runner/.env
```

Deixe assim:

```env
GITEA_INSTANCE_URL=https://git.jmsalles.homelab.br
GITEA_RUNNER_REGISTRATION_TOKEN=
GITEA_RUNNER_NAME=gitea-runner-docker-hml-01
```

Reinicie o runner.

```bash
docker compose restart
```

Valide os logs.

```bash
docker compose logs --tail=100
```

Resultado esperado:

```text
Starting runner daemon
runner: gitea-runner-docker-hml-01
declare successfully
```

---

## 18. Validar imagem usada pelo container

Confirme se o container está usando a imagem customizada com a CA interna.

```bash
docker inspect gitea-runner --format '{{.Config.Image}}'
```

Resultado esperado:

```text
local/gitea-act-runner:homelab-ca
```

Se aparecer:

```text
docker.io/gitea/act_runner:latest
```

o `docker-compose.yml` não está usando a imagem customizada corretamente.

---

## 19. Validar CA dentro do container do runner

Acesse o container.

```bash
docker exec -it gitea-runner sh
```

Valide se a CA está montada.

```bash
ls -lah /certs/
```

Resultado esperado:

```text
jmsalles-homelab-rootCA.crt
```

Valide o acesso HTTPS ao Gitea.

```bash
wget -S --spider https://git.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/1.1 200 OK
remote file exists
```

Valide com OpenSSL.

```bash
openssl s_client -connect git.jmsalles.homelab.br:443 -servername git.jmsalles.homelab.br -CAfile /etc/ssl/certs/ca-certificates.crt
```

Resultado esperado:

```text
Verify return code: 0 (ok)
```

Saia do container.

```bash
exit
```

---

## 20. Comandos de operação do runner

Acessar diretório do runner.

```bash
cd /home/jmsalles/gitea-runner
```

Ver status.

```bash
docker compose ps
```

Ver logs em tempo real.

```bash
docker compose logs -f
```

Ver últimos logs.

```bash
docker compose logs --tail=100
```

Reiniciar.

```bash
docker compose restart
```

Parar.

```bash
docker compose down
```

Subir novamente.

```bash
docker compose up -d
```

Rebuild da imagem.

```bash
docker compose build --no-cache
```

Rebuild e subida.

```bash
docker compose up -d --build
```

---

## 21. Troubleshooting

### 21.1 Erro de certificado ao registrar runner

Erro comum:

```text
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

Causa:

```text
O container do runner não confia na CA interna do homelab.
```

Valide se a CA existe:

```bash
ls -lah /home/jmsalles/gitea-runner/certs/
```

Valide se o container usa a imagem customizada:

```bash
docker inspect gitea-runner --format '{{.Config.Image}}'
```

Valide o certificado dentro do container:

```bash
docker exec -it gitea-runner sh
```

```bash
openssl s_client -connect git.jmsalles.homelab.br:443 -servername git.jmsalles.homelab.br -CAfile /etc/ssl/certs/ca-certificates.crt
```

Resultado esperado:

```text
Verify return code: 0 (ok)
```

---

### 21.2 Runner registra, mas aparece como inativo

Valide se o container está rodando.

```bash
docker compose ps
```

Valide os logs.

```bash
docker compose logs --tail=100
```

No Gitea, acesse:

```text
Administração do site
Ações
Runners
```

Clique em editar o runner e confirme se ele não está desabilitado.

---

### 21.3 Erro .runner is missing

Mensagem:

```text
.runner is missing or not a regular file
```

Essa mensagem é normal antes do primeiro registro.

Ela indica que o arquivo de registro ainda não existe.

Após o registro bem-sucedido, valide:

```bash
ls -lah /home/jmsalles/gitea-runner/data/
```

Resultado esperado:

```text
.runner
```

---

### 21.4 Labels ignoradas

Mensagem:

```text
Labels from command will be ignored, use labels defined in config file.
```

Solução:

Definir as labels diretamente no `config.yaml`.

```yaml
runner:
  labels:
    - ubuntu-latest:docker://node:20-bookworm
    - ubuntu-22.04:docker://node:20-bookworm
    - docker-hml:docker://docker:27-cli
```

---

### 21.5 Erro de montagem duplicada do Docker socket

Erro:

```text
Duplicate mount point: /var/run/docker.sock
```

Causa:

O socket foi definido manualmente no `container.options`, mas o runner já faz essa montagem no job.

Não use no `container.options`:

```text
-v /var/run/docker.sock:/var/run/docker.sock
```

Use o socket apenas no `docker-compose.yml` do runner:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

---

### 21.6 Erro bash not found

Erro:

```text
exec: "bash": executable file not found in $PATH
```

Causa:

A imagem `docker:27-cli` usa Alpine e não possui `bash` por padrão.

Solução nos workflows futuros:

```yaml
defaults:
  run:
    shell: sh
```

Ou criar uma imagem customizada para jobs com:

```text
bash
git
nodejs
docker-cli
ca-certificates
```

---

### 21.7 Erro no checkout por certificado

Possível erro:

```text
certificate signed by unknown authority
```

Causa:

O container do job também precisa confiar na CA interna.

Solução já prevista no `config.yaml`:

```yaml
container:
  options: "-v /home/jmsalles/gitea-runner/certs:/certs:ro -e GIT_SSL_CAINFO=/certs/jmsalles-homelab-rootCA.crt -e NODE_EXTRA_CA_CERTS=/certs/jmsalles-homelab-rootCA.crt"
```

Nos workflows futuros, instalar a CA dentro do job quando necessário:

```bash
cp /certs/jmsalles-homelab-rootCA.crt /usr/local/share/ca-certificates/jmsalles-homelab-rootCA.crt
```

```bash
update-ca-certificates
```

---

## 22. Estrutura final esperada

Ao final, a estrutura deve ficar assim:

```text
/home/jmsalles/gitea-runner
|
|-- Dockerfile
|-- docker-compose.yml
|-- config.yaml
|-- .env
|
|-- certs
|   |-- jmsalles-homelab-rootCA.crt
|
|-- data
    |-- .runner
```

---

## 23. Checklist final

| Item                                           | Status    |
| ---------------------------------------------- | --------- |
| Diretório `/home/jmsalles/gitea-runner` criado | Concluído |
| Diretórios `data` e `certs` criados            | Concluído |
| CA interna copiada                             | Concluído |
| Dockerfile customizado criado                  | Concluído |
| `config.yaml` gerado                           | Concluído |
| Labels configuradas no `config.yaml`           | Concluído |
| CA configurada para container de job           | Concluído |
| `.env` criado                                  | Concluído |
| Token gerado no Gitea                          | Concluído |
| `docker-compose.yml` criado                    | Concluído |
| Imagem customizada buildada                    | Concluído |
| Runner iniciado                                | Concluído |
| Runner registrado no Gitea                     | Concluído |
| Arquivo `.runner` criado                       | Concluído |
| Token removido do `.env` após registro         | Concluído |
| Runner visível em Administração do Gitea       | Concluído |

---

## 24. Resumo final

Com este procedimento, o Gitea Runner foi instalado no servidor Docker HML e integrado ao Gitea do homelab.

O runner está preparado para executar pipelines do Gitea Actions usando labels como:

```text
ubuntu-latest
ubuntu-22.04
docker-hml
```

A imagem local customizada:

```text
local/gitea-act-runner:homelab-ca
```

garante que o container principal do runner confie na CA interna do homelab.

O `config.yaml` também prepara os containers de job para receberem a CA interna, permitindo operações futuras com:

```text
git.jmsalles.homelab.br
registry.jmsalles.homelab.br
docker-hml.jmsalles.homelab.br:5001
```

Este ambiente está pronto para o próximo documento, que será a criação do pipeline da aplicação:

```text
app-hello-homelab
```

com:

```text
checkout
docker build
docker login
docker push
publicação no Nexus Registry
```

---

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
