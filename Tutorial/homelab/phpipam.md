# Tutorial completo — Instalação, configuração de rede e autenticação Active Directory no phpIPAM

## 1. Objetivo

Implantar o phpIPAM em containers Docker para gerenciamento dos endereços IP, sub-redes, dispositivos, servidores e serviços do homelab, incluindo:

* interface Web do phpIPAM;
* banco de dados MariaDB;
* container de tarefas periódicas e descoberta de hosts;
* persistência dos dados;
* resolução pelo DNS interno;
* cadastramento da rede `192.168.31.0/24`;
* configuração do gateway e DNS;
* integração com o Active Directory;
* autenticação com usuários do domínio;
* associação com o grupo `GRP_HOMELAB_ADMINS`;
* publicação opcional pelo Nginx;
* procedimentos de validação e solução de problemas.

O backup será tratado posteriormente e não faz parte deste procedimento.

---

# 2. Informações do ambiente

## 2.1 Servidor Docker

```text
Hostname:
docker-hml-lenovo-i5

Endereço IP:
192.168.31.37

Diretório da aplicação:
/home/jmsalles/phpipam

Porta publicada:
8088/TCP
```

## 2.2 Rede do homelab

```text
Rede:
192.168.31.0/24

Máscara:
255.255.255.0

Gateway:
192.168.31.2

DNS:
192.168.31.24

Primeiro endereço utilizável:
192.168.31.1

Último endereço utilizável:
192.168.31.254

Broadcast:
192.168.31.255
```

## 2.3 Active Directory

```text
Domínio:
jmsalles.homelab.br

Controlador de domínio:
winserver.jmsalles.homelab.br

IP do controlador:
192.168.31.24

Servidor DNS:
192.168.31.24

Porta LDAP:
389/TCP

Base DN:
OU=Homelab,DC=jmsalles,DC=homelab,DC=br

Sufixo das contas:
@jmsalles.homelab.br
```

## 2.4 Conta LDAP de serviço

```text
sAMAccountName:
svc-ldap-bind

Distinguished Name:
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

No phpIPAM será utilizado somente o nome curto:

```text
svc-ldap-bind
```

O phpIPAM acrescentará o sufixo:

```text
@jmsalles.homelab.br
```

Resultando no bind:

```text
svc-ldap-bind@jmsalles.homelab.br
```

## 2.5 Grupo administrativo do Active Directory

```text
Nome:
GRP_HOMELAB_ADMINS

Distinguished Name:
CN=GRP_HOMELAB_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

---

# 3. Arquitetura da solução

```text
                                 Usuário
                                    |
                                    | HTTP 8088
                                    | ou HTTPS pelo Nginx
                                    |
                           ┌────────▼────────┐
                           │  phpipam-web    │
                           │ Apache + PHP    │
                           │ Interface Web   │
                           └────────┬────────┘
                                    |
                                    | TCP/3306
                                    |
                           ┌────────▼────────┐
                           │   phpipam-db    │
                           │    MariaDB      │
                           └─────────────────┘

                           ┌─────────────────┐
                           │ phpipam-cron    │
                           │ Ping, DNS, Scan │
                           │ Descoberta IP   │
                           └────────┬────────┘
                                    |
                  ┌─────────────────┴────────────────┐
                  │                                  │
       ┌──────────▼──────────┐            ┌──────────▼──────────┐
       │ Rede 192.168.31.0/24│            │ Active Directory    │
       │ Gateway .2          │            │ winserver            │
       │ DNS .24             │            │ 192.168.31.24:389    │
       └─────────────────────┘            └─────────────────────┘
```

As imagens oficiais separam o frontend Web no container `phpipam-www` e as tarefas agendadas no container `phpipam-cron`. O projeto recomenda apenas uma instância do container cron e requer `NET_ADMIN` e `NET_RAW` para funcionalidades de ping e SNMP. 

---

# 4. Pré-requisitos

Validar se o Docker está instalado:

```bash
docker --version
```

Validar o Docker Compose:

```bash
docker compose version
```

Validar o serviço:

```bash
systemctl status docker
```

Caso esteja parado:

```bash
sudo systemctl enable --now docker
```

Validar as informações do Docker:

```bash
docker info
```

Validar espaço em disco:

```bash
df -h
```

Validar memória:

```bash
free -h
```

Validar o hostname:

```bash
hostname
hostname -f
```

Validar o endereço IP do host:

```bash
hostname -I
```

Resultado esperado contendo:

```text
192.168.31.37
```

---

# 5. Criar a estrutura de diretórios

Criar a estrutura principal:

```bash
sudo mkdir -p /home/jmsalles/phpipam/{database,logo,ca}
```

Ajustar o proprietário:

```bash
sudo chown -R jmsalles:jmsalles /home/jmsalles/phpipam
```

Acessar o diretório:

```bash
cd /home/jmsalles/phpipam
```

Validar:

```bash
find /home/jmsalles/phpipam -maxdepth 2 -type d
```

Resultado esperado:

```text
/home/jmsalles/phpipam
/home/jmsalles/phpipam/database
/home/jmsalles/phpipam/logo
/home/jmsalles/phpipam/ca
```

Estrutura final:

```text
/home/jmsalles/phpipam/
├── .env
├── .gitignore
├── docker-compose.yml
├── ca/
├── database/
└── logo/
```

---

# 6. Criar o arquivo `.env`

O arquivo `.env` armazenará as senhas do banco e as variáveis utilizadas pelo Docker Compose.

Acessar o diretório:

```bash
cd /home/jmsalles/phpipam
```

Gerar senhas aleatórias:

```bash
MARIADB_ROOT_PASSWORD=$(openssl rand -hex 32)
PHPIPAM_DB_PASSWORD=$(openssl rand -hex 32)
```

Criar o arquivo:

```bash
cat > .env <<EOF
TZ=America/Sao_Paulo

PHPIPAM_PORT=8088

PHPIPAM_DB_NAME=phpipam
PHPIPAM_DB_USER=phpipam
PHPIPAM_DB_PASSWORD=${PHPIPAM_DB_PASSWORD}

MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
EOF
```

Remover as variáveis temporárias do shell:

```bash
unset MARIADB_ROOT_PASSWORD
unset PHPIPAM_DB_PASSWORD
```

Proteger o arquivo:

```bash
chmod 600 .env
```

Validar as permissões:

```bash
ls -l .env
```

Resultado esperado:

```text
-rw------- 1 jmsalles jmsalles ... .env
```

Validar as variáveis sem exibir as senhas:

```bash
grep -v PASSWORD .env
```

Resultado esperado:

```text
TZ=America/Sao_Paulo

PHPIPAM_PORT=8088

PHPIPAM_DB_NAME=phpipam
PHPIPAM_DB_USER=phpipam
```

Não inserir o arquivo `.env` em repositórios Git.

---

# 7. Criar o `.gitignore`

```bash
cat > .gitignore <<'EOF'
.env
database/
ca/*.key
EOF
```

Validar:

```bash
cat .gitignore
```

---

# 8. Criar o `docker-compose.yml`

Editar:

```bash
vim docker-compose.yml
```

Adicionar:

```yaml
name: phpipam

services:
  phpipam-db:
    image: mariadb:11.4
    container_name: phpipam-db
    hostname: phpipam-db
    restart: unless-stopped

    environment:
      TZ: ${TZ}
      MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
      MARIADB_DATABASE: ${PHPIPAM_DB_NAME}
      MARIADB_USER: ${PHPIPAM_DB_USER}
      MARIADB_PASSWORD: ${PHPIPAM_DB_PASSWORD}

    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci

    volumes:
      - ./database:/var/lib/mysql:Z

    networks:
      - phpipam-net

    healthcheck:
      test:
        - CMD
        - healthcheck.sh
        - --connect
        - --innodb_initialized
      start_period: 20s
      interval: 10s
      timeout: 5s
      retries: 10

  phpipam-web:
    image: phpipam/phpipam-www:1.8x
    container_name: phpipam-web
    hostname: phpipam-web
    restart: unless-stopped

    environment:
      TZ: ${TZ}

      IPAM_DATABASE_HOST: phpipam-db
      IPAM_DATABASE_PORT: 3306
      IPAM_DATABASE_NAME: ${PHPIPAM_DB_NAME}
      IPAM_DATABASE_USER: ${PHPIPAM_DB_USER}
      IPAM_DATABASE_PASS: ${PHPIPAM_DB_PASSWORD}
      IPAM_DATABASE_WEBHOST: "%"

      IPAM_BASE: /
      IPAM_DISABLE_INSTALLER: "1"
      IPAM_TRUST_X_FORWARDED: "false"
      IPAM_DEBUG: "false"
      OFFLINE_MODE: "false"
      COOKIE_SAMESITE: Lax

      IPAM_FOOTER_MESSAGE: "phpIPAM - Homelab Jeferson Salles"

    ports:
      - "${PHPIPAM_PORT}:80"

    dns:
      - 192.168.31.24

    dns_search:
      - jmsalles.homelab.br

    volumes:
      - ./logo:/phpipam/css/images/logo:Z
      - ./ca:/usr/local/share/ca-certificates:ro,Z

    cap_add:
      - NET_ADMIN
      - NET_RAW

    depends_on:
      phpipam-db:
        condition: service_healthy

    networks:
      - phpipam-net

  phpipam-cron:
    image: phpipam/phpipam-cron:1.8x
    container_name: phpipam-cron
    hostname: phpipam-cron
    restart: unless-stopped

    environment:
      TZ: ${TZ}

      IPAM_DATABASE_HOST: phpipam-db
      IPAM_DATABASE_PORT: 3306
      IPAM_DATABASE_NAME: ${PHPIPAM_DB_NAME}
      IPAM_DATABASE_USER: ${PHPIPAM_DB_USER}
      IPAM_DATABASE_PASS: ${PHPIPAM_DB_PASSWORD}

      SCAN_INTERVAL: 1h
      IPAM_DEBUG: "false"

    dns:
      - 192.168.31.24

    dns_search:
      - jmsalles.homelab.br

    volumes:
      - ./ca:/usr/local/share/ca-certificates:ro,Z

    cap_add:
      - NET_ADMIN
      - NET_RAW

    depends_on:
      phpipam-db:
        condition: service_healthy

    networks:
      - phpipam-net

networks:
  phpipam-net:
    name: phpipam-net
    driver: bridge
```

A tag `1.8x` acompanha a linha de manutenção 1.8. A documentação oficial também confirma variáveis como `IPAM_DATABASE_HOST`, `IPAM_DATABASE_USER`, `IPAM_DATABASE_PASS`, `IPAM_TRUST_X_FORWARDED` e `SCAN_INTERVAL`. 

---

# 9. Validar o Docker Compose

Validar a sintaxe:

```bash
docker compose config
```

O comando não deve retornar erros.

Listar os serviços:

```bash
docker compose config --services
```

Resultado esperado:

```text
phpipam-db
phpipam-web
phpipam-cron
```

Validar as imagens configuradas:

```bash
docker compose config --images
```

Resultado esperado:

```text
mariadb:11.4
phpipam/phpipam-www:1.8x
phpipam/phpipam-cron:1.8x
```

---

# 10. Baixar as imagens

```bash
docker compose pull
```

Validar:

```bash
docker images | egrep -i 'phpipam|mariadb'
```

---

# 11. Iniciar o banco de dados

Subir inicialmente somente o MariaDB:

```bash
docker compose up -d phpipam-db
```

Acompanhar:

```bash
docker compose ps
```

Aguardar até aparecer:

```text
phpipam-db    Up ... (healthy)
```

Validar diretamente:

```bash
docker inspect \
    --format '{{.State.Health.Status}}' \
    phpipam-db
```

Resultado esperado:

```text
healthy
```

Consultar logs:

```bash
docker compose logs --tail 100 phpipam-db
```

---

# 12. Iniciar temporariamente o container Web

```bash
docker compose up -d phpipam-web
```

Validar:

```bash
docker compose ps
```

É possível que o Web apresente mensagens relacionadas à ausência das tabelas até que o schema seja importado.

---

# 13. Importar o banco inicial do phpIPAM

O arquivo oficial `SCHEMA.sql` está dentro da imagem do phpIPAM.

Executar:

```bash
docker compose exec -T phpipam-web \
    cat /phpipam/db/SCHEMA.sql \
    | docker compose exec -T phpipam-db \
        sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
```

O comando pode não exibir saída quando executado com sucesso.

