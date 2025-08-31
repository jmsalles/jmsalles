aqui está o `.md` prontinho — e também deixei um arquivo para baixar:

[Download o Markdown](sandbox:/mnt/data/guia-bind9.md)

---

# 📘 Tutorial Definitivo — **BIND 9** no Rocky Linux (VM **192.168.31.35**) para **jmsalles.homelab.br**

> 🎯 Objetivo: Servir **DNS autoritativo** para `jmsalles.homelab.br` + **recursivo com cache** para os demais domínios, com foco em **desempenho**, **segurança** e **zero conflito** com o Podman (`aardvark-dns`).

---

## 🧭 Cenário

* 🖥️ **Servidor/VM**: Rocky Linux — IP **192.168.31.35**
* 🌐 **Domínio interno**: `jmsalles.homelab.br`
* 🔁 **Zona reversa**: `31.168.192.in-addr.arpa` (para a rede `192.168.31.0/24`)
* 📦 **Podman presente**: usa `aardvark-dns` ouvindo em `10.89.0.1:53` (normal)

💡 **Estratégia anti-conflito**: o BIND vai **escutar apenas** em `127.0.0.1` e em `192.168.31.35`. Assim convivem sem briga.

---

## 🧰 Passo 0 — Pré-requisitos

```bash
sudo dnf -y install bind bind-utils firewalld
sudo systemctl enable --now firewalld
```

🔎 Conferir portas (só para referência):

```bash
sudo ss -lunpt | egrep '(:53) ' || echo "Porta 53 livre"
```

Ver `aardvark-dns` em `10.89.0.1:53` é **ok**.

---

## ⚙️ Passo 1 — `named.conf` (config principal)

Edite **/etc/named.conf** e substitua pelo conteúdo abaixo:

```conf
include "/etc/rndc.key";

options {
    directory "/var/named";

    // 🔊 Escuta só no IP da VM e no loopback
    listen-on port 53 { 127.0.0.1; 192.168.31.35; };
    listen-on-v6 { none; };

    // 🔒 Política de consulta e recursão (somente sua LAN)
    allow-query       { 127.0.0.1; 192.168.31.0/24; };
    recursion yes;
    allow-recursion   { 127.0.0.1; 192.168.31.0/24; };

    // 🚀 Desempenho do resolvedor
    forwarders { 1.1.1.1; 1.0.0.1; 8.8.8.8; };
    minimal-responses yes;
    max-cache-size 256M;
    max-cache-ttl 3600;   // até 1h
    max-ncache-ttl 300;   // NXDOMAIN até 5m
    edns-udp-size 1232;   // evita fragmentação comum em MTU 1500

    // 🔐 DNSSEC
    dnssec-validation auto;
    auth-nxdomain no;     // RFC 2308

    // 📝 Logs (ative só para debug)
    // querylog yes;
};

controls {
    inet 127.0.0.1 port 953 allow { 127.0.0.1; } keys { "rndc-key"; };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "jmsalles.homelab.br" IN {
    type master;
    file "db.jmsalles.homelab.br";
    allow-update { none; };
    allow-transfer { none; };
    notify no;
};

zone "31.168.192.in-addr.arpa" IN {
    type master;
    file "db.31.168.192.in-addr.arpa";
    allow-update { none; };
    allow-transfer { none; };
    notify no;
};
```

> ✅ Esse `listen-on` evita conflito com o `aardvark-dns` do Podman.

---

## 🗂️ Passo 2 — Zonas (arquivos em `/var/named/`)

**Regra de ouro**: sempre incremente o **serial** (formato `AAAAMMDDNN`) quando editar.

### `/var/named/db.jmsalles.homelab.br`

