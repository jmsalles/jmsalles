perfeito, Jeferson — ajustei para **somente instalar e configurar o zabbix-agent2** (sem criar host na API). Também **adição de perguntas (Survey)** no **Job Template** — na ordem correta: **crie o template primeiro**, depois **adicione o Survey**. Mantive **firewall condicional** (só adiciona regra se o firewall já estiver ativo) e deixei **validação do agente** local (e remota opcional, desativada por padrão).

---

# 📘 AWX — Instalação do Zabbix Agent 2 (Multi-Distro)

*Firewall só se ativo • Survey completo • Sem cadastro na API*

## 🔎 Resumo

Instala e configura o **zabbix-agent2** em Rocky/Alma/RHEL e Debian/Ubuntu, define `Server`, `ServerActive` e `Hostname` (curto ou FQDN), **só** abre a porta **10050/tcp** se o **firewalld** (RHEL-like) ou **UFW** (Debian/Ubuntu) já estiver **ativo**, valida com `zabbix_get`. **Não** registra o host no Zabbix.

---

## 📑 Sumário

* Pré-requisitos
* Estrutura do projeto
* Playbook (`zabbix_agent2_awx.yml`)
* Criação do Job Template (depois faremos o Survey)
* **Survey — Perguntas e validações (ordem correta)**
* Execução e validações
* Troubleshooting rápido
* Checklist final
* Assinatura

---

## ✅ Pré-requisitos

* Inventário acessível por SSH no AWX.
* Permissão de `become` nos alvos.
* Collections:

```bash
vim requirements.yml
```

```yaml
---
collections:
  - ansible.posix
  - community.general
```

> No AWX: faça **Project → Sync** para instalar as collections (Project Update com `ansible-galaxy install -r requirements.yml`).

---

## 🗂️ Estrutura do projeto

```bash
vim zabbix_agent2_awx.yml
```

> Cole o playbook completo abaixo.

Opcionalmente, defaults globais:

```bash
mkdir -p group_vars && vim group_vars/all.yml
```

```yaml
zbx_version: "7.4"
zbx_agent_port: 10050
zbx_use_fqdn: false
zbx_remote_validate: false        # validação remota via container (opcional)
zbx_server_container_host: "192.168.31.35"
zbx_container_runtime: "docker"   # "docker" ou "podman"
zbx_server_container_name: "zabbix-server"
```

---

## 🛠️ Playbook — `zabbix_agent2_awx.yml` (sem cadastro na API)

