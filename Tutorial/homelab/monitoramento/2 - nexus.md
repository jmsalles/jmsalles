Segue o tutorial completo revisado, **sem o endpoint `/service/rest/v1/status/check`**, pois no seu ambiente ele retornou `403` sem autenticação.

# Guia de monitoramento do Nexus no Zabbix

## 1. Objetivo

Este documento descreve como monitorar o Nexus Repository instalado em Docker no host físico Docker HML.

O monitoramento será feito no Zabbix existente da rede, utilizando o Zabbix Agent 2 instalado no host:

```text
docker-hml.jmsalles.homelab.br
```

Nesta etapa, o foco será apenas no Nexus Repository e no registry Docker publicado pelo Nexus.

Não serão monitorados neste documento:

```text
Gitea
Vault
Runner
Backups
Outras aplicações
```

Observação importante:

```text
O endpoint /service/rest/v1/status/check foi removido deste tutorial porque no ambiente retornou HTTP 403 sem autenticação.
O monitoramento de saúde principal será feito pelo endpoint /service/rest/v1/status.
```

---

## 2. Dados do ambiente

| Item                   | Valor                                  |
| ---------------------- | -------------------------------------- |
| Host Docker HML        | `docker-hml.jmsalles.homelab.br`       |
| IP do host             | `192.168.31.37`                        |
| URL da interface web   | `https://nexus.jmsalles.homelab.br`    |
| URL do registry Docker | `https://registry.jmsalles.homelab.br` |
| Container              | `nexus`                                |
| Porta web local        | `8081`                                 |
| Porta Docker group     | `5000`                                 |
| Porta Docker hosted    | `5001`                                 |
| Porta Docker proxy     | `5002`                                 |
| Diretório base         | `/home/jmsalles/nexus`                 |
| Diretório de dados     | `/home/jmsalles/nexus/nexus-data`      |
| Proxy reverso          | Nginx em Docker                        |
| Zabbix Agent           | Zabbix Agent 2                         |

---

## 3. Observação sobre certificado interno

O ambiente utiliza certificado interno ou autoassinado.

Por esse motivo, os testes via `curl` no Zabbix Agent usarão a opção `-k`.

Essa opção ignora a validação da cadeia de certificado.

Caso apareça o erro abaixo em testes manuais com `curl` sem `-k`, o problema está relacionado à cadeia do certificado não estar instalada como confiável no Linux ou no container do Zabbix.

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Neste momento, não será feita a instalação da CA raiz. O monitoramento seguirá usando `curl -k`.

---

## 4. O que será monitorado

| Camada     | Monitoramento                                |
| ---------- | -------------------------------------------- |
| Aplicação  | HTTPS da interface web do Nexus              |
| Aplicação  | Status API do Nexus                          |
| Aplicação  | HTTP local na porta `8081`                   |
| Registry   | HTTPS do `registry.jmsalles.homelab.br/v2/`  |
| Registry   | HTTP local na porta `5001`                   |
| Portas     | `8081`, `5000`, `5001`, `5002`               |
| Container  | Container `nexus` rodando                    |
| Container  | Restart count do container `nexus`           |
| Capacidade | Tamanho de `/home/jmsalles/nexus`            |
| Capacidade | Tamanho de `/home/jmsalles/nexus/nexus-data` |
| Logs       | Tamanho dos logs do Nexus                    |
| Web        | Web Scenario da interface web                |
| Web        | Web Scenario do registry                     |

Observação:

```text
Os itens de tamanho de diretório, logs e blobs serão criados apenas para consulta em Latest data.
Neste momento, não serão criadas triggers de capacidade para esses itens.
```

---

## 5. Validar o Nexus manualmente

Acesse o host Docker HML.

```bash
ssh jmsalles@192.168.31.37
```

Valide o container.

```bash
docker ps | grep nexus
```

Valide o compose.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose ps
```

Valide a porta web local.

```bash
curl -I http://127.0.0.1:8081
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Valide a interface web pelo Nginx.

```bash
curl -k -I https://nexus.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Valide a Status API do Nexus.

```bash
curl -k -I https://nexus.jmsalles.homelab.br/service/rest/v1/status
```

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Não usaremos o endpoint abaixo neste tutorial:

```text
https://nexus.jmsalles.homelab.br/service/rest/v1/status/check
```

Motivo:

```text
No ambiente atual, ele retornou HTTP 403 sem autenticação.
```

Valide o registry pelo Nginx.

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Resultado esperado:

```text
HTTP/1.1 401 Unauthorized
```

Esse retorno é normal. Ele indica que o registry respondeu, mas exige autenticação.

Valide a porta local do `docker-hosted`.

```bash
curl -I http://127.0.0.1:5001/v2/
```

Resultado esperado:

```text
HTTP/1.1 401 Unauthorized
```

Valide as portas locais.

```bash
ss -lntp | egrep '8081|5000|5001|5002'
```

---

## 6. Validar permissão do Zabbix para consultar Docker

O usuário `zabbix` precisa conseguir consultar o Docker.

Teste:

```bash
sudo -u zabbix docker ps
```

Se listar os containers, está correto.

Se falhar, adicione o usuário `zabbix` ao grupo `docker`.

```bash
sudo usermod -aG docker zabbix
```

Reinicie o Zabbix Agent 2.

```bash
sudo systemctl restart zabbix-agent2
```

Teste novamente.

```bash
sudo -u zabbix docker ps
```

---

## 7. Criar template do Nexus no Zabbix

No frontend do Zabbix, acesse:

```text
Data collection
Templates
Create template
```

Preencha:

| Campo         | Valor                                                            |
| ------------- | ---------------------------------------------------------------- |
| Template name | `Template Nexus JMSalles`                                        |
| Visible name  | `Monitoramento Nexus JMSalles`                                   |
| Groups        | `Templates/Applications`                                         |
| Description   | `Monitoramento do Nexus Repository em Docker no host Docker HML` |

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
Template Nexus JMSalles
Update
```

