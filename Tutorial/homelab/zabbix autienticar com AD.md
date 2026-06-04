# Guia de configuração LDAP do Zabbix com Active Directory

## 1. Objetivo

Este documento descreve como configurar o Zabbix para autenticar usuários via LDAP usando o domínio:

```text
jmsalles.homelab.br
```

O foco deste guia é somente a configuração no Zabbix.

Não será abordada nenhuma configuração no Active Directory.

## 2. Dados utilizados na integração

| Campo               | Valor                                                                          |
| ------------------- | ------------------------------------------------------------------------------ |
| Servidor LDAP       | `winserver.jmsalles.homelab.br`                                                |
| IP do servidor LDAP | `192.168.31.24`                                                                |
| Porta LDAP          | `389`                                                                          |
| Base DN             | `DC=jmsalles,DC=homelab,DC=br`                                                 |
| Search attribute    | `sAMAccountName`                                                               |
| Bind DN             | `CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br` |
| Usuário de bind     | `svc-ldap-bind`                                                                |
| Domínio             | `jmsalles.homelab.br`                                                          |
| StartTLS            | Desabilitado inicialmente                                                      |
| JIT provisioning    | Desabilitado inicialmente                                                      |

Observação:

```text
Se o Zabbix não conseguir resolver winserver.jmsalles.homelab.br, use temporariamente o IP 192.168.31.24 no campo Host.
```

## 3. Particularidade importante do Zabbix

Neste modelo, o JIT provisioning ficará desabilitado.

Isso significa que o Zabbix não criará usuários automaticamente no primeiro login LDAP.

Por isso, cada usuário que for autenticar via AD também precisa existir localmente no Zabbix.

Exemplo:

| Login no AD    | Usuário local no Zabbix |
| -------------- | ----------------------- |
| `jmsalles`     | `jmsalles`              |
| `adm-jeferson` | `adm-jeferson`          |

O campo `Username` do usuário local no Zabbix precisa bater com o atributo usado na busca LDAP.

Como usaremos:

```text
sAMAccountName
```

o usuário local no Zabbix deve ser criado com o mesmo valor do `sAMAccountName`.

Exemplo correto:

```text
jmsalles
```

Exemplo incorreto:

```text
jmsalles@jmsalles.homelab.br
```

## 4. Validar conectividade do Zabbix com o LDAP

Antes de configurar a interface, valide se o servidor Zabbix consegue acessar o AD na porta 389.

No servidor onde o Zabbix roda, execute:

```bash
nc -vz 192.168.31.24 389
```

Resultado esperado:

```text
succeeded
```

Se o comando `nc` não existir:

```bash
sudo dnf install -y nmap-ncat
```

Se o Zabbix roda em container, teste também de dentro do container do Zabbix Server.

Liste os containers:

```bash
docker ps
```

Acesse o container do Zabbix Server:

```bash
docker exec -it zabbix-server bash
```

Teste a porta:

```bash
nc -vz 192.168.31.24 389
```

Teste resolução DNS:

```bash
nslookup winserver.jmsalles.homelab.br
```

Se o nome não resolver, use o IP `192.168.31.24` na configuração do Zabbix.

Saia do container:

```bash
exit
```

## 5. Acessar a tela de autenticação LDAP

No Zabbix, acesse:

```text
Users
Authentication
LDAP settings
```

Marque:

```text
Enable LDAP authentication
```

Neste momento, deixe desmarcado:

```text
Enable JIT provisioning
```

Recomendação para o campo:

```text
Case-sensitive login
```

Para evitar problema com maiúsculas e minúsculas, recomendo deixar desmarcado.

Exemplo:

```text
jmsalles
JMSALLES
Jmsalles
```

Com login sensível a maiúsculas e minúsculas, esses valores podem ser tratados como diferentes.

## 6. Adicionar servidor LDAP

Na aba `LDAP settings`, clique em:

```text
Add
```

Preencha a tela `New LDAP server` com os dados abaixo.

## 7. Campos principais

Campo `Name`:

```text
AD JMSALLES
```

Campo `Host`:

```text
winserver.jmsalles.homelab.br
```

Se houver falha de resolução DNS, use:

```text
192.168.31.24
```

Campo `Port`:

```text
389
```

Campo `Base DN`:

```text
DC=jmsalles,DC=homelab,DC=br
```

Campo `Search attribute`:

```text
sAMAccountName
```

Campo `Bind DN`:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Campo `Bind password`:

```text
<senha_do_svc-ldap-bind>
```

Campo `Description`:

```text
Active Directory do homelab JMSalles
```

