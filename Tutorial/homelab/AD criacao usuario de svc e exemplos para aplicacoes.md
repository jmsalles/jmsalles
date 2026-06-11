Segue o tutorial completo, removendo toda a parte específica do Zabbix e mantendo apenas a criação do usuário de serviço LDAP para uso geral pelas aplicações do homelab.

# Guia de criação do usuário de serviço LDAP no Active Directory

## 1. Objetivo

Este documento descreve como criar uma conta de serviço no Active Directory para bind e consulta LDAP.

A conta será usada por aplicações do homelab que precisem consultar usuários e grupos no AD, como:

```text
Vault
Gitea
Nexus
Aplicações internas
Outras integrações LDAP
```

Conta de serviço padrão deste guia:

```text
svc-ldap-bind
```

## 2. Dados do ambiente

| Item                    | Valor                                                         |
| ----------------------- | ------------------------------------------------------------- |
| Domínio AD              | `jmsalles.homelab.br`                                         |
| Domain Controller       | `winserver.jmsalles.homelab.br`                               |
| IP do Domain Controller | `192.168.31.24`                                               |
| Base DN                 | `DC=jmsalles,DC=homelab,DC=br`                                |
| OU de contas de serviço | `OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |
| OU de grupos            | `OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br`           |
| Porta LDAP              | `389`                                                         |
| Conta de serviço        | `svc-ldap-bind`                                               |
| UPN da conta            | `svc-ldap-bind@jmsalles.homelab.br`                           |

## 3. Finalidade da conta svc-ldap-bind

A conta `svc-ldap-bind` será usada para autenticar a aplicação no AD e permitir consultas LDAP.

Exemplos de uso:

```text
Consultar se um usuário existe no AD
Consultar grupos de um usuário
Validar login de usuários em aplicações
Permitir integração LDAP com aplicações internas
```

Essa conta não deve ter privilégio administrativo.

Ela não deve ser adicionada aos grupos:

```text
Domain Admins
Enterprise Admins
Administrators
GRP_HOMELAB_ADMINS
```

Ela deve possuir somente permissão básica de leitura, suficiente para consultas LDAP.

## 4. Validar OUs existentes

No `winserver`, abra o PowerShell como Administrador.

Valide se a estrutura de OUs já existe:

```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name,DistinguishedName
```

Confirme se existem estas OUs:

```text
OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Se ainda não existirem, crie:

```powershell
New-ADOrganizationalUnit -Name "Homelab" -Path "DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Groups" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
New-ADOrganizationalUnit -Name "Service Accounts" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

## 5. Criar grupo para contas de bind LDAP

Crie um grupo específico para contas de serviço usadas em bind LDAP.

```powershell
New-ADGroup `
  -Name "GRP_SVC_LDAP_BIND" `
  -SamAccountName "GRP_SVC_LDAP_BIND" `
  -GroupScope Global `
  -GroupCategory Security `
  -Path "OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" `
  -Description "Grupo para contas de servico usadas em bind e consulta LDAP no AD"
```

Validar:

```powershell
Get-ADGroup GRP_SVC_LDAP_BIND
```

## 6. Criar o usuário de serviço svc-ldap-bind

Criar senha segura:

```powershell
$PasswordSvcLdap = Read-Host "Digite a senha do usuario svc-ldap-bind" -AsSecureString
```

Criar o usuário:

```powershell
New-ADUser `
  -Name "svc-ldap-bind" `
  -GivenName "svc" `
  -Surname "ldap-bind" `
  -SamAccountName "svc-ldap-bind" `
  -UserPrincipalName "svc-ldap-bind@jmsalles.homelab.br" `
  -Path "OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" `
  -AccountPassword $PasswordSvcLdap `
  -Enabled $true `
  -ChangePasswordAtLogon $false `
  -PasswordNeverExpires $true `
  -CannotChangePassword $true `
  -Description "Conta de servico para bind e consulta LDAP das aplicacoes do homelab"