Validar as tabelas:

```bash
docker compose exec phpipam-db sh -c \
    'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SHOW TABLES;"'
```

Contar as tabelas:

```bash
docker compose exec phpipam-db sh -c \
    'mariadb -N -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SHOW TABLES;"' \
    | wc -l
```

Validar configurações:

```bash
docker compose exec phpipam-db sh -c \
    'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT id,siteTitle,version FROM settings;"'
```

O procedimento oficial de instalação manual utiliza o `SCHEMA.sql` e informa as credenciais iniciais `Admin/ipamadmin`. 

---

# 14. Iniciar todos os containers

```bash
docker compose up -d
```

Validar:

```bash
docker compose ps
```

Resultado esperado semelhante a:

```text
NAME            STATUS
phpipam-db      Up ... (healthy)
phpipam-web     Up ...
phpipam-cron    Up ...
```

---

# 15. Validar os logs

## 15.1 MariaDB

```bash
docker compose logs --tail 100 phpipam-db
```

## 15.2 Interface Web

```bash
docker compose logs --tail 100 phpipam-web
```

## 15.3 Container cron

```bash
docker compose logs --tail 100 phpipam-cron
```

## 15.4 Todos os containers

```bash
docker compose logs --tail 100
```

Acompanhar em tempo real:

```bash
docker compose logs -f
```

Encerrar a visualização:

```text
Ctrl+C
```

---

# 16. Validar a porta publicada

No host Docker:

```bash
ss -lntp | grep 8088
```

Testar localmente:

```bash
curl -I http://127.0.0.1:8088
```

Testar pelo IP:

```bash
curl -I http://192.168.31.37:8088
```

---

# 17. Configurar o FirewallD

Caso o servidor utilize FirewallD:

```bash
sudo firewall-cmd \
    --permanent \
    --add-port=8088/tcp
```

Recarregar:

```bash
sudo firewall-cmd --reload
```

Validar:

```bash
sudo firewall-cmd --list-ports
```

Resultado esperado contendo:

```text
8088/tcp
```

---

# 18. Primeiro acesso

Acessar pelo navegador:

```text
http://192.168.31.37:8088
```

Credenciais iniciais:

```text
Usuário:
Admin

Senha:
ipamadmin
```

O usuário possui `A` maiúsculo.

Após entrar, o phpIPAM solicitará a alteração da senha.

---

# 19. Erro `Invalid CSRF cookie` durante a troca de senha

Caso apareça:

```text
Invalid CSRF cookie
```

Fechar todas as abas do phpIPAM.

Abrir uma janela anônima:

```text
Ctrl + Shift + N
```

Acessar novamente:

```text
http://192.168.31.37:8088
```

Entrar com:

```text
Admin
ipamadmin
```

Realizar novamente a troca.

Caso continue:

1. Pressionar `F12`.
2. Acessar **Application**.
3. Selecionar **Storage**.
4. Clicar em **Clear site data**.
5. Fechar a aba.
6. Abrir novamente o phpIPAM.

Também pode reiniciar somente o frontend:

```bash
cd /home/jmsalles/phpipam

docker compose restart phpipam-web
```

Esse comando não remove o banco de dados.

---

# 20. Redefinir a senha administrativa pelo terminal

Caso não seja possível trocar pela interface:

```bash
cd /home/jmsalles/phpipam
```

Executar:

```bash
docker compose exec phpipam-web \
    php /phpipam/functions/scripts/reset-admin-password.php
```

Informar a nova senha quando solicitado.

Reiniciar o frontend:

```bash
docker compose restart phpipam-web
```

Limpar os cookies do navegador e entrar novamente.

---

# 21. Configurações gerais do phpIPAM

Após o login:

```text
Administration
└── phpIPAM settings
```

Configurar:

```text
Site title:
Jeferson Salles Homelab IPAM

Site domain:
ipam.jmsalles.homelab.br

Site administrator:
Jeferson Salles

Default language:
Brazil

Enable VLAN:
Yes

Enable VRF:
Yes

Enable devices:
Yes

Enable locations:
Yes

Enable racks:
Yes
```

Outras opções recomendadas:

```text
Show hostname:
Yes

Resolve DNS names:
Yes

Visual subnet display:
Yes

Enable changelog:
Yes

Enable log:
Yes
```

Os nomes podem variar conforme a tradução e a versão da interface.

---

# 22. Criar a localização do homelab

Acessar:

```text
Administration
└── Locations
```

Adicionar:

```text
Name:
Homelab

Description:
Infraestrutura física e virtual do homelab de Jeferson Salles
```

Salvar.

---

# 23. Criar os tipos de dispositivos

Acessar:

```text
Administration
└── Device types
```

Criar:

```text
Roteador / Gateway
Servidor físico
Servidor virtual
Mini PC
Switch
Access Point
Storage / NAS
Firewall
Desktop
Notebook
Dispositivo IoT
Impressora
```

Para iniciar, os principais são:

```text
Roteador / Gateway
Servidor físico
Servidor virtual
Mini PC
```

---

# 24. Configurar o servidor DNS no phpIPAM

Acessar:

```text
Administration
└── Nameservers
```

Adicionar:

```text
Name:
DNS Homelab

Nameserver 1:
192.168.31.24

Description:
Servidor DNS e controlador de domínio do homelab
```

Salvar.

---

# 25. Criar a seção principal

Acessar:

```text
Administration
└── Sections
```

Adicionar:

```text
Name:
Homelab Jeferson Salles

Description:
Gerenciamento centralizado dos endereços IP, servidores,
equipamentos, containers, clusters e serviços do homelab.

Strict mode:
Yes

Subnet ordering:
Subnet, ascending
```

O modo estrito ajuda a evitar sub-redes sobrepostas dentro da seção.

Salvar.

---

# 26. Criar a sub-rede principal

Na seção:

```text
Homelab Jeferson Salles
```

Selecionar:

```text
Add subnet
```

Preencher:

```text
Subnet:
192.168.31.0

Mask:
24

Description:
Rede LAN principal do homelab

Section:
Homelab Jeferson Salles

VLAN:
None

VRF:
None

Master subnet:
None

Nameserver:
DNS Homelab

Scan agent:
localhost

Location:
Homelab

Is folder:
No

Is full:
No

Allow requests:
No
```