Campo `Configure JIT provisioning`:

```text
Desmarcado
```

## 8. Advanced configuration

Expanda:

```text
Advanced configuration
```

Campo `StartTLS`:

```text
Desmarcado
```

Campo `Search filter`:

```text
(%{attr}=%{user})
```

Esse filtro usa o valor do campo `Search attribute`.

Como o `Search attribute` está como:

```text
sAMAccountName
```

o Zabbix fará uma busca equivalente a:

```text
(sAMAccountName=<usuario_digitado>)
```

## 9. Resumo da tela preenchida

A tela deve ficar assim:

```text
Name: AD JMSALLES
Host: winserver.jmsalles.homelab.br
Port: 389
Base DN: DC=jmsalles,DC=homelab,DC=br
Search attribute: sAMAccountName
Bind DN: CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
Bind password: <senha_do_svc-ldap-bind>
Description: Active Directory do homelab JMSalles
Configure JIT provisioning: desmarcado
StartTLS: desmarcado
Search filter: (%{attr}=%{user})
```

## 10. Testar o servidor LDAP no Zabbix

Após preencher os campos, clique em:

```text
Test
```

Use um usuário válido para teste, por exemplo:

```text
jmsalles
```

ou:

```text
adm-jeferson
```

Se o teste funcionar, clique em:

```text
Add
```

Depois, na tela principal de autenticação LDAP, clique em:

```text
Update
```

## 11. Criar o usuário local no Zabbix

Como o JIT provisioning está desabilitado, o usuário precisa existir localmente no Zabbix.

Acesse:

```text
Users
Users
Create user
```

## 12. Criar usuário local jmsalles

Na aba `User`, preencha:

| Campo    | Valor      |
| -------- | ---------- |
| Username | `jmsalles` |
| Name     | `Jeferson` |
| Surname  | `Salles`   |

Atenção:

```text
O campo Username deve ser jmsalles.
Não use jmsalles@jmsalles.homelab.br nesse campo.
```

Em grupos, adicione o usuário a um grupo do Zabbix com permissão adequada.

Exemplo:

```text
Zabbix administrators
```

ou outro grupo administrativo que você utilize.

Na autenticação do usuário, selecione LDAP quando essa opção estiver disponível no seu fluxo de criação/edição.

Salve o usuário.

## 13. Criar usuário local adm-jeferson

Se quiser usar também o usuário administrativo `adm-jeferson`, crie outro usuário local no Zabbix.

Acesse:

```text
Users
Users
Create user
```

Preencha:

| Campo    | Valor          |
| -------- | -------------- |
| Username | `adm-jeferson` |
| Name     | `Jeferson`     |
| Surname  | `Salles Admin` |

Adicione ao grupo apropriado do Zabbix.

Exemplo:

```text
Zabbix administrators
```

Salve.

## 14. Ajustar permissões do usuário no Zabbix

O login LDAP só autentica a identidade.

As permissões dentro do Zabbix continuam sendo controladas pelos grupos e roles do próprio Zabbix.

Valide se o usuário local está associado ao grupo correto:

```text
Users
Users
jmsalles
User groups
```

Para administração total, use:

```text
Zabbix administrators
```

Para acesso restrito, use um grupo específico com permissões menores.

## 15. Testar login LDAP

Abra uma janela anônima do navegador ou saia da sessão atual.

Acesse:

```text
http://zabbix.jmsalles.homelab.br
```

ou:

```text
https://zabbix.jmsalles.homelab.br
```

Faça login com:

```text
jmsalles
```

Senha:

```text
senha do usuário no AD
```

Ou teste:

```text
adm-jeferson
```

Senha:

```text
senha do usuário no AD
```

## 16. Resultado esperado

Com a configuração correta, o Zabbix fará o seguinte fluxo:

```text
Usuário digita jmsalles
|
Zabbix procura sAMAccountName=jmsalles no LDAP
|
Zabbix usa svc-ldap-bind para consultar o AD
|
AD valida a senha do usuário jmsalles
|
Zabbix libera acesso conforme o usuário local jmsalles e seus grupos internos
```

## 17. Pontos de atenção

### 17.1 Usuário local obrigatório

Com JIT desabilitado, se o usuário existir no AD mas não existir localmente no Zabbix, o login pode falhar.

Exemplo:

```text
Usuário existe no AD: sim
Usuário existe no Zabbix: não
Resultado: login não permitido
```

### 17.2 Username precisa bater com sAMAccountName

Como o Zabbix está usando:

```text
sAMAccountName
```

o usuário local no Zabbix deve ser:

```text
jmsalles
```

e não:

```text
jmsalles@jmsalles.homelab.br
```

### 17.3 Permissão é controlada no Zabbix

O grupo do AD não dará permissão automaticamente no Zabbix neste modelo.

A permissão será definida no próprio Zabbix pelo grupo local do usuário.

Exemplo:

```text
Zabbix administrators
```

### 17.4 StartTLS desabilitado inicialmente

Neste momento, a integração usa LDAP simples na porta:

```text
389
```

Futuramente, o ideal é evoluir para LDAPS na porta:

```text
636
```

Mas isso exige certificado válido no Domain Controller e confiança da CA no container/servidor Zabbix.

## 18. Troubleshooting

### 18.1 Test falha na tela LDAP

Se o botão `Test` falhar, valide primeiro a conectividade.

No servidor Zabbix:

```bash
nc -vz 192.168.31.24 389
```

Se falhar, há problema de rede, firewall ou rota.

### 18.2 Hostname não resolve

Teste:

```bash
nslookup winserver.jmsalles.homelab.br
```

Se falhar, use temporariamente o IP no campo Host:

```text
192.168.31.24
```

### 18.3 Bind DN incorreto

Confirme se o campo está exatamente assim:

```text
CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
```

Também é possível testar usando o UPN como bind user, se o Zabbix aceitar no seu ambiente:

```text
svc-ldap-bind@jmsalles.homelab.br
```

Mas para esta configuração, o recomendado é usar o DN completo.

### 18.4 Senha do Bind incorreta

Se a senha do `svc-ldap-bind` estiver errada, o teste LDAP falhará.

Confirme a senha usada no campo:

```text
Bind password
```

### 18.5 Usuário AD autentica, mas não entra no Zabbix

Verifique se o usuário existe localmente no Zabbix.

Acesse:

```text
Users
Users
```

Confirme se existe:

```text
jmsalles
```

ou:

```text
adm-jeferson
```

### 18.6 Usuário existe no Zabbix, mas sem permissão

Verifique os grupos do usuário no Zabbix.

Acesse:

```text
Users
Users
<usuario>
User groups
```

Inclua o grupo correto, por exemplo:

```text
Zabbix administrators
```

### 18.7 Problema com maiúsculas e minúsculas

Se `Case-sensitive login` estiver marcado, o login precisa ser exatamente igual ao usuário local do Zabbix.

Exemplo:

```text
jmsalles
```

Se tentar:

```text
Jmsalles
```

pode falhar.

Recomendação:

```text
Deixar Case-sensitive login desmarcado.
```

## 19. Checklist final

| Item                                                         | Status   |
| ------------------------------------------------------------ | -------- |
| Conectividade com `192.168.31.24:389` validada               | Pendente |
| Hostname `winserver.jmsalles.homelab.br` validado            | Pendente |
| LDAP authentication habilitado no Zabbix                     | Pendente |
| JIT provisioning desabilitado                                | Pendente |
| Servidor LDAP `AD JMSALLES` adicionado                       | Pendente |
| StartTLS desabilitado                                        | Pendente |
| Search attribute configurado como `sAMAccountName`           | Pendente |
| Search filter configurado como `(%{attr}=%{user})`           | Pendente |
| Test LDAP executado com sucesso                              | Pendente |
| Usuário local `jmsalles` criado no Zabbix                    | Pendente |
| Usuário local `adm-jeferson` criado no Zabbix, se necessário | Pendente |
| Usuário associado ao grupo correto do Zabbix                 | Pendente |
| Login LDAP validado                                          | Pendente |

## 20. Resumo final

Configuração LDAP do Zabbix:

```text
Name: AD JMSALLES
Host: winserver.jmsalles.homelab.br
Port: 389
Base DN: DC=jmsalles,DC=homelab,DC=br
Search attribute: sAMAccountName
Bind DN: CN=svc-ldap-bind,OU=Service Accounts,OU=Homelab,DC=jmsalles,DC=homelab,DC=br
Search filter: (%{attr}=%{user})
StartTLS: desmarcado
JIT provisioning: desmarcado
```

Particularidade principal:

```text
Com JIT provisioning desabilitado, o usuário precisa existir localmente no Zabbix.
O Username local do Zabbix precisa ser igual ao sAMAccountName do AD.
```

Exemplo:

```text
AD: jmsalles
Zabbix: jmsalles
```

Permissões:

```text
As permissões continuam sendo definidas pelos grupos e roles internos do Zabbix.
```

Criado por Jeferson Salles
LinkedIn: https://www.linkedin.com/in/jmsalles/
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: https://github.com/jmsalles/
