# Guia completo de monitoramento do Active Directory e DNS no Zabbix 7.4.2

## 1. Objetivo

Este guia descreve a configuração de monitoramento do servidor Active Directory, DNS e LDAP do homelab JMSalles no Zabbix.

Servidor monitorado:

```text
Host no Zabbix: winserver
Visible name: Windows Server AD DNS LDAP
IP: 192.168.31.24
Sistema: Windows Server 2022
Funções: Active Directory, DNS e LDAP
Domínio: jmsalles.homelab.br
```

Versão do Zabbix:

```text
Zabbix Server: 7.4.2
```

Objetivo do monitoramento:

```text
Monitorar disponibilidade do servidor Windows
Monitorar recursos de CPU, memória, disco e rede
Monitorar serviços críticos do Active Directory
Monitorar DNS
Monitorar LDAP
Monitorar Kerberos
Monitorar Global Catalog
Monitorar eventos do AD/DNS
Usar template pronto de Active Directory sempre que possível
```

---

## 2. Estratégia adotada

A estratégia será usar primeiro templates prontos e importados.

```text
Camada 1 - Templates oficiais/base do Zabbix
|
|-- ICMP Ping
|-- Windows by Zabbix agent active

Camada 2 - Template importado de Active Directory
|
|-- Microsoft Active Directory Health
|-- AD DS Health
|-- Domain Controller Health
|-- Replication
|-- NTDS
|-- Eventos de AD
|-- Métricas específicas de Domain Controller

Camada 3 - Templates complementares simples
|
|-- Portas críticas do AD
|-- DNS Resolve
|-- Serviços Windows críticos
|-- Event Viewer
```

O template `LDAP Service` não será obrigatório neste guia, porque não foi encontrado no seu Zabbix 7.4.2.

No lugar dele, o LDAP será coberto por:

```text
Template importado de Active Directory
+
Template Homelab Active Directory Ports
```

---

## 3. Resultado esperado

Ao final, o host `winserver` terá monitoramento de:

```text
Ping
CPU
Memória
Disco
Rede
Uptime
Serviços Windows
NTDS
DNS
KDC
Netlogon
DFSR
W32Time
LDAP 389
Kerberos 88
DNS 53
SMB 445
Global Catalog 3268
Event Viewer do AD/DNS
```

---

## 4. Download do Zabbix Agent 2 para Windows Server 2016 ou superior

Para Windows Server 2016, 2019 e 2022, usar o instalador Windows x64 com OpenSSL.

Link informado:

```text
https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.11/zabbix_agent2-7.4.11-windows-amd64-openssl.msi
```

Arquivo:

```text
zabbix_agent2-7.4.11-windows-amd64-openssl.msi
```

Sugestão de pasta no Windows Server:

```text
C:\Temp
```

Caminho final sugerido:

```text
C:\Temp\zabbix_agent2-7.4.11-windows-amd64-openssl.msi
```

---

## 5. Instalar Zabbix Agent 2 via interface gráfica

No Windows Server, execute o MSI como Administrador.

Durante a instalação, preencher:

```text
Host name: winserver
Zabbix server IP/DNS: IP_DO_ZABBIX_SERVER
Server or Proxy for active checks: IP_DO_ZABBIX_SERVER
Listen port: 10050
```

Finalizar a instalação.

Validar serviço:

```powershell
Get-Service "Zabbix Agent 2"
```

Resultado esperado:

```text
Status   Name             DisplayName
------   ----             -----------
Running  Zabbix Agent 2   Zabbix Agent 2
```

---

## 6. Instalar Zabbix Agent 2 via PowerShell

Abra o PowerShell como Administrador.

Acesse a pasta:

```powershell
cd C:\Temp
```

Execute a instalação silenciosa:

```powershell
msiexec /i "C:\Temp\zabbix_agent2-7.4.11-windows-amd64-openssl.msi" /qn ^
  SERVER="IP_DO_ZABBIX_SERVER" ^
  SERVERACTIVE="IP_DO_ZABBIX_SERVER" ^
  HOSTNAME="winserver" ^
  LISTENPORT="10050" ^
  /l*v "C:\Temp\zabbix_agent2_install.log"
```

