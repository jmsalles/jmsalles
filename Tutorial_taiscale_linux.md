Perfeito, Jeferson! 👊
Vou montar um **tutorial unificado** para transformar seu **Rocky Linux 10** em um **roteador de sub-rede Tailscale** para a rede `192.168.31.0/24`, incluindo os ajustes de forwarding e performance.

---

# 🚀 Tutorial: Configurando Tailscale como Subnet Router no Rocky Linux 10

## 🔹 1. Instalar o Tailscale

Adicione o repositório compatível com Rocky 10 (base RHEL 9):

```bash
sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/rhel/9/tailscale.repo
```

Atualize e instale:

```bash
sudo dnf install tailscale -y
```

Ative o serviço:

```bash
sudo systemctl enable --now tailscaled
```

---

## 🔹 2. Habilitar IP Forwarding (IPv4 e IPv6)

Edite o arquivo `sysctl.conf`:

```bash
sudo vim /etc/sysctl.conf
```

Adicione as linhas:

```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

Aplique sem reboot:

```bash
sudo sysctl -p
```

Valide:

```bash
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
```

Deve retornar `1` nos dois.

---

## 🔹 3. Corrigir Performance de UDP (GRO)

Verifique sua interface de rede (geralmente `enp0s31f6`):

```bash
ip a
```

Ative GRO:

```bash
sudo ethtool -K enp0s31f6 gro on
```

Para persistir após reboot, crie o override do systemd:

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

## 🔹 4. Configurar o Tailscale para anunciar a rede local

Execute:

```bash
sudo tailscale up --advertise-routes=192.168.31.0/24
```

Será exibida uma URL — copie e abra no navegador para autenticar com sua conta Tailscale.

---

## 🔹 5. Autorizar a rota no Painel Admin

1. Acesse: [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)
2. Ache seu servidor.
3. Clique em **Enable Subnet Routes** para `192.168.31.0/24`.

---

## 🔹 6. Testar Conectividade

De uma máquina cliente Tailscale:

```bash
tailscale ip
tailscale status
ping 192.168.31.1
ping 192.168.31.99
```

Se responder, a rede local está roteando corretamente pela VPN. 🎉

---

## 🔹 7. (Opcional) Tornar Exit Node

Se quiser que **todo o tráfego da internet saia pelo Rocky**, adicione ao comando `tailscale up`:

```bash
sudo tailscale up --advertise-exit-node --advertise-routes=192.168.31.0/24
```

Depois, habilite no Admin Console a opção **Use as Exit Node**.

---

# ✅ Resumo

1. Instalação via repositório `rhel/9`.
2. Habilitar IPv4/IPv6 forwarding.
3. Ajustar GRO para performance.
4. Anunciar rota `192.168.31.0/24`.
5. Autorizar rota no painel Tailscale.
6. Testar acesso à rede local.
7. (Opcional) Usar como exit node.

---

👉 Quer que eu já gere também um **playbook Ansible** para automatizar todos esses passos e replicar em outros servidores Rocky que você tiver?