Na primeira configuração, utilizar:

```text
Check hosts status:
Yes

Discover new hosts:
No

Resolve DNS names:
Yes

Show DNS:
Yes
```

A descoberta automática será habilitada depois da primeira varredura manual.

Salvar.

---

# 27. Cadastrar o gateway

Abrir:

```text
Homelab Jeferson Salles
└── 192.168.31.0/24
```

Adicionar endereço:

```text
IP address:
192.168.31.2

Hostname:
gateway-homelab

Description:
Gateway padrão da rede principal do homelab

Tag:
Used

Is gateway:
Yes

Location:
Homelab

Owner:
Jeferson Salles
```

Observação:

```text
Gateway padrão da sub-rede 192.168.31.0/24.
```

Salvar.

---

# 28. Cadastrar o DNS e controlador de domínio

Adicionar:

```text
IP address:
192.168.31.24

Hostname:
winserver.jmsalles.homelab.br

Description:
Servidor DNS e controlador de domínio do homelab

Tag:
Used

Is gateway:
No

Location:
Homelab
```

Observação:

```text
Serviços:
- Active Directory Domain Services
- DNS
- LDAP
- Domínio jmsalles.homelab.br
```

Salvar.

---

# 29. Cadastrar o servidor Docker do phpIPAM

Adicionar:

```text
IP address:
192.168.31.37

Hostname:
docker-hml-lenovo-i5

Description:
Servidor Docker responsável pela execução do phpIPAM

Tag:
Used

Is gateway:
No

Location:
Homelab
```

Observação:

```text
Aplicação:
phpIPAM

Porta:
8088/TCP

Execução:
Docker Compose

Diretório:
/home/jmsalles/phpipam
```

Salvar.

---

# 30. Cadastrar os dispositivos

## 30.1 Gateway

Acessar:

```text
Administration
└── Devices
```

Adicionar:

```text
Hostname:
gateway-homelab

IP address:
192.168.31.2

Type:
Roteador / Gateway

Location:
Homelab

Description:
Gateway da rede 192.168.31.0/24
```

## 30.2 Controlador de domínio

Adicionar:

```text
Hostname:
winserver.jmsalles.homelab.br

IP address:
192.168.31.24

Type:
Servidor físico
```

Ou:

```text
Servidor virtual
```

caso o Windows Server esteja em VM.

Descrição:

```text
Controlador de domínio e servidor DNS do homelab
```

## 30.3 Servidor Docker

Adicionar:

```text
Hostname:
docker-hml-lenovo-i5

IP address:
192.168.31.37

Type:
Servidor físico

Location:
Homelab

Description:
Servidor Docker que hospeda o phpIPAM
```

Depois, editar cada endereço IP e associá-lo ao respectivo dispositivo.

---

# 31. Validar o DNS nos containers

Validar o arquivo de resolução do container Web:

```bash
cd /home/jmsalles/phpipam

docker compose exec phpipam-web \
    cat /etc/resolv.conf
```

Validar o container cron:

```bash
docker compose exec phpipam-cron \
    cat /etc/resolv.conf
```

Testar a resolução do controlador:

```bash
docker compose exec phpipam-web \
    getent hosts winserver.jmsalles.homelab.br
```

Resultado esperado:

```text
192.168.31.24 winserver.jmsalles.homelab.br
```

Testar no cron:

```bash
docker compose exec phpipam-cron \
    getent hosts winserver.jmsalles.homelab.br
```

---

# 32. Validar conectividade com a rede

Testar o gateway:

```bash
docker compose exec phpipam-cron \
    ping -c 3 192.168.31.2
```

Testar o DNS:

```bash
docker compose exec phpipam-cron \
    ping -c 3 192.168.31.24
```

Testar o host Docker:

```bash
docker compose exec phpipam-cron \
    ping -c 3 192.168.31.37
```

Validar as rotas:

```bash
docker compose exec phpipam-cron \
    ip route
```

É normal o container utilizar como gateway uma rede interna Docker semelhante a:

```text
default via 172.x.x.1 dev eth0
```

---

# 33. Validar os registros LDAP no DNS

No host Docker:

```bash
dig @192.168.31.24 \
    _ldap._tcp.dc._msdcs.jmsalles.homelab.br \
    SRV +short
```

Resultado validado:

```text
0 100 389 winserver.jmsalles.homelab.br.
```

Esse resultado confirma:

```text
Serviço:
LDAP

Porta:
389

Controlador:
winserver.jmsalles.homelab.br
```

---

# 34. Validar a extensão LDAP do PHP

```bash
docker compose exec phpipam-web \
    php -m | grep -i '^ldap$'
```

Resultado esperado:

```text
ldap
```

Teste adicional:

```bash
docker compose exec phpipam-web \
    php -r 'echo extension_loaded("ldap") ? "LDAP habilitado\n" : "LDAP não habilitado\n";'
```

Resultado esperado:

```text
LDAP habilitado
```

A própria interface de configuração do phpIPAM valida se a extensão LDAP do PHP está disponível. 

---

# 35. Validar a porta LDAP

Executar:

```bash
docker compose exec phpipam-web php -r '
$host = "winserver.jmsalles.homelab.br";
$port = 389;

$socket = @fsockopen($host, $port, $errno, $errstr, 5);

if ($socket) {
    echo "LDAP acessível em $host:$port\n";
    fclose($socket);
    exit(0);
}

fwrite(STDERR, "Falha em $host:$port - $errno - $errstr\n");
exit(1);
'
```

Resultado esperado:

```text
LDAP acessível em winserver.jmsalles.homelab.br:389
```

---

# 36. Testar o bind LDAP

Não inserir a senha diretamente no comando.

Ler a senha:

```bash
read -s -p "Senha da conta svc-ldap-bind: " LDAP_BIND_PASSWORD
echo
```

Executar:

```bash
docker compose exec \
    -e LDAP_BIND_PASSWORD="$LDAP_BIND_PASSWORD" \
    phpipam-web php -r '
$server = "ldap://winserver.jmsalles.homelab.br:389";
$user   = "svc-ldap-bind@jmsalles.homelab.br";
$pass   = getenv("LDAP_BIND_PASSWORD");

$ldap = ldap_connect($server);

if (!$ldap) {
    fwrite(STDERR, "Falha ao criar conexão LDAP\n");
    exit(1);
}

ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);
ldap_set_option($ldap, LDAP_OPT_REFERRALS, 0);

if (@ldap_bind($ldap, $user, $pass)) {
    echo "Bind LDAP realizado com sucesso\n";
    ldap_unbind($ldap);
    exit(0);
}

fwrite(STDERR, "Falha no bind LDAP: " . ldap_error($ldap) . "\n");
ldap_unbind($ldap);
exit(1);
'
```

