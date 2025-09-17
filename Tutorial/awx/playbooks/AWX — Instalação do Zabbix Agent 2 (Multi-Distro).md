perfeito, Jeferson — bora consolidar tudo com as **duas correções pedidas no Survey**:

* Pergunta para **versão do Zabbix Agent** (multiple choice) com **default = 7.4**.
* Pergunta para **Zabbix Server (IP/FQDN)** com **default = 192.168.31.35**.

Mantive: instalação multi-distro, firewall **só se já estiver ativo**, validação local com `zabbix_get`, e ordem correta no AWX (**cria o template, depois o Survey**). Também deixei os **defaults literais** no playbook para evitar loop de variáveis (trauma superado 😄).

---

# 📘 AWX — Instalação do Zabbix Agent 2 (multi-distro)

*Survey com versão (7.4 default) + Zabbix Server 192.168.31.35 • Firewall apenas se ativo • Validações*

## ✅ Pré-requisitos

* AWX com **ansible-core 2.15.13** (anotado).
* Inventário com os hosts de destino e credencial SSH válida (`become` disponível).
* Collections no projeto:

```bash
vim requirements.yml
```

```yaml
---
collections:
  - name: ansible.posix
    version: "1.*"
  - name: community.general
    version: "8.*"   # compatível e silenciosa com core 2.15.x
```

Sincronize o projeto no AWX (Project → Sync).

---

## 🗂️ Estrutura do repositório

```bash
vim zabbix_agent2_awx.yml
```

Cole o playbook abaixo (com os **defaults** pedidos e as validações robustas):

