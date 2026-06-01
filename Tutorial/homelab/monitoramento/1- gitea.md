# Guia de monitoramento do Gitea no Zabbix

## 1. Objetivo

Este documento descreve como monitorar o Gitea instalado em Docker no host fisico Docker HML.

O monitoramento sera feito no Zabbix existente da rede, utilizando o Zabbix Agent 2 instalado no host:

```text
docker-hml.jmsalles.homelab.br
```

Nesta etapa, o foco sera apenas no Gitea e no PostgreSQL do Gitea.

Nao serao monitorados neste documento:

```text
Nexus
Vault
Runner
Backups
Outras aplicacoes
```

Observacao importante sobre certificado:

```text
O ambiente utiliza certificado interno/autoassinado.
Por esse motivo, os testes via curl no Zabbix Agent usarao a opcao -k.
Essa opcao ignora a validacao da cadeia de certificado.
```

Caso apareca o erro abaixo em testes manuais com `curl` sem `-k`, o problema esta relacionado a cadeia do certificado nao estar instalada como confiavel no Linux ou no container do Zabbix.

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Neste momento, nao sera feita a instalacao da CA raiz. O monitoramento seguira usando `curl -k`.

## 2. Dados do ambiente

| Item                      | Valor                                         |
| ------------------------- | --------------------------------------------- |
| Host Docker HML           | `docker-hml.jmsalles.homelab.br`              |
| IP do host                | `192.168.31.37`                               |
| URL do Gitea              | `https://git.jmsalles.homelab.br`             |
| Health check              | `https://git.jmsalles.homelab.br/api/healthz` |
| Container do Gitea        | `gitea`                                       |
| Container do PostgreSQL   | `gitea-db`                                    |
| Porta HTTP local do Gitea | `3000`                                        |
| Porta SSH do Gitea        | `2222`                                        |
| Banco                     | PostgreSQL                                    |
| Zabbix Agent              | Zabbix Agent 2                                |

## 3. O que sera monitorado

| Camada    | Monitoramento                         |
| --------- | ------------------------------------- |
| Aplicacao | HTTPS do Gitea                        |
| Aplicacao | Health check `/api/healthz`           |
| Aplicacao | HTTP local na porta `3000`            |
| SSH Git   | Porta `2222`                          |
| Container | Container `gitea` rodando             |
| Container | Container `gitea-db` rodando          |
| Container | Restart count do container `gitea`    |
| Container | Restart count do container `gitea-db` |
| Banco     | PostgreSQL aceitando conexao          |
| Web       | Web Scenario do Gitea                 |

## 4. Validar o Gitea manualmente

Acesse o host Docker HML.

```bash
ssh jmsalles@192.168.31.37
```

Valide os containers.

```bash
docker ps | egrep 'gitea|gitea-db'
```

Valide o acesso local do Gitea.

```bash
curl -I http://127.0.0.1:3000
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Valide o acesso HTTPS pelo proxy usando `-k`, pois o certificado e interno/autoassinado.

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

Se executar sem `-k`:

```bash
curl -I https://git.jmsalles.homelab.br
```

e receber o erro abaixo:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

isso indica apenas que a CA raiz do certificado ainda nao esta instalada como confiavel nesse host ou container.

Valide o health check.

```bash
curl -k -I https://git.jmsalles.homelab.br/api/healthz
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

ou:

```text
HTTP/2 200
```

Valide a porta SSH do Gitea.

```bash
nc -vz 127.0.0.1 2222
```

Resultado esperado:

```text
succeeded
```

Valide o PostgreSQL do Gitea.

```bash
docker exec gitea-db pg_isready -U gitea -d gitea
```

Resultado esperado:

```text
accepting connections
```

## 5. Criar template do Gitea no Zabbix

No frontend do Zabbix, acesse:

```text
Data collection
Templates
Create template
```

Preencha:

| Campo         | Valor                                                 |
| ------------- | ----------------------------------------------------- |
| Template name | `Template Gitea JMSalles`                             |
| Visible name  | `Monitoramento Gitea JMSalles`                        |
| Groups        | `Templates/Applications`                              |
| Description   | `Monitoramento do Gitea em Docker no host Docker HML` |

Clique em:

```text
Add
```

Depois vincule o template ao host:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Templates
Link new templates
Template Gitea JMSalles
Update
```

## 6. Criar UserParameters do Gitea

No host Docker HML, crie o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/gitea.conf
```

