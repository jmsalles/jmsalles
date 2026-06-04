# Guia de configuração do Windows Server 2022 como Controlador de Domínio no homelab JMSalles

## 1. Objetivo

Este documento descreve como configurar uma VM Windows Server 2022 como Controlador de Domínio Active Directory no homelab JMSalles.

A VM está hospedada no Dell com Rocky Linux, usando virtualização, e será responsável pelo domínio:

```text
jmsalles.homelab.br
```

O servidor atual está com o nome:

```text
winserver
```

O IP definido para esse servidor será:

```text
192.168.31.24
```

O servidor atuará inicialmente como:

```text
Controlador de Domínio
Servidor DNS
Global Catalog
Servidor Kerberos/KDC
Base de autenticação centralizada do homelab
```

## 2. Nome do servidor: precisa ser dc01?

Não é obrigatório o servidor se chamar `dc01`.

Você pode manter o nome atual:

```text
winserver
```

Nesse caso, o FQDN do Domain Controller será:

```text
winserver.jmsalles.homelab.br
```

O nome `dc01` é apenas uma convenção comum para facilitar identificação, principalmente quando há mais de um controlador de domínio.

Exemplos comuns:

```text
dc01
dc02
ad01
winserver
```

Para este tutorial, será mantido o nome atual:

```text
winserver
```

## 3. Cenário do ambiente

| Item                       | Valor                           |
| -------------------------- | ------------------------------- |
| Host físico                | Dell com Rocky Linux            |
| Função do host físico      | Virtualização                   |
| VM                         | Windows Server 2022             |
| RAM da VM                  | 16 GB                           |
| Nome atual do servidor     | `winserver`                     |
| IP do servidor             | `192.168.31.24`                 |
| Domínio AD                 | `jmsalles.homelab.br`           |
| FQDN do DC                 | `winserver.jmsalles.homelab.br` |
| NetBIOS Domain Name        | `JMSALLES`                      |
| Rede do homelab            | `192.168.31.0/24`               |
| Gateway                    | `192.168.31.1`                  |
| DNS principal dos clientes | `192.168.31.24`                 |

## 4. Atenção sobre DNS do homelab

Como o domínio escolhido é:

```text
jmsalles.homelab.br
```

o DNS do Active Directory será autoritativo por essa zona.

Hoje você possui a zona BIND no servidor Linux:

```text
/var/named/db.jmsalles.homelab.br
```

A ideia deste procedimento é popular essas entradas no DNS do Windows Server.

Depois disso, clientes do domínio deverão usar como DNS principal:

```text
192.168.31.24
```

Ponto importante:

```text
O DNS do AD será o DNS principal do domínio.
Os registros atuais do BIND serão recriados no DNS do Windows.
O DNS do AD usará forwarders para resolver internet e nomes externos.
```

## 5. Pré-requisitos

Antes de promover o Windows Server 2022 para Domain Controller, valide:

```text
Windows Server 2022 instalado
IP fixo configurado
Nome do servidor definido como winserver
Hora correta
Rede funcionando
Gateway configurado
Acesso administrativo local
PowerShell como Administrador
```

## 6. Habilitar PowerShell Remoting

No servidor `winserver`, abra o PowerShell como Administrador.

Execute:

```powershell
Enable-PSRemoting -Force
```

Valide o serviço WinRM:

```powershell
Get-Service WinRM
```

Configure o WinRM para iniciar automaticamente:

```powershell
Set-Service WinRM -StartupType Automatic
```

Inicie o serviço, se necessário:

```powershell
Start-Service WinRM
```

Libere o firewall para PowerShell Remoting:

```powershell
Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"
```

Valide a porta WinRM HTTP:

```powershell
netstat -ano | findstr 5985
```

Da sua máquina Windows, teste:

```powershell
Test-WSMan 192.168.31.24
```

Se sua máquina ainda não estiver no domínio, adicione o servidor em `TrustedHosts`:

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.31.24" -Force
```

Valide:

```powershell
Get-Item WSMan:\localhost\Client\TrustedHosts
```

Abrir sessão remota:

```powershell
Enter-PSSession -ComputerName 192.168.31.24 -Credential Administrator
```

Executar comando remoto sem entrar na sessão:

```powershell
Invoke-Command -ComputerName 192.168.31.24 -Credential Administrator -ScriptBlock {
    hostname
}
```

Sair da sessão remota:

```powershell
Exit-PSSession
```

## 7. Validar nome atual do servidor

Abra o PowerShell como Administrador.

Execute:

```powershell
hostname
```

Resultado esperado:

```text
winserver
```

Caso queira renomear antes da promoção, execute:

```powershell
Rename-Computer -NewName "dc01" -Restart
```

Neste tutorial, manteremos:

```text
winserver
```

## 8. Configurar IP fixo pelo PowerShell

Abra o PowerShell como Administrador.

Liste as interfaces:

```powershell
Get-NetAdapter
```

Identifique o nome da interface. Normalmente será:

```text
Ethernet
```

Valide a configuração atual:

```powershell
Get-NetIPConfiguration
```

Valide se o IP `192.168.31.24` já está configurado:

```powershell
Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4
```

Se o IP já estiver configurado, não recrie o IP. Apenas ajuste o DNS para ele mesmo:

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.31.24"
```

