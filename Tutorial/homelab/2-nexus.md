Segue o tutorial completo revisado, já incluindo a opção futura de instalar a CA raiz no Docker daemon e remover o `insecure-registries`.

# Guia de instalação do Nexus Repository em Docker no homelab JMSalles

## 1. Objetivo

Este documento descreve o procedimento de instalação do Nexus Repository em Docker no servidor físico Docker HML do homelab `jmsalles.homelab.br`.

O Nexus será usado como repositório central de artefatos e como registry Docker privado para imagens do ambiente HML.

Servidor utilizado:

```text
docker-hml.jmsalles.homelab.br
```

IP:

```text
192.168.31.37
```

## 2. Visão geral da arquitetura

```text
Rede homelab
|
|-- docker-hml.jmsalles.homelab.br
|   |
|   |-- Docker
|   |-- Nginx reverse proxy
|   |-- Gitea
|   |-- Stirling PDF
|   |-- Nexus Repository
|
|-- Kubernetes HML/PRD
    |
    |-- Futuramente consumirá imagens do Nexus
```

Fluxo da interface web:

```text
Usuário
|
| HTTPS
|
nexus.jmsalles.homelab.br
|
Nginx reverse proxy
|
host.docker.internal:8081
|
Container Nexus
|
/home/jmsalles/nexus/nexus-data
```

Fluxo do registry Docker:

```text
Docker client
|
| HTTPS
|
registry.jmsalles.homelab.br
|
Nginx reverse proxy
|
host.docker.internal:5001
|
Nexus docker-hosted
```

Fluxo futuro com CI/CD:

```text
Gitea
|
act_runner
|
Build da imagem
|
Push para registry.jmsalles.homelab.br
|
Argo CD
|
Kubernetes HML/PRD
```

## 3. Padrões adotados

| Item                | Valor                                              |
| ------------------- | -------------------------------------------------- |
| Serviço             | Nexus Repository                                   |
| Host                | `docker-hml.jmsalles.homelab.br`                   |
| IP                  | `192.168.31.37`                                    |
| Interface web       | `https://nexus.jmsalles.homelab.br`                |
| Registry Docker     | `registry.jmsalles.homelab.br`                     |
| Caminho base        | `/home/jmsalles/nexus`                             |
| Container           | `nexus`                                            |
| Imagem              | `sonatype/nexus3:latest`                           |
| Porta web do Nexus  | `8081`                                             |
| Porta Docker hosted | `5001`                                             |
| Porta Docker group  | `5000`                                             |
| Porta Docker proxy  | `5002`                                             |
| Proxy reverso       | Nginx em Docker                                    |
| Certificado         | Certificado reaproveitado de `jmsalles.homelab.br` |
| JVM                 | `-Xms1200m -Xmx2g -XX:MaxDirectMemorySize=2g`      |

## 4. Observação sobre recursos

O Nexus usa Java e pode consumir bastante memória.

Como o host Docker HML possui 16 GB de RAM e também roda outros containers, o Nexus será iniciado com parâmetros controlados de JVM.

Parâmetro usado:

```text
-Xms1200m -Xmx2g -XX:MaxDirectMemorySize=2g
```

Isso ajuda a evitar que o Nexus consuma memória demais e prejudique Gitea, Nginx, Stirling PDF e outros serviços do host.

## 5. Observação sobre certificado interno

O ambiente usa certificado interno ou autoassinado.

Por isso, testes com `curl` podem precisar da opção `-k`.

```bash
curl -k -I https://nexus.jmsalles.homelab.br
```

Caso apareça o erro abaixo, o problema é a CA interna ainda não estar instalada como confiável no host ou container que está fazendo o teste.

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Neste tutorial, a CA raiz não será instalada inicialmente.

## 6. Pré-requisitos

Validar Docker.

```bash
docker --version
```

Validar Docker Compose.

```bash
docker compose version
```

Validar containers atuais.

```bash
docker ps
```

Validar host.

```bash
hostnamectl
```

Validar IP.

```bash
ip addr show
```

Validar serviço Docker.

```bash
sudo systemctl status docker
```

