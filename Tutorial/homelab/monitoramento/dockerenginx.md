# Guia de monitoramento basico do host Docker HML no Zabbix

## 1. Objetivo

Este documento descreve como monitorar o host fisico Docker HML no Zabbix.

Neste momento, o monitoramento sera focado apenas no basico e essencial do servidor fisico e no Nginx reverse proxy em container.

Nao serao monitorados nesta etapa:

```text
Gitea
Nexus
Vault
Runner
Backups
Aplicacoes especificas
SELinux
Firewalld
```

## 2. Dados do ambiente

| Item               | Valor                            |
| ------------------ | -------------------------------- |
| Host               | `docker-hml.jmsalles.homelab.br` |
| IP                 | `192.168.31.37`                  |
| Funcao             | Host fisico Docker HML           |
| Servico fixo       | Nginx reverse proxy              |
| Container do Nginx | `nginx-reverse-proxy-hml`        |
| Zabbix Agent       | Zabbix Agent 2                   |
| Porta do Agent     | `10050`                          |

## 3. O que sera monitorado

| Camada | Monitoramento                                   |
| ------ | ----------------------------------------------- |
| Host   | ICMP, Agent, CPU, memoria, swap, disco          |
| Docker | `docker.service`, Docker Engine, containers     |
| Nginx  | Container rodando, restart count, portas 80/443 |
| Rede   | Portas externas 22, 80 e 443                    |
| Web    | HTTPS base do host                              |

## 4. Criar o host no Zabbix

No frontend do Zabbix, acesse:

```text
Data collection
Hosts
Create host
```

Preencha:

| Campo        | Valor                                |
| ------------ | ------------------------------------ |
| Host name    | `docker-hml.jmsalles.homelab.br`     |
| Visible name | `Docker HML - Host Fisico`           |
| Groups       | `Homelab`, `Docker`, `Linux servers` |
| Interface    | `Agent`                              |
| IP address   | `192.168.31.37`                      |
| DNS name     | `docker-hml.jmsalles.homelab.br`     |
| Connect to   | `IP`                                 |
| Port         | `10050`                              |

Vincule os templates basicos:

```text
Linux by Zabbix agent
Docker by Zabbix agent 2
ICMP Ping
```

Clique em:

```text
Add
```

## 5. Validar ou instalar o Zabbix Agent 2 no host

Acesse o servidor Docker HML:

```bash
ssh jmsalles@192.168.31.37
```

Valide se o Agent 2 esta instalado:

```bash
rpm -qa | grep zabbix-agent2
```

Valide o servico:

```bash
sudo systemctl status zabbix-agent2
```

Caso nao esteja instalado:

```bash
sudo dnf install -y zabbix-agent2
```

Habilite e inicie:

```bash
sudo systemctl enable --now zabbix-agent2
```

Edite o arquivo de configuracao:

```bash
sudo vim /etc/zabbix/zabbix_agent2.conf
```

Ajuste conforme o IP do seu Zabbix Server:

```ini
Server=IP_DO_ZABBIX_SERVER
ServerActive=IP_DO_ZABBIX_SERVER
Hostname=docker-hml.jmsalles.homelab.br
```

Reinicie o agente:

```bash
sudo systemctl restart zabbix-agent2
```

Valide o status:

```bash
sudo systemctl status zabbix-agent2
```

Valide o log:

```bash
sudo journalctl -u zabbix-agent2 -n 100 --no-pager
```

Libere a porta do agente, se necessario:

```bash
sudo firewall-cmd --permanent --add-port=10050/tcp
```

```bash
sudo firewall-cmd --reload
```

Valide:

```bash
sudo firewall-cmd --list-ports
```

## 6. Permitir que o Zabbix consulte o Docker

O usuario `zabbix` precisa ter permissao para consultar o Docker.

Valide o usuario:

```bash
id zabbix
```

Adicione o usuario `zabbix` ao grupo `docker`:

```bash
sudo usermod -aG docker zabbix
```

Reinicie o Agent 2:

```bash
sudo systemctl restart zabbix-agent2
```

Teste o acesso ao Docker com o usuario `zabbix`:

```bash
sudo -u zabbix docker ps
```

Se listar os containers, esta correto.

Teste tambem a chave do template Docker:

```bash
zabbix_agent2 -t docker.ping
```

