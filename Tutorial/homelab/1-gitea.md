# Guia de instalação do Gitea em Docker para o homelab JMSalles

## 1. Objetivo

Este documento descreve o procedimento de instalação do Gitea em Docker no servidor Docker HML do homelab `jmsalles.homelab.br`.

O Gitea será usado como Git local leve para versionamento dos manifests Kubernetes, arquivos GitOps, pipelines, playbooks e documentação do ambiente.

A estrutura será integrada futuramente com:

* Gitea act_runner
* Nexus Registry
* Vault
* Argo CD
* Kubernetes HML
* Kubernetes PRD
* Nginx reverse proxy
* Zabbix
* Grafana

## 2. Visão geral da arquitetura

A instalação será feita fora do cluster Kubernetes, diretamente no servidor Docker HML.

```text
Servidor Docker HML
|
|-- Docker
|-- docker compose
|-- Nginx reverse proxy
|-- Gitea
|-- PostgreSQL do Gitea
|
|-- Futuramente:
|   |-- act_runner
|   |-- Nexus
|   |-- Vault
```

Fluxo esperado:

```text
Usuário
|
| HTTPS
|
git.jmsalles.homelab.br
|
Nginx reverse proxy
|
host.docker.internal:3000
|
Container Gitea
|
PostgreSQL
```

## 3. Padrões adotados

| Item                | Valor                                              |
| ------------------- | -------------------------------------------------- |
| Serviço             | Gitea                                              |
| Caminho base        | `/home/jmsalles/gitea`                             |
| URL                 | `https://git.jmsalles.homelab.br`                  |
| Porta HTTP do Gitea | `3000`                                             |
| Porta SSH do Gitea  | `2222`                                             |
| Banco               | PostgreSQL                                         |
| Proxy reverso       | Nginx em Docker                                    |
| Certificado         | Certificado reaproveitado de `jmsalles.homelab.br` |

## 4. Pré-requisitos

Antes de iniciar, valide se o Docker está instalado e funcionando.

```bash
docker --version
```

```bash
docker compose version
```

```bash
docker ps
```

Valide o hostname da máquina.

```bash
hostnamectl
```

Valide o IP da máquina.

```bash
ip addr show
```

Valide se o serviço Docker está ativo.

```bash
sudo systemctl status docker
```

Caso esteja parado, inicie e habilite o serviço.

```bash
sudo systemctl enable --now docker
```

## 5. Criar a estrutura de diretórios

Crie o diretório base do Gitea.

```bash
mkdir -p /home/jmsalles/gitea
```

Crie os subdiretórios.

```bash
mkdir -p /home/jmsalles/gitea/{data,postgres,backup}
```

Ajuste o dono dos diretórios.

```bash
sudo chown -R jmsalles:jmsalles /home/jmsalles/gitea
```

Acesse o diretório.

```bash
cd /home/jmsalles/gitea
```

Valide a estrutura.

```bash
ls -lah /home/jmsalles/gitea
```

Resultado esperado:

```text
backup
data
postgres
```

## 6. Criar o arquivo `.env`

O arquivo `.env` será usado para armazenar variáveis do ambiente.

Crie o arquivo.

```bash
vim /home/jmsalles/gitea/.env
```

Conteúdo sugerido:

```bash
GITEA_DB_USER=gitea
GITEA_DB_PASSWORD=troque_esta_senha
GITEA_DB_NAME=gitea
GITEA_DOMAIN=git.jmsalles.homelab.br
GITEA_ROOT_URL=https://git.jmsalles.homelab.br/
GITEA_SSH_PORT=2222
```

Ajuste a permissão do arquivo.

```bash
chmod 600 /home/jmsalles/gitea/.env
```

Valide.

```bash
ls -l /home/jmsalles/gitea/.env
```

## 7. Criar o `docker-compose.yml` do Gitea

Crie o arquivo.

```bash
vim /home/jmsalles/gitea/docker-compose.yml
```

Conteúdo:

```yaml
services:
  gitea:
    image: docker.gitea.com/gitea:1.26.2
    container_name: gitea
    restart: unless-stopped
    env_file:
      - .env
    environment:
      USER_UID: "1000"
      USER_GID: "1000"

      GITEA__database__DB_TYPE: postgres
      GITEA__database__HOST: gitea-db:5432
      GITEA__database__NAME: ${GITEA_DB_NAME}
      GITEA__database__USER: ${GITEA_DB_USER}
      GITEA__database__PASSWD: ${GITEA_DB_PASSWORD}

      GITEA__server__DOMAIN: ${GITEA_DOMAIN}
      GITEA__server__ROOT_URL: ${GITEA_ROOT_URL}
      GITEA__server__HTTP_PORT: "3000"
      GITEA__server__SSH_DOMAIN: ${GITEA_DOMAIN}
      GITEA__server__SSH_PORT: ${GITEA_SSH_PORT}
      GITEA__server__START_SSH_SERVER: "false"
      GITEA__server__LFS_START_SERVER: "true"

      GITEA__service__DISABLE_REGISTRATION: "true"
      GITEA__service__REQUIRE_SIGNIN_VIEW: "false"

      GITEA__actions__ENABLED: "true"

      GITEA__webhook__ALLOWED_HOST_LIST: "*"

    volumes:
      - /home/jmsalles/gitea/data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro

    ports:
      - "3000:3000"
      - "2222:22"

    depends_on:
      - gitea-db

  gitea-db:
    image: postgres:16-alpine
    container_name: gitea-db
    restart: unless-stopped
    env_file:
      - .env
    environment:
      POSTGRES_USER: ${GITEA_DB_USER}
      POSTGRES_PASSWORD: ${GITEA_DB_PASSWORD}
      POSTGRES_DB: ${GITEA_DB_NAME}
    volumes:
      - /home/jmsalles/gitea/postgres:/var/lib/postgresql/data
```

Observação importante:

A opção abaixo deve ficar como `false`.

```yaml
GITEA__server__START_SSH_SERVER: "false"
```

Motivo:

O container do Gitea já possui o serviço SSH interno disponível na porta `22`, que será publicado no host como `2222`.

Se essa opção ficar como `true`, o Gitea tentará iniciar outro servidor SSH interno na mesma porta `22`, causando erro semelhante a:

```text
listen tcp :22: bind: address already in use
```

Por isso, o correto neste cenário é manter:

```yaml
ports:
  - "2222:22"
```

e deixar:

```yaml
GITEA__server__START_SSH_SERVER: "false"
```

## 8. Ajustar SELinux no Rocky Linux

Caso o servidor esteja usando Rocky Linux com SELinux ativo, aplique o contexto para uso com containers.

Valide o SELinux.

```bash
getenforce
```

Aplique o contexto.

```bash
sudo chcon -Rt container_file_t /home/jmsalles/gitea
```

Valide os diretórios.

```bash
ls -Z /home/jmsalles/gitea
```

## 9. Liberar firewall

Libere a porta SSH do Gitea.

```bash
sudo firewall-cmd --permanent --add-port=2222/tcp
```

Caso deseje acessar diretamente a interface do Gitea para testes:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
```

Recarregue o firewall.

```bash
sudo firewall-cmd --reload
```

Valide.

```bash
sudo firewall-cmd --list-ports
```

## 10. Subir o Gitea

Acesse o diretório.

```bash
cd /home/jmsalles/gitea
```

Suba os containers.

```bash
docker compose up -d
```

Valide os containers.

```bash
docker ps
```

Valide com o compose.

```bash
docker compose ps
```

Verifique os logs.

```bash
docker compose logs -f gitea
```

Em outro terminal, valide o PostgreSQL.

```bash
docker compose logs -f gitea-db
```

## 11. Testar acesso local ao Gitea

Teste localmente.

```bash
curl -I http://127.0.0.1:3000
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

## 12. Configurar o proxy reverso no Nginx

Crie o arquivo de configuração do virtual host no diretório do Nginx.

```bash
vim /home/jmsalles/nginx/conf.d/git.jmsalles.homelab.br.conf
```

Conteúdo:

```nginx
server {
    listen 80;
    server_name git.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name git.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/git.jmsalles.homelab.br.access.log;
    error_log  /var/log/nginx/git.jmsalles.homelab.br.error.log;

    client_max_body_size 512m;

    location / {
        proxy_pass http://host.docker.internal:3000;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
}
```

Valide se o container do Nginx possui o mapeamento para `host.docker.internal`.

```bash
docker inspect nginx-reverse-proxy-hml | grep -i host.docker.internal
```

Caso o retorno não mostre o mapeamento, valide se o `docker-compose.yml` do Nginx possui este bloco:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

Valide a configuração do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Recarregue o Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