Caso o Docker esteja parado, execute:

```bash
sudo systemctl enable --now docker
```

## 7. Validar DNS

Crie os registros DNS apontando para o servidor Docker HML.

```text
nexus.jmsalles.homelab.br     -> 192.168.31.37
registry.jmsalles.homelab.br  -> 192.168.31.37
```

Validar resolução do Nexus.

```bash
nslookup nexus.jmsalles.homelab.br
```

Validar resolução do registry.

```bash
nslookup registry.jmsalles.homelab.br
```

Testar ping.

```bash
ping nexus.jmsalles.homelab.br
```

```bash
ping registry.jmsalles.homelab.br
```

## 8. Criar estrutura de diretórios

Criar diretório base.

```bash
mkdir -p /home/jmsalles/nexus
```

Criar diretório de dados.

```bash
mkdir -p /home/jmsalles/nexus/nexus-data
```

Ajustar dono do diretório base.

```bash
sudo chown -R jmsalles:jmsalles /home/jmsalles/nexus
```

O container oficial do Nexus usa o usuário interno com UID `200`. Ajuste o diretório persistente para esse UID/GID.

```bash
sudo chown -R 200:200 /home/jmsalles/nexus/nexus-data
```

Validar.

```bash
ls -lah /home/jmsalles/nexus
```

```bash
ls -lan /home/jmsalles/nexus
```

Resultado esperado para `nexus-data`:

```text
200 200 nexus-data
```

## 9. Criar o arquivo `.env`

Criar arquivo.

```bash
vim /home/jmsalles/nexus/.env
```

Conteúdo:

```bash
NEXUS_DOMAIN=nexus.jmsalles.homelab.br
NEXUS_PORT=8081
INSTALL4J_ADD_VM_PARAMS=-Xms1200m -Xmx2g -XX:MaxDirectMemorySize=2g -Djava.util.prefs.userRoot=/nexus-data/javaprefs
```

Ajustar permissão.

```bash
chmod 600 /home/jmsalles/nexus/.env
```

Validar.

```bash
ls -l /home/jmsalles/nexus/.env
```

## 10. Criar o `docker-compose.yml`

Criar arquivo.

```bash
vim /home/jmsalles/nexus/docker-compose.yml
```

Conteúdo:

```yaml
services:
  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    restart: unless-stopped
    env_file:
      - .env
    environment:
      INSTALL4J_ADD_VM_PARAMS: ${INSTALL4J_ADD_VM_PARAMS}
    ports:
      - "8081:8081"
      - "5000:5000"
      - "5001:5001"
      - "5002:5002"
    volumes:
      - /home/jmsalles/nexus/nexus-data:/nexus-data
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

Portas usadas:

|  Porta | Uso                                                     |
| -----: | ------------------------------------------------------- |
| `8081` | Interface web do Nexus                                  |
| `5001` | Docker hosted, usado por `registry.jmsalles.homelab.br` |
| `5000` | Docker group                                            |
| `5002` | Docker proxy                                            |

## 11. Validar o Compose

Acessar o diretório.

```bash
cd /home/jmsalles/nexus
```

Validar configuração.

```bash
docker compose config
```

## 12. Subir o Nexus

Subir container.

```bash
docker compose up -d
```

Validar container.

```bash
docker ps | grep nexus
```

Validar pelo Compose.

```bash
docker compose ps
```

Acompanhar logs.

```bash
docker compose logs -f nexus
```

O Nexus pode demorar alguns minutos para iniciar na primeira execução.

## 13. Validar portas locais

Validar porta web.

```bash
curl -I http://127.0.0.1:8081
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Validar portas do registry.

```bash
ss -lntp | egrep '8081|5000|5001|5002'
```

Validar porta `5001`.

```bash
curl -I http://127.0.0.1:5001/v2/
```

Resultado esperado pode ser:

```text
HTTP/1.1 401 Unauthorized
```

Esse retorno é normal, pois o registry exige autenticação.

## 14. Configurar Nginx para a interface web do Nexus

Criar virtual host.