---

## 8. Criar UserParameters do Nexus

No host Docker HML, crie o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/nexus.conf
```

Cole o conteúdo abaixo:

```ini
UserParameter=nexus.http.code,curl -k -s -o /dev/null -w "%{http_code}" https://nexus.jmsalles.homelab.br 2>/dev/null
UserParameter=nexus.status.code,curl -k -s -o /dev/null -w "%{http_code}" https://nexus.jmsalles.homelab.br/service/rest/v1/status 2>/dev/null
UserParameter=nexus.local.code,curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8081 2>/dev/null
UserParameter=nexus.registry.code,curl -k -s -o /dev/null -w "%{http_code}" https://registry.jmsalles.homelab.br/v2/ 2>/dev/null
UserParameter=nexus.registry.local.code,curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5001/v2/ 2>/dev/null
UserParameter=nexus.tcp.local[*],nc -z -w 3 127.0.0.1 $1 >/dev/null 2>&1 && printf 1 || printf 0
UserParameter=nexus.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
UserParameter=nexus.container.restart[*],v=$(docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null); if echo "$v" | grep -Eq '^[0-9]+$'; then printf "%s" "$v"; else printf 0; fi
UserParameter=nexus.dir.size,du -sb /home/jmsalles/nexus 2>/dev/null | cut -f1
UserParameter=nexus.data.size,du -sb /home/jmsalles/nexus/nexus-data 2>/dev/null | cut -f1
UserParameter=nexus.logs.size,du -sb /home/jmsalles/nexus/nexus-data/log 2>/dev/null | cut -f1
UserParameter=nexus.blobs.size,du -sb /home/jmsalles/nexus/nexus-data/blobs 2>/dev/null | cut -f1
```

Observações importantes:

```text
As chaves nexus.http.code, nexus.status.code e nexus.registry.code usam curl -k.
Isso evita falha por certificado autoassinado ou CA interna não instalada.
```

A linha abaixo retorna `1` quando o container está rodando e `0` quando está parado ou removido.

```ini
UserParameter=nexus.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Caso o comando `nc` não exista, instale o pacote:

```bash
sudo dnf install -y nmap-ncat
```

Ajuste a permissão.

```bash
sudo chmod 644 /etc/zabbix/zabbix_agent2.d/nexus.conf
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

---

## 9. Testar os UserParameters localmente

Teste a interface HTTPS.

```bash
zabbix_agent2 -t nexus.http.code
```

Resultado esperado:

```text
nexus.http.code [s|200]
```

Teste a Status API.

```bash
zabbix_agent2 -t nexus.status.code
```

Resultado esperado:

```text
nexus.status.code [s|200]
```

Teste o HTTP local.

```bash
zabbix_agent2 -t nexus.local.code
```

Resultado esperado:

```text
nexus.local.code [s|200]
```

Teste o registry HTTPS.

```bash
zabbix_agent2 -t nexus.registry.code
```

Resultado esperado:

```text
nexus.registry.code [s|401]
```

Teste o registry local.

```bash
zabbix_agent2 -t nexus.registry.local.code
```

Resultado esperado:

```text
nexus.registry.local.code [s|401]
```

Teste a porta local `8081`.

```bash
zabbix_agent2 -t 'nexus.tcp.local[8081]'
```

Resultado esperado:

```text
nexus.tcp.local[8081] [s|1]
```

Teste a porta local `5001`.

```bash
zabbix_agent2 -t 'nexus.tcp.local[5001]'
```

Resultado esperado:

```text
nexus.tcp.local[5001] [s|1]
```

Teste a porta local `5000`.

```bash
zabbix_agent2 -t 'nexus.tcp.local[5000]'
```

Resultado esperado:

```text
nexus.tcp.local[5000] [s|1]
```

Teste a porta local `5002`.

```bash
zabbix_agent2 -t 'nexus.tcp.local[5002]'
```

Resultado esperado:

```text
nexus.tcp.local[5002] [s|1]
```

Teste o container.

```bash
zabbix_agent2 -t 'nexus.container.running[nexus]'
```

Resultado esperado:

```text
nexus.container.running[nexus] [s|1]
```

Teste o restart count.

```bash
zabbix_agent2 -t 'nexus.container.restart[nexus]'
```

Resultado esperado:

```text
nexus.container.restart[nexus] [s|0]
```

ou o número atual de restarts.

Teste o tamanho do diretório base.

```bash
zabbix_agent2 -t nexus.dir.size
```

Teste o tamanho do diretório de dados.

```bash
zabbix_agent2 -t nexus.data.size
```

Teste o tamanho dos logs.

```bash
zabbix_agent2 -t nexus.logs.size
```

Teste o tamanho dos blobs.

```bash
zabbix_agent2 -t nexus.blobs.size
```

---

## 10. Criar itens no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Nexus JMSalles
Items
Create item
```