Cole o conteudo abaixo:

```ini
UserParameter=gitea.http.code,curl -k -s -o /dev/null -w "%{http_code}" https://git.jmsalles.homelab.br 2>/dev/null
UserParameter=gitea.health.code,curl -k -s -o /dev/null -w "%{http_code}" https://git.jmsalles.homelab.br/api/healthz 2>/dev/null
UserParameter=gitea.local.code,curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000 2>/dev/null
UserParameter=gitea.ssh.status,nc -z -w 3 127.0.0.1 2222 >/dev/null 2>&1 && printf 1 || printf 0
UserParameter=gitea.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
UserParameter=gitea.container.restart[*],docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null | tr -cd '0-9'
UserParameter=gitea.db.ready,docker exec gitea-db pg_isready -U gitea -d gitea >/dev/null 2>&1 && printf 1 || printf 0
UserParameter=gitea.dir.size,du -sb /home/jmsalles/gitea 2>/dev/null | awk '{print $1}'
```

Observacao:

```text
As chaves gitea.http.code e gitea.health.code usam curl -k.
Isso evita falha por certificado autoassinado ou CA interna nao instalada.
```

Ajuste a permissao.

```bash
sudo chmod 644 /etc/zabbix/zabbix_agent2.d/gitea.conf
```

Reinicie o Zabbix Agent 2.

```bash
sudo systemctl restart zabbix-agent2
```

Valide o status.

```bash
sudo systemctl status zabbix-agent2
```

Valide o log.

```bash
sudo journalctl -u zabbix-agent2 -n 100 --no-pager
```

## 7. Testar os UserParameters localmente

Teste o status HTTPS.

```bash
zabbix_agent2 -t gitea.http.code
```

Resultado esperado:

```text
gitea.http.code [s|200]
```

Teste o health check.

```bash
zabbix_agent2 -t gitea.health.code
```

Resultado esperado:

```text
gitea.health.code [s|200]
```

Teste o HTTP local.

```bash
zabbix_agent2 -t gitea.local.code
```

Resultado esperado:

```text
gitea.local.code [s|200]
```

Teste a porta SSH.

```bash
zabbix_agent2 -t gitea.ssh.status
```

Resultado esperado:

```text
gitea.ssh.status [s|1]
```

Teste o container do Gitea.

```bash
zabbix_agent2 -t 'gitea.container.running[gitea]'
```

Resultado esperado:

```text
gitea.container.running[gitea] [s|1]
```

Teste o container do PostgreSQL.

```bash
zabbix_agent2 -t 'gitea.container.running[gitea-db]'
```

Resultado esperado:

```text
gitea.container.running[gitea-db] [s|1]
```

Teste o restart count do Gitea.

```bash
zabbix_agent2 -t 'gitea.container.restart[gitea]'
```

Resultado esperado:

```text
gitea.container.restart[gitea] [s|0]
```

ou o numero atual de restarts.

Teste o restart count do PostgreSQL.

```bash
zabbix_agent2 -t 'gitea.container.restart[gitea-db]'
```

Resultado esperado:

```text
gitea.container.restart[gitea-db] [s|0]
```

ou o numero atual de restarts.

Teste o PostgreSQL.

```bash
zabbix_agent2 -t gitea.db.ready
```

Resultado esperado:

```text
gitea.db.ready [s|1]
```

Teste o tamanho do diretorio do Gitea.

```bash
zabbix_agent2 -t gitea.dir.size
```

Resultado esperado:

```text
gitea.dir.size [s|VALOR_EM_BYTES]
```

