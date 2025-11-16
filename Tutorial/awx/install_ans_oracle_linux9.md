Sim, bora ter essa segunda opção “tudo-em-um” em cima de uma **máquina Oracle Linux 9** 😄

Aqui vou usar o **Oracle Linux Automation Manager 2.3 (OLAM)**, que é o **AWX empacotado e suportado pela Oracle**, baseado em AWX 24.6.1 e disponível oficialmente para Oracle Linux 9. ([Blogs Oracle][1])
Ou seja: na prática é um AWX/Tower “Oracle-flavor”, rodando em um único host.

---

# Guia de Instalação do Oracle Linux Automation Manager (AWX) em uma máquina Oracle Linux 9

---

## 🎯 Resumo

Instalação passo a passo do **Oracle Linux Automation Manager 2.3** (AWX-based) em um único servidor **Oracle Linux 9**, usando:

* Banco **PostgreSQL 16 local**
* Serviço **ol-automation-manager** (stack AWX + Engine)
* **NGINX + TLS self-signed** na porta 443
* Containers rodando com **podman** sob o usuário `awx` ([Oracle Docs][2])

Fica perfeito como **alternativa** ao AWX no cluster Kubernetes: um único servidor OL9 que vira seu “Tower” oficial.

---

## 🧭 Sumário