```bash
vim /home/jmsalles/nginx/conf.d/nexus.jmsalles.homelab.br.conf
```

Conteúdo:

```nginx
server {
    listen 80;
    server_name nexus.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name nexus.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/nexus.jmsalles.homelab.br.access.log;
    error_log  /var/log/nginx/nexus.jmsalles.homelab.br.error.log;

    client_max_body_size 2048m;

    location / {
        proxy_pass http://host.docker.internal:8081;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 443;

        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
```

Validar Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Recarregar Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

Validar logs.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

## 15. Configurar Nginx para o Registry Docker

O registry será publicado em:

```text
registry.jmsalles.homelab.br
```

Ele apontará para a porta `5001`, que será o repositório `docker-hosted`.

Criar virtual host.

```bash
vim /home/jmsalles/nginx/conf.d/registry.jmsalles.homelab.br.conf
```

Conteúdo:

```nginx
server {
    listen 80;
    server_name registry.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name registry.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/registry.jmsalles.homelab.br.access.log;
    error_log  /var/log/nginx/registry.jmsalles.homelab.br.error.log;

    client_max_body_size 0;

    location / {
        proxy_pass http://host.docker.internal:5001;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 443;
        proxy_set_header Docker-Distribution-Api-Version registry/2.0;

        proxy_request_buffering off;
        proxy_buffering off;

        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
```

Validar Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Recarregar Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

Validar logs.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

## 16. Testar acesso HTTPS da interface web

Testar com `curl -k`.

```bash
curl -k -I https://nexus.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Acessar pelo navegador:

```text
https://nexus.jmsalles.homelab.br
```

## 17. Testar acesso HTTPS do registry

Testar endpoint `/v2/`.

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Resultado esperado:

```text
HTTP/1.1 401 Unauthorized
```

Esse resultado é esperado e indica que o registry respondeu, mas exige autenticação.

Se retornar `502`, validar a porta local.

```bash
curl -I http://127.0.0.1:5001/v2/
```

```bash
ss -lntp | grep 5001
```

## 18. Obter senha inicial do admin

A senha inicial fica no arquivo `admin.password`.

```bash
sudo cat /home/jmsalles/nexus/nexus-data/admin.password
```

Acessar:

```text
https://nexus.jmsalles.homelab.br
```

Login:

```text
admin
```

Senha:

```text
conteúdo do arquivo admin.password
```

Após o primeiro login, o Nexus solicitará a troca de senha.

## 19. Configuração inicial pelo navegador

No primeiro acesso:

```text
1. Entrar com o usuário admin.
2. Informar a senha inicial.
3. Alterar a senha do admin.
4. Escolher se deseja permitir acesso anônimo.
```

Recomendação:

```text
Permitir acesso anônimo: desabilitado inicialmente
```

Motivo:

```text
Como o Nexus será usado como registry e repositório de artefatos, é melhor controlar acesso desde o início.
```

## 20. Habilitar Docker Bearer Token Realm

Para o Docker login funcionar corretamente, habilite o realm do Docker.

No Nexus, acesse:

```text
Settings
Security
Realms
```

Mova para `Active`:

```text
Docker Bearer Token Realm
```

Salve.

## 21. Criar repositórios iniciais

Acesse:

```text
Settings
Repository
Repositories
Create repository
```

## 21.1 Criar repositório `raw-hosted`

Tipo:

```text
raw (hosted)
```

Nome:

```text
raw-hosted
```

Uso:

```text
Guardar arquivos diversos, scripts, binários, pacotes, documentação e artefatos simples.
```

## 21.2 Criar repositório `docker-hosted`

Tipo:

```text
docker (hosted)
```

Nome:

```text
docker-hosted
```

Configuração:

| Campo                        | Valor              |
| ---------------------------- | ------------------ |
| Name                         | `docker-hosted`    |
| Online                       | Marcado            |
| Repository Connectors        | `Other Connectors` |
| HTTP                         | Marcado            |
| HTTP port                    | `5001`             |
| HTTPS                        | Desmarcado         |
| Allow Anonymous Docker Pulls | Opcional           |
| Enable Docker V1 API         | Desabilitado       |

O campo `HTTP port` deve ser preenchido com:

```text
5001
```

Esse será o repositório usado pelo endereço:

```text
registry.jmsalles.homelab.br
```

## 21.3 Criar repositório `docker-proxy`

Tipo:

```text
docker (proxy)
```

Nome:

```text
docker-proxy
```

Configuração:

| Campo                 | Valor                          |
| --------------------- | ------------------------------ |
| Name                  | `docker-proxy`                 |
| Online                | Marcado                        |
| Repository Connectors | `Other Connectors`             |
| HTTP                  | Marcado                        |
| HTTP port             | `5002`                         |
| HTTPS                 | Desmarcado                     |
| Remote storage        | `https://registry-1.docker.io` |
| Docker Index          | `Use Docker Hub`               |