Resultado esperado:

```text
docker.ping [s|1]
```

Observacao:

```text
O grupo docker possui privilegios elevados no host.
No homelab, essa configuracao facilita o monitoramento.
```

## 7. Criar template customizado sem acento

No Zabbix, acesse:

```text
Data collection
Templates
Create template
```

Preencha:

| Campo         | Valor                                            |
| ------------- | ------------------------------------------------ |
| Template name | `Template Docker Host JMSalles Basico`           |
| Visible name  | `Monitoramento basico do host Docker HML`        |
| Groups        | `Templates/Operating systems`                    |
| Description   | `Monitoramento basico do host fisico Docker HML` |

Clique em:

```text
Add
```

Depois vincule esse template ao host:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Templates
Link new templates
Template Docker Host JMSalles Basico
Update
```

## 8. Criar UserParameters basicos

No host Docker HML, crie o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/docker-host-basic.conf
```

Cole o conteudo abaixo:

```ini
UserParameter=dockerhost.docker.active,systemctl is-active docker 2>/dev/null | grep -q active && echo 1 || echo 0
UserParameter=dockerhost.docker.info,docker info >/dev/null 2>&1 && echo 1 || echo 0
UserParameter=dockerhost.containers.running,docker ps -q 2>/dev/null | wc -l
UserParameter=dockerhost.containers.exited,docker ps -a -f status=exited -q 2>/dev/null | wc -l
UserParameter=dockerhost.containers.restarting,docker ps -a -f status=restarting -q 2>/dev/null | wc -l
UserParameter=dockerhost.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
UserParameter=dockerhost.container.restart[*],docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null | tr -cd '0-9'
UserParameter=dockerhost.tcp.local[*],nc -z -w 3 127.0.0.1 $1 >/dev/null 2>&1 && echo 1 || echo 0
UserParameter=dockerhost.http.code[*],curl -k -s -o /dev/null -w "%{http_code}" $1 2>/dev/null
UserParameter=dockerhost.docker.root.size,du -sb /var/lib/docker 2>/dev/null | awk '{print $1}'
```

A linha principal para monitorar se o container do Nginx esta rodando e esta:

```ini
UserParameter=dockerhost.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Essa linha garante:

```text
Container rodando: 1
Container parado: 0
Container removido: 0
```

Caso o comando `nc` nao exista, instale o pacote:

```bash
sudo dnf install -y nmap-ncat
```

Ajuste a permissao:

```bash
sudo chmod 644 /etc/zabbix/zabbix_agent2.d/docker-host-basic.conf
```

Reinicie o Agent 2:

```bash
sudo systemctl restart zabbix-agent2
```

Valide o log:

```bash
sudo journalctl -u zabbix-agent2 -n 100 --no-pager
```

## 9. Testar os UserParameters no host

Teste o Docker ativo:

```bash
zabbix_agent2 -t dockerhost.docker.active
```

Teste o Docker Engine:

```bash
zabbix_agent2 -t dockerhost.docker.info
```

Teste containers rodando:

```bash
zabbix_agent2 -t dockerhost.containers.running
```

Teste containers parados:

```bash
zabbix_agent2 -t dockerhost.containers.exited
```

Teste containers reiniciando:

```bash
zabbix_agent2 -t dockerhost.containers.restarting
```

Teste o container Nginx:

```bash
zabbix_agent2 -t 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

Teste o restart count do Nginx:

```bash
zabbix_agent2 -t 'dockerhost.container.restart[nginx-reverse-proxy-hml]'
```

Teste a porta 80 local:

```bash
zabbix_agent2 -t 'dockerhost.tcp.local[80]'
```

Teste a porta 443 local:

```bash
zabbix_agent2 -t 'dockerhost.tcp.local[443]'
```

Teste o HTTPS base:

```bash
zabbix_agent2 -t 'dockerhost.http.code[https://docker-hml.jmsalles.homelab.br]'
```

Teste o tamanho do Docker:

```bash
zabbix_agent2 -t dockerhost.docker.root.size
```

Resultados esperados:

| Chave                                                   | Esperado                                           |
| ------------------------------------------------------- | -------------------------------------------------- |
| `dockerhost.docker.active`                              | `1`                                                |
| `dockerhost.docker.info`                                | `1`                                                |
| `dockerhost.containers.running`                         | numero de containers rodando                       |
| `dockerhost.containers.exited`                          | idealmente `0`                                     |
| `dockerhost.containers.restarting`                      | `0`                                                |
| `dockerhost.container.running[nginx-reverse-proxy-hml]` | `1` com Nginx ativo, `0` com Nginx parado/removido |
| `dockerhost.tcp.local[80]`                              | `1`                                                |
| `dockerhost.tcp.local[443]`                             | `1`                                                |
| `dockerhost.http.code[...]`                             | `200`                                              |

## 10. Criar itens no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Docker Host JMSalles Basico
Items
Create item
```

Crie os itens abaixo.

### 10.1 Docker service ativo

| Campo               | Valor                              |
| ------------------- | ---------------------------------- |
| Name                | `Docker HML: docker.service ativo` |
| Type                | `Zabbix agent`                     |
| Key                 | `dockerhost.docker.active`         |
| Type of information | `Numeric unsigned`                 |
| Update interval     | `1m`                               |
| History             | `31d`                              |
| Trends              | `365d`                             |

### 10.2 Docker Engine respondendo

| Campo               | Valor                                   |
| ------------------- | --------------------------------------- |
| Name                | `Docker HML: Docker Engine respondendo` |
| Type                | `Zabbix agent`                          |
| Key                 | `dockerhost.docker.info`                |
| Type of information | `Numeric unsigned`                      |
| Update interval     | `1m`                                    |
| History             | `31d`                                   |
| Trends              | `365d`                                  |

### 10.3 Containers rodando

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Docker HML: Containers rodando` |
| Type                | `Zabbix agent`                   |
| Key                 | `dockerhost.containers.running`  |
| Type of information | `Numeric unsigned`               |
| Update interval     | `1m`                             |
| History             | `31d`                            |
| Trends              | `365d`                           |