```dns
$ORIGIN jmsalles.homelab.br.
$TTL 1h
@   IN SOA ns1.jmsalles.homelab.br. admin.jmsalles.homelab.br. (
        2025082901 ; serial
        1h         ; refresh
        15m        ; retry
        1w         ; expire
        1h )       ; minimum

    IN NS ns1.jmsalles.homelab.br.

; Servidor DNS (esta VM)
ns1                 IN A 192.168.31.35

; Hosts
ap-xioami-principal IN A 192.168.31.1
roteador            IN A 192.168.31.2
dvr                 IN A 192.168.31.3
vmware              IN A 192.168.31.11
notebook-qintess    IN A 192.168.31.29
am-pm               IN A 192.168.31.30
lenovo-i7           IN A 192.168.31.31
lenovo-server-linux IN A 192.168.31.31
vm-lenovoi7-openshift-crc IN A 192.168.31.33
openshifit          IN A 192.168.31.33
vm-lenovoi7-zabbix  IN A 192.168.31.35
zabbix              IN A 192.168.31.35
ap-ana              IN A 192.168.31.51
ap-escritorio       IN A 192.168.31.126
ap-mae              IN A 192.168.31.153
```

### `/var/named/db.31.168.192.in-addr.arpa`

```dns
$ORIGIN 31.168.192.in-addr.arpa.
$TTL 1h
@   IN SOA ns1.jmsalles.homelab.br. admin.jmsalles.homelab.br. (
        2025082901 ; serial
        1h
        15m
        1w
        1h )

    IN NS ns1.jmsalles.homelab.br.

1   IN PTR ap-xioami-principal.jmsalles.homelab.br.
2   IN PTR roteador.jmsalles.homelab.br.
3   IN PTR dvr.jmsalles.homelab.br.
11  IN PTR vmware.jmsalles.homelab.br.
29  IN PTR notebook-qintess.jmsalles.homelab.br.
30  IN PTR am-pm.jmsalles.homelab.br.
31  IN PTR lenovo-i7.jmsalles.homelab.br.           ; canônico do .31
33  IN PTR vm-lenovoi7-openshift-crc.jmsalles.homelab.br.
35  IN PTR ns1.jmsalles.homelab.br.                 ; canônico do .35
51  IN PTR ap-ana.jmsalles.homelab.br.
126 IN PTR ap-escritorio.jmsalles.homelab.br.
153 IN PTR ap-mae.jmsalles.homelab.br.
```

> 📌 Mantidas as grafias originais (ex.: `ap-xioami-principal`, `openshifit`). No PTR escolhemos **um nome canônico por IP**.

---

## 🔐 Passo 3 — Permissões e SELinux

```bash
sudo chown root:named /var/named/db.jmsalles.homelab.br /var/named/db.31.168.192.in-addr.arpa
sudo chmod 640 /var/named/db.jmsalles.homelab.br /var/named/db.31.168.192.in-addr.arpa
sudo restorecon -Rv /var/named
```

---

## 🧪 Passo 4 — Validar config e zonas

```bash
sudo named-checkconf -z
sudo named-checkzone jmsalles.homelab.br /var/named/db.jmsalles.homelab.br
sudo named-checkzone 31.168.192.in-addr.arpa /var/named/db.31.168.192.in-addr.arpa
```

---

## ▶️ Passo 5 — Subir o serviço e abrir firewall

```bash
sudo systemctl enable --now named
sudo systemctl restart named
sudo systemctl status named --no-pager -l

sudo firewall-cmd --add-service=dns --permanent
sudo firewall-cmd --reload
```

🔎 Ver escuta nas portas:

```bash
sudo ss -lunpt | egrep 'named|:53 '
```

Você deve ver **named** ouvindo em `127.0.0.1:53` e `192.168.31.35:53`. Ver também `10.89.0.1:53` (aardvark-dns) é **esperado**.

---

## 🧪 Passo 6 — Testes práticos

```bash
# Autoritativo (forward)
dig @192.168.31.35 vmware.jmsalles.homelab.br +short

# Reverso
dig @192.168.31.35 -x 192.168.31.11 +short

# Recursivo + cache
dig @192.168.31.35 cloudflare.com +stats
```