```yaml
---
- name: Instalar e configurar Zabbix Agent 2 (multi-distro, firewall só se ativo, sem API)
  hosts: all
  become: true
  gather_facts: true

  vars:
    zbx_version: "{{ zbx_version | default('7.4') }}"
    zbx_server: ""                    # definido via Survey
    zbx_use_fqdn: "{{ zbx_use_fqdn | default(false) }}"
    zbx_agent_port: "{{ zbx_agent_port | default(10050) }}"
    zbx_conf: /etc/zabbix/zabbix_agent2.conf

    # Validação remota opcional (container no host 192.168.31.35)
    zbx_remote_validate: "{{ zbx_remote_validate | default(false) }}"
    zbx_server_container_host: "{{ zbx_server_container_host | default('192.168.31.35') }}"
    zbx_container_runtime: "{{ zbx_container_runtime | default('docker') }}"
    zbx_server_container_name: "{{ zbx_server_container_name | default('zabbix-server') }}"

  pre_tasks:
    - name: Validar zbx_server (IP ou FQDN)
      assert:
        that:
          - zbx_server | length > 0
          - zbx_server is match("^(?:(?:[0-9]{1,3}\\.){3}[0-9]{1,3}|[A-Za-z0-9_.-]+)$")
        fail_msg: "Defina 'zbx_server' (IP ou FQDN) no Survey."

    - name: Definir hostname do agente (FQDN ou curto)
      set_fact:
        zbx_hostname_value: "{{ (zbx_use_fqdn | bool) | ternary(ansible_fqdn, ansible_hostname) }}"

  tasks:
    ###########################################################################
    # Instalação (RHEL-like)
    ###########################################################################
    - name: Instalar Zabbix Agent 2 — família RedHat
      when: ansible_os_family == "RedHat"
      block:
        - name: Descobrir major version
          set_fact:
            rhel_major: "{{ ansible_distribution_major_version }}"

        - name: Baixar repo zabbix-release.rpm
          get_url:
            url: "https://repo.zabbix.com/zabbix/{{ zbx_version }}/release/rhel/{{ rhel_major }}/noarch/zabbix-release-latest.el{{ rhel_major }}.noarch.rpm"
            dest: "/tmp/zabbix-release-latest.el{{ rhel_major }}.noarch.rpm"
            mode: '0644'

        - name: Instalar repo Zabbix
          yum:
            name: "/tmp/zabbix-release-latest.el{{ rhel_major }}.noarch.rpm"
            state: present

        - name: Instalar zabbix-agent2 e zabbix-get
          yum:
            name:
              - zabbix-agent2
              - zabbix-get
            state: present
            update_cache: true

    ###########################################################################
    # Instalação (Debian/Ubuntu)
    ###########################################################################
    - name: Instalar Zabbix Agent 2 — família Debian
      when: ansible_os_family == "Debian"
      block:
        - name: Pacotes base
          apt:
            name:
              - ca-certificates
              - gnupg
            state: present
            update_cache: true

        - name: Adicionar chave pública do repo Zabbix
          apt_key:
            url: https://repo.zabbix.com/zabbix-official-repo.key
            state: present

        - name: Adicionar repositório Zabbix (Apt)
          apt_repository:
            repo: "deb https://repo.zabbix.com/zabbix/{{ zbx_version }}/{{ ansible_distribution | lower }} {{ ansible_distribution_release }} main"
            state: present
            filename: "zabbix"

        - name: Instalar zabbix-agent2 e zabbix-get
          apt:
            name:
              - zabbix-agent2
              - zabbix-get
            state: present
            update_cache: true

    ###########################################################################
    # Configuração do agente
    ###########################################################################
    - name: Backup de /etc/zabbix/zabbix_agent2.conf (se existir)
      copy:
        src: "{{ zbx_conf }}"
        dest: "{{ zbx_conf }}.bak"
        remote_src: true
      when: zbx_conf is file
      ignore_errors: true

    - name: Ajustar Server
      lineinfile:
        path: "{{ zbx_conf }}"
        regexp: '^Server=.*'
        line: "Server={{ zbx_server }}"
      notify: Restart zabbix-agent2

    - name: Ajustar ServerActive
      lineinfile:
        path: "{{ zbx_conf }}"
        regexp: '^ServerActive=.*'
        line: "ServerActive={{ zbx_server }}"
      notify: Restart zabbix-agent2

    - name: Ajustar Hostname
      lineinfile:
        path: "{{ zbx_conf }}"
        regexp: '^Hostname=.*'
        line: "Hostname={{ zbx_hostname_value }}"
      notify: Restart zabbix-agent2

    ###########################################################################
    # Firewall condicional — só adiciona regra se o firewall estiver ATIVO
    ###########################################################################
    - name: Coletar facts de serviços
      service_facts:

    - name: Checar firewalld em execução (RHEL-like)
      set_fact:
        firewalld_running: >-
          {{ (ansible_facts.services is defined)
             and ('firewalld.service' in ansible_facts.services)
             and (ansible_facts.services['firewalld.service'].state == 'running') }}
      when: ansible_os_family == "RedHat"

    - name: Adicionar porta no firewalld (apenas se ativo)
      ansible.posix.firewalld:
        port: "{{ zbx_agent_port }}/tcp"
        permanent: true
        state: enabled
        immediate: true
      when:
        - ansible_os_family == "RedHat"
        - firewalld_running | bool
      notify: Reload firewalld

    - name: Checar status do UFW (Debian/Ubuntu)
      command: ufw status
      register: ufw_status
      changed_when: false
      failed_when: false
      when: ansible_os_family == "Debian"

    - name: Definir se UFW está ativo
      set_fact:
        ufw_active: "{{ (ufw_status.stdout | default('')) is search('Status:\\s+active') }}"
      when: ansible_os_family == "Debian"

    - name: Adicionar porta no UFW (apenas se ativo)
      community.general.ufw:
        rule: allow
        port: "{{ zbx_agent_port }}"
        proto: tcp
      when:
        - ansible_os_family == "Debian"
        - ufw_active | bool

    ###########################################################################
    # Serviço e validação
    ###########################################################################
    - name: Habilitar e iniciar zabbix-agent2
      systemd:
        name: zabbix-agent2
        enabled: true
        state: started
        daemon_reload: true

    - name: Verificar porta local ({{ zbx_agent_port }})
      command: "ss -lnt '( sport = :{{ zbx_agent_port }} )'"
      register: ss_check
      changed_when: false
      failed_when: false

    - name: Exibir resultado de escuta
      debug:
        msg: "{{ ss_check.stdout | default('Porta não detectada (ss)') }}"

    - name: Teste local com zabbix_get (agent.ping)
      command: "zabbix_get -s 127.0.0.1 -p {{ zbx_agent_port }} -k agent.ping"
      register: zbxget_local
      changed_when: false
      failed_when: false

    - name: Resultado zabbix_get local (esperado: 1)
      debug:
        msg: "zabbix_get local: {{ zbxget_local.stdout | default('sem saída') }}"

    # Validação remota opcional via container do Zabbix Server
    - name: Teste remoto (container) — opcional
      delegate_to: "{{ zbx_server_container_host }}"
      when: zbx_remote_validate | bool
      vars:
        _rt: "{{ 'podman' if zbx_container_runtime == 'podman' else 'docker' }}"
        _cmd: "{{ _rt }} exec -i {{ zbx_server_container_name }} zabbix_get -s {{ ansible_default_ipv4.address }} -k agent.ping"
      command: "{{ _cmd }}"
      register: zbxget_remote
      changed_when: false
      failed_when: false

    - name: Resultado zabbix_get remoto (esperado: 1)
      when: zbx_remote_validate | bool
      debug:
        msg: "zabbix_get remoto: {{ zbxget_remote.stdout | default('sem saída') }}"

  handlers:
    - name: Restart zabbix-agent2
      systemd:
        name: zabbix-agent2
        state: restarted

    - name: Reload firewalld
      command: firewall-cmd --reload
      when: firewalld_running | default(false) | bool
```

