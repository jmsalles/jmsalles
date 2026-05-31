# Guia de monitoramento do Stirling PDF no Zabbix

## 1. Objetivo

Este documento descreve como monitorar a aplicacao Stirling PDF instalada em Docker no host fisico Docker HML.

O monitoramento sera feito no Zabbix existente da rede, utilizando o Zabbix Agent 2 instalado no host:

```text
docker-hml.jmsalles.homelab.br
```

Nesta etapa, o foco sera apenas no Stirling PDF.

Nao serao monitorados neste documento:

```text
Gitea
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

| Item                       | Valor                                                          |
| -------------------------- | -------------------------------------------------------------- |
| Host Docker HML            | `docker-hml.jmsalles.homelab.br`                               |
| IP do host                 | `192.168.31.37`                                                |
| URL do Stirling PDF        | `https://pdf-hml.jmsalles.homelab.br`                          |
| Container                  | `stirling-pdf`                                                 |
| Porta externa no host      | `9999`                                                         |
| Porta interna do container | `8080`                                                         |
| Proxy reverso              | Nginx em Docker                                                |
| Arquivo Nginx              | `/home/jmsalles/nginx/conf.d/pdf-hml.jmsalles.homelab.br.conf` |
| Diretorio da aplicacao     | `/home/jmsalles/stirling`                                      |
| Zabbix Agent               | Zabbix Agent 2                                                 |

## 3. O que sera monitorado

| Camada    | Monitoramento                                  |
| --------- | ---------------------------------------------- |
| Aplicacao | HTTPS do Stirling PDF                          |
| Aplicacao | HTTP local na porta `9999`                     |
| Porta     | Porta local `9999`                             |
| Container | Container `stirling-pdf` rodando               |
| Container | Restart count do container `stirling-pdf`      |
| Arquivos  | Tamanho do diretorio `/home/jmsalles/stirling` |
| Logs      | Tamanho do diretorio de logs do Stirling PDF   |
| Web       | Web Scenario do Stirling PDF                   |

## 4. Validar o Stirling PDF manualmente

Acesse o host Docker HML.

```bash
ssh jmsalles@192.168.31.37
```

Valide o container.

```bash
docker ps | grep stirling-pdf
```

Valide o compose.

```bash
cd /home/jmsalles/stirling
```

```bash
docker compose ps
```

Valide a porta local `9999`.

```bash
ss -lntp | grep 9999
```

Valide o acesso local.

```bash
curl -I http://127.0.0.1:9999
```

Resultado esperado:

```text
HTTP/1.1 200
```

ou:

```text
HTTP/1.1 302
```

Valide o acesso HTTPS pelo proxy usando `-k`, pois o certificado e interno/autoassinado.

```bash
curl -k -I https://pdf-hml.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/1.1 200
```

ou:

```text
HTTP/2 200
```

Se executar sem `-k`:

```bash
curl -I https://pdf-hml.jmsalles.homelab.br
```

e receber o erro abaixo:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

isso indica apenas que a CA raiz do certificado ainda nao esta instalada como confiavel nesse host ou container.

Valide a configuracao do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Valide os logs do Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

## 5. Criar template do Stirling PDF no Zabbix

No frontend do Zabbix, acesse:

```text
Data collection
Templates
Create template
```

Preencha:

| Campo         | Valor                                                        |
| ------------- | ------------------------------------------------------------ |
| Template name | `Template Stirling PDF JMSalles`                             |
| Visible name  | `Monitoramento Stirling PDF JMSalles`                        |
| Groups        | `Templates/Applications`                                     |
| Description   | `Monitoramento do Stirling PDF em Docker no host Docker HML` |

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
Template Stirling PDF JMSalles
Update
```

## 6. Criar UserParameters do Stirling PDF

No host Docker HML, crie o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/stirling-pdf.conf
```

Cole o conteudo abaixo:

```ini
UserParameter=stirling.http.code,curl -k -s -o /dev/null -w "%{http_code}" https://pdf-hml.jmsalles.homelab.br 2>/dev/null
UserParameter=stirling.local.code,curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9999 2>/dev/null
UserParameter=stirling.tcp.local,nc -z -w 3 127.0.0.1 9999 >/dev/null 2>&1 && printf 1 || printf 0
UserParameter=stirling.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
UserParameter=stirling.container.restart[*],docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null | tr -cd '0-9'
UserParameter=stirling.dir.size,du -sb /home/jmsalles/stirling 2>/dev/null | awk '{print $1}'
UserParameter=stirling.logs.size,du -sb /home/jmsalles/stirling/stirling-data/logs 2>/dev/null | awk '{print $1}'
```

Observacao:

```text
A chave stirling.http.code usa curl -k.
Isso evita falha por certificado autoassinado ou CA interna nao instalada.
```

Caso o comando `nc` nao exista, instale o pacote:

```bash
sudo dnf install -y nmap-ncat
```

Ajuste a permissao.

```bash
sudo chmod 644 /etc/zabbix/zabbix_agent2.d/stirling-pdf.conf
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
zabbix_agent2 -t stirling.http.code
```

Resultado esperado:

```text
stirling.http.code [s|200]
```

Se retornar `302`, a aplicacao esta respondendo, mas existe redirecionamento. Nesse caso, ajuste o item e a trigger para aceitar `200` ou `302`, conforme explicado no troubleshooting.

Teste o HTTP local.

```bash
zabbix_agent2 -t stirling.local.code
```

Resultado esperado:

```text
stirling.local.code [s|200]
```

ou:

```text
stirling.local.code [s|302]
```

Teste a porta local `9999`.

```bash
zabbix_agent2 -t stirling.tcp.local
```

Resultado esperado:

```text
stirling.tcp.local [s|1]
```

Teste o container.

```bash
zabbix_agent2 -t 'stirling.container.running[stirling-pdf]'
```

Resultado esperado:

```text
stirling.container.running[stirling-pdf] [s|1]
```

Teste o restart count.

```bash
zabbix_agent2 -t 'stirling.container.restart[stirling-pdf]'
```

Resultado esperado:

```text
stirling.container.restart[stirling-pdf] [s|0]
```

ou o numero atual de restarts.

Teste o tamanho do diretorio da aplicacao.

```bash
zabbix_agent2 -t stirling.dir.size
```

Resultado esperado:

```text
stirling.dir.size [s|VALOR_EM_BYTES]
```

Teste o tamanho do diretorio de logs.

```bash
zabbix_agent2 -t stirling.logs.size
```

Resultado esperado:

```text
stirling.logs.size [s|VALOR_EM_BYTES]
```

## 8. Criar itens no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Stirling PDF JMSalles
Items
Create item
```

Crie os itens abaixo.

### 8.1 HTTPS do Stirling PDF

| Campo               | Valor                             |
| ------------------- | --------------------------------- |
| Name                | `Stirling PDF: HTTPS status code` |
| Type                | `Zabbix agent`                    |
| Key                 | `stirling.http.code`              |
| Type of information | `Numeric unsigned`                |
| Update interval     | `1m`                              |
| History             | `31d`                             |
| Trends              | `365d`                            |

### 8.2 HTTP local do Stirling PDF

| Campo               | Valor                                  |
| ------------------- | -------------------------------------- |
| Name                | `Stirling PDF: HTTP local status code` |
| Type                | `Zabbix agent`                         |
| Key                 | `stirling.local.code`                  |
| Type of information | `Numeric unsigned`                     |
| Update interval     | `1m`                                   |
| History             | `31d`                                  |
| Trends              | `365d`                                 |

### 8.3 Porta local 9999

| Campo               | Valor                                   |
| ------------------- | --------------------------------------- |
| Name                | `Stirling PDF: Porta local 9999 status` |
| Type                | `Zabbix agent`                          |
| Key                 | `stirling.tcp.local`                    |
| Type of information | `Numeric unsigned`                      |
| Update interval     | `1m`                                    |
| History             | `31d`                                   |
| Trends              | `365d`                                  |

### 8.4 Container Stirling PDF rodando

| Campo               | Valor                                          |
| ------------------- | ---------------------------------------------- |
| Name                | `Stirling PDF: Container stirling-pdf rodando` |
| Type                | `Zabbix agent`                                 |
| Key                 | `stirling.container.running[stirling-pdf]`     |
| Type of information | `Numeric unsigned`                             |
| Update interval     | `30s`                                          |
| History             | `31d`                                          |
| Trends              | `365d`                                         |

### 8.5 Restart count do Stirling PDF

| Campo               | Valor                                                   |
| ------------------- | ------------------------------------------------------- |
| Name                | `Stirling PDF: Restart count do container stirling-pdf` |
| Type                | `Zabbix agent`                                          |
| Key                 | `stirling.container.restart[stirling-pdf]`              |
| Type of information | `Numeric unsigned`                                      |
| Update interval     | `5m`                                                    |
| History             | `31d`                                                   |
| Trends              | `365d`                                                  |

### 8.6 Tamanho do diretorio do Stirling PDF

| Campo               | Valor                                                        |
| ------------------- | ------------------------------------------------------------ |
| Name                | `Stirling PDF: Tamanho do diretorio /home/jmsalles/stirling` |
| Type                | `Zabbix agent`                                               |
| Key                 | `stirling.dir.size`                                          |
| Type of information | `Numeric unsigned`                                           |
| Units               | `B`                                                          |
| Update interval     | `10m`                                                        |
| History             | `31d`                                                        |
| Trends              | `365d`                                                       |

### 8.7 Tamanho dos logs do Stirling PDF

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Stirling PDF: Tamanho dos logs` |
| Type                | `Zabbix agent`                   |
| Key                 | `stirling.logs.size`             |
| Type of information | `Numeric unsigned`               |
| Units               | `B`                              |
| Update interval     | `10m`                            |
| History             | `31d`                            |
| Trends              | `365d`                           |

