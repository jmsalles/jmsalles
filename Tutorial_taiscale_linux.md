Show, Jeferson 👊
Vou refazer o **tutorial unificado** incluindo o cenário completo: instalação do Tailscale no **servidor Rocky Linux 10** (que vai anunciar a rede 192.168.31.0/24) e configuração correta dos **clientes** para aceitarem e usarem essa rede compartilhada.

---

# 🚀 Tutorial Completo: Tailscale Subnet Router + Clientes (Rocky Linux 10)

## 🔹 1. Instalação do Tailscale no Servidor (Rocky 10)

Adicione o repositório oficial compatível:

```bash
sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/rhel/9/tailscale.repo
```

Instale o pacote:

```bash
sudo dnf install tailscale -y
```

Ative o serviço:

```bash
sudo systemctl enable --now tailscaled
```

---

## 🔹 2. Ativar IP Forwarding no Servidor

Edite o arquivo de configuração:

```bash
sudo vim /etc/sysctl.conf
```

Adicione:

```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

Aplicar imediatamente:

```bash
sudo sysctl -p
```

---

## 🔹 3. Otimização de rede (UDP GRO)

Descubra sua interface de rede:

```bash
ip a
```

Ative GRO (exemplo com `enp0s31f6`):

```bash
sudo ethtool -K enp0s31f6 gro on
```

Para persistir:

```bash
sudo mkdir -p /etc/systemd/system/tailscaled.service.d
sudo vim /etc/systemd/system/tailscaled.service.d/override.conf
```

Conteúdo:

```
[Service]
ExecStartPost=/usr/sbin/ethtool -K enp0s31f6 gro on
```

Recarregue:

```bash
sudo systemctl daemon-reexec
sudo systemctl restart tailscaled
```

---

## 🔹 4. Configurar o Servidor como Subnet Router

Anuncie a rota local:

```bash
sudo tailscale up --advertise-routes=192.168.31.0/24
```

Será exibido um link → abra no navegador, faça login e autorize.

---

## 🔹 5. Habilitar a Rota no Admin Console

1. Acesse [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. Localize o servidor `lenovo-server-linux`.
3. Ative ✅ a rota `192.168.31.0/24`.

---

## 🔹 6. Configuração dos Clientes (para aceitar rotas)

Por padrão os clientes **não aceitam** rotas anunciadas. É necessário habilitar:

```bash
sudo tailscale up --accept-routes
```

Isso ajusta o state do Tailscale e persiste em `/var/lib/tailscale/tailscaled.state`.

### 🔧 Tornar permanente

No Rocky (ou qualquer distro systemd), crie um drop-in:

```bash
sudo mkdir -p /etc/systemd/system/tailscaled.service.d
sudo vim /etc/systemd/system/tailscaled.service.d/10-up.conf
```

Conteúdo:

```
[Service]
ExecStartPost=/usr/bin/tailscale up --accept-routes
```

Recarregue:

```bash
sudo systemctl daemon-reload
sudo systemctl restart tailscaled
```

---

## 🔹 7. Testar Conectividade

No **cliente**:

* Verificar se a rota está ativa:

```bash
tailscale status
```

Deve aparecer:

```
192.168.31.0/24 via lenovo-server-linux
```

* Testar ping para um host da LAN:

```bash
ping 192.168.31.2
```

---

## 🔹 8. (Opcional) Exit Node

Se quiser que o servidor seja também saída para a internet:

```bash
sudo tailscale up --advertise-exit-node --advertise-routes=192.168.31.0/24
```

No Admin Console habilite **Use as Exit Node**.
Nos clientes, escolha esse exit node com:

```bash
sudo tailscale up --accept-routes --exit-node=<IP_TAILSCALE_DO_SERVIDOR>
```

---

# ✅ Resumo

* **Servidor Rocky 10**: instalar Tailscale, ativar IP forwarding, otimizar GRO, anunciar rota.
* **Painel Admin**: habilitar a rota.
* **Clientes**: rodar `tailscale up --accept-routes` (ou configurar drop-in para persistir).
* **Teste**: pingar hosts internos da LAN `192.168.31.0/24`.
* **Opcional**: configurar Exit Node para sair para a internet via servidor.

---

👉 Quer que eu te entregue também um **playbook Ansible** para instalar e configurar tanto o servidor (com `--advertise-routes`) quanto os clientes (com `--accept-routes`) em um clique?
