# 📦 AWX — Instalação de Pacotes via **Survey** (CSV)

## 🔎 Resumo

Job Template do AWX para instalar pacotes em distros Linux a partir de **CSV** informado no **Survey**. O playbook detecta o gerenciador (APT/DNF/YUM/Zypper/Pacman), atualiza cache quando aplicável e instala com `state` configurável (`present` ou `latest`).
Ambiente: **ansible-core 2.15.13**. Repositório: **`~/awx-project`** (já existente). Grupo de destino: **`post_instalação`**.

---

## 🧭 Sumário

* Playbook `os_instala_pacotes.yml`
* Criação do Template no AWX (Survey depois)
* Descrições prontas (Template e Survey)
* Execução e validação
* Solução de problemas
* Checklist
* Referências rápidas

---

## 🧱 Playbook `os_instala_pacotes.yml`

Edite no caminho padrão do teu projeto:

```bash
vim ~/awx-project/playbooks/os_instala_pacotes.yml
```

```yaml
---
- name: Instalar pacotes informados via Survey (CSV)
  hosts: post_instalação
  gather_facts: true
  become: true

  vars:
    # Recebidas do Survey
    packages_csv: "{{ packages_csv | default('', true) }}"
    pkg_state: "{{ pkg_state | default('present') }}"

  pre_tasks:
    - name: Validar entrada 'packages_csv' (não pode ser vazia)
      assert:
        that:
          - packages_csv is string
          - packages_csv | length > 0
        fail_msg: "Informe um CSV de pacotes no Survey (ex.: htop, curl, vim-enhanced)."
        success_msg: "Entrada de pacotes validada."

    - name: Normalizar CSV em lista (trim; remove itens vazios)
      set_fact:
        packages_list: >-
          {{
            packages_csv.split(',')
            | map('regex_replace', '^(\\s+)|(\\s+)$', '')
            | reject('equalto', '')
            | list
          }}

    - name: Exibir lista final de pacotes
      debug:
        var: packages_list

    - name: Atualizar cache (APT)
      apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts.pkg_mgr == 'apt'

    - name: Atualizar cache (DNF)
      dnf:
        update_cache: true
      when: ansible_facts.pkg_mgr == 'dnf'

    - name: Atualizar cache (YUM)
      yum:
        update_cache: true
      when: ansible_facts.pkg_mgr == 'yum'

    - name: Atualizar cache (Zypper)
      zypper:
        update_cache: true
      when: ansible_facts.pkg_mgr == 'zypper'

    - name: Atualizar cache (Pacman)
      pacman:
        update_cache: true
      when: ansible_facts.pkg_mgr == 'pacman'

  tasks:
    - name: Instalar pacotes (módulo genérico)
      package:
        name: "{{ packages_list }}"
        state: "{{ pkg_state }}"
      register: pkg_result

    - name: Resultado resumido
      debug:
        msg:
          changed: "{{ pkg_result.changed | default('n/a') }}"
          results: "{{ pkg_result.results | default(pkg_result) }}"
```

> Dica: `pkg_state=latest` força instalar/atualizar para a versão disponível no repositório da distro.

---

## 🏗️ Criação do Template no AWX (Survey depois)

1. **Project**

* Use o teu **Project** já apontando para `~/awx-project` (via SCM/Git conforme já configurado).

2. **Job Template** (criar **antes** do Survey)

* **Name:** `Instalar Pacotes — CSV`
* **Job Type:** `Run`
* **Inventory:** selecione **seu inventário existente**
* **Project:** (teu projeto conectado ao `~/awx-project`)
* **Playbook:** `playbooks/os_instala_pacotes.yml`
* **Credentials:** tua credencial **Machine**
* **Options:** marque **Enable Privilege Escalation** se precisar de sudo
* **Save**

3. **Survey** (após salvar o Template)

* **Pergunta 1**

  * **Question:** `Pacotes (CSV)`
  * **Description:** `Informe a lista de pacotes separados por vírgula (sem aspas). Exemplos: htop, curl • vim (Debian/Ubuntu) • vim-enhanced (RHEL/Rocky/Fedora).`
  * **Answer Variable Name:** `packages_csv`
  * **Answer Type:** `Text` (ou `Text Area`)
  * **Required:** `Yes`
  * **Default:** `htop, curl`
* **Pergunta 2**

  * **Question:** `Estado dos pacotes`
  * **Description:** `Escolha 'present' para garantir instalado ou 'latest' para instalar/atualizar.`
  * **Answer Variable Name:** `pkg_state`
  * **Answer Type:** `Multiple Choice (single select)`
  * **Choices:**

    ```
    present
    latest
    ```
  * **Default:** `present`
* **Save** o Survey.

> Observação: caso a UI não tenha “validation regex”, a validação de não-vazio já é feita via `assert`.

---

## 📝 Descrições prontas (colar no AWX)

**Descrição do Job Template:**

> Instala pacotes em Linux a partir de uma lista CSV informada no Survey. O playbook normaliza a lista, atualiza o cache do gerenciador (APT/DNF/YUM/Zypper/Pacman) e instala com state configurável (present/latest). Use nomes de pacotes compatíveis com sua distro. Ex.: htop, curl, vim-enhanced.

**Descrição da Pergunta 1 (Survey):**

> Informe a lista de pacotes separados por vírgula (sem aspas). Exemplos: `htop, curl` (genérico) • `vim` (Debian/Ubuntu) • `vim-enhanced` (RHEL/Rocky/Fedora).

---

## ▶️ Execução e validação

**Disparo**

```bash
# AWX → Templates → Instalar Pacotes — CSV → Launch
# Preencha o Survey: ex.: htop, curl, vim-enhanced
```

**Validação rápida**

```bash
# Debian/Ubuntu
dpkg -l | egrep 'htop|vim|curl'
```

```bash
# RHEL/Rocky/CentOS/Fedora
rpm -q htop vim-enhanced curl || true
dnf list installed | egrep 'htop|vim|curl'
```

```bash
# openSUSE
zypper se -i htop vim curl
```

```bash
# Arch
pacman -Qi htop vim curl
```

---

## 🧯 Solução de problemas

**Pacote não encontrado**

```bash
cat /etc/os-release
# confirme o nome exato do pacote para a família da distro
```

**Lock/Cache do gerenciador**

```bash
# Debian/Ubuntu (usar com cuidado)
sudo dpkg --configure -a
sudo rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock
```

**Proxy/CA corporativa**

```bash
# exponha HTTP(S)_PROXY no Template (Environment) ou em group_vars
```

**Falha de sudo**

```bash
# habilite Privilege Escalation na credencial/Template
```

---

## ☑️ Checklist

* `~/awx-project/playbooks/os_instala_pacotes.yml` criado.
* Job Template criado **antes** do Survey.
* Survey com `packages_csv` (obrigatório) e `pkg_state` (default `present`).
* Hosts-alvo pertencem ao grupo **post\_instalação** no teu inventário existente.
* Execução validada nos nós.

---

## 🔗 Referências rápidas

* Repositório do autor: [https://github.com/jmsalles](https://github.com/jmsalles)
* Módulos Ansible: `package`, `apt`, `dnf`, `yum`, `zypper`, `pacman`.

---

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles](https://github.com/jmsalles)
