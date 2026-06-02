# Guia de instalação do Vault em Docker no homelab JMSalles

## 1. Objetivo

Este documento descreve como instalar o HashiCorp Vault em Docker no servidor físico Docker HML do homelab JMSalles.

O Vault será usado para centralizar os segredos do ambiente, como:

```text
Credenciais do Nexus
Credenciais do registry Docker
Token do Gitea act_runner
Credenciais do usuário svc-docker-deploy
Secrets para Kubernetes HML
Tokens e senhas de automações futuras
```

Servidor utilizado:

```text
docker-hml.jmsalles.homelab.br
```

IP:

```text
192.168.31.37
```

URL final:

```text
https://vault.jmsalles.homelab.br
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
|   |-- Nexus
|   |-- Stirling PDF
|   |-- Vault
|
|-- Kubernetes HML/PRD
    |
    |-- Futuramente consumirá secrets e imagens do ambiente
```

Fluxo de acesso:

```text
Usuário / Pipeline / Cliente
|
| HTTPS
|
vault.jmsalles.homelab.br
|
Nginx reverse proxy
|
host.docker.internal:8200
|
Container Vault
|
/home/jmsalles/vault/data
```

## 3. Padrões adotados

| Item                     | Valor                                                 |
| ------------------------ | ----------------------------------------------------- |
| Serviço                  | HashiCorp Vault                                       |
| Host                     | `docker-hml.jmsalles.homelab.br`                      |
| IP                       | `192.168.31.37`                                       |
| URL                      | `https://vault.jmsalles.homelab.br`                   |
| Caminho base             | `/home/jmsalles/vault`                                |
| Container                | `vault`                                               |
| Imagem                   | `hashicorp/vault:latest`                              |
| Porta local              | `8200`                                                |
| Porta interna de cluster | `8201`                                                |
| Storage                  | Raft integrado, single node                           |
| Proxy reverso            | Nginx em Docker                                       |
| Certificado              | Certificado wildcard interno de `jmsalles.homelab.br` |
| TLS interno do Vault     | Desabilitado, TLS terminado no Nginx                  |
| KV engine                | `kv-v2` em `secret/`                                  |

## 4. Observações importantes sobre segurança

O Vault protege segredos sensíveis. Então existem três pontos críticos:

```text
Unseal keys
Root token
Diretório persistente /home/jmsalles/vault/data
```

Regras recomendadas:

```text
Não salvar unseal keys em arquivo dentro do servidor
Não salvar root token em documentação, chamado, Git ou print
Guardar unseal keys em local seguro
Guardar root token em local seguro
Usar root token somente para administração inicial
Criar políticas e tokens/usuários específicos para automações
```

Observação importante:

```text
Se o container ou o host reiniciar, o Vault pode voltar em estado sealed.
Nesse caso, será necessário executar o unseal novamente.
```

## 5. Observação sobre certificado interno

O ambiente usa certificado interno/autoassinado.

Por isso, testes com `curl` podem precisar da opção `-k`.

```bash
curl -k -I https://vault.jmsalles.homelab.br
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

## 7. Criar DNS do Vault

Crie o registro DNS apontando para o servidor Docker HML.

```text
vault.jmsalles.homelab.br -> 192.168.31.37
```

Validar resolução.

```bash
nslookup vault.jmsalles.homelab.br
```

Testar ping.

```bash
ping vault.jmsalles.homelab.br
```

## 8. Criar estrutura de diretórios

Criar diretório base.

```bash
mkdir -p /home/jmsalles/vault
```

Criar subdiretórios.

```bash
mkdir -p /home/jmsalles/vault/{config,data,logs}
```

Ajustar dono inicial para o usuário administrativo do host.

```bash
sudo chown -R jmsalles:jmsalles /home/jmsalles/vault
```

Validar.

```bash
ls -lah /home/jmsalles/vault
```

## 9. Ajustar permissões do volume persistente

O Vault roda dentro do container com um usuário interno específico. Se o diretório `/home/jmsalles/vault/data` não estiver gravável para esse usuário, o Vault pode falhar com erro semelhante a:

```text
failed to open bolt file: open /vault/data/vault.db: permission denied
```

Descubra o UID e GID usados pela imagem do Vault.

```bash
VAULT_UID=$(docker run --rm --entrypoint sh hashicorp/vault:latest -c 'id -u')
```

```bash
VAULT_GID=$(docker run --rm --entrypoint sh hashicorp/vault:latest -c 'id -g')
```

```bash
echo "${VAULT_UID}:${VAULT_GID}"
```

Ajuste o dono dos diretórios `data` e `logs`.

```bash
sudo chown -R ${VAULT_UID}:${VAULT_GID} /home/jmsalles/vault/data
```

```bash
sudo chown -R ${VAULT_UID}:${VAULT_GID} /home/jmsalles/vault/logs
```

Ajuste permissões.

```bash
sudo chmod 750 /home/jmsalles/vault/data
```

```bash
sudo chmod 750 /home/jmsalles/vault/logs
```

O diretório de configuração pode ficar legível.

```bash
sudo chmod 755 /home/jmsalles/vault/config
```

Valide.

```bash
ls -lan /home/jmsalles/vault
```

```bash
ls -lan /home/jmsalles/vault/data
```

```bash
ls -lan /home/jmsalles/vault/logs
```

## 10. Criar arquivo de configuração `vault.hcl`

Crie o arquivo:

```bash
vim /home/jmsalles/vault/config/vault.hcl
```

Conteúdo corrigido e validado:

```hcl
ui = true