Validar instalação:

```powershell
Get-Service "Zabbix Agent 2"
```

Validar log de instalação:

```powershell
Get-Content "C:\Temp\zabbix_agent2_install.log" -Tail 50
```

---

## 7. Configurar o Zabbix Agent 2

Arquivo de configuração:

```text
C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf
```

Editar como Administrador.

Configuração recomendada:

```ini
Server=IP_DO_ZABBIX_SERVER
ServerActive=IP_DO_ZABBIX_SERVER
Hostname=winserver
ListenPort=10050
LogType=file
LogFile=C:\Program Files\Zabbix Agent 2\zabbix_agent2.log
Timeout=10
```

Ponto crítico:

```text
O valor Hostname=winserver precisa ser igual ao Host name criado no Zabbix.
```

Reiniciar o serviço:

```powershell
Restart-Service "Zabbix Agent 2"
```

Validar status:

```powershell
Get-Service "Zabbix Agent 2"
```

Validar log:

```powershell
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log" -Tail 50
```

---

## 8. Liberar firewall no Windows Server

Liberar entrada para o Zabbix Agent 2 na porta `10050/tcp`:

```powershell
New-NetFirewallRule `
  -DisplayName "Zabbix Agent 2 TCP 10050" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 10050 `
  -Action Allow
```

Validar regra:

```powershell
Get-NetFirewallRule -DisplayName "Zabbix Agent 2 TCP 10050"
```

Se houver firewall de saída restritivo, liberar saída do Windows Server para o Zabbix Server na porta:

```text
10051/tcp
```

Portas do AD que o Zabbix Server precisa alcançar para os checks simples:

```text
53/tcp    DNS
88/tcp    Kerberos
135/tcp   RPC Endpoint Mapper
389/tcp   LDAP
445/tcp   SMB
464/tcp   Kerberos password change
636/tcp   LDAPS, se usado
3268/tcp  Global Catalog
3269/tcp  Global Catalog SSL, se usado
```

---

## 9. Testar conectividade a partir do Zabbix Server

No Zabbix Server, testar acesso ao Windows Server:

```bash
nc -vz 192.168.31.24 10050
```

Testar portas críticas do AD:

```bash
nc -vz 192.168.31.24 53
nc -vz 192.168.31.24 88
nc -vz 192.168.31.24 135
nc -vz 192.168.31.24 389
nc -vz 192.168.31.24 445
nc -vz 192.168.31.24 464
nc -vz 192.168.31.24 3268
```

Se usar LDAPS:

```bash
nc -vz 192.168.31.24 636
nc -vz 192.168.31.24 3269
```

---

## 10. Criar grupos no Zabbix

No frontend do Zabbix:

```text
Data collection
Host groups
Create host group
```

Criar os grupos:

```text
Homelab/Windows
Homelab/Active Directory
Homelab/DNS
Homelab/Infraestrutura
```

Criar também grupos de templates:

```text
Templates/Homelab
Templates/Homelab/Testes
Templates/Homelab/Active Directory
```

Uso recomendado:

```text
Templates/Homelab/Testes
|
|-- Templates comunitários ainda em validação

Templates/Homelab/Active Directory
|
|-- Templates já validados para AD/DNS
```

---

## 11. Criar host winserver no Zabbix

No frontend:

```text
Data collection
Hosts
Create host
```

Configuração:

```text
Host name: winserver
Visible name: Windows Server AD DNS LDAP
```

Grupos:

```text
Homelab/Windows
Homelab/Active Directory
Homelab/DNS
```

Interface:

```text
Type: Agent
IP address: 192.168.31.24
DNS name: winserver.jmsalles.homelab.br
Connect to: IP
Port: 10050
```

Templates iniciais:

```text
ICMP Ping
Windows by Zabbix agent active
```

Salvar.

---

## 12. Associar templates oficiais/base

No host `winserver`, associar:

```text
ICMP Ping
Windows by Zabbix agent active
```

Dependendo da instalação, os nomes podem aparecer como:

```text
ICMP Ping
Template Module ICMP Ping
Windows by Zabbix agent active
Template OS Windows by Zabbix agent active
```

Se não encontrar, pesquisar por:

```text
ICMP
Ping
Windows
agent active
```

---

## 13. Validar coleta básica

Aguardar alguns minutos.

No frontend:

```text
Monitoring
Latest data
```

Filtrar:

```text
Host: winserver
```

Validar se aparecem dados de:

```text
ICMP ping
Agent availability
CPU
Memory
Filesystem
Network
Uptime
Windows services
```

Se não aparecer dados do agente ativo, validar no Windows:

```powershell
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log" -Tail 80
```

No Zabbix Server, validar log:

```bash
tail -f /var/log/zabbix/zabbix_server.log
```

---

## 14. Importar template pronto de Active Directory

Como a preferência é usar template pronto, a etapa principal do guia é importar um template comunitário de Active Directory Health.

Template recomendado para teste:

```text
Microsoft Active Directory Domain Services Health Template for Zabbix
```

Repositório de referência:

```text
ffurlanetti/Zabbix-Microsoft-Active-Directory-Health-Template
```

Esse template monitora itens relacionados a:

```text
Active Directory Health
Domain Controller status
Replication status
NTDS services
Security events
User, Group and GPO audit
Domain Controller performance
Authentication events
```

Atenção:

```text
O template informa suporte para Zabbix 7.0 até Zabbix 7.2.
Como seu ambiente usa Zabbix 7.4.2, importe primeiro em teste.
```

---

## 15. Baixar o template de Active Directory

Acesse o repositório do template comunitário e baixe o arquivo de template disponível no projeto.

Normalmente o arquivo será em um destes formatos:

```text
.yaml
.xml
.json
```

Recomendação:

```text
Baixar primeiro para sua máquina de administração.
Depois importar pelo frontend do Zabbix.
```

Evite aplicar direto em produção sem validar, porque templates comunitários podem ter dependências de macros, scripts, permissões WMI ou auditoria avançada.

---

## 16. Importar o template no Zabbix 7.4.2

No frontend do Zabbix:

```text
Data collection
Templates
Import
```

Selecione o arquivo baixado do template.

Na tela de importação, marque as opções equivalentes a:

```text
Create new
Update existing
```

Clique em:

```text
Import
```

Se a importação for aceita, o template aparecerá em:

```text
Data collection
Templates
```

Filtrar por:

```text
Active Directory
Microsoft
AD
Domain Controller
```

O nome pode variar, mas deve ser semelhante a:

```text
Microsoft Active Directory Health
Active Directory Health
Template Microsoft Active Directory Health
Microsoft AD DS
```

---

## 17. Se a importação falhar

Como seu Zabbix é `7.4.2` e o template comunitário informa suporte até `7.2`, pode aparecer erro de importação.

Erros comuns:

```text
Invalid tag
Invalid element
Unsupported template version
Unknown field
Invalid YAML/XML format
```

Nesse caso:

```text
1. Verifique se baixou o arquivo de template correto.
2. Confirme se o arquivo é YAML, XML ou JSON.
3. Tente importar sem atualizar templates existentes.
4. Crie um grupo de teste e importe novamente.
5. Se necessário, ajustar o YAML/XML para o formato aceito pelo Zabbix 7.4.2.
```

Se falhar, manter o monitoramento com:

```text
Windows by Zabbix agent active
ICMP Ping
Template Homelab Active Directory Ports
Template Homelab Active Directory Services
Template Homelab Active Directory DNS Resolve
Template Homelab Active Directory EventLog
```

---

## 18. Associar o template importado ao host winserver

No frontend:

```text
Data collection
Hosts
winserver
Templates
Link new templates
```

Adicionar o template importado:

```text
Microsoft Active Directory Health
```

ou o nome equivalente que apareceu após a importação.

Manter também:

```text
ICMP Ping
Windows by Zabbix agent active
```

Conjunto inicial recomendado:

```text
winserver
|
|-- ICMP Ping
|-- Windows by Zabbix agent active
|-- Microsoft Active Directory Health
```

Salvar.

---

## 19. Validar macros exigidas pelo template importado

Depois de importar o template, abrir:

```text
Data collection
Templates
Template importado
Macros
```

Verificar se o template exige macros como:

```text
{$DOMAIN}
{$AD.DOMAIN}
{$LDAP.USER}
{$LDAP.PASSWORD}
{$WMI.USER}
{$WMI.PASSWORD}
{$DC.NAME}
```

Os nomes exatos dependem do template importado.

No host `winserver`, adicione as macros necessárias conforme o template.

Macros base sugeridas para o host:

```text
{$AD.DOMAIN}=jmsalles.homelab.br
{$AD.DC}=winserver
{$AD.DC.FQDN}=winserver.jmsalles.homelab.br
{$AD.IP}=192.168.31.24
{$AD.LDAP.PORT}=389
{$AD.LDAPS.PORT}=636
{$AD.GC.PORT}=3268
{$AD.GCSSL.PORT}=3269
```

Se o template exigir usuário e senha, criar uma conta de serviço.

---

## 20. Criar conta de serviço para monitoramento AD

No Active Directory, criar usuário:

```text
svc_zabbix_ad
```

Sugestão:

```text
Usuário: svc_zabbix_ad
Descrição: Conta de serviço para monitoramento Zabbix AD
Senha: senha forte
Opção: Password never expires
```

Usuário completo:

```text
jmsalles\svc_zabbix_ad
```

Recomendação:

```text
Não usar Domain Admin para monitoramento contínuo.
Usar conta com menor privilégio possível.
```

Para testes iniciais no homelab, pode validar com uma conta administrativa temporariamente, mas depois ajustar para usuário de serviço.

---

## 21. Permissões recomendadas para a conta de serviço

A conta `svc_zabbix_ad` deve conseguir:

```text
Ler informações do Active Directory
Consultar WMI no Domain Controller
Ler contadores de performance
Ler Event Viewer, se o template exigir
```

Grupos úteis para começar:

```text
Domain Users
Event Log Readers
Performance Monitor Users
Distributed COM Users, se WMI exigir
```

Dependendo do template, pode ser necessário liberar WMI/DCOM explicitamente.

---

## 22. Validar WMI no Windows Server

No próprio Windows Server, testar WMI:

```powershell
Get-CimInstance Win32_OperatingSystem
```

Testar serviços do AD:

```powershell
Get-Service NTDS,DNS,KDC,Netlogon,DFSR,W32Time,LanmanServer
```

Validar domínio:

```powershell
Get-ADDomain
```

Validar Domain Controller:

```powershell
Get-ADDomainController
```

Validar DNS:

```powershell
Resolve-DnsName git.jmsalles.homelab.br
Resolve-DnsName inventario-hml.jmsalles.homelab.br
```

---

## 23. Configurar auditoria avançada se o template exigir

Alguns templates de AD Health dependem de Event Viewer e auditoria avançada.

No Windows Server, validar auditoria atual:

```powershell
auditpol /get /category:*
```

Para auditoria de Domain Controller, usar GPO:

```text
Group Policy Management
Default Domain Controllers Policy
Computer Configuration
Policies
Windows Settings
Security Settings
Advanced Audit Policy Configuration
```

Categorias úteis:

```text
Account Logon
Account Management
Directory Service Access
Logon/Logoff
Policy Change
System
```

Aplicar GPO:

```powershell
gpupdate /force
```

Validar eventos:

```text
Event Viewer
Windows Logs
Security
Applications and Services Logs
Directory Service
DNS Server
DFS Replication
```

---

## 24. Validar dados do template importado

Após associar o template importado, aguardar alguns minutos.

No frontend:

```text
Monitoring
Latest data
```

Filtrar:

```text
Host: winserver
```

Buscar por:

```text
Active Directory
AD
Domain Controller
Replication
NTDS
Kerberos
DNS
LDAP
Directory Service
Security
GPO
```

Validar se existem itens com dados recentes.

---

## 25. Ajustes se houver apenas um Domain Controller

Se seu homelab tiver apenas um Domain Controller, alguns itens de replicação podem gerar alerta sem necessidade.

Nesse caso, revisar e possivelmente desabilitar triggers relacionadas a:

```text
Replication partner
Replication latency
Replication failures between DCs
```

Manter ativos:

```text
NTDS
DNS
KDC
Netlogon
W32Time
LDAP
Kerberos
DNS resolution
Event Viewer
```

---

## 26. Criar template complementar de portas AD/DNS

Mesmo com template importado, recomendo criar um template simples de portas críticas. Ele serve como validação objetiva e independente do template comunitário.

No Zabbix:

```text
Data collection
Templates
Create template
```

Configuração:

```text
Template name: Template Homelab Active Directory Ports
Groups: Templates/Homelab/Active Directory
```

---

## 27. Itens de portas críticas

Dentro do template:

```text
Items
Create item
```

### DNS TCP 53

```text
Name: AD DNS TCP 53
Type: Simple check
Key: net.tcp.service[tcp,,53]
Update interval: 1m
History: 7d
Trends: 30d
```

### Kerberos TCP 88

```text
Name: AD Kerberos TCP 88
Type: Simple check
Key: net.tcp.service[tcp,,88]
Update interval: 1m
History: 7d
Trends: 30d
```

### RPC TCP 135

```text
Name: AD RPC TCP 135
Type: Simple check
Key: net.tcp.service[tcp,,135]
Update interval: 1m
History: 7d
Trends: 30d
```

### LDAP TCP 389

```text
Name: AD LDAP TCP 389
Type: Simple check
Key: net.tcp.service[ldap,,389]
Update interval: 1m
History: 7d
Trends: 30d
```

### SMB TCP 445

```text
Name: AD SMB TCP 445
Type: Simple check
Key: net.tcp.service[tcp,,445]
Update interval: 1m
History: 7d
Trends: 30d
```

### Kerberos Password TCP 464

```text
Name: AD Kerberos Password TCP 464
Type: Simple check
Key: net.tcp.service[tcp,,464]
Update interval: 1m
History: 7d
Trends: 30d
```

### Global Catalog TCP 3268

```text
Name: AD Global Catalog TCP 3268
Type: Simple check
Key: net.tcp.service[tcp,,3268]
Update interval: 1m
History: 7d
Trends: 30d
```

### LDAPS TCP 636

Criar somente se usar LDAPS:

```text
Name: AD LDAPS TCP 636
Type: Simple check
Key: net.tcp.service[tcp,,636]
Update interval: 1m
History: 7d
Trends: 30d
```

### Global Catalog SSL TCP 3269

Criar somente se usar Global Catalog com SSL:

```text
Name: AD Global Catalog SSL TCP 3269
Type: Simple check
Key: net.tcp.service[tcp,,3269]
Update interval: 1m
History: 7d
Trends: 30d
```

---

## 28. Triggers de portas críticas

Criar triggers no template `Template Homelab Active Directory Ports`.

### DNS indisponível

```text
Name: AD DNS TCP 53 indisponível em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Ports/net.tcp.service[tcp,,53])=0
```

### Kerberos indisponível

```text
Name: AD Kerberos TCP 88 indisponível em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Ports/net.tcp.service[tcp,,88])=0
```

### LDAP indisponível

```text
Name: AD LDAP TCP 389 indisponível em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Ports/net.tcp.service[ldap,,389])=0
```

### SMB indisponível

```text
Name: AD SMB TCP 445 indisponível em {HOST.NAME}
Severity: Average
Expression:
last(/Template Homelab Active Directory Ports/net.tcp.service[tcp,,445])=0
```

### Global Catalog indisponível

```text
Name: AD Global Catalog TCP 3268 indisponível em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Ports/net.tcp.service[tcp,,3268])=0
```