Verifique os logs.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs -f nginx
```

## 13. Validar DNS

No seu DNS interno, aponte o registro abaixo para o IP do servidor Docker HML.

```text
git.jmsalles.homelab.br -> IP_DO_SERVIDOR_DOCKER_HML
```

Valide a resolução.

```bash
nslookup git.jmsalles.homelab.br
```

```bash
ping git.jmsalles.homelab.br
```

Teste HTTPS.

```bash
curl -k -I https://git.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/2 200
```

ou:

```text
HTTP/1.1 200 OK
```

## 14. Finalizar instalação pelo navegador

Acesse:

```text
https://git.jmsalles.homelab.br
```

Na tela de instalação inicial do Gitea, preencha os campos conforme abaixo.

### Configurações de banco de dados

| Campo                  | Valor                                 |
| ---------------------- | ------------------------------------- |
| Tipo de Banco de Dados | PostgreSQL                            |
| Servidor               | `gitea-db:5432`                       |
| Nome de usuário        | `gitea`                               |
| Senha                  | Senha definida em `GITEA_DB_PASSWORD` |
| Nome do Banco de Dados | `gitea`                               |
| SSL                    | Desabilitado                          |
| Esquema                | Em branco ou `public`                 |

### Configurações gerais

| Campo                                 | Valor                              |
| ------------------------------------- | ---------------------------------- |
| Nome do Site                          | `Gitea Homelab JMSalles`           |
| Caminho Raiz do Repositório           | `/data/git/repositories`           |
| Caminho raiz do Git LFS               | `/data/git/lfs`                    |
| Executar como Usuário                 | `git`                              |
| Domínio do Servidor                   | `git.jmsalles.homelab.br`          |
| Porta do servidor SSH                 | `2222`                             |
| Porta HTTP de uso do Gitea            | `3000`                             |
| URL base do Gitea                     | `https://git.jmsalles.homelab.br/` |
| Caminho do Log                        | `/data/gitea/log`                  |
| Habilitar Verificador de Atualizações | Opcional                           |

### Configurações opcionais

Expanda a seção `Configurações da Conta de Administrador` e crie o primeiro usuário administrador.

Sugestão:

| Campo   | Valor                            |
| ------- | -------------------------------- |
| Usuário | `jmsalles`                       |
| Senha   | Definir senha forte              |
| E-mail  | `jefersonmattossalles@gmail.com` |

### Variáveis de ambiente aplicadas

Durante a instalação, o Gitea informará que algumas configurações já estão sendo definidas pelo Docker através das variáveis de ambiente.

O item mais importante para este cenário é:

```text
GITEA__server__START_SSH_SERVER=false
```

Essa configuração evita conflito na porta interna `22`.

Após concluir o preenchimento, clique em `Instalar Gitea`.

Ao finalizar, faça login com o usuário administrador criado e valide o acesso à interface.

## 15. Ajustar o arquivo `app.ini` após instalação

Abra o arquivo.

```bash
vim /home/jmsalles/gitea/data/gitea/conf/app.ini
```

Valide:

```ini
[server]
DOMAIN = git.jmsalles.homelab.br
ROOT_URL = https://git.jmsalles.homelab.br/
HTTP_PORT = 3000
SSH_DOMAIN = git.jmsalles.homelab.br
SSH_PORT = 2222
START_SSH_SERVER = false
LFS_START_SERVER = true
```

Valide também:

```ini
[actions]
ENABLED = true
```