Crie os itens abaixo.

---

## 10.1 HTTPS da interface web

| Campo               | Valor                      |
| ------------------- | -------------------------- |
| Name                | `Nexus: HTTPS status code` |
| Type                | `Zabbix agent`             |
| Key                 | `nexus.http.code`          |
| Type of information | `Numeric unsigned`         |
| Update interval     | `1m`                       |
| History             | `31d`                      |
| Trends              | `365d`                     |

---

## 10.2 Status API

| Campo               | Valor                    |
| ------------------- | ------------------------ |
| Name                | `Nexus: Status API code` |
| Type                | `Zabbix agent`           |
| Key                 | `nexus.status.code`      |
| Type of information | `Numeric unsigned`       |
| Update interval     | `1m`                     |
| History             | `31d`                    |
| Trends              | `365d`                   |

---

## 10.3 HTTP local da interface web

| Campo               | Valor                                |
| ------------------- | ------------------------------------ |
| Name                | `Nexus: HTTP local 8081 status code` |
| Type                | `Zabbix agent`                       |
| Key                 | `nexus.local.code`                   |
| Type of information | `Numeric unsigned`                   |
| Update interval     | `1m`                                 |
| History             | `31d`                                |
| Trends              | `365d`                               |

---

## 10.4 Registry HTTPS status code

| Campo               | Valor                                   |
| ------------------- | --------------------------------------- |
| Name                | `Nexus: Registry HTTPS /v2 status code` |
| Type                | `Zabbix agent`                          |
| Key                 | `nexus.registry.code`                   |
| Type of information | `Numeric unsigned`                      |
| Update interval     | `1m`                                    |
| History             | `31d`                                   |
| Trends              | `365d`                                  |

---

## 10.5 Registry local status code

| Campo               | Valor                                        |
| ------------------- | -------------------------------------------- |
| Name                | `Nexus: Registry local 5001 /v2 status code` |
| Type                | `Zabbix agent`                               |
| Key                 | `nexus.registry.local.code`                  |
| Type of information | `Numeric unsigned`                           |
| Update interval     | `1m`                                         |
| History             | `31d`                                        |
| Trends              | `365d`                                       |

---

## 10.6 Porta local 8081

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Nexus: Porta local 8081 status` |
| Type                | `Zabbix agent`                   |
| Key                 | `nexus.tcp.local[8081]`          |
| Type of information | `Numeric unsigned`               |
| Update interval     | `1m`                             |
| History             | `31d`                            |
| Trends              | `365d`                           |

---

## 10.7 Porta local 5001

| Campo               | Valor                                          |
| ------------------- | ---------------------------------------------- |
| Name                | `Nexus: Porta local 5001 docker-hosted status` |
| Type                | `Zabbix agent`                                 |
| Key                 | `nexus.tcp.local[5001]`                        |
| Type of information | `Numeric unsigned`                             |
| Update interval     | `1m`                                           |
| History             | `31d`                                          |
| Trends              | `365d`                                         |

---

## 10.8 Porta local 5000

| Campo               | Valor                                         |
| ------------------- | --------------------------------------------- |
| Name                | `Nexus: Porta local 5000 docker-group status` |
| Type                | `Zabbix agent`                                |
| Key                 | `nexus.tcp.local[5000]`                       |
| Type of information | `Numeric unsigned`                            |
| Update interval     | `1m`                                          |
| History             | `31d`                                         |
| Trends              | `365d`                                        |

---

## 10.9 Porta local 5002

| Campo               | Valor                                         |
| ------------------- | --------------------------------------------- |
| Name                | `Nexus: Porta local 5002 docker-proxy status` |
| Type                | `Zabbix agent`                                |
| Key                 | `nexus.tcp.local[5002]`                       |
| Type of information | `Numeric unsigned`                            |
| Update interval     | `1m`                                          |
| History             | `31d`                                         |
| Trends              | `365d`                                        |

---

## 10.10 Container Nexus rodando

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Nexus: Container nexus rodando` |
| Type                | `Zabbix agent`                   |
| Key                 | `nexus.container.running[nexus]` |
| Type of information | `Numeric unsigned`               |
| Update interval     | `30s`                            |
| History             | `31d`                            |
| Trends              | `365d`                           |

---

## 10.11 Restart count do Nexus

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Nexus: Restart count do container nexus` |
| Type                | `Zabbix agent`                            |
| Key                 | `nexus.container.restart[nexus]`          |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `5m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