```yaml
---
- name: Instalar e configurar Zabbix Agent 2 (multi-distro, firewall só se ativo, sem API)
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Defaults seguros (Survey pode sobrescrever)
    zbx_version: "7.4"                 # default pedido
    zbx_server: "192.168.31.35"        # default pedido
    zbx_use_fqdn: false
    zbx_agent_port: 10050
    zbx_conf: /etc/zabbix/zabbix_agent2.conf

    # Controle de firewall: só adiciona regra se o firewall já estiver ativo
    zbx_firewall_manage_if_active: true

    # Validação remota opcional via container do Zabbix Server
    zbx_remote_validate: false
    zbx_server_container_host: "192.168.31.35"
    zbx_container_runtime: "docker"     # ou "podman"
    zbx_server_container_name: "zabbix-server"

    # Versões permitidas (para não quebrar URL de repo)
    zbx_version_allowed:
      - "7.4"
      - "7.2"
      - "6.4"

  pre_tasks:
    - name: Sanitizar entrada do Survey (server)
      set_fact:
        zbx_server_trim: "{{ zbx_server | trim }}"
        zbx_version_trim: "{{ zbx_version | trim }}"

    - name: Validar zbx_server (IPv4 ou FQDN)
      vars:
        _re_ipv4: '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'
        _re_fqdn: '^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$'
      assert:
        that:
          - zbx_server_trim | length > 0
          - (zbx_server_trim is match(_re_ipv4)) or (zbx_server_trim is match(_re_fqdn))
        fail_msg: >
          Valor inválido para zbx_server: "{{ zbx_server }}".
          Use IPv4 (ex.: 192.168.31.35) ou FQDN (ex.: zabbix.homelab).
      success_msg: "zbx_server validado (IPv4/FQDN)."

    - name: Validar zbx_version (lista permitida)
      assert:
        that:
          - zbx_version_trim in zbx_version_allowed
        fail_msg: >
          Versão '{{ zbx_version }}' não suportada neste playbook.
          Escolha uma de: {{ zbx_version_allowed | join(', ') }}.
      success_msg: "zbx_version = {{ zbx_version_trim }} (ok)."

    - name: Definir hostname do agente (FQDN ou curto)
      set_fact:
        zbx_hostname_value: "{{ (zbx_use_fqdn | default(false) | bool) | ternary(ansible_fqdn, ansible_hostname) }}"

  tasks:
    ###########################################################################
    # Instalação (RHEL-like)
    ###########################################################################
    - name: Instalar Zabbix Agent 2 — família RedHat
      when: ansible_os_family == "RedHat"
      block:
        - name: Major version RHEL-like
          set_fact:
            rhel_major: "{{ ansible_distribution_major_version }}"

        - name: Baixar repo Zabbix (zabbix-release.rpm)
          get_url:
            url: "https://repo.zabbix.com/zabbix/{{ zbx_version_trim }}/release/rhel/{{ rhel_major }}/noarch/zabbix-release-latest.el{{ rhel_major }}.noarch.rpm"
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
            repo: "deb https://repo.zabbix.com/zabbix/{{ zbx_version_trim }}/{{ ansible_distribution | lower }} {{ ansible_distribution_release }} main"
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
    - name: Backup do zabbix_agent2.conf (se existir)
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
        line: "Server={{ zbx_server_trim }}"
      notify: Restart zabbix-agent2

    - name: Ajustar ServerActive
      lineinfile:
        path: "{{ zbx_conf }}"
        regexp: '^ServerActive=.*'
        line: "ServerActive={{ zbx_server_trim }}"
      notify: Restart zabbix-agent2

    - name: Ajustar Hostname
      lineinfile:
        path: "{{ zbx_conf }}"
        regexp: '^Hostname=.*'
        line: "Hostname={{ zbx_hostname_value }}"
      notify: Restart zabbix-agent2

    ###########################################################################
    # Firewall condicional — só se ativo
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

    - name: Adicionar porta no firewalld (apenas se ativo e permitido)
      ansible.posix.firewalld:
        port: "{{ zbx_agent_port }}/tcp"
        permanent: true
        state: enabled
        immediate: true
      when:
        - ansible_os_family == "RedHat"
        - zbx_firewall_manage_if_active | bool
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

    - name: Adicionar porta no UFW (apenas se ativo e permitido)
      community.general.ufw:
        rule: allow
        port: "{{ zbx_agent_port }}"
        proto: tcp
      when:
        - ansible_os_family == "Debian"
        - zbx_firewall_manage_if_active | bool
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
      command: "ss -ltn sport = :{{ zbx_agent_port }}"
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

    # (Opcional) Validação remota via container do Zabbix Server
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

> Observação: **nada de Jinja auto-referenciando variáveis** nos defaults. O Survey vai **sobrepor** os valores de `zbx_version` e `zbx_server` quando você quiser.

---

## ▶️ Criar o **Job Template** no AWX (e só depois o Survey)

1. **Projects →** confirme o repositório e rode **Sync**.
2. **Templates → Add → Job Template**

   * **Name:** `Zabbix Agent 2 — Instalação`
   * **Job Type:** `Run`
   * **Inventory:** *seu inventário*
   * **Project:** *seu projeto*
   * **Playbook:** `zabbix_agent2_awx.yml`
   * **Execution Environment:** com as collections do `requirements.yml`
   * **Credentials:** Machine (SSH)
   * **Options:** habilite `Privilege Escalation` se precisar de `sudo`
   * **Save**.

---

## 📝 **Survey — Perguntas (ordem correta + defaults que você pediu)**

**1) Zabbix Version (major)**

* *Prompt:* `Zabbix Version (major)`
* *Variable:* `zbx_version`
* *Answer type:* `Multiple Choice`

  * Choices: `7.4`, `7.2`, `6.4`
  * **Default answer:** `7.4` ✅
* *Description:* “Versão do repositório oficial a usar (apenas essas são aceitas).”

**2) Zabbix Server (IP/FQDN)**

* *Prompt:* `Zabbix Server (IP/FQDN)`
* *Variable:* `zbx_server`
* *Answer type:* `Text`
* **Default answer:** `192.168.31.35` ✅
* *Required:* ✔
* *Description:* “Use IPv4 (ex.: 192.168.31.35) ou FQDN.”

**3) Usar FQDN como Hostname?**

* *Variable:* `zbx_use_fqdn`
* *Answer type:* `Multiple Choice` → `true` / `false` (default `false`)
* *Description:* “`true` usa ansible\_fqdn; `false` usa ansible\_hostname.”

**4) Porta do agente**

* *Variable:* `zbx_agent_port`
* *Answer type:* `Integer` • Default `10050` • Min `1` • Max `65535`.

**5) Gerenciar regra de firewall se ativo?**

* *Variable:* `zbx_firewall_manage_if_active`
* *Answer type:* `Multiple Choice` → `true` / `false` (default `true`)
* *Description:* “Adiciona a porta **{{ zbx\_agent\_port }}/tcp** apenas se `firewalld`/`UFW` já estiverem **ativos**.”

**(Opcional) 6–8) Validação remota via container**

* `zbx_remote_validate` (Multiple Choice `true/false`, default `false`)
* `zbx_server_container_host` (Text, default `192.168.31.35`)
* `zbx_container_runtime` (Multiple Choice `docker/podman`, default `docker`)
* `zbx_server_container_name` (Text, default `zabbix-server`)

> Importante: o AWX **não** tem “regex validation” no Survey. As **validações reais** estão no `pre_tasks` (asserts de IPv4/FQDN e versão permitida).

---

## 🧪 Execução e validações

* Rode o Job. No output, verifique:

  * `zbx_version = 7.4 (ok)` (ou a escolha do Survey).
  * `zbx_server validado (IPv4/FQDN).`
  * Instalação do repo + `zabbix-agent2` e `zabbix-get`.
  * Edição de `Server`, `ServerActive`, `Hostname`.
  * **Firewall:** só há tasks se o serviço já estiver **ativo** e `zbx_firewall_manage_if_active=true`.
  * `ss -ltn sport = :10050` exibindo a porta em escuta.
  * `zabbix_get local: 1`.

Validação manual extra (da VM `192.168.31.35`, se quiser):

```bash
docker exec -it zabbix-server zabbix_get -s <IP_DO_HOST_AGENTE> -k agent.ping
# ou
podman exec -it zabbix-server zabbix_get -s <IP_DO_HOST_AGENTE> -k agent.ping
```

---

## 🆘 Troubleshooting rápido

```bash
# Serviço e logs
systemctl status zabbix-agent2
journalctl -u zabbix-agent2 -n 200 --no-pager

# Testes locais
ss -ltn sport = :10050
zabbix_get -s 127.0.0.1 -p 10050 -k agent.ping

# Firewalld (RHEL-like)
systemctl is-active firewalld && firewall-cmd --list-ports

# UFW (Debian/Ubuntu)
ufw status verbose
```

Se der erro de versão, o assert aponta o valor aceito. Para ampliar a lista, basta adicionar versões a `zbx_version_allowed` e publicar.

---

## ✅ Checklist final

* `requirements.yml` com versões compatíveis.
* `zabbix_agent2_awx.yml` aplicado (defaults 7.4 e 192.168.31.35).
* Job Template criado → **Survey adicionado** (com os defaults acima).
* Execução concluída com `agent.ping = 1`.
* Firewall tocado **apenas** quando ativo (e autorizado).

---

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles](https://github.com/jmsalles)