Uso:

```text
Cache/proxy do Docker Hub.
```

## 21.4 Criar repositório `docker-group`

Tipo:

```text
docker (group)
```

Nome:

```text
docker-group
```

Configuração:

| Campo                 | Valor                            |
| --------------------- | -------------------------------- |
| Name                  | `docker-group`                   |
| Online                | Marcado                          |
| Repository Connectors | `Other Connectors`               |
| HTTP                  | Marcado                          |
| HTTP port             | `5000`                           |
| HTTPS                 | Desmarcado                       |
| Members               | `docker-hosted` e `docker-proxy` |

Uso:

```text
Endpoint único para pull de imagens.
```

Observação:

```text
Neste ambiente, o endpoint principal de login, push e pull será registry.jmsalles.homelab.br, apontando para o docker-hosted na porta 5001.
```

## 22. Configurar Docker daemon para usar `registry.jmsalles.homelab.br`

Como o certificado é interno/autoassinado e a CA ainda não será instalada no Docker daemon, configure temporariamente o registry como inseguro.

Esse ajuste deve ser feito em todo host Docker que for executar `docker login`, `docker pull` ou `docker push` para o registry.

No host cliente Docker, edite:

```bash
sudo vim /etc/docker/daemon.json
```

Conteúdo:

```json
{
  "insecure-registries": [
    "registry.jmsalles.homelab.br"
  ]
}
```

Reinicie o Docker.

```bash
sudo systemctl restart docker
```

No próprio host `docker-hml`, após reiniciar o Docker, suba os containers principais novamente.

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose up -d
```

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose up -d
```

Valide os containers.

```bash
docker ps
```

## 22.1 Opção recomendada futuramente

O ideal futuramente é instalar a CA raiz no Docker daemon e remover o `insecure-registries`.

Por enquanto, para o homelab, essa configuração simplifica o uso do Docker registry.

Quando for instalar a CA raiz corretamente, o caminho esperado para o Docker confiar no registry será:

```bash
sudo mkdir -p /etc/docker/certs.d/registry.jmsalles.homelab.br
```

```bash
sudo cp /home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.crt /etc/docker/certs.d/registry.jmsalles.homelab.br/ca.crt
```

Depois, remova o bloco `insecure-registries` do arquivo:

```bash
sudo vim /etc/docker/daemon.json
```

Exemplo de arquivo sem `insecure-registries`, caso não exista outra configuração:

```json
{}
```

Reinicie o Docker.

```bash
sudo systemctl restart docker
```

Suba os containers principais novamente, se estiver executando no host `docker-hml`.

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose up -d
```

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose up -d
```

Com a CA instalada corretamente, o Docker passará a confiar no certificado do registry sem precisar tratar o ambiente como inseguro.

## 23. Testar login no Registry

O login será feito em:

```text
registry.jmsalles.homelab.br
```

Executar:

```bash
docker login registry.jmsalles.homelab.br
```

Informe usuário e senha do Nexus.

Para teste inicial, pode usar o usuário `admin`.

Para uso definitivo, recomenda-se criar um usuário de serviço.

Exemplo:

```text
svc-gitea-runner
```

## 24. Testar push no Registry

Baixar imagem pequena.

```bash
docker pull alpine:latest
```

Criar tag apontando para o registry.