---

## 🧩 Criar o **Job Template** (depois faremos o Survey)

1. **Projects →** confirme o projeto com `zabbix_agent2_awx.yml` e **Sync**.
2. **Templates → Add → Job Template**

   * **Name:** `Zabbix Agent 2 — Instalação`
   * **Job Type:** `Run`
   * **Inventory:** *seu inventário*
   * **Project:** *seu projeto*
   * **Playbook:** `zabbix_agent2_awx.yml`
   * **Execution Environment:** com as collections instaladas
   * **Credentials:** `Machine` (SSH)
   * **Privilege Escalation:** habilite se necessário (`become`)
   * **Save**.

> Agora edite o Template salvo e **adicione o Survey**.

---

## 📝 **Survey — Perguntas e validações (ordem correta)**

**1) Zabbix Server (IP/FQDN)**

* *Variable:* `zbx_server`
* *Type:* `Text` • *Required:* ✔
* *Validation (Regex):*

  ```
  ^((?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9_.-]+)$
  ```
* *Help:* “Endereço do seu Zabbix Server. Ex.: `192.168.31.35` ou `zabbix.homelab`.”

**2) Usar FQDN como Hostname?**

* *Variable:* `zbx_use_fqdn`
* *Type:* `Multiple Choice` → `true` / `false` (default `false`)
* *Help:* “`true` usa `ansible_fqdn`; `false` usa `ansible_hostname`.”

