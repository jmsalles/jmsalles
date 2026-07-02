Perfeito. Pelo print, agora ficou validado:

```text
Conexão LDAP: OK
Usuário jmsalles encontrado
Grupo GRP_GRAFANA_ADMINS mapeado
Role: Admin
Grafana admin: Sim
Status: Ativa
```

O ponto principal que corrigiu foi recriar o container do Grafana, não apenas reiniciar. O `docker compose restart` não aplica mudanças feitas no `docker-compose.yml`, incluindo variáveis de ambiente; a documentação do Docker Compose informa que alterações na configuração, como variáveis de ambiente, não são refletidas após `restart`. Para aplicar, é necessário recriar o container, por exemplo com `docker compose up -d --force-recreate` ou removendo/recriando o serviço. ([Docker Documentation][1])

Abaixo está o tutorial completo revisado, usando **LDAP pela interface gráfica do Grafana** e incluindo a sequência que funcionou no seu ambiente.

---

# Tutorial — Autenticação LDAP/AD no Grafana pela Interface Gráfica

## 1. Identificação

| Item                        | Valor                                 |
| --------------------------- | ------------------------------------- |
| Aplicação                   | Grafana                               |
| URL principal               | `https://logs.jmsalles.homelab.br`    |
| URL direta                  | `http://192.168.31.17:3000`           |
| VM                          | `observabilidade`                     |
| IP da VM                    | `192.168.31.17`                       |
| AD/DC                       | `192.168.31.24`                       |
| Domínio                     | `jmsalles.homelab.br`                 |
| Base DN                     | `DC=jmsalles,DC=homelab,DC=br`        |
| Bind user                   | `svc-ldap-bind`                       |
| Senha padrão homelab        | `4796@@Eumesmo1234567`                |
| Método de configuração LDAP | Interface gráfica do Grafana          |
| Caminho no Grafana          | `Administração > Autenticação > LDAP` |

---

## 2. Objetivo

Configurar o Grafana da stack de logs para autenticar usuários no Active Directory do homelab usando a própria interface gráfica.

Fluxo final:

```text
Usuário acessa:
https://logs.jmsalles.homelab.br

Grafana autentica no AD:
ldap://192.168.31.24:389

Usuário faz login com:
jmsalles
ou
jmsalles@jmsalles.homelab.br
```

Mapeamento de permissões:

| Grupo AD              | Permissão no Grafana  |
| --------------------- | --------------------- |
| `GRP_GRAFANA_ADMINS`  | Admin + Grafana Admin |
| `GRP_GRAFANA_EDITORS` | Editor                |
| `GRP_GRAFANA_VIEWERS` | Viewer                |

A configuração LDAP pela interface do Grafana fica disponível em `Administration > Authentication > LDAP`, e a documentação oficial informa que essa UI exige o feature toggle `ssoSettingsLDAP`. ([Grafana Labs][2])

---

# 3. Preparar grupos no Active Directory

Execute os comandos abaixo no **Windows Server AD/DC** como Administrador.

## 3.1. Definir variáveis

```powershell
$PathHomelab = "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
$PathGroups = "OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

```powershell
$PathServiceAccounts = "OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

---

## 3.2. Validar OUs existentes

```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
```

Procure por:

```text
OU=Homelab,DC=jmsalles,DC=homelab,DC=br
OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Se alguma OU não existir, crie.

Criar OU principal:

```powershell
New-ADOrganizationalUnit -Name "Homelab" -Path "DC=jmsalles,DC=homelab,DC=br"
```

Criar OU de grupos:

```powershell
New-ADOrganizationalUnit -Name "Groups" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

Criar OU de contas de serviço:

```powershell
New-ADOrganizationalUnit -Name "Service Accounts" -Path "OU=Homelab,DC=jmsalles,DC=homelab,DC=br"
```

Se retornar erro dizendo que o objeto já existe, pode seguir.

---

# 4. Criar grupos do Grafana no AD

## 4.1. Grupo Admin