### 10.4 Containers parados

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Docker HML: Containers parados` |
| Type                | `Zabbix agent`                   |
| Key                 | `dockerhost.containers.exited`   |
| Type of information | `Numeric unsigned`               |
| Update interval     | `1m`                             |
| History             | `31d`                            |
| Trends              | `365d`                           |

### 10.5 Containers reiniciando

| Campo               | Valor                                |
| ------------------- | ------------------------------------ |
| Name                | `Docker HML: Containers reiniciando` |
| Type                | `Zabbix agent`                       |
| Key                 | `dockerhost.containers.restarting`   |
| Type of information | `Numeric unsigned`                   |
| Update interval     | `1m`                                 |
| History             | `31d`                                |
| Trends              | `365d`                               |

### 10.6 Container Nginx reverse proxy rodando

| Campo               | Valor                                                   |
| ------------------- | ------------------------------------------------------- |
| Name                | `Docker HML: Container Nginx reverse proxy rodando`     |
| Type                | `Zabbix agent`                                          |
| Key                 | `dockerhost.container.running[nginx-reverse-proxy-hml]` |
| Type of information | `Numeric unsigned`                                      |
| Update interval     | `30s`                                                   |
| History             | `31d`                                                   |
| Trends              | `365d`                                                  |

Observacao:

```text
O nome do container deve ser informado sem barra.
```

Correto:

```text
nginx-reverse-proxy-hml
```

Incorreto:

```text
/nginx-reverse-proxy-hml
```

### 10.7 Restart count do Nginx reverse proxy

| Campo               | Valor                                                   |
| ------------------- | ------------------------------------------------------- |
| Name                | `Docker HML: Restart count do Nginx reverse proxy`      |
| Type                | `Zabbix agent`                                          |
| Key                 | `dockerhost.container.restart[nginx-reverse-proxy-hml]` |
| Type of information | `Numeric unsigned`                                      |
| Update interval     | `5m`                                                    |
| History             | `31d`                                                   |
| Trends              | `365d`                                                  |

### 10.8 Porta local 80 aberta

| Campo               | Valor                               |
| ------------------- | ----------------------------------- |
| Name                | `Docker HML: Porta local 80 aberta` |
| Type                | `Zabbix agent`                      |
| Key                 | `dockerhost.tcp.local[80]`          |
| Type of information | `Numeric unsigned`                  |
| Update interval     | `1m`                                |
| History             | `31d`                               |
| Trends              | `365d`                              |

### 10.9 Porta local 443 aberta

| Campo               | Valor                                |
| ------------------- | ------------------------------------ |
| Name                | `Docker HML: Porta local 443 aberta` |
| Type                | `Zabbix agent`                       |
| Key                 | `dockerhost.tcp.local[443]`          |
| Type of information | `Numeric unsigned`                   |
| Update interval     | `1m`                                 |
| History             | `31d`                                |
| Trends              | `365d`                               |

### 10.10 HTTPS base status code

| Campo               | Valor                                                          |
| ------------------- | -------------------------------------------------------------- |
| Name                | `Docker HML: HTTPS base status code`                           |
| Type                | `Zabbix agent`                                                 |
| Key                 | `dockerhost.http.code[https://docker-hml.jmsalles.homelab.br]` |
| Type of information | `Numeric unsigned`                                             |
| Update interval     | `1m`                                                           |
| History             | `31d`                                                          |
| Trends              | `365d`                                                         |

### 10.11 Tamanho de `/var/lib/docker`

| Campo               | Valor                                    |
| ------------------- | ---------------------------------------- |
| Name                | `Docker HML: Tamanho de /var/lib/docker` |
| Type                | `Zabbix agent`                           |
| Key                 | `dockerhost.docker.root.size`            |
| Type of information | `Numeric unsigned`                       |
| Units               | `B`                                      |
| Update interval     | `10m`                                    |
| History             | `31d`                                    |
| Trends              | `365d`                                   |

## 11. Criar checks externos de porta

Esses checks validam as portas a partir do ponto de vista do Zabbix Server.

No template ou diretamente no host, crie os itens abaixo.

### 11.1 Porta externa 22 SSH

| Campo               | Valor                                   |
| ------------------- | --------------------------------------- |
| Name                | `Docker HML: Porta externa 22 SSH`      |
| Type                | `Simple check`                          |
| Key                 | `net.tcp.service[tcp,192.168.31.37,22]` |
| Type of information | `Numeric unsigned`                      |
| Update interval     | `1m`                                    |
| History             | `31d`                                   |
| Trends              | `365d`                                  |

### 11.2 Porta externa 80 HTTP

| Campo               | Valor                                   |
| ------------------- | --------------------------------------- |
| Name                | `Docker HML: Porta externa 80 HTTP`     |
| Type                | `Simple check`                          |
| Key                 | `net.tcp.service[tcp,192.168.31.37,80]` |
| Type of information | `Numeric unsigned`                      |
| Update interval     | `1m`                                    |
| History             | `31d`                                   |
| Trends              | `365d`                                  |

### 11.3 Porta externa 443 HTTPS

| Campo               | Valor                                    |
| ------------------- | ---------------------------------------- |
| Name                | `Docker HML: Porta externa 443 HTTPS`    |
| Type                | `Simple check`                           |
| Key                 | `net.tcp.service[tcp,192.168.31.37,443]` |
| Type of information | `Numeric unsigned`                       |
| Update interval     | `1m`                                     |
| History             | `31d`                                    |
| Trends              | `365d`                                   |

## 12. Criar triggers essenciais

No Zabbix, acesse:

```text
Data collection
Templates
Template Docker Host JMSalles Basico
Triggers
Create trigger
```

### 12.1 Docker service parado

| Campo                         | Valor                                                                    |
| ----------------------------- | ------------------------------------------------------------------------ |
| Name                          | `Docker HML: docker.service esta parado`                                 |
| Severity                      | `High`                                                                   |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.docker.active)=0` |
| OK event generation           | `Expression`                                                             |
| PROBLEM event generation mode | `Single`                                                                 |
| Enabled                       | Sim                                                                      |

### 12.2 Docker Engine nao responde

| Campo                         | Valor                                                                  |
| ----------------------------- | ---------------------------------------------------------------------- |
| Name                          | `Docker HML: Docker Engine nao responde`                               |
| Severity                      | `High`                                                                 |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.docker.info)=0` |
| OK event generation           | `Expression`                                                           |
| PROBLEM event generation mode | `Single`                                                               |
| Enabled                       | Sim                                                                    |

### 12.3 Containers reiniciando