Se precisar configurar do zero, use a sequência abaixo.

Desabilite DHCP:

```powershell
Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Disabled
```

Configure o IP fixo:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.31.24" -PrefixLength 24 -DefaultGateway "192.168.31.1"
```

Configure o DNS apontando para ele mesmo:

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.31.24"
```

Valide:

```powershell
ipconfig /all
```

Teste o gateway:

```powershell
Test-Connection 192.168.31.1 -Count 4
```

Teste acesso externo por IP:

```powershell
Test-Connection 1.1.1.1 -Count 4
```

Valide DNS configurado:

```powershell
Get-DnsClientServerAddress -InterfaceAlias "Ethernet"
```

## 9. Ajustar timezone

Validar timezone:

```powershell
Get-TimeZone
```

Configurar timezone para Brasília:

```powershell
Set-TimeZone -Id "E. South America Standard Time"
```

Validar data e hora:

```powershell
Get-Date
```

## 10. Instalar funções AD DS e DNS

Abra o PowerShell como Administrador.

Instale as funções:

```powershell
Install-WindowsFeature AD-Domain-Services,DNS -IncludeManagementTools
```

Valide:

```powershell
Get-WindowsFeature AD-Domain-Services,DNS
```

Os recursos devem aparecer como instalados.

## 11. Promover o servidor a Domain Controller

Defina a senha do DSRM em uma variável segura:

```powershell
$SafeModePassword = Read-Host "Digite a senha DSRM" -AsSecureString
```

Promova o servidor criando uma nova floresta:

```powershell
Install-ADDSForest `
  -DomainName "jmsalles.homelab.br" `
  -DomainNetbiosName "JMSALLES" `
  -InstallDNS `
  -SafeModeAdministratorPassword $SafeModePassword `
  -Force
```

O servidor será reiniciado automaticamente.

Após o reboot, o login poderá ser feito como:

```text
JMSALLES\Administrator
```

ou:

```text
Administrator@jmsalles.homelab.br
```

## 12. Validar o domínio após o reboot

Abra o PowerShell como Administrador.

Validar domínio:

```powershell
Get-ADDomain
```

Validar floresta:

```powershell
Get-ADForest
```

Validar Domain Controller:

```powershell
Get-ADDomainController
```

Validar serviços principais:

```powershell
Get-Service NTDS,DNS,KDC,Netlogon,ADWS
```

Todos devem estar em execução.

## 13. Validar DNS do domínio

Teste resolução do próprio domínio:

```powershell
Resolve-DnsName jmsalles.homelab.br
```

Teste resolução do DC:

```powershell
Resolve-DnsName winserver.jmsalles.homelab.br
```

Teste via `nslookup`:

```powershell
nslookup winserver.jmsalles.homelab.br
```

Teste registros SRV do AD:

```powershell
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

Resultado esperado:

```text
winserver.jmsalles.homelab.br
```

## 14. Configurar forwarders DNS

Como o DNS do AD será o DNS principal dos clientes, configure forwarders para resolver nomes externos.

Exemplo usando gateway/roteador e DNS públicos como fallback:

```powershell
Add-DnsServerForwarder -IPAddress 192.168.31.1,1.1.1.1,8.8.8.8
```

Validar forwarders:

```powershell
Get-DnsServerForwarder
```

Teste resolução externa:

```powershell
Resolve-DnsName google.com
```

Se quiser manter temporariamente o DNS antigo `192.168.31.35` como apoio, ele também pode ser usado como forwarder:

```powershell
Add-DnsServerForwarder -IPAddress 192.168.31.35
```

## 15. Criar zona reversa da rede 192.168.31.0/24

Crie a zona reversa:

```powershell
Add-DnsServerPrimaryZone -NetworkId "192.168.31.0/24" -ReplicationScope "Forest"
```

Valide:

```powershell
Get-DnsServerZone
```

## 16. Criar registros DNS do homelab no AD DNS