## 8. Criar itens no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Gitea JMSalles
Items
Create item
```

Crie os itens abaixo.

### 8.1 HTTPS do Gitea

| Campo               | Valor                      |
| ------------------- | -------------------------- |
| Name                | `Gitea: HTTPS status code` |
| Type                | `Zabbix agent`             |
| Key                 | `gitea.http.code`          |
| Type of information | `Numeric unsigned`         |
| Update interval     | `1m`                       |
| History             | `31d`                      |
| Trends              | `365d`                     |

### 8.2 Health check do Gitea

| Campo               | Valor                             |
| ------------------- | --------------------------------- |
| Name                | `Gitea: Health check status code` |
| Type                | `Zabbix agent`                    |
| Key                 | `gitea.health.code`               |
| Type of information | `Numeric unsigned`                |
| Update interval     | `1m`                              |
| History             | `31d`                             |
| Trends              | `365d`                            |

### 8.3 HTTP local do Gitea

| Campo               | Valor                           |
| ------------------- | ------------------------------- |
| Name                | `Gitea: HTTP local status code` |
| Type                | `Zabbix agent`                  |
| Key                 | `gitea.local.code`              |
| Type of information | `Numeric unsigned`              |
| Update interval     | `1m`                            |
| History             | `31d`                           |
| Trends              | `365d`                          |

### 8.4 Porta SSH do Gitea

| Campo               | Valor                          |
| ------------------- | ------------------------------ |
| Name                | `Gitea: Porta SSH 2222 status` |
| Type                | `Zabbix agent`                 |
| Key                 | `gitea.ssh.status`             |
| Type of information | `Numeric unsigned`             |
| Update interval     | `1m`                           |
| History             | `31d`                          |
| Trends              | `365d`                         |

### 8.5 Container Gitea rodando

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Gitea: Container gitea rodando` |
| Type                | `Zabbix agent`                   |
| Key                 | `gitea.container.running[gitea]` |
| Type of information | `Numeric unsigned`               |
| Update interval     | `30s`                            |
| History             | `31d`                            |
| Trends              | `365d`                           |

### 8.6 Container PostgreSQL do Gitea rodando

| Campo               | Valor                               |
| ------------------- | ----------------------------------- |
| Name                | `Gitea: Container gitea-db rodando` |
| Type                | `Zabbix agent`                      |
| Key                 | `gitea.container.running[gitea-db]` |
| Type of information | `Numeric unsigned`                  |
| Update interval     | `30s`                               |
| History             | `31d`                               |
| Trends              | `365d`                              |

### 8.7 Restart count do Gitea

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Gitea: Restart count do container gitea` |
| Type                | `Zabbix agent`                            |
| Key                 | `gitea.container.restart[gitea]`          |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `5m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

### 8.8 Restart count do PostgreSQL do Gitea

| Campo               | Valor                                        |
| ------------------- | -------------------------------------------- |
| Name                | `Gitea: Restart count do container gitea-db` |
| Type                | `Zabbix agent`                               |
| Key                 | `gitea.container.restart[gitea-db]`          |
| Type of information | `Numeric unsigned`                           |
| Update interval     | `5m`                                         |
| History             | `31d`                                        |
| Trends              | `365d`                                       |

### 8.9 PostgreSQL do Gitea pronto

| Campo               | Valor                     |
| ------------------- | ------------------------- |
| Name                | `Gitea: PostgreSQL ready` |
| Type                | `Zabbix agent`            |
| Key                 | `gitea.db.ready`          |
| Type of information | `Numeric unsigned`        |
| Update interval     | `1m`                      |
| History             | `31d`                     |
| Trends              | `365d`                    |

### 8.10 Tamanho do diretorio do Gitea

| Campo               | Valor                                              |
| ------------------- | -------------------------------------------------- |
| Name                | `Gitea: Tamanho do diretorio /home/jmsalles/gitea` |
| Type                | `Zabbix agent`                                     |
| Key                 | `gitea.dir.size`                                   |
| Type of information | `Numeric unsigned`                                 |
| Units               | `B`                                                |
| Update interval     | `10m`                                              |
| History             | `31d`                                              |
| Trends              | `365d`                                             |

## 9. Criar check externo da porta 2222

Esse check valida a porta a partir do ponto de vista do Zabbix Server.

No template ou diretamente no host, crie o item:

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Gitea: Porta externa 2222 SSH`           |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,2222]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

## 10. Criar triggers no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Gitea JMSalles
Triggers
Create trigger
```

### 10.1 HTTPS do Gitea indisponivel

| Campo                         | Valor                                                 |
| ----------------------------- | ----------------------------------------------------- |
| Name                          | `Gitea: HTTPS indisponivel`                           |
| Severity                      | `High`                                                |
| Expression                    | `last(/Template Gitea JMSalles/gitea.http.code)<>200` |
| OK event generation           | `Expression`                                          |
| PROBLEM event generation mode | `Single`                                              |
| Enabled                       | Sim                                                   |

### 10.2 Health check do Gitea falhando