Resultado esperado:

```text
Bind LDAP realizado com sucesso
```

Remover a senha da variável:

```bash
unset LDAP_BIND_PASSWORD
```

---

# 37. Testar a pesquisa do grupo administrativo

Ler novamente a senha:

```bash
read -s -p "Senha da conta svc-ldap-bind: " LDAP_BIND_PASSWORD
echo
```

Executar:

```bash
docker compose exec \
    -e LDAP_BIND_PASSWORD="$LDAP_BIND_PASSWORD" \
    phpipam-web php -r '
$server = "ldap://winserver.jmsalles.homelab.br:389";
$bind   = "svc-ldap-bind@jmsalles.homelab.br";
$pass   = getenv("LDAP_BIND_PASSWORD");

$base = "OU=Homelab,DC=jmsalles,DC=homelab,DC=br";

$filter = "(&(objectClass=user)(memberOf=CN=GRP_HOMELAB_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br))";

$ldap = ldap_connect($server);

if (!$ldap) {
    fwrite(STDERR, "Falha ao criar conexão LDAP\n");
    exit(1);
}

ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);
ldap_set_option($ldap, LDAP_OPT_REFERRALS, 0);

if (!@ldap_bind($ldap, $bind, $pass)) {
    fwrite(STDERR, "Falha no bind: " . ldap_error($ldap) . "\n");
    exit(1);
}

$search = @ldap_search(
    $ldap,
    $base,
    $filter,
    [
        "sAMAccountName",
        "displayName",
        "userPrincipalName",
        "mail"
    ]
);

if (!$search) {
    fwrite(STDERR, "Falha na pesquisa: " . ldap_error($ldap) . "\n");
    exit(1);
}

$entries = ldap_get_entries($ldap, $search);

echo "Usuários encontrados: " . $entries["count"] . "\n\n";

for ($i = 0; $i < $entries["count"]; $i++) {
    $login = $entries[$i]["samaccountname"][0] ?? "-";
    $nome  = $entries[$i]["displayname"][0] ?? "-";
    $upn   = $entries[$i]["userprincipalname"][0] ?? "-";
    $mail  = $entries[$i]["mail"][0] ?? "-";

    echo "Login:  $login\n";
    echo "Nome:   $nome\n";
    echo "UPN:    $upn\n";
    echo "E-mail: $mail\n";
    echo "----------------------------------------\n";
}

ldap_unbind($ldap);
'
```

Remover a senha:

```bash
unset LDAP_BIND_PASSWORD
```

---

# 38. Configurar o método Active Directory no phpIPAM

Entrar com o usuário local:

```text
Admin
```

Acessar:

```text
Administration
└── Authentication methods
```

Selecionar:

```text
Create new authentication method
```

Escolher:

```text
Active Directory
```

O formulário do método Active Directory possui campos específicos para controladores de domínio, Base DN, sufixo das contas, SSL, TLS, porta e conta de pesquisa.  

---

# 39. Preencher o método Active Directory

## Description

```text
AD JMSALLES
```

## Domain controllers

```text
winserver.jmsalles.homelab.br
```

Caso exista mais de um controlador, separar por ponto e vírgula:

```text
winserver.jmsalles.homelab.br;winserver02.jmsalles.homelab.br
```

## Base DN

```text
OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Essa base restringe as pesquisas aos objetos existentes dentro da OU `Homelab` e suas sub-OUs.

## Account suffix

```text
@jmsalles.homelab.br
```

## Use SSL

```text
false
```

## Use TLS

```text
false
```

## AD port

```text
389
```

## Domain account — Username

```text
svc-ldap-bind
```

Não informar:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

O phpIPAM concatena o usuário informado no campo `Domain account` com o `Account suffix`. Portanto, o bind utilizado será:

```text
svc-ldap-bind@jmsalles.homelab.br
```

Esse comportamento está implementado diretamente na biblioteca utilizada pelo phpIPAM. 

## Domain account — Password

Informar a senha da conta:

```text
svc-ldap-bind
```

Salvar.

---

# 40. Configuração final do método AD

```text
Description:
AD JMSALLES

Domain controllers:
winserver.jmsalles.homelab.br

Base DN:
OU=Homelab,DC=jmsalles,DC=homelab,DC=br

Account suffix:
@jmsalles.homelab.br

Use SSL:
false

Use TLS:
false

AD port:
389

Domain account:
svc-ldap-bind

Password:
SENHA_DA_CONTA_SVC_LDAP_BIND
```

---

# 41. Observação de segurança sobre LDAP 389

A configuração atual utiliza:

```text
LDAP:
389/TCP

SSL:
false

TLS:
false
```

Essa configuração foi mantida igual à integração existente no Gitea.

Em uma rede interna de laboratório ela pode ser utilizada, porém a senha de bind e as autenticações não possuem a proteção oferecida por LDAPS.

Como melhoria futura, recomenda-se:

```text
LDAPS:
636/TCP

Use SSL:
true