```

Adicionar ao grupo de bind LDAP:

```powershell
Add-ADGroupMember -Identity "GRP_SVC_LDAP_BIND" -Members "svc-ldap-bind"
```

## 7. Validar o usuário criado

Validar dados principais:

```powershell
Get-ADUser svc-ldap-bind -Properties UserPrincipalName,Enabled,PasswordNeverExpires,CannotChangePassword,Description
```

Validar grupos:

```powershell
Get-ADPrincipalGroupMembership svc-ldap-bind | Select-Object Name
```

Resultado esperado:

```text
Domain Users
GRP_SVC_LDAP_BIND
```

A conta não deve aparecer em:

```text
Domain Admins
Enterprise Admins
Administrators
GRP_HOMELAB_ADMINS
```

## 8. Obter o Distinguished Name do usuário

Algumas aplicações aceitam o usuário no formato UPN, mas outras exigem o Bind DN completo.

Execute:

```powershell
Get-ADUser svc-ldap-bind | Select-Object DistinguishedName
```

Resultado esperado:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Esse valor será usado como Bind DN em aplicações que exigem o DN completo.

## 9. Dados padrão para configuração LDAP nas aplicações

Use estes dados como referência para aplicações que precisam consultar o Active Directory.

| Campo             | Valor                                                                          |
| ----------------- | ------------------------------------------------------------------------------ |
| LDAP Host         | `winserver.jmsalles.homelab.br`                                                |
| LDAP IP           | `192.168.31.24`                                                                |
| LDAP Port         | `389`                                                                          |
| Encryption        | `None` ou `StartTLS desabilitado` inicialmente                                 |
| Base DN           | `DC=jmsalles,DC=homelab,DC=br`                                                 |
| Bind User UPN     | `svc-ldap-bind@jmsalles.homelab.br`                                            |
| Bind User NetBIOS | `JMSALLES\svc-ldap-bind`                                                       |
| Bind DN           | `CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |
| User Search Base  | `OU=Homelab,DC=jmsalles,DC=homelab,DC=br`                                      |
| Group Search Base | `OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br`                            |

Filtro comum por `sAMAccountName`:

```text
(&(objectClass=user)(sAMAccountName=%s))
```

Filtro comum por UPN:

```text
(&(objectClass=user)(userPrincipalName=%s))
```

Filtro comum para grupos:

```text
(&(objectClass=group)(cn=%s))
```

## 10. Testar porta LDAP no Windows

No próprio Windows Server ou em outro Windows, teste a porta LDAP:

```powershell
Test-NetConnection 192.168.31.24 -Port 389
```

Ou pelo nome:

```powershell
Test-NetConnection winserver.jmsalles.homelab.br -Port 389
```

Resultado esperado:

```text
TcpTestSucceeded : True
```

## 11. Testar DNS do Domain Controller

Em uma máquina cliente, valide a resolução do DC:

```powershell
nslookup winserver.jmsalles.homelab.br
```

Validar o domínio:

```powershell
nslookup jmsalles.homelab.br
```

Validar registros SRV do AD:

```powershell
nslookup -type=SRV _ldap._tcp.dc._msdcs.jmsalles.homelab.br
```

Resultado esperado:

```text
winserver.jmsalles.homelab.br
```

## 12. Testar consulta LDAP a partir de Linux

Em uma máquina Linux, instale o cliente LDAP.

Para Rocky Linux, RHEL ou AlmaLinux:

```bash
sudo dnf install -y openldap-clients
```

Para Ubuntu ou Debian:

```bash
sudo apt update
```

```bash
sudo apt install -y ldap-utils
```

Teste a consulta usando a conta de serviço:

```bash
ldapsearch -x \
  -H ldap://192.168.31.24:389 \
  -D "svc-ldap-bind@jmsalles.homelab.br" \
  -W \
  -b "DC=jmsalles,DC=homelab,DC=br" \
  "(sAMAccountName=jmsalles)" \
  sAMAccountName userPrincipalName distinguishedName memberOf
```

Teste consultando o usuário administrativo `adm-jeferson`:

```bash
ldapsearch -x \
  -H ldap://192.168.31.24:389 \
  -D "svc-ldap-bind@jmsalles.homelab.br" \
  -W \
  -b "DC=jmsalles,DC=homelab,DC=br" \
  "(sAMAccountName=adm-jeferson)" \
  sAMAccountName userPrincipalName distinguishedName memberOf
```

Teste pelo hostname:

```bash
ldapsearch -x \
  -H ldap://winserver.jmsalles.homelab.br:389 \
  -D "svc-ldap-bind@jmsalles.homelab.br" \
  -W \
  -b "DC=jmsalles,DC=homelab,DC=br" \
  "(sAMAccountName=jmsalles)" \
  sAMAccountName userPrincipalName distinguishedName memberOf
```

## 13. Exemplo genérico para aplicações

Configuração LDAP genérica para aplicações do homelab:

```text
LDAP Host: winserver.jmsalles.homelab.br
LDAP Port: 389
Use SSL/TLS: No
StartTLS: No
Base DN: DC=jmsalles,DC=homelab,DC=br
Bind DN/User: svc-ldap-bind@jmsalles.homelab.br
Bind Password: <senha_do_svc-ldap-bind>
User Search Base: OU=Homelab,DC=jmsalles,DC=homelab,DC=br
User Search Filter: (&(objectClass=user)(sAMAccountName=%s))
Group Search Base: OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Se a aplicação exigir Bind DN completo:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Se a aplicação aceitar UPN:

```text
svc-ldap-bind@jmsalles.homelab.br
```

## 14. Exemplo conceitual para Vault

Para o Vault, a conta `svc-ldap-bind` poderá ser usada futuramente no método LDAP Auth.

Dados base:

```text
url: ldap://winserver.jmsalles.homelab.br:389
userdn: OU=Homelab,DC=jmsalles,DC=homelab,DC=br
groupdn: OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
binddn: CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
userattr: sAMAccountName
```

Exemplo conceitual:

```bash
vault auth enable ldap
```

```bash
vault write auth/ldap/config \
  url="ldap://winserver.jmsalles.homelab.br:389" \
  userdn="OU=Homelab,DC=jmsalles,DC=homelab,DC=br" \
  groupdn="OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" \
  binddn="CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" \
  bindpass="<senha_do_svc-ldap-bind>" \
  userattr="sAMAccountName" \
  insecure_tls=true \
  starttls=false
```

Observação:

```text
Este exemplo é apenas base para integração futura do Vault.
A configuração final deve ser ajustada no momento da integração.
```

## 15. Exemplo conceitual para Gitea

Para Gitea, os dados geralmente serão:

```text
Authentication Type: LDAP
Security Protocol: Unencrypted ou StartTLS desabilitado inicialmente
Host: winserver.jmsalles.homelab.br
Port: 389
Bind DN: CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
Bind Password: <senha_do_svc-ldap-bind>
User Search Base: OU=Homelab,DC=jmsalles,DC=homelab,DC=br
User Filter: (&(objectClass=user)(sAMAccountName=%s))
Admin Filter: opcional
Username Attribute: sAMAccountName
Email Attribute: mail
Name Attribute: displayName
```

## 16. Exemplo conceitual para Nexus

Para Nexus, os dados geralmente serão:

```text
LDAP Server: winserver.jmsalles.homelab.br
Port: 389
Search Base: DC=jmsalles,DC=homelab,DC=br
Authentication method: Simple Authentication
Username or DN: CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
Password: <senha_do_svc-ldap-bind>
User subtree: OU=Homelab,DC=jmsalles,DC=homelab,DC=br
User object class: user
User ID attribute: sAMAccountName
User real name attribute: cn
Email attribute: mail
Group type: Static Groups
Group subtree: OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

## 17. Como alterar a senha da conta svc-ldap-bind

Se precisar redefinir a senha da conta:

```powershell
Set-ADAccountPassword -Identity "svc-ldap-bind" -Reset -NewPassword (Read-Host "Nova senha" -AsSecureString)
```

Garantir que a conta continue habilitada:

```powershell
Enable-ADAccount -Identity "svc-ldap-bind"
```

Garantir senha sem expiração:

```powershell
Set-ADUser -Identity "svc-ldap-bind" -PasswordNeverExpires $true
```

Validar:

```powershell
Get-ADUser svc-ldap-bind -Properties Enabled,PasswordNeverExpires,CannotChangePassword
```

## 18. Como bloquear a conta em caso de incidente

Se houver suspeita de vazamento da senha:

```powershell
Disable-ADAccount -Identity "svc-ldap-bind"
```

Validar:

```powershell
Get-ADUser svc-ldap-bind -Properties Enabled
```

Para reativar depois:

```powershell
Enable-ADAccount -Identity "svc-ldap-bind"
```

## 19. Armazenamento da senha no Vault

Quando o Vault estiver sendo usado para centralizar secrets, armazene a credencial do `svc-ldap-bind`.

Exemplo:

```bash
vault kv put secret/ad/svc-ldap-bind \
  username="svc-ldap-bind@jmsalles.homelab.br" \
  bind_dn="CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" \
  password="<senha_do_svc_ldap_bind>" \
  ldap_host="winserver.jmsalles.homelab.br" \
  ldap_port="389" \
  base_dn="DC=jmsalles,DC=homelab,DC=br"
```