```powershell
New-ADGroup -Name "GRP_GRAFANA_ADMINS" -SamAccountName "GRP_GRAFANA_ADMINS" -GroupScope Global -GroupCategory Security -Path $PathGroups
```

## 4.2. Grupo Editor

```powershell
New-ADGroup -Name "GRP_GRAFANA_EDITORS" -SamAccountName "GRP_GRAFANA_EDITORS" -GroupScope Global -GroupCategory Security -Path $PathGroups
```

## 4.3. Grupo Viewer

```powershell
New-ADGroup -Name "GRP_GRAFANA_VIEWERS" -SamAccountName "GRP_GRAFANA_VIEWERS" -GroupScope Global -GroupCategory Security -Path $PathGroups
```

## 4.4. Validar grupos

```powershell
Get-ADGroup -Filter 'Name -like "GRP_GRAFANA*"' | Select-Object Name, SamAccountName, DistinguishedName
```

Resultado esperado:

```text
GRP_GRAFANA_ADMINS
GRP_GRAFANA_EDITORS
GRP_GRAFANA_VIEWERS
```

---

# 5. Inserir usuários nos grupos

## 5.1. Adicionar `jmsalles` como Admin do Grafana

```powershell
Add-ADGroupMember -Identity "GRP_GRAFANA_ADMINS" -Members "jmsalles"
```

## 5.2. Validar membros do grupo Admin

```powershell
Get-ADGroupMember "GRP_GRAFANA_ADMINS" | Select-Object Name, SamAccountName
```

## 5.3. Validar grupos do usuário

```powershell
Get-ADPrincipalGroupMembership jmsalles | Select-Object Name
```

Resultado esperado: o usuário `jmsalles` deve aparecer como membro de:

```text
GRP_GRAFANA_ADMINS
```

---

# 6. Criar ou validar conta de bind LDAP

## 6.1. Validar se a conta existe

```powershell
Get-ADUser -Identity "svc-ldap-bind" -Properties DistinguishedName,Enabled,PasswordNeverExpires | Select-Object SamAccountName,Enabled,PasswordNeverExpires,DistinguishedName
```

DN esperado:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

---

## 6.2. Criar senha em variável

```powershell
$BindPassword = ConvertTo-SecureString "4796@@Eumesmo1234567" -AsPlainText -Force
```

## 6.3. Criar conta de bind, se necessário

```powershell
New-ADUser -Name "svc-ldap-bind" -SamAccountName "svc-ldap-bind" -UserPrincipalName "svc-ldap-bind@jmsalles.homelab.br" -Path $PathServiceAccounts -AccountPassword $BindPassword -Enabled $true -PasswordNeverExpires $true
```

## 6.4. Validar conta

```powershell
Get-ADUser -Identity "svc-ldap-bind" -Properties DistinguishedName,Enabled,PasswordNeverExpires | Select-Object SamAccountName,Enabled,PasswordNeverExpires,DistinguishedName
```

---

# 7. Validar DN real dos grupos

Use os comandos abaixo para confirmar os DNs que serão usados no Grafana.

## 7.1. DN do grupo Admin

```powershell
Get-ADGroup -Identity "GRP_GRAFANA_ADMINS" -Properties DistinguishedName | Select-Object DistinguishedName
```

Esperado:

```text
CN=GRP_GRAFANA_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

## 7.2. DN do grupo Editors

```powershell
Get-ADGroup -Identity "GRP_GRAFANA_EDITORS" -Properties DistinguishedName | Select-Object DistinguishedName
```

Esperado:

```text
CN=GRP_GRAFANA_EDITORS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

## 7.3. DN do grupo Viewers

```powershell
Get-ADGroup -Identity "GRP_GRAFANA_VIEWERS" -Properties DistinguishedName | Select-Object DistinguishedName
```

Esperado:

```text
CN=GRP_GRAFANA_VIEWERS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

---

# 8. Testar LDAP a partir da VM `observabilidade`

Acesse a VM:

```bash
ssh jmsalles@192.168.31.17
```

Eleve para root:

```bash
sudo -i
```

Instale o cliente LDAP:

```bash
dnf install -y openldap-clients
```

Teste bind e busca do usuário:

```bash
ldapsearch -x -H ldap://192.168.31.24:389 -D "CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" -w '4796@@Eumesmo1234567' -b "DC=jmsalles,DC=homelab,DC=br" "(sAMAccountName=jmsalles)" sAMAccountName userPrincipalName displayName givenName sn mail memberOf
```

Resultado esperado:

```text
sAMAccountName: jmsalles
givenName: Jeferson
sn: Salles
memberOf: CN=GRP_GRAFANA_ADMINS,...
```

Se este teste falhar, corrija antes de mexer no Grafana.

---

# 9. Ajustar o Grafana para permitir LDAP pela UI

Mesmo usando a interface gráfica, o container do Grafana precisa estar habilitado para LDAP e para a tela de configuração LDAP.

## 9.1. Acessar a stack

```bash
ssh jmsalles@192.168.31.17
```

```bash
sudo -i
```

```bash
cd /opt/observability
```

## 9.2. Fazer backup do Compose

```bash
cp -a docker-compose.yml docker-compose.yml.bkp.ldap-ui.$(date +%F_%H-%M-%S)
```

Validar:

```bash
ls -lh docker-compose.yml.bkp.ldap-ui.*
```

---

# 10. Editar `docker-compose.yml`

Editar:

```bash
vim /opt/observability/docker-compose.yml
```

No serviço `grafana`, deixe o bloco assim:

```yaml
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    env_file:
      - .env
    environment:
      GF_SECURITY_ADMIN_USER: "${GRAFANA_ADMIN_USER}"
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_SERVER_DOMAIN: "logs.jmsalles.homelab.br"
      GF_SERVER_ROOT_URL: "https://logs.jmsalles.homelab.br/"
      GF_SERVER_SERVE_FROM_SUB_PATH: "false"
      GF_FEATURE_TOGGLES_ENABLE: "ssoSettingsLDAP"
      GF_AUTH_LDAP_ENABLED: "true"
      GF_AUTH_LDAP_ALLOW_SIGN_UP: "true"
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - loki
    restart: unless-stopped
```

Importante: como a configuração será feita pela interface gráfica, **não precisa** usar `ldap.toml`.

Se existirem, remova ou comente estas linhas:

```yaml
      GF_AUTH_LDAP_CONFIG_FILE: "/etc/grafana/ldap.toml"
      GF_LOG_FILTERS: "ldap:debug"
```

E remova este volume, se existir:

```yaml
      - ./grafana/ldap/ldap.toml:/etc/grafana/ldap.toml:ro
```

---

# 11. Aplicar alteração recriando o container

Esse foi o ponto que resolveu no seu ambiente.

Não use somente:

```bash
docker compose restart grafana
```

Porque `restart` não aplica novas variáveis de ambiente nem mudanças do Compose. ([Docker Documentation][1])

Use a sequência validada:

```bash
cd /opt/observability
```

```bash
docker compose down grafana
```

```bash
docker compose up grafana -d
```

Alternativa equivalente e também recomendada:

```bash
docker compose up -d --force-recreate grafana
```

O `--force-recreate` força a recriação do container, aplicando as variáveis novas do `docker-compose.yml`. ([Docker Documentation][3])

---

# 12. Validar se as variáveis entraram no container

```bash
docker exec grafana printenv | egrep 'GF_FEATURE_TOGGLES_ENABLE|GF_AUTH_LDAP'
```

Resultado esperado:

```text
GF_FEATURE_TOGGLES_ENABLE=ssoSettingsLDAP
GF_AUTH_LDAP_ENABLED=true
GF_AUTH_LDAP_ALLOW_SIGN_UP=true
```

Validar container:

```bash
docker compose ps
```

Ver logs:

```bash
docker compose logs --tail=200 grafana
```

---

# 13. Acessar a interface LDAP do Grafana

Acesse:

```text
https://logs.jmsalles.homelab.br/admin/authentication
```

ou diretamente:

```text
http://192.168.31.17:3000/admin/authentication
```

Entre com o usuário local:

```text
admin
```

Depois clique em:

```text
LDAP
```

---

# 14. Configurações básicas LDAP

Preencha os campos principais assim:

| Campo                | Valor                                                                          |                                             |
| -------------------- | ------------------------------------------------------------------------------ | ------------------------------------------- |
| Host do servidor     | `192.168.31.24`                                                                |                                             |
| Vincular DN          | `CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |                                             |
| Vincular senha       | `4796@@Eumesmo1234567`                                                         |                                             |
| Filtro de pesquisa   | `(                                                                             | (sAMAccountName=%s)(userPrincipalName=%s))` |
| Base DNS de pesquisa | `DC=jmsalles,DC=homelab,DC=br`                                                 |                                             |