---

## 10.12 Tamanho do diretório base

| Campo               | Valor                                              |
| ------------------- | -------------------------------------------------- |
| Name                | `Nexus: Tamanho do diretorio /home/jmsalles/nexus` |
| Type                | `Zabbix agent`                                     |
| Key                 | `nexus.dir.size`                                   |
| Type of information | `Numeric unsigned`                                 |
| Units               | `B`                                                |
| Update interval     | `10m`                                              |
| History             | `31d`                                              |
| Trends              | `365d`                                             |

---

## 10.13 Tamanho do nexus-data

| Campo               | Valor                                    |
| ------------------- | ---------------------------------------- |
| Name                | `Nexus: Tamanho do diretorio nexus-data` |
| Type                | `Zabbix agent`                           |
| Key                 | `nexus.data.size`                        |
| Type of information | `Numeric unsigned`                       |
| Units               | `B`                                      |
| Update interval     | `10m`                                    |
| History             | `31d`                                    |
| Trends              | `365d`                                   |

---

## 10.14 Tamanho dos logs

| Campo               | Valor                     |
| ------------------- | ------------------------- |
| Name                | `Nexus: Tamanho dos logs` |
| Type                | `Zabbix agent`            |
| Key                 | `nexus.logs.size`         |
| Type of information | `Numeric unsigned`        |
| Units               | `B`                       |
| Update interval     | `10m`                     |
| History             | `31d`                     |
| Trends              | `365d`                    |

---

## 10.15 Tamanho dos blobs

| Campo               | Valor                      |
| ------------------- | -------------------------- |
| Name                | `Nexus: Tamanho dos blobs` |
| Type                | `Zabbix agent`             |
| Key                 | `nexus.blobs.size`         |
| Type of information | `Numeric unsigned`         |
| Units               | `B`                        |
| Update interval     | `10m`                      |
| History             | `31d`                      |
| Trends              | `365d`                     |

Observação:

```text
Os itens 10.12, 10.13, 10.14 e 10.15 serão usados apenas para consulta e acompanhamento em Latest data.
Não criaremos triggers de capacidade para esses itens neste momento.
```

---

## 11. Criar checks externos de porta

Esses checks validam as portas a partir do ponto de vista do Zabbix Server.

No template ou diretamente no host, crie os itens abaixo.

---

## 11.1 Porta externa 8081

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Nexus: Porta externa 8081`               |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,8081]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

---

## 11.2 Porta externa 5001

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Nexus: Porta externa 5001 docker-hosted` |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,5001]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

---

## 11.3 Porta externa 5000

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Nexus: Porta externa 5000 docker-group`  |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,5000]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

---

## 11.4 Porta externa 5002

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Nexus: Porta externa 5002 docker-proxy`  |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,5002]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

---