```bash
docker tag alpine:latest registry.jmsalles.homelab.br/lab/alpine:latest
```

Enviar para o Nexus.

```bash
docker push registry.jmsalles.homelab.br/lab/alpine:latest
```

Validar no Nexus:

```text
Browse
docker-hosted
lab/alpine
```

## 25. Testar pull no Registry

Remover imagem local.

```bash
docker rmi registry.jmsalles.homelab.br/lab/alpine:latest
```

Fazer pull a partir do Nexus.

```bash
docker pull registry.jmsalles.homelab.br/lab/alpine:latest
```

Resultado esperado:

```text
Imagem baixada com sucesso a partir do Nexus docker-hosted.
```

## 26. Testar docker-group, opcional

O `docker-group` está na porta `5000`.

Teste localmente:

```bash
curl -I http://127.0.0.1:5000/v2/
```

Resultado esperado pode ser:

```text
HTTP/1.1 401 Unauthorized
```

Neste momento, o endpoint principal continua sendo:

```text
registry.jmsalles.homelab.br
```

## 27. Ajustes recomendados de segurança

Recomendações iniciais:

```text
Trocar senha do admin no primeiro acesso
Desabilitar acesso anônimo inicialmente
Criar usuário específico para CI/CD futuramente
Não usar admin nos pipelines
Criar permissão somente para push/pull no docker-hosted
Criar usuário separado para leitura do Kubernetes futuramente
```

Usuários sugeridos futuramente:

| Usuário            | Uso                             |
| ------------------ | ------------------------------- |
| `svc-gitea-runner` | Push de imagens via pipeline    |
| `svc-k8s-pull`     | Pull de imagens pelo Kubernetes |
| `svc-admin-lab`    | Administração controlada        |

## 28. Validações operacionais

Validar container.

```bash
docker ps | grep nexus
```

Validar logs.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose logs --tail=100 nexus
```

Validar porta da interface.

```bash
curl -I http://127.0.0.1:8081
```

Validar HTTPS da interface web.

```bash
curl -k -I https://nexus.jmsalles.homelab.br
```

Validar registry pelo Nginx.

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Validar registry local.

```bash
curl -I http://127.0.0.1:5001/v2/
```

Validar consumo.

```bash
docker stats nexus
```

Validar disco.

```bash
du -sh /home/jmsalles/nexus/nexus-data
```

```bash
df -h
```

## 29. Troubleshooting

### 29.1 Nexus demora para subir

Validar logs.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose logs -f nexus
```

O Nexus pode demorar alguns minutos na primeira inicialização.

### 29.2 Erro de permissão no volume

Sintoma:

```text
Permission denied em /nexus-data
```

Corrigir permissão.

```bash
sudo chown -R 200:200 /home/jmsalles/nexus/nexus-data
```