Esse filtro permite login com:

```text
jmsalles
```

ou:

```text
jmsalles@jmsalles.homelab.br
```

---

# 15. Configurações avançadas

Clique em:

```text
Configurações avançadas > Editar
```

Preencha:

| Campo              | Valor  |
| ------------------ | ------ |
| Permitir inscrição | Ligado |
| Porta              | `389`  |
| Tempo esgotado     | `10`   |

---

# 16. Atributos

Na seção **Atributos**, preencha:

| Campo           | Valor            |
| --------------- | ---------------- |
| Nome            | `givenName`      |
| Sobrenome       | `sn`             |
| Nome de usuário | `sAMAccountName` |
| Membro de       | `memberOf`       |
| E-mail          | `mail`           |

No seu teste, esses campos funcionaram e retornaram:

```text
First name: Jeferson
Surname: Salles
Username: jmsalles
Email: mail
```

---

# 17. Mapeamento de grupo

Na seção **Mapeamento de grupo**, configure:

## 17.1. Ignorar sincronização da função da organização

Deixe:

```text
Desligado
```

Motivo:

```text
Queremos que a role do Grafana venha do grupo AD.
```

---

## 17.2. Filtro de pesquisa de grupo

```text
(member:1.2.840.113556.1.4.1941:=%s)
```

Essa regra é usada com Active Directory para resolver associação de grupos, inclusive nested groups. ([Grafana Labs][4])

## 17.3. Base DNs de pesquisa de grupo

```text
DC=jmsalles,DC=homelab,DC=br
```

## 17.4. Atributo de nome de grupo

```text
dn
```

---

# 18. Adicionar mapeamentos de grupo

Clique em:

```text
+ Adicionar mapeamento de grupo
```

## 18.1. Grupo Admin

| Campo                 | Valor                                                                     |
| --------------------- | ------------------------------------------------------------------------- |
| LDAP Group / Group DN | `CN=GRP_GRAFANA_ADMINS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |
| Organization          | `Main Org.` ou ID `1`                                                     |
| Role                  | `Admin`                                                                   |
| Grafana Admin         | Ligado                                                                    |

Resultado esperado no diagnóstico:

```text
CN=GRP_GRAFANA_ADMINS,...  Main Org.  Admin
Grafana admin: Sim
```

---

## 18.2. Grupo Editors

| Campo                 | Valor                                                                      |
| --------------------- | -------------------------------------------------------------------------- |
| LDAP Group / Group DN | `CN=GRP_GRAFANA_EDITORS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |
| Organization          | `Main Org.` ou ID `1`                                                      |
| Role                  | `Editor`                                                                   |
| Grafana Admin         | Desligado                                                                  |

---

## 18.3. Grupo Viewers