Neste item, serão criadas as entradas DNS atuais dentro do DNS do Windows.

Observação:

```text
O registro ns1 será apontado para o novo DNS do AD: 192.168.31.24.
O servidor antigo de DNS/Zabbix continuará com os registros vm-lenovoi7-zabbix, zabbix e grafana apontando para 192.168.31.35.
```

Abra o PowerShell como Administrador no Domain Controller.

Execute o bloco abaixo:

```powershell
$ZoneName = "jmsalles.homelab.br"

$Records = @(
    @{Name="ns1"; IPv4Address="192.168.31.24"},

    @{Name="ap-xioami-principal"; IPv4Address="192.168.31.1"},
    @{Name="roteador"; IPv4Address="192.168.31.2"},
    @{Name="dvr"; IPv4Address="192.168.31.3"},
    @{Name="claro"; IPv4Address="192.168.31.4"},
    @{Name="vmware"; IPv4Address="192.168.31.11"},
    @{Name="minio-hm"; IPv4Address="192.168.31.21"},
    @{Name="docker-hm"; IPv4Address="192.168.31.22"},
    @{Name="winserver"; IPv4Address="192.168.31.24"},
    @{Name="notebook-qintess"; IPv4Address="192.168.31.29"},

    @{Name="am-pm"; IPv4Address="192.168.31.30"},
    @{Name="lenovo-i7"; IPv4Address="192.168.31.31"},
    @{Name="lenovo-server-linux"; IPv4Address="192.168.31.31"},
    @{Name="pr"; IPv4Address="192.168.31.31"},
    @{Name="prd"; IPv4Address="192.168.31.31"},

    @{Name="hp-i7-desktop"; IPv4Address="192.168.31.33"},

    @{Name="vm-lenovoi7-zabbix"; IPv4Address="192.168.31.35"},
    @{Name="zabbix"; IPv4Address="192.168.31.35"},
    @{Name="grafana"; IPv4Address="192.168.31.35"},

    @{Name="hpi7"; IPv4Address="192.168.31.36"},
    @{Name="hp-server-linux"; IPv4Address="192.168.31.36"},
    @{Name="hm"; IPv4Address="192.168.31.36"},
    @{Name="hml"; IPv4Address="192.168.31.36"},

    @{Name="docker-hml"; IPv4Address="192.168.31.37"},
    @{Name="pdf-hml"; IPv4Address="192.168.31.37"},
    @{Name="git"; IPv4Address="192.168.31.37"},
    @{Name="gitea"; IPv4Address="192.168.31.37"},
    @{Name="nexus"; IPv4Address="192.168.31.37"},
    @{Name="registry"; IPv4Address="192.168.31.37"},
    @{Name="vault"; IPv4Address="192.168.31.37"},
    @{Name="virtualizacao"; IPv4Address="192.168.31.37"},
    @{Name="virtualizacao-lenovo"; IPv4Address="192.168.31.37"},
    @{Name="virtualizacao-hpi7"; IPv4Address="192.168.31.37"},
    @{Name="virtualizacao-dell"; IPv4Address="192.168.31.37"},
    @{Name="openmetadata"; IPv4Address="192.168.31.37"},

    @{Name="dell"; IPv4Address="192.168.31.38"},
    @{Name="k8s-cp1"; IPv4Address="192.168.31.40"},
    @{Name="k8s-w1"; IPv4Address="192.168.31.41"},
    @{Name="k8s-w2"; IPv4Address="192.168.31.42"},
    @{Name="awx"; IPv4Address="192.168.31.44"},

    @{Name="celular-pedro"; IPv4Address="192.168.31.106"},
    @{Name="broadlink-rmpro"; IPv4Address="192.168.31.107"},
    @{Name="impressora"; IPv4Address="192.168.31.109"},
    @{Name="print"; IPv4Address="192.168.31.109"},
    @{Name="google-escritorio"; IPv4Address="192.168.31.110"},
    @{Name="tv-sala-jantar"; IPv4Address="192.168.31.111"},
    @{Name="tv-sala"; IPv4Address="192.168.31.112"},
    @{Name="tv-box-escritorio"; IPv4Address="192.168.31.121"},
    @{Name="ap-escritorio"; IPv4Address="192.168.31.126"},
    @{Name="haos"; IPv4Address="192.168.31.128"},
    @{Name="homeassistent"; IPv4Address="192.168.31.128"},
    @{Name="s23"; IPv4Address="192.168.31.133"},
    @{Name="porta-retrato"; IPv4Address="192.168.31.135"},
    @{Name="iphone-jeferson"; IPv4Address="192.168.31.137"},
    @{Name="ap-ana"; IPv4Address="192.168.31.138"},
    @{Name="notebook-petrobras"; IPv4Address="192.168.31.140"},
    @{Name="tv-box-varanda-mae"; IPv4Address="192.168.31.141"},
    @{Name="ap-mae"; IPv4Address="192.168.31.153"},
    @{Name="tv-mae"; IPv4Address="192.168.31.160"},
    @{Name="celular-mae"; IPv4Address="192.168.31.162"}
)

foreach ($Record in $Records) {
    $Existing = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $Record.Name -RRType "A" -ErrorAction SilentlyContinue

    if ($Existing) {
        foreach ($Item in $Existing) {
            Remove-DnsServerResourceRecord -ZoneName $ZoneName -InputObject $Item -Force
        }
    }

    Add-DnsServerResourceRecordA -ZoneName $ZoneName -Name $Record.Name -IPv4Address $Record.IPv4Address

    Write-Host "Registro criado/atualizado: $($Record.Name).$ZoneName -> $($Record.IPv4Address)"
}
```