## 12. Criar triggers no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Nexus JMSalles
Triggers
Create trigger
```

---

## 12.1 HTTPS do Nexus indisponível

| Campo                         | Valor                                                 |
| ----------------------------- | ----------------------------------------------------- |
| Name                          | `Nexus: HTTPS indisponivel`                           |
| Severity                      | `High`                                                |
| Expression                    | `last(/Template Nexus JMSalles/nexus.http.code)<>200` |
| OK event generation           | `Expression`                                          |
| PROBLEM event generation mode | `Single`                                              |
| Enabled                       | Sim                                                   |

---

## 12.2 Status API falhando

| Campo                         | Valor                                                   |
| ----------------------------- | ------------------------------------------------------- |
| Name                          | `Nexus: Status API falhando`                            |
| Severity                      | `High`                                                  |
| Expression                    | `last(/Template Nexus JMSalles/nexus.status.code)<>200` |
| OK event generation           | `Expression`                                            |
| PROBLEM event generation mode | `Single`                                                |
| Enabled                       | Sim                                                     |

---

## 12.3 HTTP local 8081 falhando

| Campo                         | Valor                                                  |
| ----------------------------- | ------------------------------------------------------ |
| Name                          | `Nexus: HTTP local 8081 falhando`                      |
| Severity                      | `High`                                                 |
| Expression                    | `last(/Template Nexus JMSalles/nexus.local.code)<>200` |
| OK event generation           | `Expression`                                           |
| PROBLEM event generation mode | `Single`                                               |
| Enabled                       | Sim                                                    |

---

## 12.4 Registry HTTPS falhando

| Campo                         | Valor                                                                                                                 |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Name                          | `Nexus: Registry HTTPS /v2 falhando`                                                                                  |
| Severity                      | `High`                                                                                                                |
| Expression                    | `last(/Template Nexus JMSalles/nexus.registry.code)<>401 and last(/Template Nexus JMSalles/nexus.registry.code)<>200` |
| OK event generation           | `Expression`                                                                                                          |
| PROBLEM event generation mode | `Single`                                                                                                              |
| Enabled                       | Sim                                                                                                                   |

Observação:

```text
O código 401 é esperado quando o registry está ativo e exige autenticação.
```

---

## 12.5 Registry local 5001 falhando

| Campo                         | Valor                                                                                                                             |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Name                          | `Nexus: Registry local 5001 /v2 falhando`                                                                                         |
| Severity                      | `Average`                                                                                                                         |
| Expression                    | `last(/Template Nexus JMSalles/nexus.registry.local.code)<>401 and last(/Template Nexus JMSalles/nexus.registry.local.code)<>200` |
| OK event generation           | `Expression`                                                                                                                      |
| PROBLEM event generation mode | `Single`                                                                                                                          |
| Enabled                       | Sim                                                                                                                               |

---

## 12.6 Porta local 8081 indisponível

| Campo                         | Valor                                                    |
| ----------------------------- | -------------------------------------------------------- |
| Name                          | `Nexus: Porta local 8081 indisponivel`                   |
| Severity                      | `High`                                                   |
| Expression                    | `last(/Template Nexus JMSalles/nexus.tcp.local[8081])=0` |
| OK event generation           | `Expression`                                             |
| PROBLEM event generation mode | `Single`                                                 |
| Enabled                       | Sim                                                      |

---

## 12.7 Porta local 5001 indisponível

| Campo                         | Valor                                                    |
| ----------------------------- | -------------------------------------------------------- |
| Name                          | `Nexus: Porta local 5001 docker-hosted indisponivel`     |
| Severity                      | `High`                                                   |
| Expression                    | `last(/Template Nexus JMSalles/nexus.tcp.local[5001])=0` |
| OK event generation           | `Expression`                                             |
| PROBLEM event generation mode | `Single`                                                 |
| Enabled                       | Sim                                                      |

---

## 12.8 Porta local 5000 indisponível

| Campo                         | Valor                                                    |
| ----------------------------- | -------------------------------------------------------- |
| Name                          | `Nexus: Porta local 5000 docker-group indisponivel`      |
| Severity                      | `Warning`                                                |
| Expression                    | `last(/Template Nexus JMSalles/nexus.tcp.local[5000])=0` |
| OK event generation           | `Expression`                                             |
| PROBLEM event generation mode | `Single`                                                 |
| Enabled                       | Opcional                                                 |

---

## 12.9 Porta local 5002 indisponível

| Campo                         | Valor                                                    |
| ----------------------------- | -------------------------------------------------------- |
| Name                          | `Nexus: Porta local 5002 docker-proxy indisponivel`      |
| Severity                      | `Warning`                                                |
| Expression                    | `last(/Template Nexus JMSalles/nexus.tcp.local[5002])=0` |
| OK event generation           | `Expression`                                             |
| PROBLEM event generation mode | `Single`                                                 |
| Enabled                       | Opcional                                                 |

---

## 12.10 Container Nexus parado

| Campo                         | Valor                                                             |
| ----------------------------- | ----------------------------------------------------------------- |
| Name                          | `Nexus: Container nexus parado`                                   |
| Severity                      | `High`                                                            |
| Expression                    | `last(/Template Nexus JMSalles/nexus.container.running[nexus])=0` |
| OK event generation           | `Expression`                                                      |
| PROBLEM event generation mode | `Single`                                                          |
| Enabled                       | Sim                                                               |

---

## 12.11 Container Nexus reiniciou recentemente

| Campo                         | Valor                                                               |
| ----------------------------- | ------------------------------------------------------------------- |
| Name                          | `Nexus: Container nexus reiniciou recentemente`                     |
| Severity                      | `Warning`                                                           |
| Expression                    | `change(/Template Nexus JMSalles/nexus.container.restart[nexus])>0` |
| OK event generation           | `Expression`                                                        |
| PROBLEM event generation mode | `Single`                                                            |
| Enabled                       | Sim                                                                 |

---

## 13. Criar triggers para checks externos de porta

Se os itens de Simple check foram criados no template, crie as triggers abaixo.

---

## 13.1 Porta externa 8081 indisponível

| Campo      | Valor                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Name       | `Nexus: Porta externa 8081 indisponivel`                                   |
| Severity   | `Average`                                                                  |
| Expression | `last(/Template Nexus JMSalles/net.tcp.service[tcp,192.168.31.37,8081])=0` |

---

## 13.2 Porta externa 5001 indisponível

| Campo      | Valor                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Name       | `Nexus: Porta externa 5001 docker-hosted indisponivel`                     |
| Severity   | `High`                                                                     |
| Expression | `last(/Template Nexus JMSalles/net.tcp.service[tcp,192.168.31.37,5001])=0` |

---

## 13.3 Porta externa 5000 indisponível

| Campo      | Valor                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Name       | `Nexus: Porta externa 5000 docker-group indisponivel`                      |
| Severity   | `Warning`                                                                  |
| Expression | `last(/Template Nexus JMSalles/net.tcp.service[tcp,192.168.31.37,5000])=0` |

---

## 13.4 Porta externa 5002 indisponível

| Campo      | Valor                                                                      |
| ---------- | -------------------------------------------------------------------------- |
| Name       | `Nexus: Porta externa 5002 docker-proxy indisponivel`                      |
| Severity   | `Warning`                                                                  |
| Expression | `last(/Template Nexus JMSalles/net.tcp.service[tcp,192.168.31.37,5002])=0` |

---

## 14. Criar Web Scenario da interface web do Nexus

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
| Name            | `Nexus - HTTPS` |
| Update interval | `1m`            |
| Attempts        | `3`             |
| Agent           | `Chrome`        |
| Enabled         | Sim             |

Crie o Step 1:

| Campo                 | Valor                               |
| --------------------- | ----------------------------------- |
| Name                  | `Nexus Home`                        |
| URL                   | `https://nexus.jmsalles.homelab.br` |
| Timeout               | `10s`                               |
| Required status codes | `200`                               |

