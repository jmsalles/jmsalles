# Tutorial — Criar rota no Windows 10 para acesso aos endereços da ANS via gateway específico

## 1. Objetivo

Configurar o Windows 10 para que determinados endereços da ANS, como:

```text
vpn.ans.gov.br
ans.gov.br
```

saiam pelo gateway:

```text
192.168.31.4
```

mantendo a rota padrão normal do computador em:

```text
192.168.31.2
```

---

## 2. Cenário atual

Rota padrão do Windows:

```text
192.168.31.2
```

Gateway alternativo para acesso à ANS:

```text
192.168.31.4
```

DNS utilizado no ambiente:

```text
192.168.31.24
```

Exemplo identificado via `nslookup`:

```text
vpn.ans.gov.br -> 189.42.235.52
ans.gov.br     -> 177.223.210.68
```

---

## 3. Importante

O Windows **não cria rota por domínio**, somente por **IP ou rede**.

Ou seja, não é possível criar diretamente uma rota assim:

```text
*.ans.gov.br via 192.168.31.4
```

O correto é:

1. Descobrir o IP do endereço desejado.
2. Criar uma rota estática para esse IP.
3. Apontar essa rota para o gateway `192.168.31.4`.

---

# 4. Abrir o PowerShell como Administrador

No Windows 10:

1. Clique no menu iniciar.
2. Digite:

```text
PowerShell
```

3. Clique com o botão direito.
4. Selecione:

```text
Executar como administrador
```

---

# 5. Verificar a rota padrão atual

Execute:

```powershell
route print
```

Procure pela rota padrão:

```text
0.0.0.0          0.0.0.0        192.168.31.2
```

Isso confirma que a saída padrão da máquina continua sendo pelo gateway:

```text
192.168.31.2
```

---

# 6. Descobrir o IP do endereço da ANS

## 6.1. Descobrir o IP da VPN

Execute:

```powershell
nslookup vpn.ans.gov.br
```

Exemplo de retorno:

```text
Nome:    vpn.ans.gov.br
Address: 189.42.235.52
```

Neste caso, o IP identificado foi:

```text
189.42.235.52
```

---

## 6.2. Descobrir o IP do site principal da ANS

Execute:

```powershell
nslookup ans.gov.br
```

Exemplo de retorno:

```text
Nome:    ans.gov.br
Address: 177.223.210.68
```

Neste caso, o IP identificado foi:

```text
177.223.210.68
```

---

# 7. Criar rota persistente para sair pelo gateway 192.168.31.4

A opção `-p` faz com que a rota seja persistente, ou seja, continue existindo mesmo após reiniciar o Windows.

---

## 7.1. Criar rota para vpn.ans.gov.br

Com base no IP identificado:

```text
189.42.235.52
```

Execute:

```powershell
route -p add 189.42.235.52 mask 255.255.255.255 192.168.31.4 metric 1
```

Resultado esperado:

```text
OK!
```

---

## 7.2. Criar rota para ans.gov.br

Com base no IP identificado:

```text
177.223.210.68
```

Execute:

```powershell
route -p add 177.223.210.68 mask 255.255.255.255 192.168.31.4 metric 1
```

Resultado esperado:

```text
OK!
```

---

# 8. Validar se as rotas foram criadas

Execute:

```powershell
route print
```

Procure pelas entradas:

```text
189.42.235.52    255.255.255.255    192.168.31.4
177.223.210.68   255.255.255.255    192.168.31.4
```

Também pode validar de forma mais direta com:

```powershell
route print | findstr "189.42.235.52 177.223.210.68"
```

---

# 9. Testar o caminho utilizado

## 9.1. Testar rota para a VPN

Execute:

```powershell
tracert vpn.ans.gov.br
```

O primeiro salto esperado deve ser:

```text
192.168.31.4
```

---

## 9.2. Testar rota para ans.gov.br

Execute:

```powershell
tracert ans.gov.br
```

O primeiro salto esperado também deve ser:

```text
192.168.31.4
```

---

# 10. Comandos completos usados no exemplo

```powershell
nslookup vpn.ans.gov.br
nslookup ans.gov.br
route -p add 189.42.235.52 mask 255.255.255.255 192.168.31.4 metric 1
route -p add 177.223.210.68 mask 255.255.255.255 192.168.31.4 metric 1
route print
tracert vpn.ans.gov.br
tracert ans.gov.br
```

---

# 11. Como remover as rotas

Caso precise desfazer a configuração, execute o PowerShell como Administrador e rode os comandos abaixo.

## 11.1. Remover rota da VPN

```powershell
route delete 189.42.235.52
```

---

## 11.2. Remover rota do ans.gov.br

```powershell
route delete 177.223.210.68
```

---

## 11.3. Validar remoção

```powershell
route print | findstr "189.42.235.52 177.223.210.68"
```

Se não retornar nada, as rotas foram removidas.

---

# 12. Observação importante sobre mudança de IP

Caso o DNS da ANS mude no futuro, por exemplo:

```text
vpn.ans.gov.br
```

passar a responder outro IP, a rota antiga continuará apontando somente para o IP antigo.

Nesse caso, será necessário:

1. Rodar novamente:

```powershell
nslookup vpn.ans.gov.br
```

2. Remover a rota antiga:

```powershell
route delete IP_ANTIGO
```

3. Criar a nova rota:

```powershell
route -p add IP_NOVO mask 255.255.255.255 192.168.31.4 metric 1
```

---

# 13. Resumo do procedimento

```text
1. Descobrir o IP com nslookup.
2. Criar rota persistente com route -p add.
3. Validar com route print.
4. Testar caminho com tracert.
5. Remover com route delete, se necessário.
```

No seu caso, as rotas criadas foram:

```powershell
route -p add 189.42.235.52 mask 255.255.255.255 192.168.31.4 metric 1
route -p add 177.223.210.68 mask 255.255.255.255 192.168.31.4 metric 1
```

Com isso, somente esses IPs da ANS sairão pelo gateway `192.168.31.4`, enquanto o restante da navegação continuará usando a rota padrão `192.168.31.2`.