📜 Logs em tempo real:

```bash
sudo journalctl -u named -f -n 100
```

---

## 📡 Passo 7 — Fazer a rede usar este DNS

**Roteador/DHCP** (recomendado): definir **DNS primário = 192.168.31.35** e, opcionalmente, secundário externo (ex.: `1.1.1.1`).

**Hosts individuais (NetworkManager no Rocky):**

```bash
nmcli con mod "Wired connection 1" ipv4.dns "192.168.31.35 1.1.1.1"
nmcli con mod "Wired connection 1" ipv4.dns-search "jmsalles.homelab.br"
nmcli con mod "Wired connection 1" ipv4.ignore-auto-dns yes
nmcli con up "Wired connection 1"
```

---

## 📈 Passo 8 — Dicas de desempenho (BIND)

* ⚡ `minimal-responses yes;` → pacotes menores = menos latência
* 🧠 `max-cache-size 256M;` (ajuste conforme RAM)
* ⏱️ `max-cache-ttl 3600;` e `max-ncache-ttl 300;`
* 🧱 Limite recursão à sua LAN (já feito)
* ✍️ Evite `querylog` permanente (alto I/O)

> Opcional (se suportado pelo seu pacote): **RRL** (Response Rate Limiting) para mitigar abusos:

```conf
rate-limit { responses-per-second 20; window 5; };
```

Coloque dentro de `options { ... }`.

---

## 🧯 Troubleshooting

* ❌ **connection refused**: serviço parado, erro no `listen-on`, ou firewall. Ver:

  ```bash
  sudo systemctl status named --no-pager -l
  sudo ss -lunpt | egrep 'named|:53 '
  sudo firewall-cmd --list-services | grep dns || echo "DNS não liberado"
  ```
* 🔒 **SELinux**: rode `restorecon -Rv /var/named` após criar/editar arquivos.
* 📄 **Erros de zona**: revise `serial`, `$ORIGIN`, `NS` e **ponto final** em FQDNs.
* ♻️ **Aplicar mudanças**: `sudo rndc reload` ou `sudo systemctl reload named` (e **lembre do serial**!).
* 🧩 **Podman**: `aardvark-dns` em `10.89.0.1:53` é normal; nosso `listen-on` evita conflito.

---

## 🛠️ (Opcional) Script único de instalação/configuração

> Cole tudo abaixo em um arquivo, ex.: `setup-bind.sh`, depois execute `sudo bash setup-bind.sh`.