Use TLS:
false
```

Essa mudança exige certificado válido no controlador de domínio e confiança na CA dentro do container.

---

# 42. Pesquisar usuários do Active Directory

Acessar:

```text
Administration
└── Users
```

Selecionar a criação ou pesquisa de usuário do domínio.

Escolher:

```text
Authentication method:
AD JMSALLES
```

Pesquisar pelo `sAMAccountName`.

Exemplo:

```text
jmsalles
```

Não utilizar inicialmente:

```text
jmsalles@jmsalles.homelab.br
```

Nem:

```text
JMSALLES\jmsalles
```

O phpIPAM utilizará o sufixo configurado.

A pesquisa de usuários usa a Base DN configurada, exige credenciais da conta de pesquisa e retorna atributos como `displayName`, `sAMAccountName` e `mail`. 

---

# 43. Possível e-mail vazio durante a importação

No Gitea foi utilizado:

```text
Atributo do e-mail:
userPrincipalName
```

O phpIPAM procura o atributo:

```text
mail
```

durante a exibição dos usuários encontrados. 

Caso o atributo `mail` não esteja preenchido no Active Directory, o usuário poderá aparecer sem e-mail.

Isso não impede necessariamente a autenticação.

O e-mail poderá ser:

* preenchido no atributo `mail` do Active Directory; ou
* ajustado manualmente no phpIPAM.

---

# 44. Criar ou importar o grupo do Active Directory

Acessar:

```text
Administration
└── Groups
```

Selecionar a pesquisa de grupo do AD.

Escolher:

```text
Authentication method:
AD JMSALLES
```

Pesquisar:

```text
GRP_HOMELAB_ADMINS
```

Selecionar o grupo encontrado.

O phpIPAM possui suporte para pesquisar grupos do Active Directory e consultar seus membros.  

---

# 45. Restrição de acesso pelo grupo do AD

No Gitea foi utilizado o filtro:

```text
(&(objectClass=user)(sAMAccountName=%[1]s)(memberOf=CN=GRP_HOMELAB_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br))
```

O formulário Active Directory do phpIPAM não apresenta um campo para filtro LDAP personalizado.

Por isso, a autorização será controlada desta forma:

1. autenticação realizada pelo Active Directory;
2. importação dos usuários autorizados;
3. importação do grupo `GRP_HOMELAB_ADMINS`;
4. associação dos usuários ao grupo;
5. concessão das permissões dentro do phpIPAM.

A simples existência de um usuário no AD não deve conceder automaticamente acesso administrativo ao phpIPAM.

---

# 46. Importar o usuário do AD

Na pesquisa de usuários:

```text
Authentication method:
AD JMSALLES
```

Pesquisar o login:

```text
jmsalles
```

Selecionar o usuário.

Configurar:

```text
Authentication:
AD JMSALLES

Groups:
GRP_HOMELAB_ADMINS

Role:
Administrator

Disabled:
No
```

Não definir uma senha local para esse usuário.

A senha será validada diretamente pelo Active Directory.

---

# 47. Configurar permissões da seção

Acessar:

```text
Administration
└── Sections
└── Homelab Jeferson Salles
```

Editar permissões.

Associar:

```text
GRP_HOMELAB_ADMINS:
Administrative
```

Caso a interface utilize níveis:

```text
0:
Sem acesso

1:
Somente leitura

2:
Leitura e escrita

3:
Administração
```

Selecionar:

```text
3 - Administração
```

---

# 48. Configurar permissões da sub-rede

Abrir:

```text
192.168.31.0/24
```

Editar permissões.

Associar:

```text
GRP_HOMELAB_ADMINS:
Administrative
```

Validar também se o grupo possui acesso à seção pai.

---

# 49. Testar o login pelo Active Directory

Não encerrar a sessão do usuário local `Admin`.

Abrir uma janela anônima:

```text
Ctrl + Shift + N
```

Acessar:

```text
http://192.168.31.37:8088
```

Informar:

```text
Usuário:
SEU_SAMACCOUNTNAME

Senha:
SENHA_DO_ACTIVE_DIRECTORY
```

Exemplo de formato:

```text
jmsalles
```

Não utilizar inicialmente:

```text
jmsalles@jmsalles.homelab.br
```

Nem:

```text
JMSALLES\jmsalles
```

Após o login, validar:

* acesso à interface;
* visualização da seção;
* visualização da sub-rede;
* criação e edição de IPs;
* acesso administrativo;
* associação correta ao grupo.

---

# 50. Manter o usuário local `Admin`

Mesmo após a autenticação do AD funcionar, manter:

```text
Admin
```

como conta local de contingência.

Não:

* excluir;
* desabilitar;
* alterar para autenticação AD;
* remover os privilégios administrativos.

Essa conta será necessária caso:

* o controlador de domínio fique indisponível;
* o DNS pare de responder;
* a conta de bind seja bloqueada;
* a senha da conta de bind expire;
* a configuração LDAP seja alterada incorretamente.

---

# 51. Testar associação de grupos do usuário

O phpIPAM consulta os grupos do domínio e compara os membros com o nome do usuário importado. 

Após importar o grupo e o usuário:

1. editar o usuário;
2. verificar os grupos associados;
3. atualizar a associação pelo AD, caso a interface apresente essa opção;
4. confirmar `GRP_HOMELAB_ADMINS`;
5. salvar.

---

# 52. Executar a primeira descoberta manual

Abrir:

```text
Homelab Jeferson Salles
└── 192.168.31.0/24
```

Selecionar:

```text
Actions
└── Scan subnet for new hosts
```

Escolher:

```text
Ping scan
```

ou:

```text
ICMP scan
```

Executar.

O phpIPAM verificará os endereços de:

```text
192.168.31.1
```

até:

```text
192.168.31.254
```

Os endereços abaixo não são utilizáveis por equipamentos:

```text
192.168.31.0
192.168.31.255
```

---

# 53. Limitações da descoberta por ping

Um equipamento pode estar ativo e não aparecer quando:

* bloqueia ICMP;
* possui firewall local;
* está em modo de economia;
* é um dispositivo móvel desconectado;
* responde apenas por TCP;
* está temporariamente desligado;
* está em outra VLAN sem rota;
* o host Docker não alcança a rede.

Um endereço que não respondeu ao ping não deve ser automaticamente considerado livre.

---

# 54. Habilitar a descoberta automática

Depois de revisar o primeiro scan manual, editar:

```text
192.168.31.0/24
```

Configurar:

```text
Check hosts status:
Yes

Discover new hosts:
Yes

Resolve DNS names:
Yes

Nameserver:
DNS Homelab

Scan agent:
localhost
```

O container está configurado com:

```yaml
SCAN_INTERVAL: 1h
```

Portanto, as tarefas serão executadas periodicamente.

---

# 55. Acompanhar o cron de descoberta

```bash
cd /home/jmsalles/phpipam

docker compose logs -f phpipam-cron
```

Filtrar mensagens:

```bash
docker compose logs phpipam-cron 2>&1 \
    | grep -iE 'scan|discover|ping|dns|error|warning'