| Campo                         | Valor                                                   |
| ----------------------------- | ------------------------------------------------------- |
| Name                          | `Gitea: Health check falhando`                          |
| Severity                      | `High`                                                  |
| Expression                    | `last(/Template Gitea JMSalles/gitea.health.code)<>200` |
| OK event generation           | `Expression`                                            |
| PROBLEM event generation mode | `Single`                                                |
| Enabled                       | Sim                                                     |

### 10.3 HTTP local do Gitea falhando

| Campo                         | Valor                                                  |
| ----------------------------- | ------------------------------------------------------ |
| Name                          | `Gitea: HTTP local falhando`                           |
| Severity                      | `Average`                                              |
| Expression                    | `last(/Template Gitea JMSalles/gitea.local.code)<>200` |
| OK event generation           | `Expression`                                           |
| PROBLEM event generation mode | `Single`                                               |
| Enabled                       | Sim                                                    |

### 10.4 Porta SSH do Gitea indisponivel

| Campo                         | Valor                                               |
| ----------------------------- | --------------------------------------------------- |
| Name                          | `Gitea: Porta SSH 2222 indisponivel`                |
| Severity                      | `Average`                                           |
| Expression                    | `last(/Template Gitea JMSalles/gitea.ssh.status)=0` |
| OK event generation           | `Expression`                                        |
| PROBLEM event generation mode | `Single`                                            |
| Enabled                       | Sim                                                 |

### 10.5 Container Gitea parado

| Campo                         | Valor                                                             |
| ----------------------------- | ----------------------------------------------------------------- |
| Name                          | `Gitea: Container gitea parado`                                   |
| Severity                      | `High`                                                            |
| Expression                    | `last(/Template Gitea JMSalles/gitea.container.running[gitea])=0` |
| OK event generation           | `Expression`                                                      |
| PROBLEM event generation mode | `Single`                                                          |
| Enabled                       | Sim                                                               |

### 10.6 Container PostgreSQL do Gitea parado

| Campo                         | Valor                                                                |
| ----------------------------- | -------------------------------------------------------------------- |
| Name                          | `Gitea: Container gitea-db parado`                                   |
| Severity                      | `High`                                                               |
| Expression                    | `last(/Template Gitea JMSalles/gitea.container.running[gitea-db])=0` |
| OK event generation           | `Expression`                                                         |
| PROBLEM event generation mode | `Single`                                                             |
| Enabled                       | Sim                                                                  |

### 10.7 PostgreSQL do Gitea nao esta pronto

| Campo                         | Valor                                             |
| ----------------------------- | ------------------------------------------------- |
| Name                          | `Gitea: PostgreSQL nao esta pronto`               |
| Severity                      | `High`                                            |
| Expression                    | `last(/Template Gitea JMSalles/gitea.db.ready)=0` |
| OK event generation           | `Expression`                                      |
| PROBLEM event generation mode | `Single`                                          |
| Enabled                       | Sim                                               |

### 10.8 Container Gitea reiniciou recentemente

| Campo                         | Valor                                                               |
| ----------------------------- | ------------------------------------------------------------------- |
| Name                          | `Gitea: Container gitea reiniciou recentemente`                     |
| Severity                      | `Warning`                                                           |
| Expression                    | `change(/Template Gitea JMSalles/gitea.container.restart[gitea])>0` |
| OK event generation           | `Expression`                                                        |
| PROBLEM event generation mode | `Single`                                                            |
| Enabled                       | Sim                                                                 |

### 10.9 Container PostgreSQL do Gitea reiniciou recentemente

| Campo                         | Valor                                                                  |
| ----------------------------- | ---------------------------------------------------------------------- |
| Name                          | `Gitea: Container gitea-db reiniciou recentemente`                     |
| Severity                      | `Warning`                                                              |
| Expression                    | `change(/Template Gitea JMSalles/gitea.container.restart[gitea-db])>0` |
| OK event generation           | `Expression`                                                           |
| PROBLEM event generation mode | `Single`                                                               |
| Enabled                       | Sim                                                                    |

### 10.10 Tamanho do diretorio do Gitea acima de 5 GB

| Campo                         | Valor                                                      |
| ----------------------------- | ---------------------------------------------------------- |
| Name                          | `Gitea: Diretorio /home/jmsalles/gitea acima de 5 GB`      |
| Severity                      | `Warning`                                                  |
| Expression                    | `last(/Template Gitea JMSalles/gitea.dir.size)>5368709120` |
| OK event generation           | `Expression`                                               |
| PROBLEM event generation mode | `Single`                                                   |
| Enabled                       | Opcional                                                   |