Reinicie o Gitea caso necessário.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose restart gitea
```

Valide os logs.

```bash
docker compose logs -f gitea
```

## 16. Criar repositórios iniciais

Sugestão de repositórios para seu projeto:

```text
k8s-gitops
k8s-apps
dockerfiles
helm-charts
infra-docs
ansible-homelab
homelab-labs
```

Estrutura sugerida para o repositório `k8s-gitops`:

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

## 17. Testar clone via HTTPS

Em uma estação cliente, teste o clone via HTTPS.

```bash
git clone https://git.jmsalles.homelab.br/jmsalles/k8s-gitops.git
```

Caso use certificado interno, instale a CA raiz do seu homelab na estação cliente para evitar erro de certificado.

## 18. Testar clone via SSH

A porta SSH do Gitea será `2222`, pois a porta `22` normalmente já é usada pelo SSH do host.

Teste a conexão.

```bash
ssh -T -p 2222 git@git.jmsalles.homelab.br
```

Exemplo de clone via SSH:

```bash
git clone ssh://git@git.jmsalles.homelab.br:2222/jmsalles/k8s-gitops.git
```

Caso ainda não tenha chave SSH na estação, gere uma chave.

```bash
ssh-keygen -t ed25519 -C "jmsalles@git.jmsalles.homelab.br"
```

Exiba a chave pública.

```bash
cat ~/.ssh/id_ed25519.pub
```

Cadastre essa chave no Gitea em:

```text
Configurações
Chaves SSH/GPG
Adicionar chave
```

## 19. Preparação para Argo CD

Depois que o Gitea estiver instalado, o Argo CD poderá consumir os repositórios GitOps.

Fluxo esperado:

```text
Gitea
|
Repositório k8s-gitops
|
Argo CD
|
Cluster Kubernetes HML/PRD
```

Para o Argo CD acessar o Gitea, recomenda-se criar uma chave SSH dedicada.

Na máquina administrativa, crie uma chave específica.

```bash
ssh-keygen -t ed25519 -C "argocd@git.jmsalles.homelab.br" -f ~/.ssh/argocd_gitea
```

Exiba a chave pública.

```bash
cat ~/.ssh/argocd_gitea.pub
```

Cadastre a chave pública no Gitea.

Depois, no Argo CD, cadastre o repositório usando a chave privada.

Exemplo de URL SSH:

```text
ssh://git@git.jmsalles.homelab.br:2222/jmsalles/k8s-gitops.git
```

## 20. Preparação para act_runner

O Gitea Actions ficará habilitado nesta instalação.

O runner será instalado depois em:

```text
/home/jmsalles/runner
```

Fluxo futuro:

```text
Commit no Gitea
|
Workflow Gitea Actions
|
act_runner
|
Build da imagem
|
Push para Nexus
|
Atualização do GitOps
|
Argo CD aplica no Kubernetes
```

Exemplo de estrutura futura:

```text
/home/jmsalles/
├── gitea/
├── nginx/
├── nexus/
├── vault/
└── runner/
```

## 21. Validações operacionais

Validar containers.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose ps
```

Validar logs do Gitea.

```bash
docker compose logs --tail=100 gitea
```

Validar logs do PostgreSQL.

```bash
docker compose logs --tail=100 gitea-db
```

Validar porta interna.

```bash
curl -I http://127.0.0.1:3000
```

Validar HTTPS pelo proxy.

```bash
curl -k -I https://git.jmsalles.homelab.br
```

Validar porta SSH do Gitea.

```bash
ss -lntp | grep 2222
```

Validar uso de disco.

```bash
df -h
```

Validar consumo dos containers.

```bash
docker stats
```

## 22. Monitoramento no Zabbix

Adicionar no Zabbix o monitoramento dos seguintes itens:

```text
Disponibilidade HTTPS de git.jmsalles.homelab.br
Porta 443
Porta 2222
Status do container gitea
Status do container gitea-db
Uso de CPU
Uso de memória
Uso de disco em /home
Uso de disco em /home/jmsalles/gitea
```

Comandos úteis para item customizado:

```bash
docker inspect -f '{{.State.Running}}' gitea
```

```bash
docker inspect -f '{{.State.Running}}' gitea-db
```

Validação HTTP:

```bash
curl -k -s -o /dev/null -w "%{http_code}\n" https://git.jmsalles.homelab.br
```

## 23. Backup básico

Crie o diretório de backup.

```bash
mkdir -p /home/jmsalles/gitea/backup
```

Backup lógico do PostgreSQL com o container rodando:

```bash
docker exec gitea-db pg_dump -U gitea gitea > /home/jmsalles/gitea/backup/gitea-db-$(date +%F_%H%M).sql
```

Compactar o dump.

```bash
gzip /home/jmsalles/gitea/backup/gitea-db-*.sql
```

Backup dos dados do Gitea.

```bash
tar -czf /home/jmsalles/gitea/backup/gitea-data-$(date +%F_%H%M).tar.gz -C /home/jmsalles/gitea data
```

Listar backups.

```bash
ls -lh /home/jmsalles/gitea/backup
```

Backup frio, caso deseje parar os containers antes de copiar os dados.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose down
```

```bash
tar -czf /home/jmsalles/gitea/backup/gitea-postgres-$(date +%F_%H%M).tar.gz -C /home/jmsalles/gitea postgres
```

```bash
docker compose up -d
```

Valide.

```bash
docker compose ps
```

## 24. Atualização do Gitea

Antes de atualizar, faça backup.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose ps
```

Baixe a nova imagem definida no `docker-compose.yml`.

```bash
docker compose pull
```

Recrie o container.

```bash
docker compose up -d
```

Valide logs.

```bash
docker compose logs -f gitea
```

Valide a interface.

```bash
curl -k -I https://git.jmsalles.homelab.br
```

## 25. Troubleshooting

### 25.1 Container não sobe