disable_mlock = false

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-docker-hml-01"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "127.0.0.1:8201"
  tls_disable     = true
}

api_addr     = "https://vault.jmsalles.homelab.br"
cluster_addr = "http://127.0.0.1:8201"

log_level = "info"
```

Ajuste permissão do arquivo.

```bash
sudo chmod 644 /home/jmsalles/vault/config/vault.hcl
```

Explicação dos principais campos:

| Campo                                    | Função                                                     |
| ---------------------------------------- | ---------------------------------------------------------- |
| `ui = true`                              | Habilita a interface web do Vault                          |
| `storage "raft"`                         | Usa storage integrado do Vault                             |
| `path = "/vault/data"`                   | Define onde os dados serão persistidos dentro do container |
| `address = "0.0.0.0:8200"`               | Porta principal de acesso ao Vault                         |
| `cluster_address = "127.0.0.1:8201"`     | Porta interna de cluster exigida pelo Raft                 |
| `cluster_addr = "http://127.0.0.1:8201"` | Endereço de cluster obrigatório quando usa Raft            |
| `tls_disable = true`                     | Desabilita TLS interno porque o TLS será feito no Nginx    |
| `api_addr`                               | Endereço público usado pelos clientes                      |

Observação importante:

```text
Quando usar storage raft, o cluster_addr é obrigatório.
Sem ele, o Vault pode retornar:
Cluster address must be set when using raft storage
```

## 11. Criar o `docker-compose.yml`

Crie o arquivo:

```bash
vim /home/jmsalles/vault/docker-compose.yml
```

Conteúdo:

```yaml
services:
  vault:
    image: hashicorp/vault:latest
    container_name: vault
    restart: unless-stopped
    entrypoint: ["vault"]
    cap_add:
      - IPC_LOCK
    ports:
      - "8200:8200"
    volumes:
      - /home/jmsalles/vault/config:/vault/config
      - /home/jmsalles/vault/data:/vault/data
      - /home/jmsalles/vault/logs:/vault/logs
    environment:
      VAULT_ADDR: "http://127.0.0.1:8200"
    command: ["server", "-config=/vault/config/vault.hcl"]
```

Observações:

```text
A porta 8200 será publicada no host.
A porta 8201 será usada internamente pelo Vault para o Raft.
Não é necessário publicar a porta 8201 no host.
```

Validar o Compose.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose config
```

Valide se aparece:

```text
entrypoint:
  - vault
```

E também:

```text
command:
  - server
  - -config=/vault/config/vault.hcl
```

## 12. Subir o Vault