## 9. Criar check externo da porta 9999

Esse check valida a porta a partir do ponto de vista do Zabbix Server.

No template ou diretamente no host, crie o item:

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Stirling PDF: Porta externa 9999`        |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,9999]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

Observacao:

```text
A porta 9999 esta publicada no host pelo Docker.
Mesmo assim, o acesso principal da aplicacao deve ser via HTTPS pelo Nginx:
https://pdf-hml.jmsalles.homelab.br
```

## 10. Criar triggers no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Stirling PDF JMSalles
Triggers
Create trigger
```

### 10.1 HTTPS do Stirling PDF indisponivel

| Campo                         | Valor                                                           |
| ----------------------------- | --------------------------------------------------------------- |
| Name                          | `Stirling PDF: HTTPS indisponivel`                              |
| Severity                      | `High`                                                          |
| Expression                    | `last(/Template Stirling PDF JMSalles/stirling.http.code)<>200` |
| OK event generation           | `Expression`                                                    |
| PROBLEM event generation mode | `Single`                                                        |
| Enabled                       | Sim                                                             |

Se o seu Stirling PDF retornar `302` no acesso principal, use esta expressao alternativa:

```text
last(/Template Stirling PDF JMSalles/stirling.http.code)<>200 and last(/Template Stirling PDF JMSalles/stirling.http.code)<>302
```

### 10.2 HTTP local do Stirling PDF falhando

| Campo                         | Valor                                                            |
| ----------------------------- | ---------------------------------------------------------------- |
| Name                          | `Stirling PDF: HTTP local falhando`                              |
| Severity                      | `Average`                                                        |
| Expression                    | `last(/Template Stirling PDF JMSalles/stirling.local.code)<>200` |
| OK event generation           | `Expression`                                                     |
| PROBLEM event generation mode | `Single`                                                         |
| Enabled                       | Sim                                                              |

Se o HTTP local retornar `302`, use esta expressao alternativa:

```text
last(/Template Stirling PDF JMSalles/stirling.local.code)<>200 and last(/Template Stirling PDF JMSalles/stirling.local.code)<>302
```

### 10.3 Porta local 9999 indisponivel

| Campo                         | Valor                                                        |
| ----------------------------- | ------------------------------------------------------------ |
| Name                          | `Stirling PDF: Porta local 9999 indisponivel`                |
| Severity                      | `Average`                                                    |
| Expression                    | `last(/Template Stirling PDF JMSalles/stirling.tcp.local)=0` |
| OK event generation           | `Expression`                                                 |
| PROBLEM event generation mode | `Single`                                                     |
| Enabled                       | Sim                                                          |