Observação:

```text
O script remove e recria registros A existentes.
Isso evita erro caso algum registro já tenha sido criado automaticamente ou manualmente.
```

## 17. Validar registros DNS criados

Validar registros principais:

```powershell
Resolve-DnsName winserver.jmsalles.homelab.br
```

```powershell
Resolve-DnsName docker-hml.jmsalles.homelab.br
```

```powershell
Resolve-DnsName git.jmsalles.homelab.br
```

```powershell
Resolve-DnsName nexus.jmsalles.homelab.br
```

```powershell
Resolve-DnsName registry.jmsalles.homelab.br
```

```powershell
Resolve-DnsName vault.jmsalles.homelab.br
```

```powershell
Resolve-DnsName zabbix.jmsalles.homelab.br
```

```powershell
Resolve-DnsName grafana.jmsalles.homelab.br
```

```powershell
Resolve-DnsName k8s-cp1.jmsalles.homelab.br
```

Validar todos os registros da zona:

```powershell
Get-DnsServerResourceRecord -ZoneName "jmsalles.homelab.br" | Sort-Object HostName
```

## 18. Exemplo de criação manual de entrada DNS pelo PowerShell

Para criar uma entrada DNS manual no domínio `jmsalles.homelab.br`, use o comando abaixo.

Exemplo criando o registro:

```text
teste.jmsalles.homelab.br -> 192.168.31.50
```

Comando:

```powershell
Add-DnsServerResourceRecordA `
  -ZoneName "jmsalles.homelab.br" `
  -Name "teste" `
  -IPv4Address "192.168.31.50"
```

Validar:

```powershell
Resolve-DnsName teste.jmsalles.homelab.br
```

Também pode validar com:

```powershell
nslookup teste.jmsalles.homelab.br
```

## 19. Exemplo criando entrada DNS com PTR

Se a zona reversa já estiver criada, você pode criar o registro A e o PTR ao mesmo tempo usando `-CreatePtr`.

```powershell
Add-DnsServerResourceRecordA `
  -ZoneName "jmsalles.homelab.br" `
  -Name "teste" `
  -IPv4Address "192.168.31.50" `
  -CreatePtr
```

Validar reverso:

```powershell
Resolve-DnsName 192.168.31.50
```

## 20. Exemplo criando uma entrada real do homelab

Exemplo para criar um novo serviço chamado `portainer.jmsalles.homelab.br` apontando para o servidor Docker HML:

```powershell
Add-DnsServerResourceRecordA `
  -ZoneName "jmsalles.homelab.br" `
  -Name "portainer" `
  -IPv4Address "192.168.31.37" `
  -CreatePtr
```

Validar:

```powershell
Resolve-DnsName portainer.jmsalles.homelab.br
```

```powershell
nslookup portainer.jmsalles.homelab.br
```

## 21. Exemplo para atualizar uma entrada DNS existente

Se o registro já existir, remova e recrie.

Exemplo alterando `portainer.jmsalles.homelab.br` para outro IP:

```powershell
$ZoneName = "jmsalles.homelab.br"
$RecordName = "portainer"
$NewIP = "192.168.31.37"

$Existing = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $RecordName -RRType "A" -ErrorAction SilentlyContinue

if ($Existing) {
    foreach ($Item in $Existing) {
        Remove-DnsServerResourceRecord -ZoneName $ZoneName -InputObject $Item -Force
    }
}