---

## 29. Criar template complementar de serviços AD

Criar template:

```text
Template name: Template Homelab Active Directory Services
Groups: Templates/Homelab/Active Directory
```

Itens:

### NTDS

```text
Name: Service NTDS state
Type: Zabbix agent active
Key: service.info[NTDS,state]
Update interval: 1m
```

### DNS

```text
Name: Service DNS state
Type: Zabbix agent active
Key: service.info[DNS,state]
Update interval: 1m
```

### KDC

```text
Name: Service KDC state
Type: Zabbix agent active
Key: service.info[KDC,state]
Update interval: 1m
```

### Netlogon

```text
Name: Service Netlogon state
Type: Zabbix agent active
Key: service.info[Netlogon,state]
Update interval: 1m
```

### DFSR

```text
Name: Service DFSR state
Type: Zabbix agent active
Key: service.info[DFSR,state]
Update interval: 1m
```

### W32Time

```text
Name: Service W32Time state
Type: Zabbix agent active
Key: service.info[W32Time,state]
Update interval: 1m
```

### LanmanServer

```text
Name: Service LanmanServer state
Type: Zabbix agent active
Key: service.info[LanmanServer,state]
Update interval: 1m
```

---

## 30. Triggers de serviços AD

### NTDS parado

```text
Name: Serviço NTDS parado em {HOST.NAME}
Severity: Disaster
Expression:
last(/Template Homelab Active Directory Services/service.info[NTDS,state])<>0
```

### DNS parado

```text
Name: Serviço DNS parado em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Services/service.info[DNS,state])<>0
```

### KDC parado

```text
Name: Serviço KDC parado em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Services/service.info[KDC,state])<>0
```

### Netlogon parado

```text
Name: Serviço Netlogon parado em {HOST.NAME}
Severity: High
Expression:
last(/Template Homelab Active Directory Services/service.info[Netlogon,state])<>0
```

### DFSR parado

```text
Name: Serviço DFSR parado em {HOST.NAME}
Severity: Average
Expression:
last(/Template Homelab Active Directory Services/service.info[DFSR,state])<>0
```

### W32Time parado

```text
Name: Serviço W32Time parado em {HOST.NAME}
Severity: Warning
Expression:
last(/Template Homelab Active Directory Services/service.info[W32Time,state])<>0
```

---

## 31. Criar template complementar de DNS Resolve

Criar template:

```text
Template name: Template Homelab Active Directory DNS Resolve
Groups: Templates/Homelab/Active Directory
```

Itens:

### Resolver Gitea

```text
Name: DNS resolve git.jmsalles.homelab.br
Type: Zabbix agent active
Key: net.dns[127.0.0.1,git.jmsalles.homelab.br,A,2,1]
Update interval: 1m
```

### Resolver Vault

```text
Name: DNS resolve vault.jmsalles.homelab.br
Type: Zabbix agent active
Key: net.dns[127.0.0.1,vault.jmsalles.homelab.br,A,2,1]
Update interval: 1m
```

### Resolver Inventário

```text
Name: DNS resolve inventario-hml.jmsalles.homelab.br
Type: Zabbix agent active
Key: net.dns[127.0.0.1,inventario-hml.jmsalles.homelab.br,A,2,1]
Update interval: 1m
```

### Resolver Portal API

```text
Name: DNS resolve portal-api-hml.jmsalles.homelab.br
Type: Zabbix agent active
Key: net.dns[127.0.0.1,portal-api-hml.jmsalles.homelab.br,A,2,1]
Update interval: 1m
```

---

## 32. Criar template complementar de EventLog

Criar template:

```text
Template name: Template Homelab Active Directory EventLog
Groups: Templates/Homelab/Active Directory
```

Itens:

### Directory Service errors

```text
Name: AD Directory Service errors
Type: Zabbix agent active
Key: eventlog[Directory Service,,,,^(1|2)$,,skip]
Type of information: Log
Update interval: 1m
```

### DNS Server errors

