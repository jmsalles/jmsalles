# Guia de monitoramento do Vault no Zabbix

## 1. Objetivo

Este documento descreve como monitorar o HashiCorp Vault instalado em Docker no servidor físico Docker HML do homelab JMSalles.

O monitoramento será feito no Zabbix existente da rede, utilizando o Zabbix Agent 2 instalado no host:

```text
docker-hml.jmsalles.homelab.br
```

Nesta etapa, o foco será apenas no Vault.

Não serão monitorados neste documento:

```text
Gitea
Nexus
Stirling PDF
Runner
Backups
Outras aplicações
```

O Vault será monitorado principalmente por:

```text
Container Docker
Porta local 8200
Endpoint de health
Estado sealed/unsealed
Estado initialized
Web Scenario HTTPS
Restart count
Tamanho básico dos diretórios data e logs
```

## 2. Dados do ambiente

| Item                     | Valor                                   |
| ------------------------ | --------------------------------------- |
| Host Docker HML          | `docker-hml.jmsalles.homelab.br`        |
| IP do host               | `192.168.31.37`                         |
| URL do Vault             | `https://vault.jmsalles.homelab.br`     |
| Container                | `vault`                                 |
| Porta local              | `8200`                                  |
| Porta interna de cluster | `8201`                                  |
| Diretório base           | `/home/jmsalles/vault`                  |
| Diretório de dados       | `/home/jmsalles/vault/data`             |
| Diretório de logs        | `/home/jmsalles/vault/logs`             |
| Arquivo de configuração  | `/home/jmsalles/vault/config/vault.hcl` |
| Proxy reverso            | Nginx em Docker                         |
| Zabbix Agent             | Zabbix Agent 2                          |

## 3. Observação sobre certificado interno

O ambiente utiliza certificado interno ou autoassinado.

Por esse motivo, os testes via `curl` no Zabbix Agent usarão a opção `-k`.

Essa opção ignora a validação da cadeia de certificado.

Caso apareça o erro abaixo em testes manuais com `curl` sem `-k`, o problema está relacionado à cadeia do certificado não estar instalada como confiável no Linux ou no container do Zabbix.

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Neste momento, não será feita a instalação da CA raiz. O monitoramento seguirá usando `curl -k`.

## 4. Observação sobre sealed/unsealed

O Vault pode estar em três situações principais para este monitoramento:

| Estado              | Significado                                           |
| ------------------- | ----------------------------------------------------- |
| `initialized=false` | Vault ainda não foi inicializado                      |
| `sealed=true`       | Vault inicializado, porém bloqueado aguardando unseal |
| `sealed=false`      | Vault inicializado e liberado para uso                |

No seu ambiente, após restart do container, o Vault pode voltar como sealed.

Isso é esperado quando não existe auto-unseal configurado.

Neste tutorial, vamos monitorar explicitamente quando o Vault estiver sealed para gerar alerta.

## 5. O que será monitorado

| Camada     | Monitoramento                          |
| ---------- | -------------------------------------- |
| Container  | Container `vault` rodando              |
| Container  | Restart count do container `vault`     |
| Porta      | Porta local `8200`                     |
| Health     | HTTP local `/v1/sys/health`            |
| Health     | HTTPS externo `/v1/sys/health`         |
| Estado     | Vault initialized                      |
| Estado     | Vault sealed                           |
| Web        | Web Scenario HTTPS do health endpoint  |
| Capacidade | Tamanho de `/home/jmsalles/vault/data` |
| Capacidade | Tamanho de `/home/jmsalles/vault/logs` |

Observação:

```text
Os itens de tamanho de diretório serão criados apenas para consulta em Latest data.
Neste momento, não serão criadas triggers de capacidade para esses itens.
```

## 6. Validar o Vault manualmente

Acesse o host Docker HML.

```bash
ssh jmsalles@192.168.31.37
```

Valide o container.

```bash
docker ps | grep vault
```