```bash
#!/usr/bin/env bash
set -euo pipefail

SRV_IP=192.168.31.35
SERIAL=2025082901

sudo dnf -y install bind bind-utils firewalld
sudo systemctl enable --now firewalld

sudo tee /etc/named.conf >/dev/null <<CONF
include "/etc/rndc.key";
options {
    directory "/var/named";
    listen-on port 53 { 127.0.0.1; ${SRV_IP}; };
    listen-on-v6 { none; };
    allow-query       { 127.0.0.1; 192.168.31.0/24; };
    recursion yes;
    allow-recursion   { 127.0.0.1; 192.168.31.0/24; };
    forwarders { 1.1.1.1; 1.0.0.1; 8.8.8.8; };
    minimal-responses yes;
    max-cache-size 256M;
    max-cache-ttl 3600;
    max-ncache-ttl 300;
    edns-udp-size 1232;
    dnssec-validation auto;
    auth-nxdomain no;
};
controls {
    inet 127.0.0.1 port 953 allow { 127.0.0.1; } keys { "rndc-key"; };
};
zone "." IN { type hint; file "named.ca"; };
zone "jmsalles.homelab.br" IN { type master; file "db.jmsalles.homelab.br"; allow-update { none; }; allow-transfer { none; }; notify no; };
zone "31.168.192.in-addr.arpa" IN { type master; file "db.31.168.192.in-addr.arpa"; allow-update { none; }; allow-transfer { none; }; notify no; };
CONF

sudo tee /var/named/db.jmsalles.homelab.br >/dev/null <<Z1
$ORIGIN jmsalles.homelab.br.
$TTL 1h
@   IN SOA ns1.jmsalles.homelab.br. admin.jmsalles.homelab.br. (
        ${SERIAL}
        1h 15m 1w 1h )
    IN NS ns1.jmsalles.homelab.br.
ns1                 IN A ${SRV_IP}
ap-xioami-principal IN A 192.168.31.1
roteador            IN A 192.168.31.2
dvr                 IN A 192.168.31.3
vmware              IN A 192.168.31.11
notebook-qintess    IN A 192.168.31.29
am-pm               IN A 192.168.31.30
lenovo-i7           IN A 192.168.31.31
lenovo-server-linux IN A 192.168.31.31
vm-lenovoi7-openshift-crc IN A 192.168.31.33
openshifit          IN A 192.168.31.33
vm-lenovoi7-zabbix  IN A 192.168.31.35
zabbix              IN A 192.168.31.35
ap-ana              IN A 192.168.31.51
ap-escritorio       IN A 192.168.31.126
ap-mae              IN A 192.168.31.153
Z1

sudo tee /var/named/db.31.168.192.in-addr.arpa >/dev/null <<Z2
$ORIGIN 31.168.192.in-addr.arpa.
$TTL 1h
@   IN SOA ns1.jmsalles.homelab.br. admin.jmsalles.homelab.br. (
        ${SERIAL}
        1h 15m 1w 1h )
    IN NS ns1.jmsalles.homelab.br.
1   IN PTR ap-xioami-principal.jmsalles.homelab.br.
2   IN PTR roteador.jmsalles.homelab.br.
3   IN PTR dvr.jmsalles.homelab.br.
11  IN PTR vmware.jmsalles.homelab.br.
29  IN PTR notebook-qintess.jmsalles.homelab.br.
30  IN PTR am-pm.jmsalles.homelab.br.
31  IN PTR lenovo-i7.jmsalles.homelab.br.
33  IN PTR vm-lenovoi7-openshift-crc.jmsalles.homelab.br.
35  IN PTR ns1.jmsalles.homelab.br.
51  IN PTR ap-ana.jmsalles.homelab.br.
126 IN PTR ap-escritorio.jmsalles.homelab.br.
153 IN PTR ap-mae.jmsalles.homelab.br.
Z2

sudo chown root:named /var/named/db.jmsalles.homelab.br /var/named/db.31.168.192.in-addr.arpa
sudo chmod 640 /var/named/db.jmsalles.homelab.br /var/named/db.31.168.192.in-addr.arpa
sudo restorecon -Rv /var/named

sudo named-checkconf -z
sudo named-checkzone jmsalles.homelab.br /var/named/db.jmsalles.homelab.br
sudo named-checkzone 31.168.192.in-addr.arpa /var/named/db.31.168.192.in-addr.arpa

sudo systemctl enable --now named
sudo firewall-cmd --add-service=dns --permanent
sudo firewall-cmd --reload

echo "\n>>> Verificando portas:"
sudo ss -lunpt | egrep 'named|:53 ' || true

echo "\n>>> Testes:"
dig @${SRV_IP} vmware.jmsalles.homelab.br +short || true
dig @${SRV_IP} -x 192.168.31.11 +short || true
dig @${SRV_IP} cloudflare.com +stats || true
```

---

## ✅ Checklist final

* [ ] `named` ativo ouvindo em **127.0.0.1:53** e **192.168.31.35:53**
* [ ] Zonas direta/reversa criadas e **serial** atualizado
* [ ] Firewall liberado para **dns**
* [ ] Roteador/hosts usando **192.168.31.35** como DNS
* [ ] `dig` responde rápido para locais e externos (cache funcionando)

---

Pronto! 🚀 Quer que eu ajuste o **serial** para a data de hoje e inclua mais registros (CNAME/MX/AAAA)?