| Campo                         | Valor                                                                            |
| ----------------------------- | -------------------------------------------------------------------------------- |
| Name                          | `Docker HML: Existe container em restarting`                                     |
| Severity                      | `High`                                                                           |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.containers.restarting)>0` |
| OK event generation           | `Expression`                                                                     |
| PROBLEM event generation mode | `Single`                                                                         |
| Enabled                       | Sim                                                                              |

### 12.4 Containers parados

| Campo                         | Valor                                                                        |
| ----------------------------- | ---------------------------------------------------------------------------- |
| Name                          | `Docker HML: Existem containers parados`                                     |
| Severity                      | `Warning`                                                                    |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.containers.exited)>0` |
| OK event generation           | `Expression`                                                                 |
| PROBLEM event generation mode | `Single`                                                                     |
| Enabled                       | Opcional                                                                     |

Observacao:

```text
Se voce costuma manter containers parados propositalmente, deixe essa trigger desabilitada.
```

### 12.5 Container Nginx reverse proxy parado

| Campo                         | Valor                                                                                                 |
| ----------------------------- | ----------------------------------------------------------------------------------------------------- |
| Name                          | `Docker HML: Container Nginx reverse proxy parado`                                                    |
| Severity                      | `High`                                                                                                |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.container.running[nginx-reverse-proxy-hml])=0` |
| OK event generation           | `Expression`                                                                                          |
| PROBLEM event generation mode | `Single`                                                                                              |
| Enabled                       | Sim                                                                                                   |

### 12.6 Container Nginx reiniciou recentemente

| Campo                         | Valor                                                                                                   |
| ----------------------------- | ------------------------------------------------------------------------------------------------------- |
| Name                          | `Docker HML: Container Nginx reiniciou recentemente`                                                    |
| Severity                      | `Warning`                                                                                               |
| Expression                    | `change(/Template Docker Host JMSalles Basico/dockerhost.container.restart[nginx-reverse-proxy-hml])>0` |
| OK event generation           | `Expression`                                                                                            |
| PROBLEM event generation mode | `Single`                                                                                                |
| Enabled                       | Sim                                                                                                     |

### 12.7 Porta local 80 fechada

| Campo                         | Valor                                                                    |
| ----------------------------- | ------------------------------------------------------------------------ |
| Name                          | `Docker HML: Porta local 80 fechada`                                     |
| Severity                      | `Average`                                                                |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.tcp.local[80])=0` |
| OK event generation           | `Expression`                                                             |
| PROBLEM event generation mode | `Single`                                                                 |
| Enabled                       | Sim                                                                      |

### 12.8 Porta local 443 fechada