### 10.4 Container Stirling PDF parado

| Campo                         | Valor                                                                              |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| Name                          | `Stirling PDF: Container stirling-pdf parado`                                      |
| Severity                      | `High`                                                                             |
| Expression                    | `last(/Template Stirling PDF JMSalles/stirling.container.running[stirling-pdf])=0` |
| OK event generation           | `Expression`                                                                       |
| PROBLEM event generation mode | `Single`                                                                           |
| Enabled                       | Sim                                                                                |

### 10.5 Container Stirling PDF reiniciou recentemente

| Campo                         | Valor                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| Name                          | `Stirling PDF: Container stirling-pdf reiniciou recentemente`                        |
| Severity                      | `Warning`                                                                            |
| Expression                    | `change(/Template Stirling PDF JMSalles/stirling.container.restart[stirling-pdf])>0` |
| OK event generation           | `Expression`                                                                         |
| PROBLEM event generation mode | `Single`                                                                             |
| Enabled                       | Sim                                                                                  |

### 10.6 Diretorio do Stirling PDF acima de 10 GB

| Campo                         | Valor                                                                 |
| ----------------------------- | --------------------------------------------------------------------- |
| Name                          | `Stirling PDF: Diretorio /home/jmsalles/stirling acima de 10 GB`      |
| Severity                      | `Warning`                                                             |
| Expression                    | `last(/Template Stirling PDF JMSalles/stirling.dir.size)>10737418240` |
| OK event generation           | `Expression`                                                          |
| PROBLEM event generation mode | `Single`                                                              |
| Enabled                       | Opcional                                                              |

Observacao:

```text
10737418240 equivale a 10 GB.
Ajuste conforme o crescimento real da aplicacao.
```

### 10.7 Logs do Stirling PDF acima de 2 GB

| Campo                         | Valor                                                                 |
| ----------------------------- | --------------------------------------------------------------------- |
| Name                          | `Stirling PDF: Logs acima de 2 GB`                                    |
| Severity                      | `Warning`                                                             |
| Expression                    | `last(/Template Stirling PDF JMSalles/stirling.logs.size)>2147483648` |
| OK event generation           | `Expression`                                                          |
| PROBLEM event generation mode | `Single`                                                              |
| Enabled                       | Opcional                                                              |

Observacao:

```text
2147483648 equivale a 2 GB.
Ajuste conforme o volume real de logs.
```

## 11. Criar trigger para check externo da porta 9999

Se o item de Simple check foi criado no template, crie a trigger:

| Campo      | Valor                                                                             |
| ---------- | --------------------------------------------------------------------------------- |
| Name       | `Stirling PDF: Porta externa 9999 indisponivel`                                   |
| Severity   | `Average`                                                                         |
| Expression | `last(/Template Stirling PDF JMSalles/net.tcp.service[tcp,192.168.31.37,9999])=0` |

Se o item foi criado diretamente no host, use a expressao apontando para o host:

```text
last(/docker-hml.jmsalles.homelab.br/net.tcp.service[tcp,192.168.31.37,9999])=0
```

## 12. Criar Web Scenario do Stirling PDF

No Zabbix, acesse:

```text
Data collection
Hosts
docker-hml.jmsalles.homelab.br
Web
Create web scenario
```

Preencha:

| Campo           | Valor                  |
| --------------- | ---------------------- |
| Name            | `Stirling PDF - HTTPS` |
| Update interval | `1m`                   |
| Attempts        | `3`                    |
| Agent           | `Chrome`               |
| Enabled         | Sim                    |

Crie o Step 1:

| Campo                 | Valor                                 |
| --------------------- | ------------------------------------- |
| Name                  | `Stirling PDF Home`                   |
| URL                   | `https://pdf-hml.jmsalles.homelab.br` |
| Timeout               | `10s`                                 |
| Required status codes | `200`                                 |

Se o retorno for `302`, use:

```text
200,302
```

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

| Campo                         | Valor                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------ |
| Name                          | `Stirling PDF: Web scenario HTTPS falhando`                                    |
| Severity                      | `High`                                                                         |
| Expression                    | `last(/docker-hml.jmsalles.homelab.br/web.test.fail[Stirling PDF - HTTPS])<>0` |
| OK event generation           | `Expression`                                                                   |
| PROBLEM event generation mode | `Single`                                                                       |
| Enabled                       | Sim                                                                            |