Add-DnsServerResourceRecordA -ZoneName $ZoneName -Name $RecordName -IPv4Address $NewIP -CreatePtr
```

Validar:

```powershell
Resolve-DnsName portainer.jmsalles.homelab.br
```

## 22. Criar OUs básicas do homelab

Abra o PowerShell como Administrador.

Crie a estrutura base:

```powershell
New-ADOrganizationalUnit -Name "Homelab" -Path "DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Servers" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Workstations" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Users" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Groups" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Service Accounts" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Admins" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

Validar:

```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name,DistinguishedName
```

## 23. Criar grupo administrativo do homelab

Criar grupo para administradores:

```powershell
New-ADGroup `
  -Name "GRP_HOMELAB_ADMINS" `
  -SamAccountName "GRP_HOMELAB_ADMINS" `
  -GroupScope Global `
  -GroupCategory Security `
  -Path "OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

Validar:

```powershell
Get-ADGroup GRP_HOMELAB_ADMINS
```

## 24. Criar usuário administrativo `adm-jeferson`

Criar senha segura:

```powershell
$PasswordAdmJeferson = Read-Host "Digite a senha inicial do usuario adm-jeferson" -AsSecureString
```

Criar usuário administrativo:

```powershell
New-ADUser `
  -Name "Jeferson Salles Admin" `
  -GivenName "Jeferson" `
  -Surname "Salles Admin" `
  -SamAccountName "adm-jeferson" `
  -UserPrincipalName "adm-jeferson@jmsalles.homelab.br" `
  -Path "OU=Admins,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" `
  -AccountPassword $PasswordAdmJeferson `
  -Enabled $true `
  -ChangePasswordAtLogon $false
```

Adicionar ao grupo administrativo do homelab:

```powershell
Add-ADGroupMember -Identity "GRP_HOMELAB_ADMINS" -Members "adm-jeferson"
```

Adicionar ao grupo `Domain Admins`:

```powershell
Add-ADGroupMember -Identity "Domain Admins" -Members "adm-jeferson"
```

Validar usuário:

```powershell
Get-ADUser adm-jeferson -Properties UserPrincipalName,Enabled,MemberOf
```

Validar grupos do usuário:

```powershell
Get-ADPrincipalGroupMembership adm-jeferson | Select-Object Name
```

## 25. Criar usuário administrativo `jmsalles`

O usuário `jmsalles` será criado com as mesmas permissões e grupos do `adm-jeferson`.

Criar senha segura:

```powershell
$PasswordJmsalles = Read-Host "Digite a senha inicial do usuario jmsalles" -AsSecureString
```

Criar o usuário:

```powershell
New-ADUser `
  -Name "Jeferson Salles" `
  -GivenName "Jeferson" `
  -Surname "Salles" `
  -SamAccountName "jmsalles" `
  -UserPrincipalName "jmsalles@jmsalles.homelab.br" `
  -Path "OU=Admins,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" `
  -AccountPassword $PasswordJmsalles `
  -Enabled $true `
  -ChangePasswordAtLogon $false
```

Adicionar ao grupo administrativo do homelab:

```powershell
Add-ADGroupMember -Identity "GRP_HOMELAB_ADMINS" -Members "jmsalles"
```

Adicionar ao grupo `Domain Admins`:

```powershell
Add-ADGroupMember -Identity "Domain Admins" -Members "jmsalles"
```

Validar usuário:

```powershell
Get-ADUser jmsalles -Properties UserPrincipalName,Enabled,MemberOf
```

Validar grupos do usuário:

```powershell
Get-ADPrincipalGroupMembership jmsalles | Select-Object Name
```

Comparar os grupos dos dois usuários:

```powershell
Get-ADPrincipalGroupMembership adm-jeferson | Select-Object Name
```

```powershell
Get-ADPrincipalGroupMembership jmsalles | Select-Object Name
```

Resultado esperado:

```text
Domain Admins
GRP_HOMELAB_ADMINS
Domain Users
```

## 26. Usuários administrativos criados

Ao final, você terá dois usuários administrativos:

```text
adm-jeferson
jmsalles
```

Uso sugerido:

| Usuário        | Finalidade                                           |
| -------------- | ---------------------------------------------------- |
| `adm-jeferson` | Conta administrativa nominal principal               |
| `jmsalles`     | Conta administrativa alternativa para uso no homelab |

Login no domínio:

```text
JMSALLES\adm-jeferson
```

```text
JMSALLES\jmsalles
```

Ou usando UPN:

```text
adm-jeferson@jmsalles.homelab.br
```

```text
jmsalles@jmsalles.homelab.br
```

## 27. Configurar sincronização de horário

Em um domínio Active Directory, o horário é crítico para Kerberos.

No DC, configure NTP externo.

Abra o PowerShell como Administrador:

```powershell
w32tm /config /manualpeerlist:"a.ntp.br b.ntp.br pool.ntp.org" /syncfromflags:manual /reliable:yes /update
```

Reinicie o serviço de tempo:

```powershell
Restart-Service w32time
```

Force sincronização:

```powershell
w32tm /resync
```

Valide:

```powershell
w32tm /query /status
```

```powershell
w32tm /query /source
```

## 28. Validar saúde do Domain Controller

Execute:

```powershell
dcdiag
```

Para salvar em arquivo:

```powershell
dcdiag /v > C:\dcdiag-jmsalles.txt
```

Validar DNS:

```powershell
dcdiag /test:dns /v
```

Validar FSMO roles:

```powershell
netdom query fsmo
```

Resultado esperado:

```text
Todas as FSMO roles devem estar no winserver.
```

Validar serviços:

```powershell
Get-Service NTDS,DNS,KDC,Netlogon,ADWS
```

## 29. Ajustar DNS dos clientes da rede

Para clientes Windows, Linux e outros servidores ingressarem no domínio, eles devem usar como DNS principal:

```text
192.168.31.24
```

Não use como DNS principal em máquinas do domínio:

```text
1.1.1.1
8.8.8.8
Roteador
```

Motivo:

```text
Máquinas de domínio precisam consultar os registros SRV do Active Directory.
Esses registros existem no DNS do AD.
```

O roteador ou DHCP da rede pode entregar o DNS do DC para os clientes.

Exemplo:

```text
DNS primário via DHCP: 192.168.31.24
DNS secundário: vazio ou futuro DC02
```

## 30. Testar resolução DNS a partir de outro cliente

Em uma máquina Windows cliente, configure temporariamente o DNS para:

```text
192.168.31.24
```

Teste:

```powershell
nslookup jmsalles.homelab.br
```

```powershell
nslookup winserver.jmsalles.homelab.br
```

```powershell
nslookup git.jmsalles.homelab.br
```

```powershell
nslookup nexus.jmsalles.homelab.br
```

```powershell
nslookup vault.jmsalles.homelab.br
```

```powershell
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

## 31. Ingressar uma máquina Windows no domínio

Na estação Windows, configure o DNS para:

```text
192.168.31.24
```

Validar DNS:

```powershell
nslookup jmsalles.homelab.br
```

```powershell
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

Ingressar no domínio via PowerShell:

```powershell
Add-Computer -DomainName "jmsalles.homelab.br" -Credential "JMSALLES\adm-jeferson" -Restart
```

Ou usando o usuário `jmsalles`:

```powershell
Add-Computer -DomainName "jmsalles.homelab.br" -Credential "JMSALLES\jmsalles" -Restart
```

Após reiniciar, faça login com:

```text
JMSALLES\adm-jeferson
```

ou:

```text
JMSALLES\jmsalles
```

## 32. Ingressar uma máquina Linux no domínio

Exemplo para Rocky Linux.

Instalar pacotes:

```bash
sudo dnf install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir adcli samba-common-tools krb5-workstation
```

Configurar DNS da máquina Linux para apontar para o DC:

```text
192.168.31.24
```

Validar resolução:

```bash
nslookup jmsalles.homelab.br
```

```bash
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

Descobrir domínio:

```bash
realm discover jmsalles.homelab.br
```

Ingressar no domínio:

```bash
sudo realm join --user=adm-jeferson jmsalles.homelab.br
```

Ou usando o usuário `jmsalles`:

```bash
sudo realm join --user=jmsalles jmsalles.homelab.br
```

Validar:

```bash
realm list
```

```bash
id adm-jeferson@jmsalles.homelab.br
```

```bash
id jmsalles@jmsalles.homelab.br
```

Habilitar criação automática de home:

```bash
sudo authselect enable-feature with-mkhomedir
```

```bash
sudo systemctl restart sssd
```

## 33. Política de senha inicial

Neste momento não serão criadas GPOs.

Apenas será ajustada a política padrão de senha do domínio.

Para homelab, uma política inicial razoável:

```text
Tamanho mínimo: 12 caracteres
Complexidade: habilitada
Histórico: 5 senhas
Bloqueio por tentativa: habilitado
```

Validar política atual:

```powershell
Get-ADDefaultDomainPasswordPolicy
```

Exemplo de ajuste:

```powershell
Set-ADDefaultDomainPasswordPolicy `
  -Identity "jmsalles.homelab.br" `
  -MinPasswordLength 12 `
  -PasswordHistoryCount 5 `
  -ComplexityEnabled $true `
  -LockoutThreshold 5 `
  -LockoutDuration "00:15:00" `
  -LockoutObservationWindow "00:15:00"
```

