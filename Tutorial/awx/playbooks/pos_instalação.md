perfeito—aqui vai um **playbook pós-instalação** no seu **template AWX**, ultra documentado, pensado para **RHEL/Rocky/Alma (DNF)**.
Ele:

* habilita **EPEL** + **dnf-plugins-core**;
* liga **CRB** (Rocky/Alma 9+) ou **PowerTools** (Rocky/Alma 8); em **RHEL**, tenta habilitar o **CodeReady Builder** via `subscription-manager` (sem travar se não estiver registrado);
* instala **cada pacote individualmente** (um a um), **sem abortar** em caso de erro, e no final mostra **sumário** do que falhou;
* instala o **grupo** “Development Tools”;
* habilita e inicia **chronyd**;
* ajusta o **timezone** para `America/Sao_Paulo`;
* inclui guard-rails para **pular** hosts que não usam **DNF**.

Salve como `playbooks/os_pos_instalacao.yml` no seu repositório `awx-project`.

```yaml
---
---
# playbooks/os_pos_instalacao.yml
# Pós-instalação para RHEL/Rocky/Alma (DNF)
# - Repos: EPEL + CRB/PowerTools/CRB-RHEL
# - Instala pacotes essenciais (um a um, sem travar o play se falhar)
# - Instala o grupo "Development Tools"
# - Habilita chronyd e seta timezone America/Sao_Paulo
# - Pula hosts que não usam DNF

- name: Pós-instalação (RHEL/Rocky/Alma) com DNF
  hosts: pos_instalacao
  gather_facts: true
  become: true

  vars:
    # present | latest | absent
    pos_pkg_state: present

    # Lista de pacotes (um a um; se um falhar, seguimos para o próximo)
    pos_pkg_list:
      # Repositórios e utilitários base
      - epel-release
      - dnf-plugins-core

      # Ferramentas essenciais
      - chrony
      - atop
      - ncdu
      - git
      - samba-client
      - nfs-utils
      - cifs-utils
      - vim-enhanced
      - bash-completion
      - man-db
      - man-pages
      - less
      - tree
      - which

      # Compressão/arquivos
      - tar
      - zip
      - unzip
      - bzip2
      - xz
      - pigz
      - p7zip
      - p7zip-plugins

      # Transferência/CA/SSH
      - wget
      - curl
      - rsync
      - openssh-clients
      - ca-certificates

      # Toolchain/dev libs
      - gcc
      - gcc-c++
      - make
      - cmake
      - ninja-build
      - pkgconf
      - pkgconf-pkg-config
      - autoconf
      - automake
      - libtool
      - kernel-headers
      - kernel-devel
      - elfutils-libelf-devel
      - openssl-devel
      - zlib-devel
      - libffi-devel
      - bison
      - flex
      - python3
      - python3-pip

      # Rede e troubleshooting
      - iproute
      - iputils
      - net-tools
      - ethtool
      - nmap-ncat
      - nmap
      - tcpdump
      - traceroute
      - mtr
      - bind-utils
      - socat
      - telnet
      - lsof
      - strace
      - htop
      - iotop
      - perf

      # SELinux/Policy
      - policycoreutils
      - setools-console

  pre_tasks:
    - name: Pular hosts sem gerenciador suportado (só DNF)
      ansible.builtin.meta: end_host
      when: ansible_facts.pkg_mgr != 'dnf'

    - name: Atualizar cache do DNF
      ansible.builtin.dnf:
        update_cache: true

    # Preparar plugins para usar config-manager
    - name: Garantir dnf-plugins-core (para config-manager)
      ansible.builtin.dnf:
        name: dnf-plugins-core
        state: present
      register: dnf_plugins_core
      failed_when: false

    # --- Habilitação de repositórios ---

    - name: Habilitar CRB (Rocky/Alma 9+)
      ansible.builtin.command: dnf -y config-manager --set-enabled crb
      register: crb_set
      changed_when: "'enabled' in ((crb_set.stdout | default('')) + (crb_set.stderr | default('')))"
      failed_when: false
      when:
        - ansible_facts.distribution in ['Rocky', 'AlmaLinux']
        - (ansible_facts.distribution_major_version | int) >= 9

    - name: Habilitar PowerTools (Rocky/Alma 8)
      ansible.builtin.command: dnf -y config-manager --set-enabled powertools
      register: powertools_set
      changed_when: "'enabled' in ((powertools_set.stdout | default('')) + (powertools_set.stderr | default('')))"
      failed_when: false
      when:
        - ansible_facts.distribution in ['Rocky', 'AlmaLinux']
        - (ansible_facts.distribution_major_version | int) == 8

    - name: Habilitar CodeReady Builder (RHEL) via subscription-manager
      ansible.builtin.command: "subscription-manager repos --enable=codeready-builder-for-rhel-{{ ansible_facts.distribution_major_version }}-{{ ansible_facts.architecture }}-rpms"
      register: crb_rhel_set
      changed_when: "'enabled' in ((crb_rhel_set.stdout | default('')) + (crb_rhel_set.stderr | default('')))"
      failed_when: false
      when: ansible_facts.distribution == 'RedHat'

  tasks:
    - name: Garantir EPEL (epel-release)
      ansible.builtin.dnf:
        name: epel-release
        state: present
      register: epel_res
      failed_when: false

    - name: Atualizar cache do DNF (após repositórios)
      ansible.builtin.dnf:
        update_cache: true

    # --- Instalação de pacotes (um a um) ---
    - name: Instalar pacote individualmente
      ansible.builtin.dnf:
        name: "{{ item }}"
        state: "{{ pos_pkg_state }}"
      loop: "{{ pos_pkg_list }}"
      loop_control:
        label: "{{ item }}"
      register: pos_pkg_install
      ignore_errors: yes

    # Separar sucesso e falha a partir dos resultados do loop
    - name: Computar listas de sucesso/falha
      ansible.builtin.set_fact:
        pos_failed: >-
          {{ (pos_pkg_install.results | selectattr('failed','defined') | selectattr('failed') | map(attribute='item') | list) | default([]) }}
        pos_success: >-
          {{ (pos_pkg_install.results | rejectattr('failed','defined') | map(attribute='item') | list) | default([]) }}

    # --- Grupo "Development Tools" ---
    - name: Instalar grupo "Development Tools"
      ansible.builtin.dnf:
        name: "@Development Tools"
        state: "{{ pos_pkg_state }}"
      register: devtools_result
      failed_when: false

    # --- Timezone e Chrony ---
    - name: Ajustar timezone (timedatectl)
      ansible.builtin.command: timedatectl set-timezone America/Sao_Paulo
      changed_when: false
      failed_when: false

    - name: Habilitar e iniciar chronyd
      ansible.builtin.service:
        name: chronyd
        state: started
        enabled: true
      failed_when: false

  post_tasks:
    - name: Sumário — pacotes que falharam
      ansible.builtin.debug:
        msg: >-
          {{ 'Falharam: ' + (pos_failed | join(', ')) if (pos_failed | length > 0)
             else 'Falharam: nenhum' }}

    - name: Sumário — pacotes instalados/ok (amostra de até 15)
      ansible.builtin.debug:
        msg: >-
          {{ 'Sucesso (até 15): ' + ((pos_success | default([]))[:15] | join(', '))
             if (pos_success | default([]) | length > 0) else 'Sucesso: nenhum' }}

    - name: Status do grupo Development Tools (debug)
      ansible.builtin.debug:
        var: devtools_result
      when: devtools_result is defined

```