Verifique logs.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose logs -f
```

Valide permissões.

```bash
ls -lah /home/jmsalles/gitea
```

```bash
ls -lah /home/jmsalles/gitea/data
```

Aplique novamente o contexto SELinux.

```bash
sudo chcon -Rt container_file_t /home/jmsalles/gitea
```

Reinicie.

```bash
docker compose restart
```

### 25.2 Erro de banco de dados

Valide se o PostgreSQL está rodando.

```bash
docker ps | grep gitea-db
```

Verifique os logs.

```bash
docker compose logs -f gitea-db
```

Teste conexão a partir do container Gitea.

```bash
docker exec -it gitea sh
```

Dentro do container:

```bash
nc -vz gitea-db 5432
```

### 25.3 Erro 502 no Nginx

Valide se o Gitea está rodando.

```bash
docker ps | grep gitea
```

Teste acesso direto ao serviço.

```bash
curl -I http://127.0.0.1:3000
```

Valide a configuração do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Veja os logs.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs -f nginx
```

Confirme que o container do Nginx consegue resolver e acessar:

```text
http://host.docker.internal:3000
```

### 25.4 URL aparece errada no Gitea

Abra o `app.ini`.

```bash
vim /home/jmsalles/gitea/data/gitea/conf/app.ini
```

Valide:

```ini
ROOT_URL = https://git.jmsalles.homelab.br/
DOMAIN = git.jmsalles.homelab.br
SSH_DOMAIN = git.jmsalles.homelab.br
SSH_PORT = 2222
START_SSH_SERVER = false
```

Reinicie.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose restart gitea
```

### 25.5 Clone SSH não funciona

Valide se a porta está escutando.

```bash
ss -lntp | grep 2222
```

Valide firewall.

```bash
sudo firewall-cmd --list-ports
```

Teste SSH.

```bash
ssh -T -p 2222 git@git.jmsalles.homelab.br
```

### 25.6 Tela fica presa em `Installing now, please wait...`

Valide os logs.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose logs -f gitea
```

Se aparecer erro semelhante a este:

```text
listen tcp :22: bind: address already in use
```

corrija o `docker-compose.yml`.

```bash
vim /home/jmsalles/gitea/docker-compose.yml
```

Garanta que esteja assim:

```yaml
GITEA__server__START_SSH_SERVER: "false"
```

Garanta que o mapeamento de portas continue assim:

```yaml
ports:
  - "3000:3000"
  - "2222:22"
```

Se o arquivo `app.ini` já existir, ajuste também nele.

```bash
vim /home/jmsalles/gitea/data/gitea/conf/app.ini
```

Na seção `[server]`, deixe:

```ini
START_SSH_SERVER = false
SSH_DOMAIN = git.jmsalles.homelab.br
SSH_PORT = 2222
```

Reinicie os containers.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose down
```

```bash
docker compose up -d
```

Acompanhe os logs.

```bash
docker compose logs -f gitea
```

Depois limpe o cache do navegador ou abra em aba anônima e acesse novamente:

```text
https://git.jmsalles.homelab.br
```

## 26. Checklist final

| Item                                                    | Status   |
| ------------------------------------------------------- | -------- |
| Diretório `/home/jmsalles/gitea` criado                 | Pendente |
| `.env` criado                                           | Pendente |
| `docker-compose.yml` criado                             | Pendente |
| `START_SSH_SERVER` configurado como `false`             | Pendente |
| Gitea iniciado                                          | Pendente |
| PostgreSQL iniciado                                     | Pendente |
| Proxy reverso criado                                    | Pendente |
| DNS `git.jmsalles.homelab.br` apontando para o servidor | Pendente |
| HTTPS validado                                          | Pendente |
| Primeiro usuário administrador criado                   | Pendente |
| Clone HTTPS validado                                    | Pendente |
| Clone SSH validado                                      | Pendente |
| Repositório `k8s-gitops` criado                         | Pendente |
| Backup básico testado                                   | Pendente |
| Monitoramento no Zabbix planejado                       | Pendente |

## 27. Resumo final

Com essa instalação, o servidor Docker HML passa a ter um Git local leve, organizado e preparado para o fluxo DevOps/GitOps do homelab.

Modelo final:

```text
Gitea
|
Repositórios GitOps
|
Argo CD
|
Kubernetes HML/PRD
```

Modelo futuro com pipeline:

```text
Gitea
|
act_runner
|
Build de imagem
|
Nexus Registry
|
Atualização de manifest
|
Argo CD
|
Kubernetes
```

Essa escolha mantém o ambiente leve, reduz consumo de memória em comparação com GitLab CE e deixa a base pronta para Nexus, Vault, Argo CD, Zabbix e Grafana.

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)
