# Tutorial: instalar a CA raiz do homelab no Windows para remover erro de certificado no Chrome/Edge

## Resumo

Você não precisa mexer no Nginx.

Pelos testes que você executou, o certificado está correto:

```bash
openssl verify -CAfile /home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.crt /home/jmsalles/nginx/ssl/jmsalles.homelab.br.crt
```

Retorno validado:

```text
/home/jmsalles/nginx/ssl/jmsalles.homelab.br.crt: OK
```

O certificado também possui SAN compatível com o Nexus:

```text
DNS:*.jmsalles.homelab.br, DNS:jmsalles.homelab.br, DNS:docker-hm.jmsalles.homelab.br
```

Logo, o endereço abaixo está coberto pelo wildcard:

```text
https://nexus.jmsalles.homelab.br
```

O que falta é o Windows confiar na sua CA raiz.

## Arquivo correto para importar

Importe no Windows somente este arquivo:

```bash
/home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.crt
```

Não importe a chave privada da CA:

```bash
/home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.key
```

Também não é necessário importar o certificado do site como raiz:

```bash
/home/jmsalles/nginx/ssl/jmsalles.homelab.br.crt
```

## 1. Copiar a CA para o Windows

No Windows, abra o PowerShell e copie o arquivo com `scp`:

```powershell
scp root@docker-hml-lenovo-i5:/home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.crt "$env:USERPROFILE\Downloads\"
```

Caso o nome `docker-hml-lenovo-i5` não resolva no Windows, use o IP do servidor:

```powershell
scp root@192.168.31.37:/home/jmsalles/nginx/ca/jmsalles-homelab-rootCA.crt "$env:USERPROFILE\Downloads\"
```

Confirme se o arquivo foi copiado:

```powershell
dir "$env:USERPROFILE\Downloads\jmsalles-homelab-rootCA.crt"
```

## 2. Opção A: importar via PowerShell

Abra o PowerShell como Administrador.

Execute:

```powershell
Import-Certificate -FilePath "$env:USERPROFILE\Downloads\jmsalles-homelab-rootCA.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

Valide se a CA foi instalada:

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*JMSalles*"} | Select-Object Subject, Issuer, NotAfter, Thumbprint
```

O resultado deve exibir algo parecido com:

```text
CN=JMSalles Homelab Root CA
```

Depois feche totalmente o Chrome:

```powershell
taskkill /F /IM chrome.exe
```

Abra o Chrome novamente e acesse:

```text
https://nexus.jmsalles.homelab.br
```

## 3. Opção B: importar pela interface gráfica do Windows

No Windows, pressione:

```text
Win + R
```

Digite:

```text
certlm.msc
```

Esse console instala o certificado para a máquina inteira.

Vá até:

```text
Autoridades de Certificação Raiz Confiáveis
Certificados
```

Clique com o botão direito em `Certificados`.

Selecione:

```text
Todas as Tarefas
Importar
```

Clique em `Avançar`.

Selecione o arquivo:

```text
jmsalles-homelab-rootCA.crt
```

Escolha:

```text
Colocar todos os certificados no repositório a seguir
```

Selecione:

```text
Autoridades de Certificação Raiz Confiáveis
```

Finalize o assistente.

Depois feche totalmente o Chrome:

```powershell
taskkill /F /IM chrome.exe
```

Abra novamente e acesse:

```text
https://nexus.jmsalles.homelab.br
```

## 4. Validação final no navegador

Após importar a CA, acesse:

```text
https://nexus.jmsalles.homelab.br
```

O erro esperado deve desaparecer:

```text
NET::ERR_CERT_AUTHORITY_INVALID
```

Se ainda aparecer erro, teste também no Edge, pois ele usa o mesmo repositório de certificados do Windows.

## 5. Se ainda não funcionar

Valide se o Windows está resolvendo o nome corretamente:

```powershell
nslookup nexus.jmsalles.homelab.br
```

Teste a conectividade na porta 443:

```powershell
Test-NetConnection nexus.jmsalles.homelab.br -Port 443
```

Limpe o cache DNS do Windows:

```powershell
ipconfig /flushdns
```

Feche novamente o Chrome:

```powershell
taskkill /F /IM chrome.exe
```

Abra o Chrome e teste de novo.

## Checklist

```text
CA raiz importada: jmsalles-homelab-rootCA.crt
Repositório correto: Autoridades de Certificação Raiz Confiáveis
Certificado do site validado: OK
SAN wildcard presente: *.jmsalles.homelab.br
Nginx mantido sem alteração
Chrome fechado e aberto novamente
```

## Assinatura

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)