| Campo                         | Valor                                                                     |
| ----------------------------- | ------------------------------------------------------------------------- |
| Name                          | `Docker HML: Porta local 443 fechada`                                     |
| Severity                      | `High`                                                                    |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.tcp.local[443])=0` |
| OK event generation           | `Expression`                                                              |
| PROBLEM event generation mode | `Single`                                                                  |
| Enabled                       | Sim                                                                       |

### 12.9 HTTPS base diferente de 200

| Campo                         | Valor                                                                                                           |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Name                          | `Docker HML: HTTPS base retornando codigo diferente de 200`                                                     |
| Severity                      | `Average`                                                                                                       |
| Expression                    | `last(/Template Docker Host JMSalles Basico/dockerhost.http.code[https://docker-hml.jmsalles.homelab.br])<>200` |
| OK event generation           | `Expression`                                                                                                    |
| PROBLEM event generation mode | `Single`                                                                                                        |
| Enabled                       | Sim                                                                                                             |

## 13. Criar triggers para checks externos de porta

### 13.1 Porta externa 22 indisponivel

| Campo      | Valor                                                                                 |
| ---------- | ------------------------------------------------------------------------------------- |
| Name       | `Docker HML: Porta externa 22 SSH indisponivel`                                       |
| Severity   | `High`                                                                                |
| Expression | `last(/Template Docker Host JMSalles Basico/net.tcp.service[tcp,192.168.31.37,22])=0` |

### 13.2 Porta externa 80 indisponivel

| Campo      | Valor                                                                                 |
| ---------- | ------------------------------------------------------------------------------------- |
| Name       | `Docker HML: Porta externa 80 HTTP indisponivel`                                      |
| Severity   | `Average`                                                                             |
| Expression | `last(/Template Docker Host JMSalles Basico/net.tcp.service[tcp,192.168.31.37,80])=0` |

### 13.3 Porta externa 443 indisponivel

| Campo      | Valor                                                                                  |
| ---------- | -------------------------------------------------------------------------------------- |
| Name       | `Docker HML: Porta externa 443 HTTPS indisponivel`                                     |
| Severity   | `High`                                                                                 |
| Expression | `last(/Template Docker Host JMSalles Basico/net.tcp.service[tcp,192.168.31.37,443])=0` |

## 14. Criar Web Scenario simples

No Zabbix, acesse:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Web
Create web scenario
```

Preencha:

| Campo           | Valor                     |
| --------------- | ------------------------- |
| Name            | `Docker HML - HTTPS base` |
| Update interval | `1m`                      |
| Attempts        | `3`                       |
| Agent           | `Chrome`                  |
| Enabled         | Sim                       |

Crie o step:

| Campo                 | Valor                                    |
| --------------------- | ---------------------------------------- |
| Name                  | `Home HTTPS`                             |
| URL                   | `https://docker-hml.jmsalles.homelab.br` |
| Timeout               | `10s`                                    |
| Required status codes | `200`                                    |

Crie a trigger do Web Scenario no host:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Triggers
Create trigger
```

| Campo      | Valor                                                                             |
| ---------- | --------------------------------------------------------------------------------- |
| Name       | `Docker HML: Web scenario HTTPS base falhando`                                    |
| Severity   | `High`                                                                            |
| Expression | `last(/docker-hml.jmsalles.homelab.br/web.test.fail[Docker HML - HTTPS base])<>0` |

## 15. Validar em Latest data

No Zabbix, acesse:

```text
Monitoring
Latest data
```

Use o filtro:

```text
Host: docker-hml.jmsalles.homelab.br
Name: Docker HML
```

Voce deve ver os itens:

```text
Docker HML: docker.service ativo
Docker HML: Docker Engine respondendo
Docker HML: Containers rodando
Docker HML: Containers parados
Docker HML: Containers reiniciando
Docker HML: Container Nginx reverse proxy rodando
Docker HML: Restart count do Nginx reverse proxy
Docker HML: Porta local 80 aberta
Docker HML: Porta local 443 aberta
Docker HML: HTTPS base status code
Docker HML: Tamanho de /var/lib/docker
```

## 16. Teste controlado do Nginx

Para testar o alerta do Nginx, pare somente o container do proxy.

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose stop nginx
```

Teste localmente:

```bash
zabbix_agent2 -t 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

Resultado esperado:

```text
dockerhost.container.running[nginx-reverse-proxy-hml] [s|0]
```

No Zabbix, o alerta esperado e:

```text
Docker HML: Container Nginx reverse proxy parado
```

Tambem podem abrir alertas relacionados as portas:

```text
Docker HML: Porta local 80 fechada
Docker HML: Porta local 443 fechada
Docker HML: HTTPS base retornando codigo diferente de 200
Docker HML: Web scenario HTTPS base falhando
```

Para subir novamente:

```bash
docker compose start nginx
```

Valide:

```bash
docker ps | grep nginx
```

Teste novamente:

```bash
zabbix_agent2 -t 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

Resultado esperado:

```text
dockerhost.container.running[nginx-reverse-proxy-hml] [s|1]
```

O alerta deve fechar automaticamente.

## 17. Teste com container removido

Se voce usar `docker compose down`, o container sera removido.

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose down
```

Mesmo assim, o item customizado deve retornar `0`.

```bash
zabbix_agent2 -t 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

Resultado esperado:

```text
dockerhost.container.running[nginx-reverse-proxy-hml] [s|0]
```

Para subir novamente:

```bash
docker compose up -d
```

Valide:

```bash
docker ps | grep nginx
```

## 18. Testar coleta a partir do Zabbix Server

No servidor Zabbix, se tiver `zabbix_get`, teste:

```bash
zabbix_get -s 192.168.31.37 -k dockerhost.docker.active
```

```bash
zabbix_get -s 192.168.31.37 -k dockerhost.docker.info
```

```bash
zabbix_get -s 192.168.31.37 -k 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

```bash
zabbix_get -s 192.168.31.37 -k 'dockerhost.tcp.local[443]'
```

Resultados esperados:

```text
1
```

Para instalar o `zabbix_get`, caso necessario:

```bash
sudo dnf install -y zabbix-get
```

## 19. Troubleshooting

### 19.1 Item retorna erro de tipo no Zabbix

Erro comum:

```text
Value of type "string" is not suitable for value type "Numeric (unsigned)"
```

Causa provavel:

```text
O UserParameter esta retornando valor com quebra de linha ou texto indevido.
```

Correcao:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/docker-host-basic.conf
```

Garanta que a linha esteja assim:

```ini
UserParameter=dockerhost.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Reinicie:

```bash
sudo systemctl restart zabbix-agent2
```

Teste:

```bash
zabbix_agent2 -t 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

### 19.2 Container esta rodando, mas item retorna 0

Valide primeiro o Docker puro:

```bash
docker inspect -f '{{.State.Running}}' nginx-reverse-proxy-hml
```

Resultado esperado:

```text
true
```

Teste o comando completo do UserParameter:

```bash
docker inspect -f '{{.State.Running}}' "nginx-reverse-proxy-hml" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Resultado esperado:

```text
1
```

Se funcionar no shell e nao funcionar no Agent, reinicie o Agent:

```bash
sudo systemctl restart zabbix-agent2
```

Depois teste:

```bash
zabbix_agent2 -t 'dockerhost.container.running[nginx-reverse-proxy-hml]'
```

### 19.3 Zabbix nao consegue consultar Docker

Teste com usuario `zabbix`:

```bash
sudo -u zabbix docker ps
```

Se falhar, adicione ao grupo `docker`:

```bash
sudo usermod -aG docker zabbix
```

Reinicie o Agent:

```bash
sudo systemctl restart zabbix-agent2
```

Teste novamente:

```bash
sudo -u zabbix docker ps
```

### 19.4 Item de porta local retorna 0

Valide se a porta esta aberta no host:

```bash
ss -lntp | egrep ':80|:443'
```

Valide o Nginx:

```bash
docker ps | grep nginx
```

Valide o compose do Nginx:

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose ps
```

### 19.5 HTTPS base retorna diferente de 200

Teste manual:

```bash
curl -k -I https://docker-hml.jmsalles.homelab.br
```

Valide logs do Nginx:

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose logs --tail=100 nginx
```

Valide configuracao do Nginx:

```bash
docker compose exec nginx nginx -t
```

Recarregue se necessario:

```bash
docker compose exec nginx nginx -s reload
```

## 20. Checklist final

| Item                                                   | Status   |
| ------------------------------------------------------ | -------- |
| Host `docker-hml.jmsalles.homelab.br` criado no Zabbix | Pendente |
| IP `192.168.31.37` configurado                         | Pendente |
| Template `Linux by Zabbix agent` vinculado             | Pendente |
| Template `Docker by Zabbix agent 2` vinculado          | Pendente |
| Template `ICMP Ping` vinculado                         | Pendente |
| Template `Template Docker Host JMSalles Basico` criado | Pendente |
| Zabbix Agent 2 instalado e ativo                       | Pendente |
| Usuario `zabbix` no grupo `docker`                     | Pendente |
| Arquivo `docker-host-basic.conf` criado                | Pendente |
| UserParameter corrigido com `grep -qx true`            | Pendente |
| Testes com `zabbix_agent2 -t` executados               | Pendente |
| Itens customizados criados                             | Pendente |
| Triggers essenciais criadas                            | Pendente |
| Web Scenario criado                                    | Pendente |
| Teste de parada do Nginx validado                      | Pendente |

## 21. Resumo final

Neste momento, o monitoramento do host Docker HML ficara restrito ao essencial:

```text
ICMP
Zabbix Agent
Linux basico
Docker Engine
Containers
Nginx reverse proxy
Portas 22, 80 e 443
HTTPS base do host
/var/lib/docker
```

O principal item customizado para o Nginx e:

```text
dockerhost.container.running[nginx-reverse-proxy-hml]
```

A trigger principal e:

```text
last(/Template Docker Host JMSalles Basico/dockerhost.container.running[nginx-reverse-proxy-hml])=0
```

Com esse modelo, o Zabbix alerta rapidamente quando o host Docker HML ou o Nginx reverse proxy apresentar falha, sem gerar ruido com aplicacoes que serao monitoradas separadamente depois.

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