Validar:

```powershell
Get-ADDefaultDomainPasswordPolicy
```

## 34. Backup inicial do Domain Controller

Para um DC, o backup mais importante é o System State.

Instalar recurso de backup:

```powershell
Install-WindowsFeature Windows-Server-Backup
```

Validar:

```powershell
Get-WindowsFeature Windows-Server-Backup
```

Executar backup manual do System State para um disco dedicado ou volume de backup.

Exemplo:

```powershell
wbadmin start systemstatebackup -backupTarget:E: -quiet
```

Observação:

```text
A unidade E: é apenas exemplo.
Use um disco/volume de backup real.
Não salve backup crítico apenas dentro do mesmo disco da VM.
```

## 35. Portas principais do Active Directory

As principais portas envolvidas no funcionamento do AD são:

|       Porta | Protocolo | Uso                      |
| ----------: | --------- | ------------------------ |
|          53 | TCP/UDP   | DNS                      |
|          88 | TCP/UDP   | Kerberos                 |
|         123 | UDP       | NTP                      |
|         135 | TCP       | RPC Endpoint Mapper      |
|         389 | TCP/UDP   | LDAP                     |
|         445 | TCP       | SMB                      |
|         464 | TCP/UDP   | Kerberos password change |
|         636 | TCP       | LDAPS                    |
|        3268 | TCP       | Global Catalog           |
|        3269 | TCP       | Global Catalog SSL       |
| 49152-65535 | TCP       | RPC dinâmico             |

No próprio Windows Server, as regras do firewall são criadas ao instalar AD DS e DNS.

Validar regras relacionadas ao AD:

```powershell
Get-NetFirewallRule | Where-Object DisplayGroup -Like "*Active Directory*" | Select-Object DisplayName,Enabled
```

Validar regras de DNS:

```powershell
Get-NetFirewallRule | Where-Object DisplayGroup -Like "*DNS*" | Select-Object DisplayName,Enabled
```

## 36. Validações finais

Validar domínio:

```powershell
Get-ADDomain
```

Validar floresta:

```powershell
Get-ADForest
```

Validar DC:

```powershell
Get-ADDomainController
```

Validar FSMO:

```powershell
netdom query fsmo
```

Validar DNS do DC:

```powershell
Resolve-DnsName winserver.jmsalles.homelab.br
```

Validar DNS dos serviços do homelab:

```powershell
Resolve-DnsName docker-hml.jmsalles.homelab.br
```

```powershell
Resolve-DnsName git.jmsalles.homelab.br
```

```powershell
Resolve-DnsName nexus.jmsalles.homelab.br
```

```powershell
Resolve-DnsName registry.jmsalles.homelab.br
```

```powershell
Resolve-DnsName vault.jmsalles.homelab.br
```

```powershell
Resolve-DnsName zabbix.jmsalles.homelab.br
```

Validar internet via DNS forwarder:

```powershell
Resolve-DnsName google.com
```

Validar serviços:

```powershell
Get-Service NTDS,DNS,KDC,Netlogon,ADWS
```

Validar saúde geral:

```powershell
dcdiag
```

## 37. Próximos passos recomendados

Após o DC estar funcionando, a ordem recomendada para o seu lab é:

```text
1. Ajustar DHCP da rede para entregar 192.168.31.24 como DNS principal
2. Validar resolução dos nomes do homelab usando o DNS do AD
3. Ingressar uma máquina Windows de teste no domínio
4. Ingressar uma máquina Linux de teste no domínio
5. Monitorar o Windows Server 2022 Domain Controller no Zabbix
6. Futuramente criar GPOs básicas
7. Futuramente criar usuários padrão e contas de serviço
8. Futuramente integrar serviços do homelab com LDAP/AD
```

Serviços que futuramente podem autenticar no AD:

```text
Gitea
Nexus
Vault
Windows Servers
Linux Servers via SSSD
Aplicações internas do homelab
```

## 38. Troubleshooting

### 38.1 Cliente não ingressa no domínio

Valide se o cliente usa o DNS do DC:

```powershell
ipconfig /all
```

Teste SRV:

```powershell
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

Teste ping no DC:

```powershell
Test-Connection winserver.jmsalles.homelab.br -Count 4
```

### 38.2 Nome do homelab não resolve

Valide se o registro existe no DNS do Windows:

```powershell
Get-DnsServerResourceRecord -ZoneName "jmsalles.homelab.br"
```

Criar registro manual, se necessário:

```powershell
Add-DnsServerResourceRecordA -ZoneName "jmsalles.homelab.br" -Name "<NOME>" -IPv4Address "<IP>"
```

### 38.3 Internet não resolve após apontar DNS para o DC

Valide forwarders:

```powershell
Get-DnsServerForwarder
```

Teste resolução externa:

```powershell
Resolve-DnsName google.com
```

Adicionar forwarder, se necessário:

```powershell
Add-DnsServerForwarder -IPAddress 192.168.31.1,1.1.1.1
```

### 38.4 Erro de horário ou Kerberos

Valide hora no cliente e no DC:

```powershell
w32tm /query /status
```

No DC:

```powershell
w32tm /query /source
```

Forçar resync:

```powershell
w32tm /resync
```

### 38.5 DC sem registros SRV

Reinicie Netlogon:

```powershell
Restart-Service Netlogon
```

Registrar DNS novamente:

```powershell
ipconfig /registerdns
```

Validar SRV:

```powershell
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

### 38.6 Serviço DNS parado

Validar:

```powershell
Get-Service DNS
```

Iniciar:

```powershell
Start-Service DNS
```

Configurar inicialização automática:

```powershell
Set-Service DNS -StartupType Automatic
```

### 38.7 Erro ao criar registro DNS já existente

Valide o registro:

```powershell
Get-DnsServerResourceRecord -ZoneName "jmsalles.homelab.br" -Name "<NOME>" -RRType "A"
```

Remova o registro antigo:

```powershell
Remove-DnsServerResourceRecord -ZoneName "jmsalles.homelab.br" -Name "<NOME>" -RRType "A" -Force
```

Crie novamente:

```powershell
Add-DnsServerResourceRecordA -ZoneName "jmsalles.homelab.br" -Name "<NOME>" -IPv4Address "<IP>"
```

## 39. Checklist final

| Item                                                  | Status   |
| ----------------------------------------------------- | -------- |
| VM Windows Server 2022 instalada                      | Pendente |
| IP fixo `192.168.31.24` configurado                   | Pendente |
| Nome `winserver` validado                             | Pendente |
| PowerShell Remoting habilitado                        | Pendente |
| Timezone configurado                                  | Pendente |
| AD DS instalado                                       | Pendente |
| DNS Server instalado                                  | Pendente |
| Servidor promovido a DC                               | Pendente |
| Domínio `jmsalles.homelab.br` criado                  | Pendente |
| NetBIOS `JMSALLES` criado                             | Pendente |
| Forwarders DNS configurados                           | Pendente |
| Zona reversa criada                                   | Pendente |
| Registros DNS do homelab migrados                     | Pendente |
| OUs básicas criadas                                   | Pendente |
| Grupo `GRP_HOMELAB_ADMINS` criado                     | Pendente |
| Usuário `adm-jeferson` criado                         | Pendente |
| Usuário `adm-jeferson` adicionado ao `Domain Admins`  | Pendente |
| Usuário `jmsalles` criado                             | Pendente |
| Usuário `jmsalles` adicionado ao `Domain Admins`      | Pendente |
| Usuário `jmsalles` adicionado ao `GRP_HOMELAB_ADMINS` | Pendente |
| NTP configurado                                       | Pendente |
| `dcdiag` executado                                    | Pendente |
| Cliente Windows de teste ingressado                   | Pendente |
| Cliente Linux de teste ingressado                     | Pendente |
| Backup System State planejado                         | Pendente |

## 40. Resumo final

Ao final deste procedimento, o homelab terá um domínio Active Directory funcional:

```text
jmsalles.homelab.br
```

Com Domain Controller:

```text
winserver.jmsalles.homelab.br
```

IP do Domain Controller:

```text
192.168.31.24
```

DNS principal da rede/domínio:

```text
192.168.31.24
```

E DNS centralizado para os serviços do homelab, incluindo:

```text
docker-hml.jmsalles.homelab.br
git.jmsalles.homelab.br
gitea.jmsalles.homelab.br
nexus.jmsalles.homelab.br
registry.jmsalles.homelab.br
vault.jmsalles.homelab.br
zabbix.jmsalles.homelab.br
grafana.jmsalles.homelab.br
pdf-hml.jmsalles.homelab.br
k8s-cp1.jmsalles.homelab.br
k8s-w1.jmsalles.homelab.br
k8s-w2.jmsalles.homelab.br
awx.jmsalles.homelab.br
```

Usuários administrativos criados:

```text
adm-jeferson
jmsalles
```

Não serão criadas GPOs neste momento.

Próxima etapa recomendada:

```text
Monitorar o Windows Server 2022 Domain Controller no Zabbix.
```

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
