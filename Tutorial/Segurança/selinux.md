# 🛡️ Guia SELinux — Desabilitar, Ajustar e Reativar (RHEL / Rocky / Alma / Oracle Linux)

> 🧭 **Resumo curto:** mantenha o SELinux **ligado** sempre que possível; use **Permissive** para diagnosticar e ajustar políticas. **Disabled** é último recurso.

---

## 📌 Sumário

* [Visão geral](#visão-geral)
* [Checar o estado atual](#checar-o-estado-atual)
* [Mudar temporariamente (sem reboot)](#mudar-temporariamente-sem-reboot)
* [Desativar de forma permanente](#desativar-de-forma-permanente)

  * [Opção A — Permissive (recomendado)](#opção-a--permissive-recomendado)
  * [Opção B — Disabled (evite em produção)](#opção-b--disabled-evite-em-produção)
  * [Alternativa via parâmetros do kernel (grubby)](#alternativa-via-parâmetros-do-kernel-grubby)
* [Reativar depois (com relabel)](#reativar-depois-com-relabel)
* [Conferir após o reboot](#conferir-após-o-reboot)
* [Manter SELinux ativo: como corrigir sem desabilitar](#manter-selinux-ativo-como-corrigir-sem-desabilitar)
* [FAQ de problemas comuns](#faq-de-problemas-comuns)
* [Checklist de decisão](#checklist-de-decisão)
* [Referências rápidas](#referências-rápidas)

---

## 🧩 Visão geral

Entenda os modos do SELinux e quando usar cada um:

| Modo           | O que faz                                | Uso típico          |
| -------------- | ---------------------------------------- | ------------------- |
| **Enforcing**  | Bloqueia e registra violações            | Produção            |
| **Permissive** | Não bloqueia; **apenas registra** (logs) | Diagnóstico/Ajustes |
| **Disabled**   | Desliga completamente                    | Último recurso      |

> ⚠️ Em ambientes de **containers** e **OpenShift**, o modo **Enforcing** costuma ser requisito de segurança/isolamento.

---

## 🔎 Checar o estado atual

Checar o **modo** atual:

```bash
getenforce
```

Exibir o **status detalhado**:

```bash
sestatus
```

(Opcional) Listar **booleans** ativos rapidamente:

```bash
sestatus -b | head -n 20
```

---

## ♻️ Mudar temporariamente (sem reboot)

Colocar em modo **permissivo** (temporário):

```bash
sudo setenforce 0
```

Voltar para modo **enforcing** (temporário):

```bash
sudo setenforce 1
```

> 💡 Se o SELinux estiver *Disabled*, `setenforce` falhará — é esperado.

---

## 🧰 Desativar de forma permanente

### Opção A — *Permissive* (recomendado)

Editar o arquivo de configuração para permanecer **permissive** após o boot:

```bash
sudo vim /etc/selinux/config
# Ajuste/garanta:
# SELINUX=permissive
# SELINUXTYPE=targeted
```

Validar a edição:

```bash
grep ^SELINUX= /etc/selinux/config
```

Reiniciar para aplicar:

```bash
sudo systemctl reboot
```

---

### Opção B — *Disabled* (evite em produção)

Editar o arquivo de configuração para **desabilitar** completamente:

```bash
sudo vim /etc/selinux/config
# Ajuste/garanta:
# SELINUX=disabled
```

Validar a edição:

```bash
grep ^SELINUX= /etc/selinux/config
```

Reiniciar para aplicar:

```bash
sudo systemctl reboot
```

> 🔒 *Disabled* remove proteções MAC do host e amplia a superfície de ataque.

---

### 🔧 Alternativa via parâmetros do kernel (*grubby*)

Desabilitar o SELinux via argumentos do kernel:

```bash
sudo grubby --update-kernel ALL --args "selinux=0 enforcing=0"
```

Reverter os argumentos do kernel:

```bash
sudo grubby --update-kernel ALL --remove-args "selinux enforcing"
```

Ajustar novamente o `/etc/selinux/config` para o modo desejado:

```bash
sudo vim /etc/selinux/config
```

---

## 🔁 Reativar depois (com relabel)

Definir o modo desejado para **permissive** ou **enforcing** no arquivo:

```bash
sudo vim /etc/selinux/config
# Ex.: SELINUX=permissive  (ou enforcing)
```

Marcar o sistema para **relabel** completo no próximo boot:

```bash
sudo touch /.autorelabel
```

Reiniciar para efetuar o relabel (pode demorar):

```bash
sudo systemctl reboot
```

---

## ✅ Conferir após o reboot

Checar o status do SELinux depois das mudanças:

```bash
sestatus
```

Confirmar o modo atual:

```bash
getenforce
```

---

## 🟢 Manter SELinux ativo: como corrigir sem desabilitar

Encontrar negações recentes (AVC) no audit:

```bash
sudo ausearch -m avc -ts recent
```

Analisar o audit log com **sealert** (se instalado):

```bash
sudo sealert -a /var/log/audit/audit.log
```

Habilitar booleans comuns conforme necessidade:

```bash
# Web → conexões de rede e banco
sudo setsebool -P httpd_can_network_connect on
sudo setsebool -P httpd_can_network_connect_db on

# Samba → homes
sudo setsebool -P samba_enable_home_dirs on

# Virtualização/NFS
sudo setsebool -P virt_use_nfs on

# Containers → gerenciar cgroup
sudo setsebool -P container_manage_cgroup on
```

Restaurar contextos padrão recursivamente:

```bash
sudo restorecon -Rv /caminho
```

Definir contexto persistente e aplicar:

```bash
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/www(/.*)?"
sudo restorecon -Rv /srv/www
```

> 💡 Prefira `semanage fcontext` para persistência; use `chcon` apenas em teste rápido.

---

## 🧪 FAQ de problemas comuns

Aplicação web não conecta ao banco (bloqueio de rede do httpd):

```bash
sudo setsebool -P httpd_can_network_connect_db on
```

Samba não acessa/expõe compartilhamento:

```bash
sudo setsebool -P samba_enable_home_dirs on
sudo semanage fcontext -a -t samba_share_t "/srv/samba(/.*)?"
sudo restorecon -Rv /srv/samba
```

Containers sem acesso a volumes recém-movidos:

```bash
sudo semanage fcontext -a -t container_file_t "/dados/containers(/.*)?"
sudo restorecon -Rv /dados/containers
```

---

## 🧾 Checklist de decisão

Marcar que tentou **permissive** e ajustes antes de desabilitar:

```bash
echo "✓ Tentei Permissive + policies antes de usar Disabled"
```

Planejar janela, rollback e registro de mudanças:

```bash
echo "✓ Janela/rollback definidos e mudanças registradas"
```

Documentar booleans/contextos para manter **enforcing** depois:

```bash
echo "✓ Booleans e fcontext documentados para retorno ao Enforcing"
```

Prever **relabel** completo se usou *Disabled*:

```bash
echo "✓ Relabel planejado para reativar SELinux"
```

---

## 📚 Referências rápidas

Consultar páginas de manual do SELinux e ferramentas:

```bash
man selinux
man semanage
man setsebool
man restorecon
```

Conferir logs e utilitários de auditoria:

```bash
sudo tail -n 200 /var/log/audit/audit.log
sudo ausearch -m avc -ts recent
```

---

Criado por **Jeferson Salles**
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
