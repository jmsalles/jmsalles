# SELinux — AWX (modificação **permanente**)

## 🧭 Resumo

Guia **exclusivo para AWX/Tower**: aplica **permanentemente** o modo do SELinux (**enforcing**, **permissive** ou **disabled**) via **templates** e **playbook**. Sem `setenforce` (temporário). Inclui **Survey** para escolher o modo e **reboot automático** para efetivar a alteração.

---

## 📑 Sumário

* [Visão geral (modos)](#visão-geral-modos)
* [Estrutura do projeto (AWX/Ansible)](#estrutura-do-projeto-awxansible)
* [Templates (`/etc/selinux/config`)](#templates-etcselinuxconfig)
* [Playbook (aplicação permanente)](#playbook-aplicação-permanente)
* [Configuração no AWX/Tower](#configuração-no-awxtower)
* [Execução e critérios de reboot](#execução-e-critérios-de-reboot)
* [Validação pós-job (opcional)](#validação-pós-job-opcional)
* [Assinatura](#assinatura)

---

## Visão geral (modos)

| Modo       | Comportamento                             | Observação                            |
| ---------- | ----------------------------------------- | ------------------------------------- |
| enforcing  | Aplica políticas e **bloqueia** violações | Recomendado em produção               |
| permissive | **Não bloqueia**, apenas **loga**         | Útil para investigar AVCs             |
| disabled   | SELinux **desligado**                     | Exige **reboot**; relabel ao reativar |

> **Permanente** = editar `/etc/selinux/config` **e** reiniciar quando necessário.

---

## Estrutura do projeto (AWX/Ansible)

```bash
├── playbooks/
│   └── os_selinux.yml
└── templates/
    ├── selinux_enforcing.j2
    ├── selinux_permissive.j2
    └── selinux_disabled.j2
```

Crie/edite os arquivos no **repositório Git** consumido pelo **Projeto** do AWX.

---

## Templates (`/etc/selinux/config`)

**templates/selinux\_enforcing.j2**

```bash
# /etc/selinux/config — ENFORCING
SELINUX=enforcing
SELINUXTYPE=targeted
SETLOCALDEFS=0
```

**templates/selinux\_permissive.j2**

```bash
# /etc/selinux/config — PERMISSIVE
SELINUX=permissive
SELINUXTYPE=targeted
SETLOCALDEFS=0
```

**templates/selinux\_disabled.j2**

```bash
# /etc/selinux/config — DISABLED
SELINUX=disabled
SELINUXTYPE=targeted
SETLOCALDEFS=0
```

> Ajuste `SELINUXTYPE` (ex.: `mls`) se sua política exigir.

---

## Playbook (aplicação permanente)

**playbooks/os\_selinux.yml**

```bash
---
- name: SELinux — aplicar modo permanente via template
  hosts: all
  become: true
  vars:
    selinux_mode: "enforcing"   # enforcing|permissive|disabled (sobreposto pelo Survey)
    reboot_when_needed: true    # padrão true para efetivar a mudança

  pre_tasks:
    - name: Obter modo atual (getenforce)
      command: getenforce
      register: getenforce_out
      changed_when: false
      failed_when: false

    - name: Normalizar modo atual
      set_fact:
        current_mode: "{{ (getenforce_out.stdout | default('Unknown')) | title }}"  # Enforcing/Permissive/Disabled/Unknown

  tasks:
    - name: Validar parâmetro selinux_mode
      assert:
        that: selinux_mode in ['enforcing', 'permissive', 'disabled']
        fail_msg: "selinux_mode deve ser enforcing|permissive|disabled"

    - name: Aplicar template permanente
      ansible.builtin.template:
        src: "selinux_{{ selinux_mode }}.j2"
        dest: "/etc/selinux/config"
        owner: root
        group: root
        mode: '0644'

    - name: Marcar relabel se reativando (Disabled -> ativo)
      ansible.builtin.file:
        path: /.autorelabel
        state: touch
      when:
        - selinux_mode in ['enforcing', 'permissive']
        - current_mode == 'Disabled'

    - name: Reboot para efetivar configuração
      ansible.builtin.reboot:
        msg: "Reboot automático — aplicar SELinux {{ selinux_mode }}"
        connect_timeout: 60
        reboot_timeout: 1800
        pre_reboot_delay: 0
        post_reboot_delay: 15
        test_command: /usr/bin/true
      when:
        - reboot_when_needed | bool
        - selinux_mode != (current_mode | lower) or current_mode == 'Disabled'
```

---

## Configuração no AWX/Tower

### 1) Projeto, Inventário e Credenciais

* **Project**: aponte para o repositório Git que contém `playbooks/os_selinux.yml` e `templates/`.
* **Inventory**: selecione o inventário (ex.: `inv-lab`).
* **Credential (Machine)**: usuário SSH com `sudo`. Em *Privilege Escalation*, selecione `sudo` se necessário.

### 2) Criar o Job Template

1. Acesse **Templates → Add → Add job template**.
2. Preencha os campos principais:

   * **Name**: `OS_Selinux` (ou outro padrão interno).
   * **Job Type**: `Run`.
   * **Inventory**: `inv-lab` (exemplo).
   * **Project**: `proj-awx-project` (exemplo).
   * **Playbook**: `playbooks/os_selinux.yml`.
   * **Credentials**: escolha a credencial SSH com `sudo`.
   * **Options**: habilite **Privilege Escalation** se aplicável.
3. Clique em **Save** para habilitar a aba **Survey** (obrigatório salvar ao menos uma vez).

### 3) Survey — passo a passo (UI)

1. Abra o **Job Template** recém-salvo e clique na aba **Survey**.
2. Clique em **Add** e crie a **Pergunta 1** (Modo do SELinux):

   * **Question Name**: `Modo do SELinux`
   * **Description**: `Escolha o modo permanente para /etc/selinux/config`
   * **Answer Variable Name**: `selinux_mode`
   * **Answer Type**: `Multiple Choice (single select)`
   * **Choices** (uma por linha):

     ```bash
     enforcing
     permissive
     disabled
     ```
   * **Default Answer**: `enforcing`
   * **Required**: `Yes`
   * **Min/Max**: deixe em branco.
   * **New Question** → **Save**.
3. Clique em **Add** e crie a **Pergunta 2** (Reboot automático):

   * **Question Name**: `Reboot automático`
   * **Description**: `Reiniciar o host para efetivar a alteração?`
   * **Answer Variable Name**: `reboot_when_needed`
   * **Answer Type**: `Multiple Choice (single select)`
   * **Choices**:

     ```bash
     true
     false
     ```
   * **Default Answer**: `true`
   * **Required**: `Yes`
   * **New Question** → **Save**.
4. Ative o **Enable Survey** e clique em **Save** no topo da aba Survey.

#### Observações importantes sobre Survey

* O Survey injeta respostas como **`extra_vars`** na execução, **sobrepondo** os `vars` definidos no playbook.
* Não é necessário marcar **Prompt on launch** em *Variables* do template.
* Utilize **validation** apenas se quiser limitar formatos de entrada (não necessário para múltipla escolha).

### 4) Validação do Survey em execução

1. Clique em **Launch** no Job Template.
2. Responda ao Survey:

   * `Modo do SELinux`: escolha `enforcing`, `permissive` ou `disabled`.
   * `Reboot automático`: deixe `true` para aplicação imediata.
3. Após iniciar, acesse **Jobs → (seu job)**:

   * Em **Details → Variables**, confirme que `selinux_mode` e `reboot_when_needed` aparecem em `extra_vars`.
   * Verifique o **stdout**: deve mostrar a aplicação do template correto e o reboot quando aplicável.

## Execução e critérios de reboot

* Mudanças **para `disabled`**: sempre **reboot**.
* Mudanças **de `disabled` → (`enforcing`/`permissive`)**: cria `/.autorelabel` e **reboot obrigatório**.
* Mudanças entre **`enforcing` ↔ `permissive`**: o arquivo é atualizado; para refletir o novo modo em runtime e torná-lo efetivo no boot seguinte, **reboot recomendado** (automatizado pelo playbook quando `reboot_when_needed=true`).

---

## Validação pós-job (opcional)

> Opcionalmente, adicione um *Job* separado (ou *post tasks*) que verifique o estado após o reboot.

```bash
getenforce
sestatus | egrep 'SELinux status|Current mode'
cat /etc/selinux/config | egrep '^SELINUX='
```

---

## Assinatura

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles](https://github.com/jmsalles)