```

---

# 56. Não cadastrar a faixa DHCP sem confirmação

Ainda é necessário confirmar no roteador:

```text
Início da faixa DHCP
Fim da faixa DHCP
Tempo de concessão
Reservas DHCP
Endereços estáticos
```

Não assumir uma faixa como:

```text
192.168.31.100-192.168.31.200
```

sem validar a configuração real.

Depois de identificar a faixa, os endereços podem ser marcados no phpIPAM com uma tag específica de DHCP.

---

# 57. Publicação opcional pelo Nginx

Nome sugerido:

```text
ipam.jmsalles.homelab.br
```

Criar no DNS interno um registro:

```text
ipam.jmsalles.homelab.br    A    192.168.31.37
```

Validar:

```bash
dig @192.168.31.24 \
    ipam.jmsalles.homelab.br \
    A +short
```

Resultado esperado:

```text
192.168.31.37
```

---

# 58. Habilitar confiança no proxy reverso

Editar:

```bash
cd /home/jmsalles/phpipam

vim docker-compose.yml
```

Alterar:

```yaml
IPAM_TRUST_X_FORWARDED: "false"
```

Para:

```yaml
IPAM_TRUST_X_FORWARDED: "true"
```

Validar:

```bash
docker compose config
```

Aplicar:

```bash
docker compose up -d phpipam-web
```

A documentação das imagens alerta que os cabeçalhos `X-Forwarded-*` devem ser sobrescritos ou filtrados pelo proxy quando essa opção estiver habilitada. 

---

# 59. Configuração Nginx

Criar:

```bash
vim /home/jmsalles/nginx/conf.d/phpipam.conf
```

Adicionar:

```nginx
server {
    listen 80;
    server_name ipam.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ipam.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/certs/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/certs/jmsalles.homelab.br.key;

    location / {
        proxy_pass http://192.168.31.37:8088;

        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Port  $server_port;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 30s;
        proxy_send_timeout    300s;
        proxy_read_timeout    300s;
    }
}
```

Validar o nome do container Nginx:

```bash
docker ps --format '{{.Names}}' | grep -i nginx
```

Validar a configuração:

```bash
docker exec nginx nginx -t
```

Recarregar:

```bash
docker exec nginx nginx -s reload
```

Acessar:

```text
https://ipam.jmsalles.homelab.br
```

---

# 60. Restringir a porta 8088

Depois que o acesso HTTPS estiver funcionando, remover a abertura geral:

```bash
sudo firewall-cmd \
    --permanent \
    --remove-port=8088/tcp
```

Caso o Nginx esteja em outro servidor, permitir somente o IP dele:

```bash
sudo firewall-cmd \
    --permanent \
    --add-rich-rule='rule family="ipv4" source address="IP_DO_NGINX/32" port protocol="tcp" port="8088" accept'
```

Recarregar:

```bash
sudo firewall-cmd --reload
```

Validar:

```bash
sudo firewall-cmd --list-all
```

Se o Nginx estiver no mesmo servidor Docker e consumir a porta localmente, talvez não seja necessário liberar a porta na interface externa.

---

# 61. Operação diária

## Consultar o status

```bash
cd /home/jmsalles/phpipam

docker compose ps
```

## Iniciar

```bash
docker compose up -d
```

## Parar

```bash
docker compose stop
```

## Reiniciar todos

```bash
docker compose restart
```

## Reiniciar somente o Web

```bash
docker compose restart phpipam-web
```

## Reiniciar somente o cron

```bash
docker compose restart phpipam-cron
```

## Reiniciar somente o banco

```bash
docker compose restart phpipam-db
```

Evitar reiniciar o banco sem necessidade.

---

# 62. Consultar consumo de recursos

```bash
docker stats \
    phpipam-web \
    phpipam-cron \
    phpipam-db
```

Consultar processos:

```bash
docker compose top
```

Consultar espaço ocupado:

```bash
du -sh /home/jmsalles/phpipam/database
```

---

# 63. Consultar os logs recentes

```bash
docker compose logs --since 15m
```

Somente Web:

```bash
docker compose logs --since 15m phpipam-web
```

Somente LDAP e autenticação:

```bash
docker compose logs --since 15m phpipam-web 2>&1 \
    | grep -iE 'ldap|active directory|bind|credential|authentication|login'
```

Somente erros:

```bash
docker compose logs --since 15m 2>&1 \
    | grep -iE 'error|fatal|exception|denied|failed'
```

---

# 64. Validar a saúde do banco

```bash
docker inspect \
    --format '{{.State.Health.Status}}' \
    phpipam-db
```

Resultado esperado:

```text
healthy
```

Consultar a versão:

```bash
docker compose exec phpipam-db sh -c \
    'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "SELECT VERSION();"'
```

Testar o banco do phpIPAM:

```bash
docker compose exec phpipam-db sh -c \
    'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT COUNT(*) AS total_tabelas FROM information_schema.tables WHERE table_schema = DATABASE();"'
```

---

# 65. Validar as capabilities do cron

```bash
docker inspect phpipam-cron \
    --format '{{json .HostConfig.CapAdd}}'
```

Resultado esperado:

```text
["NET_ADMIN","NET_RAW"]
```

Validar o Web:

```bash
docker inspect phpipam-web \
    --format '{{json .HostConfig.CapAdd}}'
```

---

# 66. Solução de problemas — banco não saudável

Consultar logs:

```bash
docker compose logs --tail 200 phpipam-db
```

Validar permissões:

```bash
ls -ldZ /home/jmsalles/phpipam/database
```

Restaurar contextos SELinux:

```bash
sudo restorecon -Rv /home/jmsalles/phpipam
```

Reiniciar:

```bash
docker compose restart phpipam-db
```

Não utilizar:

```bash
chmod -R 777 /home/jmsalles/phpipam
```

---

# 67. Solução de problemas — banco vazio

Validar:

```bash
docker compose exec phpipam-db sh -c \
    'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SHOW TABLES;"'
```

Caso realmente não existam tabelas:

```bash
docker compose exec -T phpipam-web \
    cat /phpipam/db/SCHEMA.sql \
    | docker compose exec -T phpipam-db \
        sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
```

Não importar novamente o schema em um banco já preenchido.

---

# 68. Solução de problemas — `Invalid credentials`

Verificar:

```text
Senha da conta svc-ldap-bind
Conta bloqueada
Conta desabilitada
Senha expirada
Account suffix
Nome de usuário
```

Configuração correta:

```text
Domain account:
svc-ldap-bind