Crie o Step 2:

| Campo                 | Valor                                                      |
| --------------------- | ---------------------------------------------------------- |
| Name                  | `Nexus Status`                                             |
| URL                   | `https://nexus.jmsalles.homelab.br/service/rest/v1/status` |
| Timeout               | `10s`                                                      |
| Required status codes | `200`                                                      |

Não crie step para:

```text
https://nexus.jmsalles.homelab.br/service/rest/v1/status/check
```

Motivo:

```text
Esse endpoint retornou HTTP 403 no ambiente sem autenticação.
```

Observação sobre certificado autoassinado:

```text
Como o Zabbix roda em container e a CA raiz ainda não será instalada,
o Web Scenario pode falhar caso a validação SSL esteja habilitada.
```

Neste momento, deixe desmarcado no Web Scenario:

```text
SSL verify peer
SSL verify host
```

---

## 15. Criar trigger do Web Scenario da interface web

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
| Name                          | `Nexus: Web scenario HTTPS falhando`                                    |
| Severity                      | `High`                                                                  |
| Expression                    | `last(/docker-hml.jmsalles.homelab.br/web.test.fail[Nexus - HTTPS])<>0` |
| OK event generation           | `Expression`                                                            |
| PROBLEM event generation mode | `Single`                                                                |
| Enabled                       | Sim                                                                     |

Opcionalmente, crie uma trigger para tempo de resposta alto:

| Campo      | Valor                                                                                  |
| ---------- | -------------------------------------------------------------------------------------- |
| Name       | `Nexus: Tempo de resposta alto`                                                        |
| Severity   | `Warning`                                                                              |
| Expression | `last(/docker-hml.jmsalles.homelab.br/web.test.time[Nexus - HTTPS,Nexus Home,resp])>5` |
| Enabled    | Sim                                                                                    |

Observação:

```text
O valor 5 representa 5 segundos.
Como o Nexus usa Java e pode demorar mais para responder em momentos de carga, esse limite pode ser ajustado depois.
```

---

## 16. Criar Web Scenario do registry

No Zabbix, acesse:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Web
Create web scenario
```

Preencha:

| Campo           | Valor                    |
| --------------- | ------------------------ |
| Name            | `Nexus Registry - HTTPS` |
| Update interval | `1m`                     |
| Attempts        | `3`                      |
| Agent           | `Chrome`                 |
| Enabled         | Sim                      |

Crie o Step 1:

| Campo                 | Valor                                      |
| --------------------- | ------------------------------------------ |
| Name                  | `Registry V2`                              |
| URL                   | `https://registry.jmsalles.homelab.br/v2/` |
| Timeout               | `10s`                                      |
| Required status codes | `401`                                      |

Observação:

```text
O código 401 é esperado porque o registry está ativo e exigindo autenticação.
```

Deixe desmarcado:

```text
SSL verify peer
SSL verify host
```

---

## 17. Criar trigger do Web Scenario do registry

No host, acesse:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Triggers
Create trigger
```

Crie a trigger:

| Campo                         | Valor                                                                            |
| ----------------------------- | -------------------------------------------------------------------------------- |
| Name                          | `https://registry.jmsalles.homelab.br/v2/`                                    |
| Severity                      | `High`                                                                           |
| Expression                    | `last(/docker-hml.jmsalles.homelab.br/web.test.fail[Nexus Registry - HTTPS])<>0` |
| OK event generation           | `Expression`                                                                     |
| PROBLEM event generation mode | `Single`                                                                         |
| Enabled                       | Sim                                                                              |

---

## 18. Validar em Latest data

No Zabbix, acesse:

```text
Monitoring
Latest data
```

Use os filtros:

```text
Host: docker-hml.jmsalles.homelab.br
Name: Nexus
```

Você deve ver itens como:

```text
Nexus: HTTPS status code
Nexus: Status API code
Nexus: HTTP local 8081 status code
Nexus: Registry HTTPS /v2 status code
Nexus: Registry local 5001 /v2 status code
Nexus: Porta local 8081 status
Nexus: Porta local 5001 docker-hosted status
Nexus: Container nexus rodando
Nexus: Restart count do container nexus
Nexus: Tamanho do diretorio nexus-data
Nexus: Tamanho dos logs
Nexus: Tamanho dos blobs
```

Valores esperados:

| Item                                           | Valor esperado |
| ---------------------------------------------- | -------------- |
| `Nexus: HTTPS status code`                     | `200`          |
| `Nexus: Status API code`                       | `200`          |
| `Nexus: HTTP local 8081 status code`           | `200`          |
| `Nexus: Registry HTTPS /v2 status code`        | `401`          |
| `Nexus: Registry local 5001 /v2 status code`   | `401`          |
| `Nexus: Porta local 8081 status`               | `1`            |
| `Nexus: Porta local 5001 docker-hosted status` | `1`            |
| `Nexus: Container nexus rodando`               | `1`            |

---

## 19. Teste controlado de falha do Nexus

Para testar os alertas, pare somente o container do Nexus.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose stop nexus
```

Teste localmente:

```bash
zabbix_agent2 -t 'nexus.container.running[nexus]'
```

Resultado esperado:

```text
nexus.container.running[nexus] [s|0]
```

Alertas esperados no Zabbix:

```text
Nexus: Container nexus parado
Nexus: HTTPS indisponivel
Nexus: Status API falhando
Nexus: HTTP local 8081 falhando
Nexus: Registry HTTPS /v2 falhando
Nexus: Porta local 8081 indisponivel
Nexus: Porta local 5001 docker-hosted indisponivel
Nexus: Web scenario HTTPS falhando
Nexus: Web scenario Registry HTTPS falhando
```

Suba novamente.

```bash
docker compose start nexus
```

Valide.

```bash
docker ps | grep nexus
```

Teste novamente.

```bash
zabbix_agent2 -t 'nexus.container.running[nexus]'
```

Resultado esperado:

```text
nexus.container.running[nexus] [s|1]
```

---

## 20. Teste com container removido

Se você usar `docker compose down`, o container será removido.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose down
```

Mesmo assim, o item customizado deve retornar `0`.

```bash
zabbix_agent2 -t 'nexus.container.running[nexus]'
```

Resultado esperado:

```text
nexus.container.running[nexus] [s|0]
```

Para subir novamente:

```bash
docker compose up -d
```

Valide:

```bash
docker ps | grep nexus
```

---

## 21. Testar coleta a partir do Zabbix Server

No servidor Zabbix, se tiver `zabbix_get`, teste:

```bash
zabbix_get -s 192.168.31.37 -k nexus.http.code
```

```bash
zabbix_get -s 192.168.31.37 -k nexus.status.code
```

```bash
zabbix_get -s 192.168.31.37 -k nexus.registry.code
```

```bash
zabbix_get -s 192.168.31.37 -k 'nexus.container.running[nexus]'
```

```bash
zabbix_get -s 192.168.31.37 -k 'nexus.tcp.local[5001]'
```

Resultados esperados:

```text
200
```

ou:

```text
401
```

ou:

```text
1
```

Para instalar o `zabbix_get`, caso necessário:

```bash
sudo dnf install -y zabbix-get
```

---

## 22. Troubleshooting

---

## 22.1 Erro de certificado no curl

Erro:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Causa:

```text
O certificado do Nexus ou Registry é interno/autoassinado, ou foi assinado por uma CA interna que ainda não está instalada como confiável no host ou container.
```

Contorno adotado neste tutorial:

```bash
curl -k -I https://nexus.jmsalles.homelab.br
```

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Nos UserParameters, o contorno já está aplicado:

```ini
UserParameter=nexus.http.code,curl -k -s -o /dev/null -w "%{http_code}" https://nexus.jmsalles.homelab.br 2>/dev/null
UserParameter=nexus.registry.code,curl -k -s -o /dev/null -w "%{http_code}" https://registry.jmsalles.homelab.br/v2/ 2>/dev/null
```

No Web Scenario do Zabbix, enquanto a CA não for instalada no container do Zabbix, deixe desmarcado:

```text
SSL verify peer
SSL verify host
```

---

## 22.2 Item retorna erro de tipo no Zabbix

Erro comum:

```text
Value of type "string" is not suitable for value type "Numeric (unsigned)"
```

Causa provável:

```text
O UserParameter está retornando valor com quebra de linha ou texto indevido.
```

Valide o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/nexus.conf
```

Garanta que a linha do container esteja assim:

```ini
UserParameter=nexus.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Reinicie:

```bash
sudo systemctl restart zabbix-agent2
```

Teste:

```bash
zabbix_agent2 -t 'nexus.container.running[nexus]'
```

---

## 22.3 Container está rodando, mas item retorna 0

Valide o Docker puro:

```bash
docker inspect -f '{{.State.Running}}' nexus
```

Resultado esperado:

```text
true
```

Teste o comando completo:

```bash
docker inspect -f '{{.State.Running}}' "nexus" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Resultado esperado:

```text
1
```

Se funcionar no shell e não funcionar no Agent, reinicie o Agent.

```bash
sudo systemctl restart zabbix-agent2
```

Depois teste:

```bash
zabbix_agent2 -t 'nexus.container.running[nexus]'
```

---

## 22.4 Zabbix não consegue consultar Docker

Teste com o usuário `zabbix`.

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

---

## 22.5 HTTPS do Nexus retorna diferente de 200

Teste manualmente com `-k`.

```bash
curl -k -I https://nexus.jmsalles.homelab.br
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