### Como colocar no seu repositório

```bash
cd ~/awx-project
git add playbooks/os_pos_instalacao.yml
git commit -m "pos-instalação: EPEL+CRB/PowerTools/CRB-RHEL + pacotes essenciais, devtools, chrony e timezone"
git push
```

### Template no AWX

* **Project:** `proj-awx-project` (faça **Sync** após o push)
* **Inventory:** `inv-lab` (ou via SCM Source `inventory.ini`)
* **Credential:** sua credencial SSH (usuario que tem sudo)
* **Playbook:** `playbooks/os_pos_instalacao.yml`
* **Privilege escalation:** habilitado
* **Prompt on launch (opcional):** habilite **Limit** para canário (`Lenovo-i7` por ex.) e depois rode geral.

### Observações úteis

* Se algum pacote não existir na versão do SO/repos habilitados, ele será listado em **“Falharam”**, mas **o play continua**.
* **CRC/CoreOS** ou hosts sem DNF serão **auto-pulados** (pre\_tasks).
* Em **RHEL** sem `subscription-manager` registrado, a ativação do CodeReady vai **ignorar o erro** (não quebra o play).
* Se quiser forçar “sempre a última versão”, rode com `-e pos_pkg_state=latest` (ou defina via **Variables** no Template).

Se quiser, eu adiciono um **Survey** no Template para você escolher `present/latest` e ativar/desativar a instalação do grupo “Development Tools” em runtime.