Opcionalmente, crie uma trigger para tempo de resposta alto:

| Campo      | Valor                                                                                                |
| ---------- | ---------------------------------------------------------------------------------------------------- |
| Name       | `Stirling PDF: Tempo de resposta alto`                                                               |
| Severity   | `Warning`                                                                                            |
| Expression | `last(/docker-hml.jmsalles.homelab.br/web.test.time[Stirling PDF - HTTPS,Stirling PDF Home,resp])>5` |
| Enabled    | Sim                                                                                                  |

Observacao:

```text
O valor 5 representa 5 segundos.
Como a aplicacao manipula PDF, OCR e arquivos grandes, o limite pode ser maior que o de uma aplicacao comum.
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
Name: Stirling PDF
```

Voce deve ver itens como:

```text
Stirling PDF: HTTPS status code
Stirling PDF: HTTP local status code
Stirling PDF: Porta local 9999 status
Stirling PDF: Container stirling-pdf rodando
Stirling PDF: Restart count do container stirling-pdf
Stirling PDF: Tamanho do diretorio /home/jmsalles/stirling
Stirling PDF: Tamanho dos logs
```

Valores esperados:

| Item                                           | Valor esperado |
| ---------------------------------------------- | -------------- |
| `Stirling PDF: HTTPS status code`              | `200` ou `302` |
| `Stirling PDF: HTTP local status code`         | `200` ou `302` |
| `Stirling PDF: Porta local 9999 status`        | `1`            |
| `Stirling PDF: Container stirling-pdf rodando` | `1`            |

## 15. Teste controlado de falha do Stirling PDF

Para testar os alertas, pare somente o container do Stirling PDF.

```bash
cd /home/jmsalles/stirling
```

```bash
docker compose stop stirling-pdf
```

Teste localmente:

```bash
zabbix_agent2 -t 'stirling.container.running[stirling-pdf]'
```

Resultado esperado:

```text
stirling.container.running[stirling-pdf] [s|0]
```

Alertas esperados no Zabbix:

```text
Stirling PDF: Container stirling-pdf parado
Stirling PDF: HTTPS indisponivel
Stirling PDF: HTTP local falhando
Stirling PDF: Porta local 9999 indisponivel
Stirling PDF: Web scenario HTTPS falhando
```

Suba novamente:

```bash
docker compose start stirling-pdf
```

Valide:

```bash
docker ps | grep stirling-pdf
```

Teste novamente:

```bash
zabbix_agent2 -t 'stirling.container.running[stirling-pdf]'
```

Resultado esperado:

```text
stirling.container.running[stirling-pdf] [s|1]
```

## 16. Teste com container removido

Se voce usar `docker compose down`, o container sera removido.

```bash
cd /home/jmsalles/stirling
```

```bash
docker compose down
```

Mesmo assim, o item customizado deve retornar `0`.

```bash
zabbix_agent2 -t 'stirling.container.running[stirling-pdf]'
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
docker ps | grep stirling-pdf
```

## 17. Testar coleta a partir do Zabbix Server

No servidor Zabbix, se tiver `zabbix_get`, teste:

```bash
zabbix_get -s 192.168.31.37 -k stirling.http.code
```

```bash
zabbix_get -s 192.168.31.37 -k stirling.local.code
```

```bash
zabbix_get -s 192.168.31.37 -k stirling.tcp.local
```

```bash
zabbix_get -s 192.168.31.37 -k 'stirling.container.running[stirling-pdf]'
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

## 18. Troubleshooting

### 18.1 Erro de certificado no curl

Erro:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Causa:

```text
O certificado do Stirling PDF e interno/autoassinado, ou foi assinado por uma CA interna que ainda nao esta instalada como confiavel no host ou container.
```

Contorno adotado neste tutorial:

```bash
curl -k -I https://pdf-hml.jmsalles.homelab.br
```

Nos UserParameters, o contorno ja esta aplicado:

```ini
UserParameter=stirling.http.code,curl -k -s -o /dev/null -w "%{http_code}" https://pdf-hml.jmsalles.homelab.br 2>/dev/null
```

No Web Scenario do Zabbix, enquanto a CA nao for instalada no container do Zabbix, deixe desmarcado:

```text
SSL verify peer
SSL verify host
```

### 18.2 Item retorna erro de tipo no Zabbix

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
sudo vim /etc/zabbix/zabbix_agent2.d/stirling-pdf.conf
```