**3) Porta do agente**

* *Variable:* `zbx_agent_port`
* *Type:* `Integer` • *Default:* `10050` • *Min:* `1` • *Max:* `65535`
* *Help:* “Porta TCP do zabbix-agent2.”

**4) Adicionar regra de firewall se o firewall estiver ATIVO?**

* *Variable:* `zbx_firewall_manage_if_active`
* *Type:* `Multiple Choice` → `true` / `false` (default `true`)
* *Help:* “Se `true`, adiciona `{{ zbx_agent_port }}/tcp` **somente** se `firewalld`/`UFW` já estiverem ativos.”

> Para usar essa pergunta, inclua duas pequenas mudanças no playbook:
> a) adicione `zbx_firewall_manage_if_active: "{{ zbx_firewall_manage_if_active | default(true) }}"` em `vars`;
> b) acrescente a condição `- zbx_firewall_manage_if_active | bool` nas tasks de firewalld/UFW.

**5) Validação remota pelo container do Zabbix Server (opcional)**

* *Variable:* `zbx_remote_validate`
* *Type:* `Multiple Choice` → `true` / `false` (default `false`)
* *Help:* “Executa `zabbix_get` de dentro do container na VM `192.168.31.35`.”

**6) Host do container do Zabbix Server**

* *Variable:* `zbx_server_container_host`
* *Type:* `Text` • *Default:* `192.168.31.35`

**7) Runtime do container**

* *Variable:* `zbx_container_runtime`
* *Type:* `Multiple Choice` → `docker` / `podman` (default `docker`)

**8) Nome do container do Zabbix Server**

* *Variable:* `zbx_server_container_name`
* *Type:* `Text` • *Default:* `zabbix-server`

> Se quiser manter o playbook enxuto, você pode **pular as perguntas 5–8** (a validação local já é suficiente).

---

## ▶️ Execução e validações

* Rode o **Job** e confira no output:

  * `zabbix_get local: 1` (ok)
  * `ss -lnt '( sport = :10050 )'` mostra a porta em escuta
  * Logs de firewall **só** se o firewall estiver ativo (e `zbx_firewall_manage_if_active=true`)

* Validação manual extra na VM `192.168.31.35` (Zabbix em container):

```bash
docker exec -it zabbix-server zabbix_get -s <IP_DO_HOST_AGENTE> -k agent.ping
# ou, se usa Podman:
podman exec -it zabbix-server zabbix_get -s <IP_DO_HOST_AGENTE> -k agent.ping
```

---

## 🆘 Troubleshooting rápido

```bash
# Serviço e logs
systemctl status zabbix-agent2
journalctl -u zabbix-agent2 -n 200 --no-pager

# Testes locais
zabbix_get -s 127.0.0.1 -p 10050 -k agent.ping
ss -lnt '( sport = :10050 )'

# Firewalld ativo?
systemctl is-active firewalld && firewall-cmd --list-ports

# UFW ativo?
ufw status verbose
```

Pontos de atenção:

* `zbx_server` precisa ser roteável a partir do agente (para *active checks*).
* Se seu `zabbix_agent2.conf` estiver muito custom, `lineinfile` mantém só as três diretivas alvo.

---

## ✅ Checklist final

* Projeto contém `requirements.yml` e `zabbix_agent2_awx.yml`.
* Job Template criado e salvo; **Survey adicionado depois**.
* Variáveis cruciais no Survey: `zbx_server`, `zbx_use_fqdn`, `zbx_agent_port`.
* Firewall: regra só se **ativo** (e conforme sua opção no Survey).
* Output mostra `agent.ping = 1`.

---

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles](https://github.com/jmsalles)