Observacao:

```text
5368709120 equivale a 5 GB.
Ajuste conforme o crescimento real dos repositorios.
```

## 11. Criar trigger para check externo da porta 2222

Se o item de Simple check foi criado no template, crie a trigger:

| Campo      | Valor                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Name       | `Gitea: Porta externa 2222 SSH indisponivel`                               |
| Severity   | `Average`                                                                  |
| Expression | `last(/Template Gitea JMSalles/net.tcp.service[tcp,192.168.31.37,2222])=0` |

Se o item foi criado diretamente no host, use a expressao apontando para o host:

```text
last(/docker-hml.jmsalles.homelab.br/net.tcp.service[tcp,192.168.31.37,2222])=0
```

## 12. Criar Web Scenario do Gitea

No Zabbix, acesse:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Web
Create web scenario
```

Preencha:

| Campo           | Valor           |
| --------------- | --------------- |
| Name            | `Gitea - HTTPS` |
| Update interval | `1m`            |
| Attempts        | `3`             |
| Agent           | `Chrome`        |
| Enabled         | Sim             |

Crie o Step 1:

| Campo                 | Valor                             |
| --------------------- | --------------------------------- |
| Name                  | `Gitea Home`                      |
| URL                   | `https://git.jmsalles.homelab.br` |
| Timeout               | `10s`                             |
| Required status codes | `200`                             |

Crie o Step 2:

| Campo                 | Valor                                         |
| --------------------- | --------------------------------------------- |
| Name                  | `Gitea Healthz`                               |
| URL                   | `https://git.jmsalles.homelab.br/api/healthz` |
| Timeout               | `10s`                                         |
| Required status codes | `200`                                         |

Observacao sobre certificado autoassinado:

```text
Como o Zabbix roda em container e a CA raiz ainda nao sera instalada,
o Web Scenario pode falhar caso a validacao SSL esteja habilitada.
```

Neste momento, deixe desmarcado no Web Scenario:

```text
SSL verify peer
SSL verify host
```

Caso futuramente a CA raiz seja instalada no container do Zabbix Server ou Proxy, essas opcoes poderao ser habilitadas.

## 13. Criar trigger do Web Scenario

No host, acesse:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Triggers
Create trigger
```

Crie a trigger:

| Campo                         | Valor                                                                   |
| ----------------------------- | ----------------------------------------------------------------------- |
| Name                          | `Gitea: Web scenario HTTPS falhando`                                    |
| Severity                      | `High`                                                                  |
| Expression                    | `last(/docker-hml.jmsalles.homelab.br/web.test.fail[Gitea - HTTPS])<>0` |
| OK event generation           | `Expression`                                                            |
| PROBLEM event generation mode | `Single`                                                                |
| Enabled                       | Sim                                                                     |

Opcionalmente, crie uma trigger para tempo de resposta alto:

| Campo      | Valor                                                                                  |
| ---------- | -------------------------------------------------------------------------------------- |
| Name       | `Gitea: Tempo de resposta alto`                                                        |
| Severity   | `Warning`                                                                              |
| Expression | `last(/docker-hml.jmsalles.homelab.br/web.test.time[Gitea - HTTPS,Gitea Home,resp])>3` |
| Enabled    | Sim                                                                                    |

Observacao:

```text
O valor 3 representa 3 segundos.
```

## 14. Validar em Latest data

No Zabbix, acesse:

```text
Monitoring
Latest data
```

Use os filtros:

```text
Host: docker-hml.jmsalles.homelab.br
Name: Gitea
```

Voce deve ver itens como:

```text
Gitea: HTTPS status code
Gitea: Health check status code
Gitea: HTTP local status code
Gitea: Porta SSH 2222 status
Gitea: Container gitea rodando
Gitea: Container gitea-db rodando
Gitea: Restart count do container gitea
Gitea: Restart count do container gitea-db
Gitea: PostgreSQL ready
Gitea: Tamanho do diretorio /home/jmsalles/gitea
```

Valores esperados:

| Item                                | Valor esperado |
| ----------------------------------- | -------------- |
| `Gitea: HTTPS status code`          | `200`          |
| `Gitea: Health check status code`   | `200`          |
| `Gitea: HTTP local status code`     | `200`          |
| `Gitea: Porta SSH 2222 status`      | `1`            |
| `Gitea: Container gitea rodando`    | `1`            |
| `Gitea: Container gitea-db rodando` | `1`            |
| `Gitea: PostgreSQL ready`           | `1`            |

## 15. Teste controlado de falha do Gitea

Para testar os alertas, pare somente o container do Gitea.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose stop gitea
```