Valide o compose.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose ps
```

Valide os logs.

```bash
docker compose logs --tail=100 vault
```

Valide a porta local.

```bash
curl -I http://127.0.0.1:8200/v1/sys/health
```

Valide o health em JSON.

```bash
curl -s http://127.0.0.1:8200/v1/sys/health
```

Valide via HTTPS pelo Nginx.

```bash
curl -k -I https://vault.jmsalles.homelab.br/v1/sys/health
```

Valide o JSON via HTTPS.

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health
```

Resultado esperado com Vault inicializado e unsealed:

```text
HTTP/1.1 200 OK
```

Resultado esperado no JSON:

```json
{
  "initialized": true,
  "sealed": false
}
```

Se o Vault estiver sealed, o health pode retornar HTTP `503`.

Isso será usado para alerta.

## 7. Validar status dentro do container

Entre no container.

```bash
docker exec -it vault sh
```

Configure o endereço local.

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

Valide status.

```bash
vault status
```

Resultado esperado quando está funcionando:

```text
Initialized     true
Sealed          false
Storage Type    raft
```

Saia do container.

```bash
exit
```

## 8. Validar permissão do Zabbix para consultar Docker

O usuário `zabbix` precisa conseguir consultar o Docker para validar o container.

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

## 9. Instalar dependência para teste de porta

O UserParameter de porta usará o comando `nc`.

Valide se existe:

```bash
which nc
```

Se não existir, instale:

```bash
sudo dnf install -y nmap-ncat
```

Valide novamente:

```bash
which nc
```

## 10. Criar template do Vault no Zabbix

No frontend do Zabbix, acesse:

```text
Data collection
Templates
Create template
```

Preencha:

| Campo         | Valor                                                           |
| ------------- | --------------------------------------------------------------- |
| Template name | `Template Vault JMSalles`                                       |
| Visible name  | `Monitoramento Vault JMSalles`                                  |
| Groups        | `Templates/Applications`                                        |
| Description   | `Monitoramento do HashiCorp Vault em Docker no host Docker HML` |

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
Template Vault JMSalles
Update
```

## 11. Criar UserParameters do Vault

No host Docker HML, crie o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/vault.conf
```

Cole o conteúdo abaixo:

```ini
UserParameter=vault.health.local.code,curl -s --max-time 5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8200/v1/sys/health 2>/dev/null
UserParameter=vault.health.https.code,curl -k -s --max-time 5 -o /dev/null -w "%{http_code}" https://vault.jmsalles.homelab.br/v1/sys/health 2>/dev/null
UserParameter=vault.initialized,json=$(curl -k -s --max-time 5 https://vault.jmsalles.homelab.br/v1/sys/health 2>/dev/null); echo "$json" | grep -q '"initialized":true' && printf 1 || { echo "$json" | grep -q '"initialized":false' && printf 0 || printf 2; }
UserParameter=vault.sealed,json=$(curl -k -s --max-time 5 https://vault.jmsalles.homelab.br/v1/sys/health 2>/dev/null); echo "$json" | grep -q '"sealed":true' && printf 1 || { echo "$json" | grep -q '"sealed":false' && printf 0 || printf 2; }
UserParameter=vault.tcp.local[*],nc -z -w 3 127.0.0.1 $1 >/dev/null 2>&1 && printf 1 || printf 0
UserParameter=vault.container.running[*],docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true && printf 1 || printf 0
UserParameter=vault.container.restart[*],v=$(docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null); if echo "$v" | grep -Eq '^[0-9]+$'; then printf "%s" "$v"; else printf 0; fi
UserParameter=vault.data.size,du -sb /home/jmsalles/vault/data 2>/dev/null | cut -f1
UserParameter=vault.logs.size,du -sb /home/jmsalles/vault/logs 2>/dev/null | cut -f1
```

Explicação dos principais itens:

| Chave                            | Retorno esperado                                         |
| -------------------------------- | -------------------------------------------------------- |
| `vault.health.local.code`        | Código HTTP local do health endpoint                     |
| `vault.health.https.code`        | Código HTTP via HTTPS pelo Nginx                         |
| `vault.initialized`              | `1` inicializado, `0` não inicializado, `2` desconhecido |
| `vault.sealed`                   | `0` unsealed, `1` sealed, `2` desconhecido               |
| `vault.tcp.local[8200]`          | `1` porta aberta, `0` porta fechada                      |
| `vault.container.running[vault]` | `1` rodando, `0` parado ou removido                      |
| `vault.container.restart[vault]` | Quantidade de restarts                                   |
| `vault.data.size`                | Tamanho do diretório de dados em bytes                   |
| `vault.logs.size`                | Tamanho do diretório de logs em bytes                    |

Ajuste a permissão.

```bash
sudo chmod 644 /etc/zabbix/zabbix_agent2.d/vault.conf
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

## 12. Testar os UserParameters localmente

Teste o health local.

```bash
zabbix_agent2 -t vault.health.local.code
```

Resultado esperado com Vault unsealed:

```text
vault.health.local.code [s|200]
```

Se estiver sealed, pode retornar:

```text
vault.health.local.code [s|503]
```

Teste o health HTTPS.

```bash
zabbix_agent2 -t vault.health.https.code
```

Resultado esperado com Vault unsealed:

```text
vault.health.https.code [s|200]
```

Teste initialized.

```bash
zabbix_agent2 -t vault.initialized
```

Resultado esperado:

```text
vault.initialized [s|1]
```

Teste sealed.

```bash
zabbix_agent2 -t vault.sealed
```

Resultado esperado com Vault liberado:

```text
vault.sealed [s|0]
```

Resultado esperado com Vault selado:

```text
vault.sealed [s|1]
```

Teste a porta local `8200`.

```bash
zabbix_agent2 -t 'vault.tcp.local[8200]'
```

Resultado esperado:

```text
vault.tcp.local[8200] [s|1]
```

Teste o container.

```bash
zabbix_agent2 -t 'vault.container.running[vault]'
```

Resultado esperado:

```text
vault.container.running[vault] [s|1]
```

Teste o restart count.

```bash
zabbix_agent2 -t 'vault.container.restart[vault]'
```

Resultado esperado:

```text
vault.container.restart[vault] [s|0]
```

ou o número atual de restarts.

Teste o tamanho do diretório de dados.

```bash
zabbix_agent2 -t vault.data.size
```

Teste o tamanho do diretório de logs.

```bash
zabbix_agent2 -t vault.logs.size
```

## 13. Criar itens no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Vault JMSalles
Items
Create item
```

Crie os itens abaixo.

## 13.1 Health local code

| Campo               | Valor                             |
| ------------------- | --------------------------------- |
| Name                | `Vault: Health local status code` |
| Type                | `Zabbix agent`                    |
| Key                 | `vault.health.local.code`         |
| Type of information | `Numeric unsigned`                |
| Update interval     | `1m`                              |
| History             | `31d`                             |
| Trends              | `365d`                            |

## 13.2 Health HTTPS code

| Campo               | Valor                             |
| ------------------- | --------------------------------- |
| Name                | `Vault: Health HTTPS status code` |
| Type                | `Zabbix agent`                    |
| Key                 | `vault.health.https.code`         |
| Type of information | `Numeric unsigned`                |
| Update interval     | `1m`                              |
| History             | `31d`                             |
| Trends              | `365d`                            |

## 13.3 Vault initialized

| Campo               | Valor                       |
| ------------------- | --------------------------- |
| Name                | `Vault: Initialized status` |
| Type                | `Zabbix agent`              |
| Key                 | `vault.initialized`         |
| Type of information | `Numeric unsigned`          |
| Update interval     | `1m`                        |
| History             | `31d`                       |
| Trends              | `365d`                      |

Valores:

```text
1 = initialized
0 = not initialized
2 = unknown
```

## 13.4 Vault sealed

| Campo               | Valor                  |
| ------------------- | ---------------------- |
| Name                | `Vault: Sealed status` |
| Type                | `Zabbix agent`         |
| Key                 | `vault.sealed`         |
| Type of information | `Numeric unsigned`     |
| Update interval     | `30s`                  |
| History             | `31d`                  |
| Trends              | `365d`                 |