Validar:

```bash
vault kv get secret/ad/svc-ldap-bind
```

## 20. Observação sobre LDAPS

Neste momento, o ambiente está usando LDAP simples na porta:

```text
389
```

Futuramente, o ideal é evoluir para LDAPS na porta:

```text
636
```

Para isso, será necessário:

```text
Configurar certificado no Domain Controller
Garantir que o certificado tenha o nome correto do DC
Instalar a CA raiz nos clientes/aplicações
Validar conexão LDAPS
Alterar aplicações para usar ldaps://winserver.jmsalles.homelab.br:636
```

Teste futuro de LDAPS:

```bash
openssl s_client -connect winserver.jmsalles.homelab.br:636 -showcerts
```

## 21. Troubleshooting

### 21.1 Falha na conexão LDAP

Teste a porta:

```bash
nc -vz 192.168.31.24 389
```

Ou:

```powershell
Test-NetConnection 192.168.31.24 -Port 389
```

Verifique:

```text
Firewall do Windows
Serviços do AD
Rota entre aplicação e Domain Controller
DNS resolvendo corretamente
```

### 21.2 Hostname não resolve

Teste:

```bash
nslookup winserver.jmsalles.homelab.br
```

Se falhar, use temporariamente:

```text
192.168.31.24
```

Ou corrija o DNS do cliente/aplicação para consultar o DNS do AD.

### 21.3 Bind falhando

Confirme o DN do usuário:

```powershell
Get-ADUser svc-ldap-bind | Select-Object DistinguishedName
```

Confirme se a conta está habilitada:

```powershell
Get-ADUser svc-ldap-bind -Properties Enabled
```

Confirme senha:

```powershell
Set-ADAccountPassword -Identity "svc-ldap-bind" -Reset -NewPassword (Read-Host "Nova senha" -AsSecureString)
```

### 21.4 Consulta não retorna usuários

Verifique se a Base DN está correta:

```text
DC=jmsalles,DC=homelab,DC=br
```

Teste filtro mais amplo:

```bash
ldapsearch -x \
  -H ldap://192.168.31.24:389 \
  -D "svc-ldap-bind@jmsalles.homelab.br" \
  -W \
  -b "DC=jmsalles,DC=homelab,DC=br" \
  "(objectClass=user)" \
  sAMAccountName
```

### 21.5 Usuário não aparece com memberOf

Verifique se o usuário realmente pertence a algum grupo:

```powershell
Get-ADPrincipalGroupMembership jmsalles | Select-Object Name
```

Consulta LDAP:

```bash
ldapsearch -x \
  -H ldap://192.168.31.24:389 \
  -D "svc-ldap-bind@jmsalles.homelab.br" \
  -W \
  -b "DC=jmsalles,DC=homelab,DC=br" \
  "(sAMAccountName=jmsalles)" \
  memberOf
```

## 22. Checklist final

| Item                                            | Status   |
| ----------------------------------------------- | -------- |
| OU `Service Accounts` validada                  | Pendente |
| OU `Groups` validada                            | Pendente |
| Grupo `GRP_SVC_LDAP_BIND` criado                | Pendente |
| Usuário `svc-ldap-bind` criado                  | Pendente |
| Usuário habilitado                              | Pendente |
| Senha configurada                               | Pendente |
| `PasswordNeverExpires` habilitado               | Pendente |
| `CannotChangePassword` habilitado               | Pendente |
| Usuário adicionado ao grupo `GRP_SVC_LDAP_BIND` | Pendente |
| DN do usuário validado                          | Pendente |
| Porta 389 validada                              | Pendente |
| Consulta LDAP testada a partir de Linux         | Pendente |
| Dados de integração documentados                | Pendente |
| Secret criado no Vault                          | Pendente |

## 23. Resumo final

Conta criada:

```text
svc-ldap-bind
```

Função:

```text
Conta de serviço para bind e consulta LDAP no Active Directory
```

Grupo:

```text
GRP_SVC_LDAP_BIND
```

Servidor LDAP:

```text
winserver.jmsalles.homelab.br
```

IP:

```text
192.168.31.24
```

Porta:

```text
389
```

Base DN:

```text
DC=jmsalles,DC=homelab,DC=br
```

Bind DN:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

UPN:

```text
svc-ldap-bind@jmsalles.homelab.br
```

A conta não possui privilégios administrativos e será usada por aplicações do homelab que precisam consultar o AD.

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)