Reiniciar container.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose restart nexus
```

### 29.3 Erro de certificado no curl

Erro:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Contorno para interface web:

```bash
curl -k -I https://nexus.jmsalles.homelab.br
```

Contorno para registry:

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Causa:

```text
CA raiz interna ainda não instalada no host ou container que faz o teste.
```

### 29.4 Erro 502 no Nginx para interface web

Validar se o Nexus responde localmente.

```bash
curl -I http://127.0.0.1:8081
```

Validar configuração do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Validar logs do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

### 29.5 Erro 502 no Nginx para registry

Validar porta `5001`.

```bash
curl -I http://127.0.0.1:5001/v2/
```

Validar se a porta está escutando.

```bash
ss -lntp | grep 5001
```

Validar logs do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

Validar arquivo do registry.

```bash
cat /home/jmsalles/nginx/conf.d/registry.jmsalles.homelab.br.conf
```

### 29.6 Não encontra senha inicial

Validar arquivo.

```bash
sudo ls -l /home/jmsalles/nexus/nexus-data/admin.password
```

Ler senha.

```bash
sudo cat /home/jmsalles/nexus/nexus-data/admin.password
```

Se o arquivo não existir, provavelmente a senha já foi alterada no primeiro login.

### 29.7 Docker login falha

Validar endpoint.

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Validar Docker daemon.

```bash
cat /etc/docker/daemon.json
```

Deve conter:

```json
{
  "insecure-registries": [
    "registry.jmsalles.homelab.br"
  ]
}
```

Reiniciar Docker.

```bash
sudo systemctl restart docker
```

Subir containers novamente, caso necessário.

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose up -d
```

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose up -d
```

Testar login novamente.

```bash
docker login registry.jmsalles.homelab.br
```

### 29.8 Push falha com `unauthorized`

Causa provável:

```text
Usuário sem permissão de escrita no repositório docker-hosted.
```

Validar no Nexus:

```text
Settings
Security
Users
Roles
Privileges
```

Para teste inicial, use `admin`.

Para uso definitivo, crie um usuário de serviço com permissão de push/pull no `docker-hosted`.

### 29.9 Push falha com `blob upload unknown` ou erro durante upload

Validar configuração do Nginx do registry.

```bash
cat /home/jmsalles/nginx/conf.d/registry.jmsalles.homelab.br.conf
```

Confirmar que existem as linhas:

```nginx
client_max_body_size 0;
proxy_request_buffering off;
proxy_buffering off;
```

Recarregar Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

## 30. Checklist final

| Item                                                                         | Status   |
| ---------------------------------------------------------------------------- | -------- |
| DNS `nexus.jmsalles.homelab.br` criado                                       | Pendente |
| DNS `registry.jmsalles.homelab.br` criado                                    | Pendente |
| Diretório `/home/jmsalles/nexus` criado                                      | Pendente |
| Diretório `nexus-data` com UID/GID `200:200`                                 | Pendente |
| Arquivo `.env` criado                                                        | Pendente |
| `docker-compose.yml` criado                                                  | Pendente |
| Container `nexus` iniciado                                                   | Pendente |
| Porta local `8081` validada                                                  | Pendente |
| Porta local `5001` validada                                                  | Pendente |
| Nginx web `nexus.jmsalles.homelab.br` configurado                            | Pendente |
| Nginx registry `registry.jmsalles.homelab.br` configurado                    | Pendente |
| HTTPS `nexus.jmsalles.homelab.br` validado                                   | Pendente |
| HTTPS `registry.jmsalles.homelab.br/v2/` validado                            | Pendente |
| Senha inicial coletada                                                       | Pendente |
| Primeiro login realizado                                                     | Pendente |
| Senha admin alterada                                                         | Pendente |
| Docker Bearer Token Realm habilitado                                         | Pendente |
| Repositório `raw-hosted` criado                                              | Pendente |
| Repositório `docker-hosted` criado na porta `5001`                           | Pendente |
| Repositório `docker-proxy` criado na porta `5002`                            | Pendente |
| Repositório `docker-group` criado na porta `5000`                            | Pendente |
| Docker daemon configurado temporariamente com `registry.jmsalles.homelab.br` | Pendente |
| Login em `registry.jmsalles.homelab.br` validado                             | Pendente |
| Push em `registry.jmsalles.homelab.br` validado                              | Pendente |
| Pull em `registry.jmsalles.homelab.br` validado                              | Pendente |

## 31. Resumo final

Interface web do Nexus:

```text
https://nexus.jmsalles.homelab.br
```

Registry Docker:

```text
registry.jmsalles.homelab.br
```

Login Docker:

```bash
docker login registry.jmsalles.homelab.br
```

Push Docker:

```bash
docker push registry.jmsalles.homelab.br/lab/alpine:latest
```

Pull Docker:

```bash
docker pull registry.jmsalles.homelab.br/lab/alpine:latest
```

Diretório crítico:

```text
/home/jmsalles/nexus/nexus-data
```

Modelo futuro:

```text
Gitea
|
act_runner
|
Build da imagem
|
Push para registry.jmsalles.homelab.br
|
Argo CD
|
Kubernetes HML/PRD
```

Observação importante:

```text
O ideal futuramente é instalar a CA raiz no Docker daemon e remover o insecure registry.
Por enquanto, para o homelab, essa configuração simplifica o uso do Docker registry.
```

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)