Teste localmente:

```bash
zabbix_agent2 -t 'gitea.container.running[gitea]'
```

Resultado esperado:

```text
gitea.container.running[gitea] [s|0]
```

Alertas esperados no Zabbix:

```text
Gitea: Container gitea parado
Gitea: HTTPS indisponivel
Gitea: Health check falhando
Gitea: HTTP local falhando
Gitea: Web scenario HTTPS falhando
```

Suba novamente:

```bash
docker compose start gitea
```

Valide:

```bash
docker ps | grep gitea
```

Teste novamente:

```bash
zabbix_agent2 -t 'gitea.container.running[gitea]'
```

Resultado esperado:

```text
gitea.container.running[gitea] [s|1]
```

## 16. Teste controlado de falha do banco

Para testar o alerta do banco, pare o container `gitea-db`.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose stop gitea-db
```

Teste localmente:

```bash
zabbix_agent2 -t 'gitea.container.running[gitea-db]'
```

Resultado esperado:

```text
gitea.container.running[gitea-db] [s|0]
```

Teste o banco:

```bash
zabbix_agent2 -t gitea.db.ready
```

Resultado esperado:

```text
gitea.db.ready [s|0]
```

Alertas esperados:

```text
Gitea: Container gitea-db parado
Gitea: PostgreSQL nao esta pronto
Gitea: Health check falhando
```

Suba novamente:

```bash
docker compose start gitea-db
```

Aguarde alguns segundos e valide:

```bash
docker ps | grep gitea-db
```

Teste novamente:

```bash
zabbix_agent2 -t gitea.db.ready
```

Resultado esperado:

```text
gitea.db.ready [s|1]
```

## 17. Teste com container removido

Se voce usar `docker compose down`, os containers serao removidos.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose down
```

Mesmo assim, os itens customizados devem retornar `0`.

```bash
zabbix_agent2 -t 'gitea.container.running[gitea]'
```

```bash
zabbix_agent2 -t 'gitea.container.running[gitea-db]'
```

Resultado esperado:

```text
[s|0]
```

Para subir novamente:

```bash
docker compose up -d
```

Valide:

```bash
docker ps | egrep 'gitea|gitea-db'
```

## 18. Testar coleta a partir do Zabbix Server

No servidor Zabbix, se tiver `zabbix_get`, teste:

```bash
zabbix_get -s 192.168.31.37 -k gitea.http.code
```

```bash
zabbix_get -s 192.168.31.37 -k gitea.health.code
```

```bash
zabbix_get -s 192.168.31.37 -k 'gitea.container.running[gitea]'
```

```bash
zabbix_get -s 192.168.31.37 -k 'gitea.container.running[gitea-db]'
```

```bash
zabbix_get -s 192.168.31.37 -k gitea.db.ready
```

Resultados esperados:

```text
200
```

ou:

```text
1
```

Para instalar o `zabbix_get`, caso necessario:

```bash
sudo dnf install -y zabbix-get
```

## 19. Troubleshooting

### 19.1 Erro de certificado no curl

Erro:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Causa:

```text
O certificado do Gitea e interno/autoassinado, ou foi assinado por uma CA interna que ainda nao esta instalada como confiavel no host ou container.
```

Contorno adotado neste tutorial:

```bash
curl -k -I https://git.jmsalles.homelab.br
```

Nos UserParameters, o contorno ja esta aplicado:

```ini
UserParameter=gitea.http.code,curl -k -s -o /dev/null -w "%{http_code}" https://git.jmsalles.homelab.br 2>/dev/null
UserParameter=gitea.health.code,curl -k -s -o /dev/null -w "%{http_code}" https://git.jmsalles.homelab.br/api/healthz 2>/dev/null
```

No Web Scenario do Zabbix, enquanto a CA nao for instalada no container do Zabbix, deixe desmarcado:

```text
SSL verify peer
SSL verify host
```

### 19.2 Item retorna erro de tipo no Zabbix

Erro comum:

```text
Value of type "string" is not suitable for value type "Numeric (unsigned)"
```

Causa provavel:

```text
O UserParameter esta retornando valor com quebra de linha ou texto indevido.
```