Valores:

```text
0 = unsealed
1 = sealed
2 = unknown
```

## 13.5 Porta local 8200

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Vault: Porta local 8200 status` |
| Type                | `Zabbix agent`                   |
| Key                 | `vault.tcp.local[8200]`          |
| Type of information | `Numeric unsigned`               |
| Update interval     | `1m`                             |
| History             | `31d`                            |
| Trends              | `365d`                           |

## 13.6 Container Vault rodando

| Campo               | Valor                            |
| ------------------- | -------------------------------- |
| Name                | `Vault: Container vault rodando` |
| Type                | `Zabbix agent`                   |
| Key                 | `vault.container.running[vault]` |
| Type of information | `Numeric unsigned`               |
| Update interval     | `30s`                            |
| History             | `31d`                            |
| Trends              | `365d`                           |

## 13.7 Restart count do Vault

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Vault: Restart count do container vault` |
| Type                | `Zabbix agent`                            |
| Key                 | `vault.container.restart[vault]`          |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `5m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

## 13.8 Tamanho do diretório data

| Campo               | Valor                              |
| ------------------- | ---------------------------------- |
| Name                | `Vault: Tamanho do diretorio data` |
| Type                | `Zabbix agent`                     |
| Key                 | `vault.data.size`                  |
| Type of information | `Numeric unsigned`                 |
| Units               | `B`                                |
| Update interval     | `10m`                              |
| History             | `31d`                              |
| Trends              | `365d`                             |

## 13.9 Tamanho do diretório logs

| Campo               | Valor                              |
| ------------------- | ---------------------------------- |
| Name                | `Vault: Tamanho do diretorio logs` |
| Type                | `Zabbix agent`                     |
| Key                 | `vault.logs.size`                  |
| Type of information | `Numeric unsigned`                 |
| Units               | `B`                                |
| Update interval     | `10m`                              |
| History             | `31d`                              |
| Trends              | `365d`                             |

Observação:

```text
Os itens de tamanho serão usados apenas para consulta em Latest data.
Não criaremos triggers de capacidade neste momento.
```

## 14. Criar check externo de porta

Esse check valida a porta `8200` a partir do ponto de vista do Zabbix Server.

No template ou diretamente no host, crie o item abaixo.

## 14.1 Porta externa 8200

| Campo               | Valor                                     |
| ------------------- | ----------------------------------------- |
| Name                | `Vault: Porta externa 8200`               |
| Type                | `Simple check`                            |
| Key                 | `net.tcp.service[tcp,192.168.31.37,8200]` |
| Type of information | `Numeric unsigned`                        |
| Update interval     | `1m`                                      |
| History             | `31d`                                     |
| Trends              | `365d`                                    |

## 15. Criar triggers no template

No Zabbix, acesse:

```text
Data collection
Templates
Template Vault JMSalles
Triggers
Create trigger
```

## 15.1 Vault HTTPS health falhando

| Campo                         | Valor                                                         |
| ----------------------------- | ------------------------------------------------------------- |
| Name                          | `Vault: HTTPS health falhando`                                |
| Severity                      | `High`                                                        |
| Expression                    | `last(/Template Vault JMSalles/vault.health.https.code)<>200` |
| OK event generation           | `Expression`                                                  |
| PROBLEM event generation mode | `Single`                                                      |
| Enabled                       | Sim                                                           |

Observação:

```text
Quando o Vault está sealed, o health pode retornar 503.
Nesse caso, esta trigger também abre alerta.
```

## 15.2 Vault health local falhando

| Campo                         | Valor                                                         |
| ----------------------------- | ------------------------------------------------------------- |
| Name                          | `Vault: Health local falhando`                                |
| Severity                      | `High`                                                        |
| Expression                    | `last(/Template Vault JMSalles/vault.health.local.code)<>200` |
| OK event generation           | `Expression`                                                  |
| PROBLEM event generation mode | `Single`                                                      |
| Enabled                       | Sim                                                           |

## 15.3 Vault não inicializado

| Campo                         | Valor                                                |
| ----------------------------- | ---------------------------------------------------- |
| Name                          | `Vault: Nao inicializado`                            |
| Severity                      | `High`                                               |
| Expression                    | `last(/Template Vault JMSalles/vault.initialized)=0` |
| OK event generation           | `Expression`                                         |
| PROBLEM event generation mode | `Single`                                             |
| Enabled                       | Sim                                                  |

## 15.4 Vault initialized desconhecido

| Campo                         | Valor                                                |
| ----------------------------- | ---------------------------------------------------- |
| Name                          | `Vault: Initialized status desconhecido`             |
| Severity                      | `Average`                                            |
| Expression                    | `last(/Template Vault JMSalles/vault.initialized)=2` |
| OK event generation           | `Expression`                                         |
| PROBLEM event generation mode | `Single`                                             |
| Enabled                       | Sim                                                  |

## 15.5 Vault sealed

| Campo                         | Valor                                           |
| ----------------------------- | ----------------------------------------------- |
| Name                          | `Vault: Sealed`                                 |
| Severity                      | `High`                                          |
| Expression                    | `last(/Template Vault JMSalles/vault.sealed)=1` |
| OK event generation           | `Expression`                                    |
| PROBLEM event generation mode | `Single`                                        |
| Enabled                       | Sim                                             |

Observação:

```text
Este é um dos alertas mais importantes.
Quando disparar, será necessário executar o unseal com 3 unseal keys.
```

## 15.6 Vault sealed status desconhecido

| Campo                         | Valor                                           |
| ----------------------------- | ----------------------------------------------- |
| Name                          | `Vault: Sealed status desconhecido`             |
| Severity                      | `Average`                                       |
| Expression                    | `last(/Template Vault JMSalles/vault.sealed)=2` |
| OK event generation           | `Expression`                                    |
| PROBLEM event generation mode | `Single`                                        |
| Enabled                       | Sim                                             |

## 15.7 Porta local 8200 indisponível

| Campo                         | Valor                                                    |
| ----------------------------- | -------------------------------------------------------- |
| Name                          | `Vault: Porta local 8200 indisponivel`                   |
| Severity                      | `High`                                                   |
| Expression                    | `last(/Template Vault JMSalles/vault.tcp.local[8200])=0` |
| OK event generation           | `Expression`                                             |
| PROBLEM event generation mode | `Single`                                                 |
| Enabled                       | Sim                                                      |

## 15.8 Container Vault parado

| Campo                         | Valor                                                             |
| ----------------------------- | ----------------------------------------------------------------- |
| Name                          | `Vault: Container vault parado`                                   |
| Severity                      | `High`                                                            |
| Expression                    | `last(/Template Vault JMSalles/vault.container.running[vault])=0` |
| OK event generation           | `Expression`                                                      |
| PROBLEM event generation mode | `Single`                                                          |
| Enabled                       | Sim                                                               |

## 15.9 Container Vault reiniciou recentemente

| Campo                         | Valor                                                               |
| ----------------------------- | ------------------------------------------------------------------- |
| Name                          | `Vault: Container vault reiniciou recentemente`                     |
| Severity                      | `Warning`                                                           |
| Expression                    | `change(/Template Vault JMSalles/vault.container.restart[vault])>0` |
| OK event generation           | `Expression`                                                        |
| PROBLEM event generation mode | `Single`                                                            |
| Enabled                       | Sim                                                                 |

## 16. Criar trigger para check externo de porta

Se o item de Simple check foi criado no template, crie a trigger abaixo.

## 16.1 Porta externa 8200 indisponível

| Campo                         | Valor                                                                      |
| ----------------------------- | -------------------------------------------------------------------------- |
| Name                          | `Vault: Porta externa 8200 indisponivel`                                   |
| Severity                      | `Average`                                                                  |
| Expression                    | `last(/Template Vault JMSalles/net.tcp.service[tcp,192.168.31.37,8200])=0` |
| OK event generation           | `Expression`                                                               |
| PROBLEM event generation mode | `Single`                                                                   |
| Enabled                       | Sim                                                                        |

## 17. Criar Web Scenario do Vault

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
| Name            | `Vault - HTTPS` |
| Update interval | `1m`            |
| Attempts        | `3`             |
| Agent           | `Chrome`        |
| Enabled         | Sim             |

Crie o Step 1:

| Campo                 | Valor                                             |
| --------------------- | ------------------------------------------------- |
| Name                  | `Vault Health`                                    |
| URL                   | `https://vault.jmsalles.homelab.br/v1/sys/health` |
| Timeout               | `10s`                                             |
| Required status codes | `200`                                             |

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