Account suffix:
@jmsalles.homelab.br
```

Bind resultante:

```text
svc-ldap-bind@jmsalles.homelab.br
```

---

# 69. Solução de problemas — `Can't contact LDAP server`

Validar DNS:

```bash
docker compose exec phpipam-web \
    getent hosts winserver.jmsalles.homelab.br
```

Validar a porta:

```bash
docker compose exec phpipam-web php -r '
$s = @fsockopen(
    "winserver.jmsalles.homelab.br",
    389,
    $errno,
    $errstr,
    5
);

echo $s
    ? "Porta LDAP acessível\n"
    : "Falha: $errno - $errstr\n";

if ($s) {
    fclose($s);
}
'
```

Validar o registro SRV:

```bash
dig @192.168.31.24 \
    _ldap._tcp.dc._msdcs.jmsalles.homelab.br \
    SRV +short
```

---

# 70. Solução de problemas — nenhum usuário encontrado

Verificar a Base DN:

```text
OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Verificar se o usuário está dentro da OU `Homelab` ou de alguma sub-OU.

Verificar a conta de bind:

```text
svc-ldap-bind
```

Testar pelo terminal usando os comandos apresentados anteriormente.

Verificar se o usuário possui:

```text
sAMAccountName
displayName
mail
userPrincipalName
```

---

# 71. Solução de problemas — grupo não encontrado

Confirmar o DN:

```text
CN=GRP_HOMELAB_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Confirmar a Base DN:

```text
OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Confirmar que o grupo está em:

```text
OU=Groups,OU=Homelab
```

Pesquisar pelo nome curto:

```text
GRP_HOMELAB_ADMINS
```

---

# 72. Solução de problemas — login funciona, mas sem permissão

Verificar:

* usuário importado no phpIPAM;
* método de autenticação `AD JMSALLES`;
* associação ao grupo;
* permissão da seção;
* permissão da sub-rede;
* função administrativa do usuário.

Configuração esperada:

```text
Usuário:
Autenticação AD JMSALLES

Grupo:
GRP_HOMELAB_ADMINS

Seção:
Administrative

Sub-rede:
Administrative
```

---

# 73. Solução de problemas — descoberta não encontra hosts

Testar pelo cron:

```bash
docker compose exec phpipam-cron \
    ping -c 3 192.168.31.2
```

Validar as capabilities:

```bash
docker inspect phpipam-cron \
    --format '{{json .HostConfig.CapAdd}}'
```

Validar rotas:

```bash
docker compose exec phpipam-cron \
    ip route
```

Validar DNS:

```bash
docker compose exec phpipam-cron \
    getent hosts winserver.jmsalles.homelab.br
```

Validar firewall do host:

```bash
sudo firewall-cmd --list-all
```

---

# 74. Solução de problemas — loop de login no Nginx

Confirmar no Compose:

```yaml
IPAM_TRUST_X_FORWARDED: "true"
```

Recriar o Web:

```bash
docker compose up -d phpipam-web
```

Confirmar no Nginx:

```nginx
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Port  $server_port;
proxy_set_header X-Forwarded-Proto $scheme;
```

Limpar os cookies do navegador.

---

# 75. Checklist final

## Containers

```text
[ ] phpipam-db está Running
[ ] phpipam-db está Healthy
[ ] phpipam-web está Running
[ ] phpipam-cron está Running
```

## Acesso

```text
[ ] http://192.168.31.37:8088 está acessível
[ ] Usuário Admin teve a senha alterada
[ ] Usuário Admin local foi mantido
```

## Rede

```text
[ ] Seção Homelab Jeferson Salles criada
[ ] Sub-rede 192.168.31.0/24 criada
[ ] Gateway 192.168.31.2 cadastrado
[ ] DNS 192.168.31.24 cadastrado
[ ] Servidor 192.168.31.37 cadastrado
[ ] Nameserver DNS Homelab configurado
[ ] Localização Homelab criada
```

## Descoberta

```text
[ ] phpipam-cron alcança o gateway
[ ] phpipam-cron alcança o DNS
[ ] NET_ADMIN configurado
[ ] NET_RAW configurado
[ ] Primeiro scan manual executado
[ ] IPs encontrados foram revisados
```

## Active Directory

```text
[ ] Registro SRV LDAP responde
[ ] winserver.jmsalles.homelab.br resolve para 192.168.31.24
[ ] Porta 389 está acessível
[ ] Extensão LDAP do PHP está habilitada
[ ] Bind svc-ldap-bind funciona
[ ] Método AD JMSALLES foi criado
[ ] Base DN está correta
[ ] Sufixo está correto
[ ] Grupo GRP_HOMELAB_ADMINS foi importado
[ ] Usuário do AD foi importado
[ ] Login com sAMAccountName funciona
[ ] Permissões administrativas foram validadas
```

## Proxy reverso

```text
[ ] Registro ipam.jmsalles.homelab.br criado
[ ] Certificado configurado
[ ] Nginx validado
[ ] IPAM_TRUST_X_FORWARDED habilitado
[ ] Acesso HTTPS validado
```

---

# 76. Configuração consolidada

```text
Aplicação:
phpIPAM

Host:
docker-hml-lenovo-i5

IP:
192.168.31.37

Porta:
8088

Diretório:
/home/jmsalles/phpipam

Rede:
192.168.31.0/24

Gateway:
192.168.31.2

DNS:
192.168.31.24

Domínio:
jmsalles.homelab.br

Controlador:
winserver.jmsalles.homelab.br

LDAP:
389/TCP

Base DN:
OU=Homelab,DC=jmsalles,DC=homelab,DC=br

Conta de bind:
svc-ldap-bind

Bind UPN:
svc-ldap-bind@jmsalles.homelab.br

Grupo administrativo:
GRP_HOMELAB_ADMINS

DN do grupo:
CN=GRP_HOMELAB_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br

Método de autenticação:
AD JMSALLES
```

O ambiente estará operacional quando o acesso Web, o banco, a descoberta da rede, a resolução DNS e o login pelo Active Directory estiverem funcionando simultaneamente. O procedimento de backup deverá ser definido antes de futuras atualizações relevantes das imagens ou do banco de dados.