| Campo                 | Valor                                                                      |
| --------------------- | -------------------------------------------------------------------------- |
| LDAP Group / Group DN | `CN=GRP_GRAFANA_VIEWERS,OU=Groups,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |
| Organization          | `Main Org.` ou ID `1`                                                      |
| Role                  | `Viewer`                                                                   |
| Grafana Admin         | Desligado                                                                  |

---

## 18.4. Wildcard opcional

Se quiser permitir qualquer usuário autenticado no AD como Viewer, adicione:

| Campo                 | Valor                 |
| --------------------- | --------------------- |
| LDAP Group / Group DN | `*`                   |
| Organization          | `Main Org.` ou ID `1` |
| Role                  | `Viewer`              |
| Grafana Admin         | Desligado             |

Se quiser restringir o acesso somente aos grupos explícitos, não adicione o wildcard.

---

# 19. Medidas de segurança extras

Para LDAP simples no homelab:

| Campo     | Valor     |
| --------- | --------- |
| Usar SSL  | Desligado |
| Start TLS | Desligado |
| Porta     | `389`     |

No futuro, para LDAPS:

| Campo     | Valor           |
| --------- | --------------- |
| Host      | `192.168.31.24` |
| Porta     | `636`           |
| Usar SSL  | Ligado          |
| Start TLS | Desligado       |

---

# 20. Salvar e ativar

Depois de preencher tudo:

```text
Salvar e ativar
```

Depois clique em:

```text
Teste
```

Teste com:

```text
jmsalles
```

O resultado esperado é parecido com o que apareceu no seu print:

```text
Conexão LDAP:
192.168.31.24 389 OK

User Information:
First name: Jeferson
Surname: Salles
Username: jmsalles

Permissions:
Grafana admin: Sim
Status: Ativa

LDAP Group:
CN=GRP_GRAFANA_ADMINS,...  Main Org.  Admin
```

---

# 21. Testar login real

Abra uma aba anônima.

Acesse:

```text
https://logs.jmsalles.homelab.br
```

Teste login com:

```text
jmsalles
```

ou:

```text
jmsalles@jmsalles.homelab.br
```

Senha:

```text
Senha do usuário jmsalles no AD
```

Depois valide:

```text
Administração > Usuários e acesso > Usuários
```

O usuário deve aparecer como LDAP.

---

# 22. Manter login local de emergência

Mesmo com LDAP funcionando, mantenha o usuário local:

```text
admin
```

com a senha padrão do seu homelab:

```text
4796@@Eumesmo1234567
```

Isso permite recuperação caso o AD, DNS, bind user ou mapeamento LDAP falhe.

---

# 23. Validação via linha de comando

## 23.1. Validar variáveis no container

```bash
cd /opt/observability
docker exec grafana printenv | egrep 'GF_FEATURE_TOGGLES_ENABLE|GF_AUTH_LDAP'
```

Esperado:

```text
GF_FEATURE_TOGGLES_ENABLE=ssoSettingsLDAP
GF_AUTH_LDAP_ENABLED=true
GF_AUTH_LDAP_ALLOW_SIGN_UP=true
```

## 23.2. Validar logs do Grafana

```bash
docker compose logs --tail=200 grafana
```

Filtrar autenticação/LDAP:

```bash
docker compose logs grafana | egrep -i 'ldap|auth|ssoSettingsLDAP|feature'
```

## 23.3. Validar LDAP pela VM

```bash
ldapsearch -x -H ldap://192.168.31.24:389 -D "CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" -w '4796@@Eumesmo1234567' -b "DC=jmsalles,DC=homelab,DC=br" "(sAMAccountName=jmsalles)" sAMAccountName userPrincipalName displayName givenName sn mail memberOf
```

---

# 24. Troubleshooting

## 24.1. Erro: `LDAP is not enabled`

Causa provável:

```text
O container do Grafana não foi recriado após adicionar:
GF_FEATURE_TOGGLES_ENABLE=ssoSettingsLDAP
GF_AUTH_LDAP_ENABLED=true
```

Correção validada no seu ambiente:

```bash
cd /opt/observability
docker compose down grafana
docker compose up grafana -d
```

Alternativa:

```bash
docker compose up -d --force-recreate grafana
```

Depois validar:

```bash
docker exec grafana printenv | egrep 'GF_FEATURE_TOGGLES_ENABLE|GF_AUTH_LDAP'
```

---

## 24.2. `docker compose restart grafana` não resolveu

Isso é esperado. O `restart` não aplica mudanças do `docker-compose.yml`, como variáveis novas. A própria documentação do Docker Compose informa que mudanças na configuração não são refletidas depois de `docker compose restart`. ([Docker Documentation][1])

Use:

```bash
docker compose down grafana
docker compose up grafana -d
```

ou:

```bash
docker compose up -d --force-recreate grafana
```

---

## 24.3. Login funciona, mas usuário entra como Viewer

Validar grupos do usuário no AD:

```powershell
Get-ADPrincipalGroupMembership jmsalles | Select-Object Name
```

Validar DN real do grupo Admin:

```powershell
Get-ADGroup -Identity "GRP_GRAFANA_ADMINS" -Properties DistinguishedName | Select-Object DistinguishedName
```

Compare exatamente com o mapeamento da interface do Grafana.

---

## 24.4. Conexão LDAP falha

Na VM `observabilidade`:

```bash
ldapsearch -x -H ldap://192.168.31.24:389 -D "CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br" -w '4796@@Eumesmo1234567' -b "DC=jmsalles,DC=homelab,DC=br" "(sAMAccountName=jmsalles)"
```

Se falhar, revisar:

```text
IP do DC
Porta 389
Bind DN
Senha do bind
Base DN
Firewall/rede
Usuário svc-ldap-bind habilitado
```

---

## 24.5. PowerShell fica em `>>`

Causa:

```text
Comando incompleto, aspa aberta ou uso de crase/backtick.
```

Correção:

```text
Pressione CTRL + C.
Use comandos em uma linha ou variáveis, como neste tutorial.
```

---

# 25. Backup recomendado

Depois de validar, faça backup do Compose:

```bash
cd /opt/observability
cp -a docker-compose.yml docker-compose.yml.ok.ldap-ui.$(date +%F_%H-%M-%S)
```

Faça backup geral da configuração da stack:

```bash
/usr/local/sbin/backup-observability-config.sh
```

Se o script existir, validar:

```bash
ls -lh /opt/backup-observability
```

---

# 26. Rollback

Se precisar voltar sem LDAP pela UI, edite:

```bash
cd /opt/observability
vim docker-compose.yml
```

Remova:

```yaml
      GF_FEATURE_TOGGLES_ENABLE: "ssoSettingsLDAP"
      GF_AUTH_LDAP_ENABLED: "true"
      GF_AUTH_LDAP_ALLOW_SIGN_UP: "true"