* [Visão geral e premissas](#visão-geral-e-premissas)
* [Pré-requisitos do sistema](#pré-requisitos-do-sistema)
* [Habilitar repositórios e firewall](#habilitar-repositórios-e-firewall)
* [Instalar e configurar PostgreSQL 16](#instalar-e-configurar-postgresql-16)
* [Instalar o Oracle Linux Automation Manager](#instalar-o-oracle-linux-automation-manager)
* [Ajustar Redis (socket UNIX)](#ajustar-redis-socket-unix)
* [Configurar o arquivo olam.py (DB + cluster)](#configurar-o-arquivo-olampy-db--cluster)
* [Habilitar lingering para o usuário awx](#habilitar-lingering-para-o-usuário-awx)
* [Baixar imagem e inicializar o AWX](#baixar-imagem-e-inicializar-o-awx)
* [Configurar TLS com NGINX](#configurar-tls-com-nginx)
* [Configurar o Receptor e registrar o nó](#configurar-o-receptor-e-registrar-o-nó)
* [Subir o serviço e acessar a UI](#subir-o-serviço-e-acessar-a-ui)
* [Verificações básicas](#verificações-básicas)
* [Troubleshooting rápido](#troubleshooting-rápido)
* [Checklist final](#checklist-final)

---

## Visão geral e premissas

Premissas do cenário:

* Servidor `Oracle Linux 9` x86_64 atualizado
* Acesso `root` ou `sudo`
* Host com FQDN, por exemplo: `olam.jmsalles.homelab.br`
* Porta **443/TCP** liberada na rede
* Uso de **PostgreSQL local** e instalação **single host** (não cluster) conforme docs oficiais da Oracle ([Oracle Docs][2])

---

## Pré-requisitos do sistema

Atualize o sistema e instale ferramentas básicas:

```bash
sudo dnf -y update
sudo dnf -y install vim git firewalld curl bc
```

Garanta que o `firewalld` esteja ativo:

```bash
sudo systemctl enable --now firewalld
sudo systemctl status firewalld
```

---

## Habilitar repositórios e firewall

Instalar o repositório do **Oracle Linux Automation Manager** para OL9:

```bash
sudo dnf -y install oraclelinux-automation-manager-release-el9
```

(Esse pacote habilita o repo de Automation Manager 2.x para Oracle Linux 9. ([Oracle Docs][3]))

Liberar HTTPS no firewall:

```bash
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload
```

Se quiser também HTTP (para redirecionar):

```bash
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload
```

---

## Instalar e configurar PostgreSQL 16

A Oracle recomenda **PostgreSQL 16** para OLAM 2.3. ([Oracle Docs][2])

### 1. Habilitar o módulo do PostgreSQL 16

```bash
sudo dnf module reset postgresql
sudo dnf -y module enable postgresql:16
```

### 2. Instalar o servidor PostgreSQL

```bash
sudo dnf -y install postgresql-server
```

### 3. Inicializar o banco

```bash
sudo postgresql-setup --initdb
```

### 4. Configurar criptografia de senha e acesso

Habilitar `scram-sha-256`:

```bash
sudo sed -i "s/#password_encryption.*/password_encryption = scram-sha-256/" /var/lib/pgsql/data/postgresql.conf
```

Permitir acesso usando SCRAM:

```bash
echo "host  all  all 0.0.0.0/0 scram-sha-256" | sudo tee -a /var/lib/pgsql/data/pg_hba.conf > /dev/null
```

Fazer o Postgres escutar no IP da máquina:

```bash
sudo sed -i "/^#port = 5432/i listen_addresses = '"$(hostname -i)"'" /var/lib/pgsql/data/postgresql.conf
```

(Se preferir, pode trocar `$(hostname -i)` por `127.0.0.1` em ambiente bem fechado.)

### 5. Subir o Postgres

```bash
sudo systemctl enable --now postgresql
sudo systemctl status postgresql
```

### 6. Criar usuário e base `awx`

Defina uma senha forte para o usuário do banco (guarde para usar no `olam.py`):

```bash
sudo su - postgres -c "createuser -S -P awx"
sudo su - postgres -c "createdb -O awx awx"
```

---

## Instalar o Oracle Linux Automation Manager

Agora instalamos o “Tower” da Oracle (AWX baseado na versão 24.6.1 no OLAM 2.3). ([Blogs Oracle][1])

```bash
sudo dnf -y install ol-automation-manager
```

Esse pacote traz:

* Serviços do AWX (web, task, receptor)
* NGINX
* Arquivos em `/etc/tower` e `/var/lib/ol-automation-manager`

---

## Ajustar Redis (socket UNIX)

O OLAM usa Redis com socket UNIX. Para OL9, ajuste o arquivo adequado: ([Oracle Docs][2])

```bash
sudo sed -i '/^# unixsocketperm/a unixsocket /var/run/redis/redis.sock\nunixsocketperm 775' /etc/redis/redis.conf
```

Reinicie o Redis:

```bash
sudo systemctl enable --now redis
sudo systemctl status redis
```

---

## Configurar o arquivo `olam.py` (DB + cluster)

Vamos centralizar as configurações do cluster e do banco em `/etc/tower/conf.d/olam.py`.

Edite com `vim`:

```bash
sudo vim /etc/tower/conf.d/olam.py
```

Conteúdo sugerido (ajuste IP/host e senha do banco):

```python
CLUSTER_HOST_ID = '<IP-ou-FQDN-do-servidor>'

DATABASES = {
    'default': {
        'ATOMIC_REQUESTS': True,
        'ENGINE': 'awx.main.db.profiled_pg',
        'NAME': 'awx',
        'USER': 'awx',
        'PASSWORD': '<senha-do-usuario-awx-no-postgres>',
        'HOST': '<IP-ou-127.0.0.1>',
        'PORT': '5432',
    }
}
```

Depois ajuste as permissões:

```bash
sudo chown awx.awx /etc/tower/conf.d/olam.py
sudo chmod 0640 /etc/tower/conf.d/olam.py
```

---

## Habilitar lingering para o usuário `awx` (cgroup v2)

Para evitar problemas com cgroup v2 e pods rootless, habilite “linger” no usuário `awx` no OL9: ([Oracle Docs][2])

```bash
sudo loginctl enable-linger awx
```

---

## Baixar imagem e inicializar o AWX

Agora vamos operar como usuário `awx` e preparar o ambiente.

### 1. Entrar como `awx`

```bash
sudo su -l awx -s /bin/bash
```

### 2. Ajustar podman e baixar a imagem OLAM

```bash
podman system migrate

podman pull container-registry.oracle.com/oracle_linux_automation_manager/olam-ee:2.3-ol9
```

*(Se o registry da Oracle pedir login, use `podman login container-registry.oracle.com` com uma conta integrada.)* ([Oracle Docs][2])

### 3. Migrar o banco e criar o usuário admin

```bash
awx-manage migrate

awx-manage createsuperuser --username admin --email admin@example.com
```

Defina uma senha forte para o usuário `admin` (será usada na UI).

Saia do shell do `awx`:

```bash
exit
```

---

## Configurar TLS com NGINX

Gerar um certificado autoassinado (para produção, ideal usar CA interna/cert-manager):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/tower/tower.key -out /etc/tower/tower.crt
```

Preencha ou apenas dê ENTER nas perguntas.

O OLAM já traz a configuração de NGINX preparada para servir a UI na 443 usando esses arquivos; se quiser seguir exatamente o modelo do guia da Oracle, você pode sobrescrever o `/etc/nginx/nginx.conf` como eles sugerem, mas na maior parte dos casos o padrão empacotado já funciona bem. ([Oracle Docs][2])

---

## Configurar o Receptor e registrar o nó

O **receptor** orquestra a execução (control plane + execution). Vamos garantir uma configuração simples de nó híbrido.

Edite o arquivo de configuração do Receptor:

```bash
sudo vim /etc/receptor/receptor.conf
```

Sugestão de conteúdo (ajuste o host se quiser algo mais estático):

```yaml
---
- node:
    id: <IP-ou-FQDN-do-servidor>
- log-level: debug

- tcp-listener:
    port: 27199

- control-service:
    service: control
    filename: /var/run/receptor/receptor.sock

- work-command:
    worktype: local
    command: /var/lib/ol-automation-manager/venv/awx/bin/ansible-runner
    params: worker
    allowruntimeparams: true
    verifysignature: false
```

Salve, depois registre o nó/queues como `awx`:

```bash
sudo su -l awx -s /bin/bash

awx-manage provision_instance --hostname=$(hostname -i) --node_type=hybrid
awx-manage register_default_execution_environments
awx-manage register_queue --queuename=default --hostnames=$(hostname -i)
awx-manage register_queue --queuename=controlplane --hostnames=$(hostname -i)
awx-manage create_preload_data

exit
```

---

## Subir o serviço e acessar a UI

Ative e inicie o serviço principal:

```bash
sudo systemctl enable --now ol-automation-manager.service
sudo systemctl status ol-automation-manager.service
```

Se tudo estiver OK, abra no navegador:

```text
https://<ip-ou-fqdn-do-servidor>
```

Login:

* Usuário: `admin`
* Senha: a que você definiu no `createsuperuser`

---

## Verificações básicas

Checar se os serviços principais estão ok:

```bash
sudo systemctl status ol-automation-manager
sudo systemctl status nginx
sudo systemctl status redis
sudo systemctl status postgresql
sudo systemctl status receptor
```

Se algo estiver estranho, veja os logs do Automation Manager:

```bash
sudo journalctl -u ol-automation-manager -f
```

E os logs do NGINX:

```bash
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

---

## Troubleshooting rápido

Alguns sintomas típicos:

* **Página não abre / timeout**

  * Verifique firewall (`firewall-cmd --list-services`) e se NGINX está ativo.

* **Erro 502 / 500 na UI**

  * Veja `journalctl -u ol-automation-manager -f`.
  * Revise `DATABASES` em `/etc/tower/conf.d/olam.py` (senha/host/porta).

* **Erro de conexão ao Postgres**

  * Teste com `psql`:

    ```bash
    sudo -u awx psql -h <IP-do-servidor> -U awx -d awx -c 'select 1;'
    ```

* **Erro de cgroup / systemd user session**

  * Confirme se o `loginctl enable-linger awx` foi executado corretamente. ([Oracle Docs][2])

---

## Checklist final

* [ ] Oracle Linux 9 atualizado
* [ ] Repositório `oraclelinux-automation-manager-release-el9` instalado
* [ ] PostgreSQL 16 configurado com `password_encryption = scram-sha-256`
* [ ] Usuário e DB `awx` criados no Postgres
* [ ] Pacote `ol-automation-manager` instalado
* [ ] Redis ajustado com socket UNIX
* [ ] `/etc/tower/conf.d/olam.py` configurado e com permissões corretas
* [ ] `loginctl enable-linger awx` aplicado
* [ ] Imagem `olam-ee:2.3-ol9` baixada via `podman`
* [ ] `awx-manage migrate` e `createsuperuser` executados
* [ ] Certificado TLS criado para o NGINX
* [ ] Receptor configurado e instância registrada como `hybrid`
* [ ] Serviço `ol-automation-manager.service` ativo e acessível via HTTPS

---

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)

[1]: https://blogs.oracle.com/linux/oracle-linux-automation-manager-23?utm_source=chatgpt.com "Oracle Linux Automation Manager 2.3 is now available on ..."
[2]: https://docs.oracle.com/en/learn/olam-install/index.html "Install Oracle Linux Automation Manager on Oracle Linux"
[3]: https://docs.oracle.com/en/operating-systems/oracle-linux-automation-manager/2/install2.3/OLAM2-INSTALL2-3.pdf?utm_source=chatgpt.com "Oracle Linux Automation Manager 2.3 - Installation Guide"