```text
Name: AD DNS Server errors
Type: Zabbix agent active
Key: eventlog[DNS Server,,,,^(1|2)$,,skip]
Type of information: Log
Update interval: 1m
```

### DFS Replication errors

```text
Name: AD DFS Replication errors
Type: Zabbix agent active
Key: eventlog[DFS Replication,,,,^(1|2)$,,skip]
Type of information: Log
Update interval: 1m
```

### Windows System errors

```text
Name: Windows System errors
Type: Zabbix agent active
Key: eventlog[System,,,,^(1|2)$,,skip]
Type of information: Log
Update interval: 1m
```

Observação:

```text
EventLog pode gerar ruído.
Comece coletando e só depois ajuste triggers.
```

---

## 33. Templates finais no host winserver

Configuração recomendada final:

```text
Host: winserver

Templates:
  ICMP Ping
  Windows by Zabbix agent active
  Microsoft Active Directory Health
  Template Homelab Active Directory Ports
  Template Homelab Active Directory Services
  Template Homelab Active Directory DNS Resolve
  Template Homelab Active Directory EventLog
```

Se o template importado gerar erro ou ruído, manter temporariamente:

```text
ICMP Ping
Windows by Zabbix agent active
Template Homelab Active Directory Ports
Template Homelab Active Directory Services
Template Homelab Active Directory DNS Resolve
Template Homelab Active Directory EventLog
```

---

## 34. Tags recomendadas no host

No host `winserver`, adicionar tags:

```text
environment: homelab
service: active-directory
service: dns
service: ldap
os: windows
criticality: high
```

Em triggers, usar tags como:

```text
component: ad
component: dns
component: ldap
component: kerberos
component: windows-service
component: eventlog
```

---

## 35. Validação final no Zabbix

Acessar:

```text
Monitoring
Latest data
```

Filtrar:

```text
Host: winserver
```

Validar itens:

```text
ICMP ping
Agent availability
Windows CPU
Windows memory
Windows filesystem
Windows network
AD DNS TCP 53
AD Kerberos TCP 88
AD LDAP TCP 389
AD SMB TCP 445
AD Global Catalog TCP 3268
Service NTDS state
Service DNS state
Service KDC state
Service Netlogon state
DNS resolve git.jmsalles.homelab.br
DNS resolve vault.jmsalles.homelab.br
Directory Service errors
DNS Server errors
```

---

## 36. Validação no Windows Server

No Windows Server:

```powershell
Get-Service NTDS,DNS,KDC,Netlogon,DFSR,W32Time,LanmanServer
```

Validar domínio:

```powershell
Get-ADDomain
```

Validar Domain Controller:

```powershell
Get-ADDomainController
```

Validar DNS:

```powershell
Resolve-DnsName git.jmsalles.homelab.br
Resolve-DnsName vault.jmsalles.homelab.br
Resolve-DnsName inventario-hml.jmsalles.homelab.br
Resolve-DnsName portal-api-hml.jmsalles.homelab.br
```

Validar logs do agente:

```powershell
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log" -Tail 80
```

---

## 37. Dashboard sugerido

Criar dashboard:

```text
Dashboard: Homelab - Active Directory
```

Widgets recomendados:

```text
Problems
Host availability
Latest data
Graph CPU
Graph Memory
Graph Disk C:
Portas AD
Serviços AD
Eventos AD/DNS
```

Filtro:

```text
Host group: Homelab/Active Directory
Host: winserver
```

---

## 38. Severidades recomendadas

```text
ICMP indisponível: High
Agent indisponível: Average
NTDS parado: Disaster
DNS parado: High
KDC parado: High
Netlogon parado: High
LDAP 389 indisponível: High
Kerberos 88 indisponível: High
DNS 53 indisponível: High
Global Catalog 3268 indisponível: High
DFSR parado: Average
W32Time parado: Warning
EventLog Directory Service Error: Average
EventLog DNS Server Error: Average
```

---

## 39. Testes controlados

Teste de DNS:

```powershell
Restart-Service DNS
```

Aguardar alerta no Zabbix e validar recuperação.