```

Depois recrie o Grafana:

```bash
docker compose down grafana
docker compose up grafana -d
```

Ou restaure o backup:

```bash
cp -a docker-compose.yml.bkp.ldap-ui.YYYY-MM-DD_HH-MM-SS docker-compose.yml
docker compose down grafana
docker compose up grafana -d
```

---

# 27. Checklist final

```text
Grupos AD criados
Usuário jmsalles no grupo GRP_GRAFANA_ADMINS
Conta svc-ldap-bind criada/validada
ldapsearch da VM observabilidade funciona
docker-compose.yml contém ssoSettingsLDAP e GF_AUTH_LDAP_ENABLED=true
Container Grafana recriado com down/up
LDAP ativado pela interface do Grafana
Teste LDAP mostra conexão OK
Usuário jmsalles retorna atributos corretamente
Grupo GRP_GRAFANA_ADMINS mapeia para Admin
Grafana admin = Sim
Login local admin continua funcionando
Login LDAP jmsalles funciona
Dashboards continuam acessíveis
```

Com isso, o Grafana da stack de logs está autenticando no AD do homelab pela interface gráfica e usando grupos do AD para aplicar permissões.

[1]: https://docs.docker.com/reference/cli/docker/compose/restart/?utm_source=chatgpt.com "docker compose restart"
[2]: https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/ldap-ui/?utm_source=chatgpt.com "Configure LDAP authentication using the Grafana user ..."
[3]: https://docs.docker.com/reference/cli/docker/compose/up/?utm_source=chatgpt.com "docker compose up"
[4]: https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/ldap/?utm_source=chatgpt.com "Configure LDAP authentication | Grafana documentation"