Valide a configuração.

```bash
docker compose exec nginx nginx -t
```

Recarregue, se necessário.

```bash
docker compose exec nginx nginx -s reload
```

---

## 22.6 Status API retorna diferente de 200

Teste manualmente.

```bash
curl -k -v https://nexus.jmsalles.homelab.br/service/rest/v1/status
```

Valide o Nexus.

```bash
cd /home/jmsalles/nexus
```

```bash
docker compose ps
```

```bash
docker compose logs --tail=100 nexus
```

Não usar este endpoint para monitoramento sem autenticação:

```text
/service/rest/v1/status/check
```

Motivo:

```text
No ambiente atual, ele retornou HTTP 403.
```

---

## 22.7 Registry retorna diferente de 401

Teste manualmente.

```bash
curl -k -I https://registry.jmsalles.homelab.br/v2/
```

Se retornar `401`, está correto.

Se retornar `502`, valide o Nginx e a porta local.

```bash
curl -I http://127.0.0.1:5001/v2/
```

```bash
ss -lntp | grep 5001
```

Valide o arquivo do Nginx.

```bash
cat /home/jmsalles/nginx/conf.d/registry.jmsalles.homelab.br.conf
```

Valide logs.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

---

## 22.8 Porta 5001 retorna 0

Valide se a porta está aberta.

```bash
ss -lntp | grep 5001
```

Valide o container.

```bash
docker ps | grep nexus
```

Valide o mapeamento de porta.

```bash
docker port nexus
```

Resultado esperado deve incluir:

```text
5001/tcp -> 0.0.0.0:5001
```

ou:

```text
5001/tcp -> [::]:5001
```

---

## 22.9 Tamanho de logs ou blobs retorna vazio

Valide se os diretórios existem.

```bash
ls -lah /home/jmsalles/nexus/nexus-data
```

```bash
ls -lah /home/jmsalles/nexus/nexus-data/log
```

```bash
ls -lah /home/jmsalles/nexus/nexus-data/blobs
```

Se o diretório ainda não existir, o Nexus pode ainda não ter criado esses dados.

---

## 23. Checklist final

| Item                                                        | Status   |
| ----------------------------------------------------------- | -------- |
| Template `Template Nexus JMSalles` criado                   | Pendente |
| Template vinculado ao host `docker-hml.jmsalles.homelab.br` | Pendente |
| Arquivo `/etc/zabbix/zabbix_agent2.d/nexus.conf` criado     | Pendente |
| UserParameters testados localmente                          | Pendente |
| Item HTTPS criado                                           | Pendente |
| Item Status API criado                                      | Pendente |
| Item HTTP local 8081 criado                                 | Pendente |
| Item Registry HTTPS criado                                  | Pendente |
| Item Registry local 5001 criado                             | Pendente |
| Itens de portas 8081, 5000, 5001 e 5002 criados             | Pendente |
| Item container `nexus` criado                               | Pendente |
| Item restart count criado                                   | Pendente |
| Itens de tamanho de diretório/logs/blobs criados            | Pendente |
| Triggers criadas até o item 12.11                           | Pendente |
| Web Scenario do Nexus criado sem `/status/check`            | Pendente |
| Web Scenario do Registry criado                             | Pendente |
| Validação SSL desabilitada nos Web Scenarios                | Pendente |
| Teste de parada do Nexus validado                           | Pendente |

---

## 24. Resumo final

O monitoramento do Nexus ficará dividido em cinco camadas:

```text
Disponibilidade externa
|
HTTPS Nexus
Status API
Web Scenario
```

```text
Registry Docker
|
registry.jmsalles.homelab.br/v2/
Porta 5001
Código esperado 401
```

```text
Serviço local
|
HTTP 8081
Portas 5000, 5001, 5002
```

```text
Container
|
nexus
restart count
```

```text
Capacidade básica
|
nexus-data
logs
blobs
```

Os principais itens customizados são:

```text
nexus.container.running[nexus]
nexus.http.code
nexus.status.code
nexus.registry.code
nexus.registry.local.code
nexus.tcp.local[8081]
nexus.tcp.local[5001]
```

O item abaixo foi removido:

```text
nexus.status.check.code
```

Motivo:

```text
O endpoint /service/rest/v1/status/check retornou HTTP 403 sem autenticação no ambiente atual.
```

Como o certificado é interno/autoassinado, este tutorial usa `curl -k` nos UserParameters e recomenda deixar `SSL verify peer` e `SSL verify host` desmarcados nos Web Scenarios até que a CA raiz seja instalada no container do Zabbix.

Os itens de capacidade foram mantidos para consulta, mas sem triggers neste momento, para evitar ruído operacional.

Com esse modelo, o Zabbix consegue identificar se a falha está no container, no Nexus, no registry Docker, no Nginx reverse proxy, nas portas locais ou apenas na validação do certificado.

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)