Teste de W32Time:

```powershell
Restart-Service W32Time
```

Teste de conectividade LDAP a partir do Zabbix Server:

```bash
nc -vz 192.168.31.24 389
```

Não recomendo parar serviços como:

```text
NTDS
KDC
Netlogon
```

sem snapshot ou janela de teste, porque pode afetar autenticação e funcionamento do domínio.

---

## 40. Troubleshooting

### 40.1 Host não coleta dados de Agent Active

Validar se o nome está igual.

No Zabbix:

```text
Host name: winserver
```

No Windows:

```ini
Hostname=winserver
```

Reiniciar agente:

```powershell
Restart-Service "Zabbix Agent 2"
```

Ver log:

```powershell
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log" -Tail 80
```

---

### 40.2 Não encontra template LDAP Service

Neste guia, o template `LDAP Service` não é obrigatório.

Usar:

```text
Template Homelab Active Directory Ports
```

Item LDAP:

```text
net.tcp.service[ldap,,389]
```

---

### 40.3 Template importado não funciona no Zabbix 7.4.2

Possível causa:

```text
Template comunitário criado/testado para Zabbix 7.0 até 7.2.
Ambiente atual: Zabbix 7.4.2.
```

Ações:

```text
Importar em grupo de teste
Revisar erro de importação
Ajustar YAML/XML se necessário
Desabilitar triggers com erro
Manter templates complementares manuais
```

---

### 40.4 Porta LDAP não responde

No Zabbix Server:

```bash
nc -vz 192.168.31.24 389
```

No Windows:

```powershell
Get-Service NTDS
```

Validar firewall:

```powershell
Get-NetFirewallProfile
```

---

### 40.5 DNS não resolve

No Windows Server:

```powershell
Get-Service DNS
```

```powershell
Resolve-DnsName git.jmsalles.homelab.br
```

No Zabbix Server:

```bash
nslookup git.jmsalles.homelab.br 192.168.31.24
```

---

## 41. Checklist final

| Item                                              | Status   |
| ------------------------------------------------- | -------- |
| Zabbix Server 7.4.2 validado                      | Pendente |
| Agent 2 Windows baixado                           | Pendente |
| Agent 2 instalado no Windows Server               | Pendente |
| `Hostname=winserver` configurado                  | Pendente |
| Firewall 10050/tcp liberado                       | Pendente |
| Host `winserver` criado no Zabbix                 | Pendente |
| Template ICMP Ping associado                      | Pendente |
| Template Windows by Zabbix agent active associado | Pendente |
| Template AD Health importado                      | Pendente |
| Template AD Health aplicado em teste              | Pendente |
| Template Homelab AD Ports criado                  | Pendente |
| Template Homelab AD Services criado               | Pendente |
| Template Homelab DNS Resolve criado               | Pendente |
| Template Homelab EventLog criado                  | Pendente |
| Portas 53, 88, 389, 445 e 3268 monitoradas        | Pendente |
| Serviços NTDS, DNS, KDC e Netlogon monitorados    | Pendente |
| Latest data validado                              | Pendente |
| Dashboard criado                                  | Pendente |

---

## 42. Resultado final

Ao final deste procedimento, o Active Directory do homelab será monitorado no Zabbix com:

```text
Host: winserver
IP: 192.168.31.24
Zabbix Server: 7.4.2
```

Templates principais:

```text
ICMP Ping
Windows by Zabbix agent active
Microsoft Active Directory Health
```

Templates complementares:

```text
Template Homelab Active Directory Ports
Template Homelab Active Directory Services
Template Homelab Active Directory DNS Resolve
Template Homelab Active Directory EventLog
```

Download usado para o Agent 2 Windows Server 2016 ou superior:

```text
https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.11/zabbix_agent2-7.4.11-windows-amd64-openssl.msi
```

Esse modelo prioriza template pronto de Active Directory, mas mantém verificações complementares simples para garantir monitoramento confiável de DNS, LDAP, Kerberos e serviços críticos do Domain Controller.

---

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