Subir o container.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose up -d
```

Validar container.

```bash
docker ps | grep vault
```

Validar pelo Compose.

```bash
docker compose ps
```

Acompanhar logs.

```bash
docker compose logs -f vault
```

O Vault deve permanecer em execução, sem ficar reiniciando.

## 13. Validar porta local do Vault

Teste localmente no host:

```bash
curl -I http://127.0.0.1:8200/v1/sys/health
```

Antes da inicialização, é comum o Vault retornar status indicando que ainda não foi inicializado.

Valide também com saída JSON:

```bash
curl -s http://127.0.0.1:8200/v1/sys/health
```

Se tiver `jq` instalado:

```bash
curl -s http://127.0.0.1:8200/v1/sys/health | jq .
```

Validar porta escutando no host.

```bash
sudo ss -lntp | grep 8200
```

## 14. Configurar Nginx reverse proxy

Crie o arquivo de virtual host do Vault.

```bash
vim /home/jmsalles/nginx/conf.d/vault.jmsalles.homelab.br.conf
```

Conteúdo:

```nginx
server {
    listen 80;
    server_name vault.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name vault.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/vault.jmsalles.homelab.br.access.log;
    error_log  /var/log/nginx/vault.jmsalles.homelab.br.error.log;

    client_max_body_size 50m;

    location / {
        proxy_pass http://host.docker.internal:8200;

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

## 15. Testar acesso via HTTPS

Teste com `curl -k`.

```bash
curl -k -I https://vault.jmsalles.homelab.br/v1/sys/health
```

Antes de inicializar, o status pode não ser `200`.

Teste com JSON:

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health
```

Acesse pelo navegador:

```text
https://vault.jmsalles.homelab.br
```

## 16. Inicializar o Vault

A inicialização cria as unseal keys e o root token inicial.

Entre no container:

```bash
docker exec -it vault sh
```

Configure o endereço local dentro do container:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

Valide status.

```bash
vault status
```

Inicialize o Vault com 5 chaves e quorum de 3.

```bash
vault operator init -key-shares=5 -key-threshold=3
```

Resultado esperado:

```text
Unseal Key 1: ...
Unseal Key 2: ...
Unseal Key 3: ...
Unseal Key 4: ...
Unseal Key 5: ...
Initial Root Token: ...
```

Atenção:

```text
Guarde as 5 unseal keys em local seguro.
Guarde o Initial Root Token em local seguro.
Não salve essas informações em Git, documentação pública, chamado, print ou arquivo no servidor.
```

## 17. Fazer unseal do Vault

Ainda dentro do container, execute o unseal com 3 chaves diferentes.

```bash
vault operator unseal
```

Cole a primeira unseal key.

Execute novamente:

```bash
vault operator unseal
```

Cole a segunda unseal key.

Execute novamente:

```bash
vault operator unseal
```

Cole a terceira unseal key.

Valide status.

```bash
vault status
```

Resultado esperado:

```text
Initialized     true
Sealed          false
Storage Type    raft
```

Saia do container:

```bash
exit
```

## 18. Validar Vault unsealed via HTTPS

No host, execute:

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health
```

Se tiver `jq`:

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health | jq .
```

Resultado esperado após inicializado e unsealed:

```json
{
  "initialized": true,
  "sealed": false,
  "standby": false
}
```

Teste o cabeçalho HTTP:

```bash
curl -k -I https://vault.jmsalles.homelab.br/v1/sys/health
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

## 19. Fazer login no Vault

Entre no container:

```bash
docker exec -it vault sh
```

Configure o endereço local:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

Faça login com o Initial Root Token:

```bash
vault login
```

Cole o root token inicial.

Valide:

```bash
vault token lookup
```

## 20. Habilitar KV v2 em `secret/`

Verifique os secrets engines atuais.

```bash
vault secrets list
```

Se `secret/` ainda não existir, habilite o KV v2:

```bash
vault secrets enable -path=secret kv-v2
```

Se já existir, valide se é `kv-v2`:

```bash
vault secrets list -detailed
```

## 21. Criar estrutura inicial de secrets

Criaremos a estrutura planejada do seu projeto:

```text
secret/nexus/svc-gitea-runner
secret/nexus/svc-k8s-pull
secret/docker/svc-docker-deploy
secret/gitea/act-runner
secret/kubernetes/hml
```

## 21.1 Secret do `svc-gitea-runner`

Use este secret para guardar a credencial usada pelo Gitea act_runner para fazer push no Nexus.

```bash
vault kv put secret/nexus/svc-gitea-runner \
  username="svc-gitea-runner" \
  password="<SENHA_DO_SVC_GITEA_RUNNER>" \
  registry="registry.jmsalles.homelab.br"
```

Validar:

```bash
vault kv get secret/nexus/svc-gitea-runner
```

## 21.2 Secret do `svc-k8s-pull`

Use este secret para guardar a credencial usada pelo Kubernetes para pull de imagens privadas.

```bash
vault kv put secret/nexus/svc-k8s-pull \
  username="svc-k8s-pull" \
  password="<SENHA_DO_SVC_K8S_PULL>" \
  registry="registry.jmsalles.homelab.br"
```

Validar:

```bash
vault kv get secret/nexus/svc-k8s-pull
```

## 21.3 Secret do `svc-docker-deploy`

Use este secret para guardar informações do usuário que fará deploy em Docker HML.

```bash
vault kv put secret/docker/svc-docker-deploy \
  username="svc-docker-deploy" \
  host="docker-hml.jmsalles.homelab.br" \
  ip="192.168.31.37" \
  auth_type="ssh-key-and-password"
```

Validar:

```bash
vault kv get secret/docker/svc-docker-deploy
```

Se quiser guardar a senha também, execute:

```bash
vault kv patch secret/docker/svc-docker-deploy \
  password="<SENHA_DO_SVC_DOCKER_DEPLOY>"
```

Observação:

```text
A chave privada SSH pode ser armazenada futuramente em um secret separado, mas evite colar chave privada em terminal compartilhado ou gravar em histórico sem controle.
```

## 21.4 Secret do Gitea act_runner

Use este secret para guardar o token do runner quando ele for criado.

```bash
vault kv put secret/gitea/act-runner \
  runner_name="docker-hml-runner" \
  gitea_url="https://git.jmsalles.homelab.br" \
  token="<TOKEN_DO_ACT_RUNNER>"
```

Validar:

```bash
vault kv get secret/gitea/act-runner
```

## 21.5 Secret do Kubernetes HML

Use este secret para guardar informações futuras de integração com Kubernetes HML.

```bash
vault kv put secret/kubernetes/hml \
  cluster_name="k8s-hml" \
  registry="registry.jmsalles.homelab.br" \
  image_pull_user="svc-k8s-pull"
```

Validar:

```bash
vault kv get secret/kubernetes/hml
```

## 22. Criar política para leitura da esteira Docker

Agora criaremos uma política para permitir que uma automação leia apenas os secrets necessários para pipeline Docker HML.

Crie o arquivo de policy dentro do container.

```bash
cat > /tmp/policy-docker-hml.hcl <<'EOF'
path "secret/data/nexus/svc-gitea-runner" {
  capabilities = ["read"]
}

path "secret/data/docker/svc-docker-deploy" {
  capabilities = ["read"]
}

path "secret/data/gitea/act-runner" {
  capabilities = ["read"]
}
EOF
```

Aplicar a policy.

```bash
vault policy write policy-docker-hml /tmp/policy-docker-hml.hcl
```

Validar.

```bash
vault policy read policy-docker-hml
```

## 23. Criar política para leitura do Kubernetes HML

Crie a policy:

```bash
cat > /tmp/policy-k8s-hml.hcl <<'EOF'
path "secret/data/nexus/svc-k8s-pull" {
  capabilities = ["read"]
}

path "secret/data/kubernetes/hml" {
  capabilities = ["read"]
}
EOF
```

Aplicar:

```bash
vault policy write policy-k8s-hml /tmp/policy-k8s-hml.hcl
```

Validar:

```bash
vault policy read policy-k8s-hml
```

## 24. Habilitar AppRole para automações futuras

O AppRole será usado futuramente para autenticar pipelines e automações no Vault.

Habilite:

```bash
vault auth enable approle
```

Crie uma role para a esteira Docker HML:

```bash
vault write auth/approle/role/approle-docker-hml \
  token_policies="policy-docker-hml" \
  token_ttl="1h" \
  token_max_ttl="4h"
```

Obtenha o `role_id`:

```bash
vault read auth/approle/role/approle-docker-hml/role-id
```

Gere um `secret_id`:

```bash
vault write -f auth/approle/role/approle-docker-hml/secret-id
```

Atenção:

```text
Guarde role_id e secret_id em local seguro.
Eles serão usados futuramente pela esteira para autenticar no Vault.
```

Crie uma role para o Kubernetes HML:

```bash
vault write auth/approle/role/approle-k8s-hml \
  token_policies="policy-k8s-hml" \
  token_ttl="1h" \
  token_max_ttl="4h"
```

Obtenha o `role_id`:

```bash
vault read auth/approle/role/approle-k8s-hml/role-id
```

Gere o `secret_id`:

```bash
vault write -f auth/approle/role/approle-k8s-hml/secret-id
```

## 25. Testar leitura com AppRole

Exemplo para a role `approle-docker-hml`.

Faça login usando `role_id` e `secret_id`.

```bash
vault write auth/approle/login \
  role_id="<ROLE_ID_DOCKER_HML>" \
  secret_id="<SECRET_ID_DOCKER_HML>"
```

O retorno terá um client token.

Exporte temporariamente o token:

```bash
export VAULT_TOKEN="<TOKEN_RETORNADO>"
```

Teste leitura permitida:

```bash
vault kv get secret/nexus/svc-gitea-runner
```

```bash
vault kv get secret/docker/svc-docker-deploy
```

Teste uma leitura que deve ser negada:

```bash
vault kv get secret/nexus/svc-k8s-pull
```

Resultado esperado:

```text
permission denied
```

Depois volte para o root token apenas se necessário:

```bash
vault login
```

## 26. Testar reinício do container

Saia do container se ainda estiver dentro dele.

```bash
exit
```

Reinicie o Vault.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose restart vault
```

Valide status.

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health
```

Após restart, é provável que o Vault esteja sealed.

Entre no container:

```bash
docker exec -it vault sh
```

Configure o endereço:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

Valide:

```bash
vault status
```

Se estiver sealed, execute unseal com 3 chaves:

```bash
vault operator unseal
```

```bash
vault operator unseal
```

```bash
vault operator unseal
```

Valide:

```bash
vault status
```

Saia:

```bash
exit
```

## 27. Validações finais

Validar container.

```bash
docker ps | grep vault
```

Validar Compose.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose ps
```

Validar logs.

```bash
docker compose logs --tail=100 vault
```

Validar porta local.

```bash
curl -I http://127.0.0.1:8200/v1/sys/health
```

Validar HTTPS pelo Nginx.

```bash
curl -k -I https://vault.jmsalles.homelab.br/v1/sys/health
```

Validar UI.

```text
https://vault.jmsalles.homelab.br
```

## 28. Como acessar a UI do Vault

Acesse:

```text
https://vault.jmsalles.homelab.br
```

Selecione método de login:

```text
Token
```

Informe o token administrativo ou um token apropriado.

Observação:

```text
Evite usar o root token no dia a dia.
O root token deve ser reservado para administração inicial e contingência.
```

## 29. Estrutura final de secrets

A estrutura inicial ficará assim:

```text
secret/
|
|-- nexus/
|   |-- svc-gitea-runner
|   |-- svc-k8s-pull
|
|-- docker/
|   |-- svc-docker-deploy
|
|-- gitea/
|   |-- act-runner
|
|-- kubernetes/
    |-- hml
```

## 30. Próximas etapas recomendadas

Depois do Vault instalado, a ordem recomendada do projeto fica:

```text
1. Criar monitoramento do Vault no Zabbix
2. Instalar Gitea act_runner
3. Registrar o runner no Gitea
4. Criar primeira pipeline Docker HML
5. Pipeline fazer docker build
6. Pipeline fazer docker push para registry.jmsalles.homelab.br
7. Pipeline fazer deploy via svc-docker-deploy no docker-hml
8. Depois evoluir para deploy no Kubernetes HML via Argo CD
```

## 31. Troubleshooting

### 31.1 Erro de permissão no Raft

Erro:

```text
failed to open bolt file: open /vault/data/vault.db: permission denied
```

Causa:

```text
O diretório /home/jmsalles/vault/data não está gravável para o usuário interno do container Vault.
```

Correção:

```bash
cd /home/jmsalles/vault
```

```bash
docker compose down
```

```bash
VAULT_UID=$(docker run --rm --entrypoint sh hashicorp/vault:latest -c 'id -u')
```

```bash
VAULT_GID=$(docker run --rm --entrypoint sh hashicorp/vault:latest -c 'id -g')
```

```bash
sudo chown -R ${VAULT_UID}:${VAULT_GID} /home/jmsalles/vault/data
```

```bash
sudo chown -R ${VAULT_UID}:${VAULT_GID} /home/jmsalles/vault/logs
```

```bash
sudo chmod 750 /home/jmsalles/vault/data
```

```bash
sudo chmod 750 /home/jmsalles/vault/logs
```

```bash
docker compose up -d
```

### 31.2 Erro `Cluster address must be set when using raft storage`

Erro:

```text
Cluster address must be set when using raft storage
```

Causa:

```text
O storage raft exige cluster_addr configurado.
```

Correção no `vault.hcl`:

```hcl
listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "127.0.0.1:8201"
  tls_disable     = true
}

cluster_addr = "http://127.0.0.1:8201"
```

Depois:

```bash
cd /home/jmsalles/vault
```

```bash
docker compose down
```

```bash
docker compose up -d
```

### 31.3 Erro `address already in use` na porta 8200

Erro:

```text
listen tcp4 0.0.0.0:8200: bind: address already in use
```

Valide host:

```bash
sudo ss -lntp | grep 8200
```

Valide containers:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep 8200
```

Valide containers antigos:

```bash
docker ps -a | grep -i vault
```

Remova container antigo, se necessário:

```bash
docker rm -f vault
```

Valide se o `vault.hcl` tem apenas um listener:

```bash
grep -n "listener" /home/jmsalles/vault/config/vault.hcl
```

Valide se `address` e `cluster_address` não estão usando a mesma porta:

```bash
grep -n "8200\|8201" /home/jmsalles/vault/config/vault.hcl
```

Esperado:

```text
address = 8200
cluster_address = 8201
cluster_addr = 8201
```

### 31.4 Vault retorna sealed

Sintoma:

```text
sealed: true
```

Valide:

```bash
docker exec -it vault sh
```

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

```bash
vault status
```

Faça unseal com 3 chaves:

```bash
vault operator unseal
```

```bash
vault operator unseal
```

```bash
vault operator unseal
```

### 31.5 Vault retorna `connection refused`

Valide se o container está rodando.

```bash
docker ps | grep vault
```

Valide logs.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose logs --tail=100 vault
```

Valide porta.

```bash
ss -lntp | grep 8200
```

### 31.6 Nginx retorna 502 para o Vault

Teste localmente no host.

```bash
curl -I http://127.0.0.1:8200/v1/sys/health
```

Valide Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Valide logs.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

Valide se o container Nginx resolve `host.docker.internal`.

```bash
docker exec -it nginx-reverse-proxy-hml sh
```

Dentro do container:

```bash
getent hosts host.docker.internal
```

Saia:

```bash
exit
```

### 31.7 Erro de certificado no curl

Erro:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Use `-k` enquanto a CA não estiver instalada:

```bash
curl -k -I https://vault.jmsalles.homelab.br/v1/sys/health
```

### 31.8 Erro `permission denied` ao ler secret

Valide a policy.

```bash
vault policy read policy-docker-hml
```

Valide o token atual.

```bash
vault token lookup
```

Valide se o path está correto para KV v2.

```text
secret/data/<caminho>
```

Exemplo de policy correta para KV v2:

```hcl
path "secret/data/nexus/svc-gitea-runner" {
  capabilities = ["read"]
}
```

### 31.9 Comando `vault` não encontrado dentro do container

Valide se está no container correto.

```bash
docker exec -it vault sh
```

Teste:

```bash
vault version
```

Se não funcionar, valide a imagem.

```bash
docker inspect vault --format '{{.Config.Image}}'
```

## 32. Checklist final

| Item                                                                | Status   |
| ------------------------------------------------------------------- | -------- |
| DNS `vault.jmsalles.homelab.br` criado                              | Pendente |
| Diretório `/home/jmsalles/vault` criado                             | Pendente |
| Permissões de `data` e `logs` ajustadas para o UID/GID do container | Pendente |
| Arquivo `vault.hcl` criado com `cluster_addr`                       | Pendente |
| `docker-compose.yml` criado com `entrypoint: ["vault"]`             | Pendente |
| Container `vault` iniciado                                          | Pendente |
| Porta local `8200` validada                                         | Pendente |
| Nginx reverse proxy configurado                                     | Pendente |
| HTTPS `vault.jmsalles.homelab.br` validado                          | Pendente |
| Vault inicializado                                                  | Pendente |
| Unseal realizado com 3 chaves                                       | Pendente |
| Root token guardado em local seguro                                 | Pendente |
| KV v2 habilitado em `secret/`                                       | Pendente |
| Secrets iniciais criados                                            | Pendente |
| Policies criadas                                                    | Pendente |
| AppRole habilitado                                                  | Pendente |
| AppRoles criadas                                                    | Pendente |
| Teste de leitura com AppRole realizado                              | Pendente |
| Restart e unseal testados                                           | Pendente |

## 33. Resumo final

Com esta instalação, o homelab passa a ter um cofre central de segredos.

URL:

```text
https://vault.jmsalles.homelab.br
```

Container:

```text
vault
```

Diretório crítico:

```text
/home/jmsalles/vault/data
```

Secrets iniciais:

```text
secret/nexus/svc-gitea-runner
secret/nexus/svc-k8s-pull
secret/docker/svc-docker-deploy
secret/gitea/act-runner
secret/kubernetes/hml
```

Fluxo futuro:

```text
Gitea
|
act_runner
|
Vault
|
Nexus Registry
|
Docker HML
|
Kubernetes HML
```

Próxima etapa recomendada:

```text
Criar monitoramento do Vault no Zabbix
```

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