Valide o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/gitea.conf
```

Garanta que a linha do container esteja assim:

```ini
UserParameter=gitea.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Reinicie:

```bash
sudo systemctl restart zabbix-agent2
```

Teste:

```bash
zabbix_agent2 -t 'gitea.container.running[gitea]'
```

### 19.3 Container esta rodando, mas item retorna 0

Valide o Docker puro:

```bash
docker inspect -f '{{.State.Running}}' gitea
```

Resultado esperado:

```text
true
```

Teste o comando completo:

```bash
docker inspect -f '{{.State.Running}}' "gitea" 2>/dev/null | grep -qx true && printf 1 || printf 0
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
zabbix_agent2 -t 'gitea.container.running[gitea]'
```

### 19.4 Zabbix nao consegue consultar Docker

Teste com o usuario `zabbix`.

```bash
sudo -u zabbix docker ps
```

Se falhar, adicione ao grupo `docker`.

```bash
sudo usermod -aG docker zabbix
```

Reinicie o Agent.

```bash
sudo systemctl restart zabbix-agent2
```

Teste novamente.

```bash
sudo -u zabbix docker ps
```

### 19.5 HTTPS do Gitea retorna diferente de 200

Teste manualmente com `-k`.

```bash
curl -k -I https://git.jmsalles.homelab.br
```

Valide o Nginx reverse proxy.

```bash
cd /home/jmsalles/nginx
```

```bash
docker compose ps
```

```bash
docker compose logs --tail=100 nginx
```

Valide a configuracao.

```bash
docker compose exec nginx nginx -t
```

Recarregue, se necessario.

```bash
docker compose exec nginx nginx -s reload
```

### 19.6 Health check retorna diferente de 200

Teste manualmente.

```bash
curl -k -v https://git.jmsalles.homelab.br/api/healthz
```

Valide o Gitea.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose ps
```

```bash
docker compose logs --tail=100 gitea
```

### 19.7 PostgreSQL ready retorna 0

Teste direto no container.

```bash
docker exec gitea-db pg_isready -U gitea -d gitea
```

Valide logs do banco.

```bash
cd /home/jmsalles/gitea
```

```bash
docker compose logs --tail=100 gitea-db
```

Valide se o container esta rodando.

```bash
docker ps | grep gitea-db
```

## 20. Checklist final

| Item                                                        | Status   |
| ----------------------------------------------------------- | -------- |
| Template `Template Gitea JMSalles` criado                   | Pendente |
| Template vinculado ao host `docker-hml.jmsalles.homelab.br` | Pendente |
| Arquivo `/etc/zabbix/zabbix_agent2.d/gitea.conf` criado     | Pendente |
| UserParameters testados localmente                          | Pendente |
| Item HTTPS criado                                           | Pendente |
| Item health check criado                                    | Pendente |
| Item HTTP local criado                                      | Pendente |
| Item porta SSH criado                                       | Pendente |
| Item container `gitea` criado                               | Pendente |
| Item container `gitea-db` criado                            | Pendente |
| Item PostgreSQL ready criado                                | Pendente |
| Triggers criadas                                            | Pendente |
| Web Scenario criado                                         | Pendente |
| Validacao SSL desabilitada no Web Scenario                  | Pendente |
| Teste de parada do Gitea validado                           | Pendente |
| Teste de parada do banco validado                           | Pendente |

## 21. Resumo final

O monitoramento do Gitea ficara dividido em quatro camadas:

```text
Disponibilidade externa
|
HTTPS
/api/healthz
Web Scenario
```

```text
Servico local
|
HTTP 3000
SSH 2222
```

```text
Containers
|
gitea
gitea-db
restart count
```

```text
Banco
|
PostgreSQL ready
```

Os principais itens customizados sao:

```text
gitea.container.running[gitea]
gitea.container.running[gitea-db]
gitea.db.ready
gitea.health.code
gitea.http.code
```

Como o certificado e interno/autoassinado, este tutorial usa `curl -k` nos UserParameters e recomenda deixar `SSL verify peer` e `SSL verify host` desmarcados no Web Scenario ate que a CA raiz seja instalada no container do Zabbix.

Com esse modelo, o Zabbix consegue identificar se a falha esta no Gitea, no banco PostgreSQL, no proxy reverso, na porta SSH, na publicacao HTTPS ou apenas na validacao do certificado.

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