Garanta que a linha do container esteja assim:

```ini
UserParameter=stirling.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
```

Reinicie:

```bash
sudo systemctl restart zabbix-agent2
```

Teste:

```bash
zabbix_agent2 -t 'stirling.container.running[stirling-pdf]'
```

### 18.3 Container esta rodando, mas item retorna 0

Valide o Docker puro:

```bash
docker inspect -f '{{.State.Running}}' stirling-pdf
```

Resultado esperado:

```text
true
```

Teste o comando completo:

```bash
docker inspect -f '{{.State.Running}}' "stirling-pdf" 2>/dev/null | grep -qx true && printf 1 || printf 0
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
zabbix_agent2 -t 'stirling.container.running[stirling-pdf]'
```

### 18.4 Zabbix nao consegue consultar Docker

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

### 18.5 HTTPS do Stirling PDF retorna diferente de 200

Teste manualmente com `-k`.

```bash
curl -k -I https://pdf-hml.jmsalles.homelab.br
```

Se retornar `302`, ajuste a trigger para aceitar `200` e `302`.

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

### 18.6 HTTP local retorna diferente de 200

Teste localmente.

```bash
curl -I http://127.0.0.1:9999
```

Valide o compose.

```bash
cd /home/jmsalles/stirling
```

```bash
docker compose ps
```

Valide logs da aplicacao.

```bash
docker compose logs --tail=100 stirling-pdf
```

### 18.7 Porta 9999 retorna 0

Valide se a porta esta aberta.

```bash
ss -lntp | grep 9999
```

Valide o container.

```bash
docker ps | grep stirling-pdf
```

Valide o mapeamento de porta.

```bash
docker port stirling-pdf
```

Resultado esperado:

```text
8080/tcp -> 0.0.0.0:9999
```

ou:

```text
8080/tcp -> [::]:9999
```

## 19. Checklist final

| Item                                                           | Status   |
| -------------------------------------------------------------- | -------- |
| Template `Template Stirling PDF JMSalles` criado               | Pendente |
| Template vinculado ao host `docker-hml.jmsalles.homelab.br`    | Pendente |
| Arquivo `/etc/zabbix/zabbix_agent2.d/stirling-pdf.conf` criado | Pendente |
| UserParameters testados localmente                             | Pendente |
| Item HTTPS criado                                              | Pendente |
| Item HTTP local criado                                         | Pendente |
| Item porta 9999 criado                                         | Pendente |
| Item container `stirling-pdf` criado                           | Pendente |
| Item restart count criado                                      | Pendente |
| Itens de tamanho de diretorio/logs criados                     | Pendente |
| Triggers criadas                                               | Pendente |
| Web Scenario criado                                            | Pendente |
| Validacao SSL desabilitada no Web Scenario                     | Pendente |
| Teste de parada do Stirling PDF validado                       | Pendente |

## 20. Resumo final

O monitoramento do Stirling PDF ficara dividido em quatro camadas:

```text
Disponibilidade externa
|
HTTPS
Web Scenario
```

```text
Servico local
|
HTTP 9999
Porta 9999
```

```text
Container
|
stirling-pdf
restart count
```

```text
Capacidade basica
|
Diretorio da aplicacao
Diretorio de logs
```

Os principais itens customizados sao:

```text
stirling.container.running[stirling-pdf]
stirling.http.code
stirling.local.code
stirling.tcp.local
stirling.dir.size
stirling.logs.size
```

Como o certificado e interno/autoassinado, este tutorial usa `curl -k` nos UserParameters e recomenda deixar `SSL verify peer` e `SSL verify host` desmarcados no Web Scenario ate que a CA raiz seja instalada no container do Zabbix.

Com esse modelo, o Zabbix consegue identificar se a falha esta no container, na porta local, no proxy reverso, na publicacao HTTPS ou apenas na validacao do certificado.

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