## 18. Criar trigger do Web Scenario

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
| Name                          | `Vault: Web scenario HTTPS falhando`                                    |
| Severity                      | `High`                                                                  |
| Expression                    | `last(/docker-hml.jmsalles.homelab.br/web.test.fail[Vault - HTTPS])<>0` |
| OK event generation           | `Expression`                                                            |
| PROBLEM event generation mode | `Single`                                                                |
| Enabled                       | Sim                                                                     |

Opcionalmente, crie uma trigger para tempo de resposta alto:

| Campo      | Valor                                                                                    |
| ---------- | ---------------------------------------------------------------------------------------- |
| Name       | `Vault: Tempo de resposta alto`                                                          |
| Severity   | `Warning`                                                                                |
| Expression | `last(/docker-hml.jmsalles.homelab.br/web.test.time[Vault - HTTPS,Vault Health,resp])>3` |
| Enabled    | Sim                                                                                      |

Observação:

```text
O valor 3 representa 3 segundos.
Esse limite pode ser ajustado depois conforme o comportamento real do ambiente.
```

## 19. Validar em Latest data

No Zabbix, acesse:

```text
Monitoring
Latest data
```

Use os filtros:

```text
Host: docker-hml.jmsalles.homelab.br
Name: Vault
```

Você deve ver itens como:

```text
Vault: Health local status code
Vault: Health HTTPS status code
Vault: Initialized status
Vault: Sealed status
Vault: Porta local 8200 status
Vault: Container vault rodando
Vault: Restart count do container vault
Vault: Tamanho do diretorio data
Vault: Tamanho do diretorio logs
```

Valores esperados com Vault funcionando:

| Item                              | Valor esperado |
| --------------------------------- | -------------- |
| `Vault: Health local status code` | `200`          |
| `Vault: Health HTTPS status code` | `200`          |
| `Vault: Initialized status`       | `1`            |
| `Vault: Sealed status`            | `0`            |
| `Vault: Porta local 8200 status`  | `1`            |
| `Vault: Container vault rodando`  | `1`            |

## 20. Teste controlado de sealed

Este teste valida se o Zabbix alerta quando o Vault fica sealed.

Como seu Vault não possui auto-unseal, após restart ele pode voltar sealed.

Reinicie o container.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose restart vault
```

Aguarde alguns segundos e valide:

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health
```

Teste o item:

```bash
zabbix_agent2 -t vault.sealed
```

Resultado esperado se estiver sealed:

```text
vault.sealed [s|1]
```

Alertas esperados no Zabbix:

```text
Vault: Sealed
Vault: HTTPS health falhando
Vault: Health local falhando
Vault: Web scenario HTTPS falhando
```

Agora faça o unseal.

```bash
docker exec -it vault sh
```

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
```

Execute o unseal com 3 chaves diferentes.

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

Teste novamente:

```bash
zabbix_agent2 -t vault.sealed
```

Resultado esperado:

```text
vault.sealed [s|0]
```

## 21. Teste controlado de container parado

Para testar alerta de container parado, pare o Vault.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose stop vault
```

Teste localmente:

```bash
zabbix_agent2 -t 'vault.container.running[vault]'
```

Resultado esperado:

```text
vault.container.running[vault] [s|0]
```

Alertas esperados no Zabbix:

```text
Vault: Container vault parado
Vault: Porta local 8200 indisponivel
Vault: HTTPS health falhando
Vault: Health local falhando
Vault: Web scenario HTTPS falhando
```

Suba novamente:

```bash
docker compose start vault
```

Valide:

```bash
docker ps | grep vault
```

Como o Vault pode voltar sealed, faça o unseal se necessário.

## 22. Teste com container removido

Se você usar `docker compose down`, o container será removido.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose down
```

Mesmo assim, o item customizado deve retornar `0`.

```bash
zabbix_agent2 -t 'vault.container.running[vault]'
```

Resultado esperado:

```text
vault.container.running[vault] [s|0]
```

Para subir novamente:

```bash
docker compose up -d
```

Valide:

```bash
docker ps | grep vault
```

Faça unseal se necessário.

## 23. Testar coleta a partir do Zabbix Server

No servidor Zabbix, se tiver `zabbix_get`, teste:

```bash
zabbix_get -s 192.168.31.37 -k vault.health.local.code
```

```bash
zabbix_get -s 192.168.31.37 -k vault.health.https.code
```

```bash
zabbix_get -s 192.168.31.37 -k vault.initialized
```

```bash
zabbix_get -s 192.168.31.37 -k vault.sealed
```

```bash
zabbix_get -s 192.168.31.37 -k 'vault.container.running[vault]'
```

```bash
zabbix_get -s 192.168.31.37 -k 'vault.tcp.local[8200]'
```

Resultados esperados com Vault funcionando:

```text
200
```

ou:

```text
1
```

ou:

```text
0
```

Para instalar o `zabbix_get`, caso necessário:

```bash
sudo dnf install -y zabbix-get
```

## 24. Troubleshooting

## 24.1 Erro de certificado no curl

Erro:

```text
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Causa:

```text
O certificado do Vault é interno/autoassinado, ou foi assinado por uma CA interna que ainda não está instalada como confiável no host ou container.
```

Contorno adotado neste tutorial:

```bash
curl -k -I https://vault.jmsalles.homelab.br/v1/sys/health
```

Nos UserParameters, o contorno já está aplicado:

```ini
UserParameter=vault.health.https.code,curl -k -s --max-time 5 -o /dev/null -w "%{http_code}" https://vault.jmsalles.homelab.br/v1/sys/health 2>/dev/null
```

No Web Scenario do Zabbix, enquanto a CA não for instalada no container do Zabbix, deixe desmarcado:

```text
SSL verify peer
SSL verify host
```

## 24.2 Item retorna erro de tipo no Zabbix

Erro comum:

```text
Value of type "string" is not suitable for value type "Numeric (unsigned)"
```

Causa provável:

```text
O UserParameter está retornando valor com texto indevido.
```

Valide o arquivo:

```bash
sudo vim /etc/zabbix/zabbix_agent2.d/vault.conf
```

Garanta que os itens retornem apenas números.

Teste:

```bash
zabbix_agent2 -t vault.sealed
```

```bash
zabbix_agent2 -t vault.initialized
```

Os retornos devem ser:

```text
0
1
2
```

Reinicie o Agent:

```bash
sudo systemctl restart zabbix-agent2
```

## 24.3 Vault está rodando, mas `vault.sealed` retorna 2

Teste manualmente:

```bash
curl -k -s https://vault.jmsalles.homelab.br/v1/sys/health
```

Se o retorno estiver vazio, valide Nginx e Vault.

```bash
cd /home/jmsalles/vault
```

```bash
docker compose ps
```

```bash
docker compose logs --tail=100 vault
```

Valide Nginx.

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs --tail=100 nginx
```

Valide DNS.

```bash
nslookup vault.jmsalles.homelab.br
```

## 24.4 Vault sealed

Sintoma:

```text
vault.sealed = 1
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

Valide:

```bash
vault status
```

Saia:

```bash
exit
```

## 24.5 Vault não inicializado

Sintoma:

```text
vault.initialized = 0
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

Se realmente não estiver inicializado, inicialize apenas uma vez.

```bash
vault operator init -key-shares=5 -key-threshold=3
```

Atenção:

```text
Não execute init novamente em Vault já inicializado.
Se aparecer Vault is already initialized, use apenas o unseal.
```

## 24.6 Container Vault parado

Valide:

```bash
docker ps | grep vault
```

Valide compose:

```bash
cd /home/jmsalles/vault
```

```bash
docker compose ps
```

Suba:

```bash
docker compose up -d
```

Acompanhe logs:

```bash
docker compose logs -f vault
```

## 24.7 Porta 8200 indisponível

Valide porta:

```bash
ss -lntp | grep 8200
```

Valide container:

```bash
docker ps | grep vault
```

Valide porta publicada:

```bash
docker port vault
```

Resultado esperado:

```text
8200/tcp -> 0.0.0.0:8200
```

ou:

```text
8200/tcp -> [::]:8200
```

## 24.8 Nginx retorna 502 para o Vault

Teste localmente no host:

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

## 24.9 Zabbix não consegue consultar Docker

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

## 24.10 Tamanho de data ou logs retorna vazio

Valide se os diretórios existem.

```bash
ls -lah /home/jmsalles/vault
```

```bash
ls -lah /home/jmsalles/vault/data
```

```bash
ls -lah /home/jmsalles/vault/logs
```

Teste manualmente:

```bash
du -sb /home/jmsalles/vault/data
```

```bash
du -sb /home/jmsalles/vault/logs
```

## 25. Checklist final

| Item                                                        | Status   |
| ----------------------------------------------------------- | -------- |
| Template `Template Vault JMSalles` criado                   | Pendente |
| Template vinculado ao host `docker-hml.jmsalles.homelab.br` | Pendente |
| Arquivo `/etc/zabbix/zabbix_agent2.d/vault.conf` criado     | Pendente |
| UserParameters testados localmente                          | Pendente |
| Item health local criado                                    | Pendente |
| Item health HTTPS criado                                    | Pendente |
| Item initialized criado                                     | Pendente |
| Item sealed criado                                          | Pendente |
| Item porta local 8200 criado                                | Pendente |
| Item container `vault` criado                               | Pendente |
| Item restart count criado                                   | Pendente |
| Itens de tamanho de data/logs criados                       | Pendente |
| Trigger de Vault sealed criada                              | Pendente |
| Trigger de container parado criada                          | Pendente |
| Trigger de health falhando criada                           | Pendente |
| Trigger de porta 8200 indisponível criada                   | Pendente |
| Web Scenario do Vault criado                                | Pendente |
| Validação SSL desabilitada no Web Scenario                  | Pendente |
| Teste de sealed validado                                    | Pendente |
| Teste de parada do container validado                       | Pendente |

## 26. Resumo final

O monitoramento do Vault ficará dividido em cinco camadas:

```text
Disponibilidade externa
|
HTTPS Vault
Health endpoint
Web Scenario
```

```text
Estado do Vault
|
initialized
sealed
unsealed
```

```text
Serviço local
|
HTTP 8200
Porta local 8200
```

```text
Container
|
vault
restart count
```

```text
Capacidade básica
|
data
logs
```

Os principais itens customizados são:

```text
vault.container.running[vault]
vault.health.local.code
vault.health.https.code
vault.initialized
vault.sealed
vault.tcp.local[8200]
vault.container.restart[vault]
```

Valores principais esperados:

```text
vault.health.https.code = 200
vault.health.local.code = 200
vault.initialized = 1
vault.sealed = 0
vault.tcp.local[8200] = 1
vault.container.running[vault] = 1
```

Como o certificado é interno/autoassinado, este tutorial usa `curl -k` nos UserParameters e recomenda deixar `SSL verify peer` e `SSL verify host` desmarcados no Web Scenario até que a CA raiz seja instalada no container do Zabbix.

Com esse modelo, o Zabbix consegue identificar se a falha está no container, no Vault, no estado sealed, no Nginx reverse proxy, na porta local ou apenas na validação do certificado.

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
