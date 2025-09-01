# 📘 Procedimento Padrão – Monitoramento de Saída por Link (RSL × TSCM) + Velocidade

**Plataforma:** Rocky Linux 10 • **Coletor/Zabbix agent:** `vm-lenovoi7-zabbix (192.168.31.35)` • **Zabbix:** 7.4 • **Agendamento:** CRON

---

## 🧭 Visão geral

* **Coleta**: lê IP público → classifica **RSL/TSCM** por faixa → mede **Download** (v1) ou **Download+Upload** (v2) com **Ookla CLI** (`/usr/bin/speedtest`, servidor **61444 – Nova Iguaçu**) → envia chaves *trapper* → *calculated* formam “Proporção 100”.
* **Agendamento**: CRON com janelas:

  * **07:00–17:59** → a **cada 5 min**
  * **18:00–06:59** → a **cada 2 min**
* **Zabbix**: 4 itens *trapper* (v1) + **2 trapper extras** (upload, p/ v2), 2 *calculated*, **Graphs (classic)** e widgets no dashboard.

---

## 0) Pré-requisitos no coletor

```bash
sudo dnf -y install curl bind-utils jq zabbix-sender cronie
sudo systemctl enable --now crond
```

---

## 1) Instalar a **Ookla CLI** (repo EL9 compatível com Rocky 10)

```bash
sudo tee /etc/yum.repos.d/ookla-speedtest.repo >/dev/null <<'EOF'
[ookla-speedtest]
name=Ookla Speedtest for EL9 (compat on Rocky 10)
baseurl=https://packagecloud.io/ookla/speedtest-cli/el/9/$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/ookla/speedtest-cli/gpgkey
sslverify=1

[ookla-speedtest-source]
name=Ookla Speedtest - Source (EL9)
baseurl=https://packagecloud.io/ookla/speedtest-cli/el/9/SRPMS
repo_gpgcheck=1
gpgcheck=0
enabled=0
gpgkey=https://packagecloud.io/ookla/speedtest-cli/gpgkey
sslverify=1
EOF

sudo dnf makecache
sudo dnf -y install speedtest

# sanity
/usr/bin/speedtest --accept-license --accept-gdpr -V
/usr/bin/speedtest --accept-license --accept-gdpr -L | head
```

---

## 2) Scripts de coleta

### 2.1 **v1** — seu script atual (Download)

> Colado abaixo **completo**, apenas acrescentei a 1ª linha `#!/usr/bin/env bash` (shebang) para execução correta via cron/systemd. O restante está **idêntico** ao que você enviou.

```bash
sudo tee /usr/local/bin/monitor_link_v1.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u -o pipefail   # (sem -e para não matar o serviço por qualquer retorno !=0)

# ======= CONFIG =======
ZBX_HOST="${ZBX_HOST:-vm-lenovoi7-zabbix}"
LOGFILE="${LOGFILE:-/var/log/monitor_links.log}"

SPEEDTEST_BIN="/usr/bin/speedtest"
SPEEDTEST_SERVER_ID="${SPEEDTEST_SERVER_ID:-61444}"   # RJ – Nova Iguaçu

TSCM_PREFIXES=("181.191.")
RSL_PREFIXES=("168.121.")

FAST_ONLY=false
[[ "${1:-}" == "--no-speedtest" ]] && FAST_ONLY=true

LOCKFILE="/run/monitor_link.lock"

# ======= FUNÇÕES =======
detect_zbx_server() {
  local cfg val
  for cfg in /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agentd.conf; do
    [[ -f "$cfg" ]] || continue
    val=$(grep -E '^(ServerActive|Server)=' "$cfg" | tail -n1 | cut -d= -f2 | tr -d ' ')
    [[ -n "$val" ]] || continue
    echo "${val%%,*}"
    return 0
  done
  echo "127.0.0.1"
}

get_public_ip() {
  local ip=""
  ip=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
  [[ -z "$ip" ]] && ip=$(dig +short ANY whoami.akamai.net @ns1-1.akamaitech.net || true)
  [[ -z "$ip" ]] && ip=$(curl -s https://ifconfig.me || true)
  echo "$ip"
}

match_prefix(){ local ip="$1"; shift; for p in "$@"; do [[ "$ip" == "$p"* ]] && return 0; done; return 1; }
identify_provider(){
  local ip="$1"
  if match_prefix "$ip" "${TSCM_PREFIXES[@]}"; then echo "TSCM"; return; fi
  if match_prefix "$ip" "${RSL_PREFIXES[@]}";  then echo "RSL";  return; fi
  echo "DESCONHECIDO"
}

TOOL_USED="[ookla:/usr/bin/speedtest]"

run_speedtest_json() {
  # $1 = "fixed" ou "auto"
  if [[ "$1" == "fixed" && -n "$SPEEDTEST_SERVER_ID" ]]; then
    "$SPEEDTEST_BIN" --accept-license --accept-gdpr -f json -s "$SPEEDTEST_SERVER_ID" 2>/dev/null || true
  else
    "$SPEEDTEST_BIN" --accept-license --accept-gdpr -f json 2>/dev/null || true
  fi
}

parse_mbps_from_json() {
  # Entrada: JSON em stdin. Saída: Mbps (string) ou nada se não conseguir.
  local BW_BYTES BYTES ELAPSED
  BW_BYTES=$(jq -r '.download.bandwidth // empty')
  if [[ -n "$BW_BYTES" && "$BW_BYTES" != "null" && "$BW_BYTES" != "0" ]]; then
    awk -v b="$BW_BYTES" 'BEGIN {printf "%.2f", (b*8)/1000000}'
    return 0
  fi
  BYTES=$(jq -r '.download.bytes // empty')
  ELAPSED=$(jq -r '.download.elapsed // empty')
  if [[ -n "$BYTES" && -n "$ELAPSED" && "$BYTES" != "null" && "$ELAPSED" != "null" && "$ELAPSED" != "0" ]]; then
    awk -v bytes="$BYTES" -v ms="$ELAPSED" 'BEGIN {printf "%.2f", (bytes*8)/(ms*1000)}'
    return 0
  fi
  return 1
}

get_download_mbps() {
  local JSON MBPS tries mode
  tries=0
  # sequência: fixed -> auto -> fixed (até 3 tentativas)
  for mode in fixed auto fixed; do
    JSON="$(run_speedtest_json "$mode")"
    MBPS="$(echo "$JSON" | parse_mbps_from_json || true)"
    if [[ -n "${MBPS:-}" ]]; then echo "$MBPS"; return 0; fi
    ((tries++))
    sleep 3
  done

  # Dump p/ debug
  {
    echo "==== $(date '+%F %T%z') FAIL JSON ===="
    echo "$JSON"
  } >> /var/log/monitor_links.lastjson 2>/dev/null || true

  echo "0.00"
  return 0
}

# ======= LOCK (não roda concorrente) =======
exec 9>"$LOCKFILE" || true
if ! flock -n 9; then
  # já tem outro rodando, sai sem erro
  exit 0
fi

# ======= FLUXO =======
ZBX_SERVER="${ZBX_SERVER:-$(detect_zbx_server)}"
DATE="$(date '+%Y-%m-%d %H:%M:%S%z')"
IP="$(get_public_ip)"
if [[ -z "$IP" ]]; then
  echo "$DATE | Falha ao obter IP público | Zabbix: $ZBX_SERVER" | tee -a "$LOGFILE"
  exit 0
fi

PROV="$(identify_provider "$IP")"

DL_Mbps="0.00"
if ! $FAST_ONLY; then
  DL_Mbps="$(get_download_mbps)"
fi

echo "$DATE | IP: $IP ($PROV) | Download: ${DL_Mbps} Mbps | Tool:${TOOL_USED} | Zabbix: $ZBX_SERVER" | tee -a "$LOGFILE"

# Envio tolerante (não derruba o serviço se falhar)
case "$PROV" in
  "RSL")
    $FAST_ONLY || zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.speed  -o "$DL_Mbps" >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.count -o 1 >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.count -o 0 >/dev/null 2>&1 || true
    ;;
  "TSCM")
    $FAST_ONLY || zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.speed -o "$DL_Mbps" >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.count -o 1 >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.count  -o 0 >/dev/null 2>&1 || true
    ;;
  *)
    ;;
esac

exit 0
EOF

sudo chmod +x /usr/local/bin/monitor_link_v1.sh
```

> **Opcional**: manter também um atalho “legado” (se algum lugar ainda chama `monitor_link.sh`):

```bash
sudo cp -a /usr/local/bin/monitor_link_v1.sh /usr/local/bin/monitor_link.sh
```

---

### 2.2 **v2** — Download **e** Upload (uma execução só)

```bash
sudo tee /usr/local/bin/monitor_link_v2.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# /usr/local/bin/monitor_link_v2.sh
# Mede Download e Upload (Mbps) com /usr/bin/speedtest e envia via zabbix_sender.
# Robustez: lock, retries (fixed->auto->fixed), fallback de parsing, dump de JSON, zabbix_sender tolerante.

set -u -o pipefail   # (sem -e para não matar por retorno !=0 em zabbix_sender)

# ======= CONFIG =======
ZBX_HOST="${ZBX_HOST:-vm-lenovoi7-zabbix}"
LOGFILE="${LOGFILE:-/var/log/monitor_links.log}"

SPEEDTEST_BIN="/usr/bin/speedtest"
SPEEDTEST_SERVER_ID="${SPEEDTEST_SERVER_ID:-61444}"   # RJ – Nova Iguaçu

# Prefixos por operadora
TSCM_PREFIXES=("181.191.")
RSL_PREFIXES=("168.121.")

# Execução sem speedtest (só contagem)? Use --no-speedtest
FAST_ONLY=false
[[ "${1:-}" == "--no-speedtest" ]] && FAST_ONLY=true

LOCKFILE="/run/monitor_link.lock"
TOOL_USED="[ookla:/usr/bin/speedtest]"

# ======= FUNÇÕES =======
detect_zbx_server() {
  local cfg val
  for cfg in /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agentd.conf; do
    [[ -f "$cfg" ]] || continue
    val=$(grep -E '^(ServerActive|Server)=' "$cfg" | tail -n1 | cut -d= -f2 | tr -d ' ')
    [[ -n "$val" ]] || continue
    echo "${val%%,*}"
    return 0
  done
  echo "127.0.0.1"
}

get_public_ip() {
  local ip=""
  ip=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
  [[ -z "$ip" ]] && ip=$(dig +short ANY whoami.akamai.net @ns1-1.akamaitech.net || true)
  [[ -z "$ip" ]] && ip=$(curl -s https://ifconfig.me || true)
  echo "$ip"
}

match_prefix(){ local ip="$1"; shift; for p in "$@"; do [[ "$ip" == "$p"* ]] && return 0; done; return 1; }
identify_provider(){
  local ip="$1"
  if match_prefix "$ip" "${TSCM_PREFIXES[@]}"; then echo "TSCM"; return; fi
  if match_prefix "$ip" "${RSL_PREFIXES[@]}";  then echo "RSL";  return; fi
  echo "DESCONHECIDO"
}

run_speedtest_json() {
  # $1 = "fixed" ou "auto"
  if [[ "$1" == "fixed" && -n "$SPEEDTEST_SERVER_ID" ]]; then
    "$SPEEDTEST_BIN" --accept-license --accept-gdpr -f json -s "$SPEEDTEST_SERVER_ID" 2>/dev/null || true
  else
    "$SPEEDTEST_BIN" --accept-license --accept-gdpr -f json 2>/dev/null || true
  fi
}

parse_dir_mbps_from_json() {
  # $1 = "download"|"upload"; stdin: JSON
  local DIR="$1" BW BYTES ELAPSED
  BW=$(jq -r ".${DIR}.bandwidth // empty")
  if [[ -n "$BW" && "$BW" != "null" && "$BW" != "0" ]]; then
    awk -v b="$BW" 'BEGIN{printf "%.2f",(b*8)/1000000}'; return 0
  fi
  BYTES=$(jq -r ".${DIR}.bytes // empty")
  ELAPSED=$(jq -r ".${DIR}.elapsed // empty")
  if [[ -n "$BYTES" && -n "$ELAPSED" && "$BYTES" != "null" && "$ELAPSED" != "null" && "$ELAPSED" != "0" ]]; then
    awk -v bytes="$BYTES" -v ms="$ELAPSED" 'BEGIN{printf "%.2f",(bytes*8)/(ms*1000)}'; return 0
  fi
  return 1
}

get_speeds_mbps() {
  # ecoa: "DL UL" (ambos com 2 casas)
  local JSON DL UL mode
  for mode in fixed auto fixed; do
    JSON="$(run_speedtest_json "$mode")"
    DL="$(echo "$JSON" | parse_dir_mbps_from_json download || true)"
    UL="$(echo "$JSON" | parse_dir_mbps_from_json upload   || true)"
    if [[ -n "${DL:-}" || -n "${UL:-}" ]]; then
      [[ -z "${DL:-}" ]] && DL="0.00"
      [[ -z "${UL:-}" ]] && UL="0.00"
      echo "$DL $UL"
      return 0
    fi
    sleep 3
  done
  { echo "==== $(date '+%F %T%z') FAIL JSON ===="; echo "$JSON"; } >> /var/log/monitor_links.lastjson 2>/dev/null || true
  echo "0.00 0.00"
  return 0
}

# ======= LOCK (não roda concorrente) =======
exec 9>"$LOCKFILE" || true
if ! flock -n 9; then
  exit 0
fi

# ======= FLUXO =======
ZBX_SERVER="${ZBX_SERVER:-$(detect_zbx_server)}"
DATE="$(date '+%Y-%m-%d %H:%M:%S%z')"
IP="$(get_public_ip)"
if [[ -z "$IP" ]]; then
  echo "$DATE | Falha ao obter IP público | Zabbix: $ZBX_SERVER" | tee -a "$LOGFILE"
  exit 0
fi

PROV="$(identify_provider "$IP")"

DL_Mbps="0.00"; UL_Mbps="0.00"
if ! $FAST_ONLY; then
  read -r DL_Mbps UL_Mbps < <(get_speeds_mbps)
fi

echo "$DATE | IP: $IP ($PROV) | Download: ${DL_Mbps} Mbps | Upload: ${UL_Mbps} Mbps | Tool:${TOOL_USED} | Zabbix: $ZBX_SERVER" | tee -a "$LOGFILE"

# Envio (somente para o link ativo, igual ao v1)
case "$PROV" in
  "RSL")
    $FAST_ONLY || zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.speed   -o "$DL_Mbps" >/dev/null 2>&1 || true
    $FAST_ONLY || zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.upload  -o "$UL_Mbps" >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.count -o 1 >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.count -o 0 >/dev/null 2>&1 || true
    ;;
  "TSCM")
    $FAST_ONLY || zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.speed  -o "$DL_Mbps" >/dev/null 2>&1 || true
    $FAST_ONLY || zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.upload -o "$UL_Mbps" >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.tscm.count -o 1 >/dev/null 2>&1 || true
    zabbix_sender -z "$ZBX_SERVER" -s "$ZBX_HOST" -k link.rsl.count  -o 0 >/dev/null 2>&1 || true
    ;;
  *)
    ;;
esac

exit 0
EOF

sudo chmod +x /usr/local/bin/monitor_link_v2.sh
```

---

## 3) Agendamento com **CRON**

> (mantém **v1** rodando; mude para v2 quando quiser)

```bash
sudo tee /etc/cron.d/monitor-link >/dev/null <<'EOF'
# Monitorar saída por link com /usr/local/bin/monitor_link_v1.sh
# Janelas:
#  - 07:00–17:59  => a cada 5 min
#  - 18:00–06:59  => a cada 2 min
SHELL=/bin/bash
PATH=/usr/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin
MAILTO=""

# 07:00–17:59 (*/5)
*/5 7-17 * * * root /usr/local/bin/monitor_link_v1.sh >/dev/null 2>&1

# 18:00–06:59 (*/2)
*/2 18-23,0-6 * * * root /usr/local/bin/monitor_link_v1.sh >/dev/null 2>&1
EOF

sudo systemctl reload crond 2>/dev/null || true
```

> **Para trocar para v2**, troque `monitor_link_v1.sh` por `monitor_link_v2.sh` nas duas linhas e recarregue o crond.

---

## 4) Zabbix 7.4 — Itens do host `vm-lenovoi7-zabbix`

### 4.1 **Trapper** (Download + Contagem — usados pelo v1 e v2)

* **RSL - Download Mbps**
  Type: *Zabbix trapper* • Key: `link.rsl.speed` • Info: *Numeric (float)* • Units: `Mbps` • **Allowed hosts:** `192.168.31.35`
* **TSCM - Download Mbps**
  Type: trapper • Key: `link.tscm.speed` • Info: float • Units: `Mbps` • **Allowed hosts:** `192.168.31.35`
* **RSL - Contagem**
  Type: trapper • Key: `link.rsl.count` • Info: *Numeric (unsigned)* • **Allowed hosts:** `192.168.31.35`
* **TSCM - Contagem**
  Type: trapper • Key: `link.tscm.count` • Info: unsigned • **Allowed hosts:** `192.168.31.35`

### 4.2 **Trapper adicionais** (Upload — **para v2**)

* **RSL - Upload Mbps**
  Type: trapper • Key: `link.rsl.upload` • Info: float • Units: `Mbps` • **Allowed hosts:** `192.168.31.35`
* **TSCM - Upload Mbps**
  Type: trapper • Key: `link.tscm.upload` • Info: float • Units: `Mbps` • **Allowed hosts:** `192.168.31.35`

### 4.3 **Calculated** (Proporção — últimas 100)

* **RSL - Últimas 100 medições**
  Type: *Calculated* • Key: `link.rsl.last100` • Update: `60s`
  **Formula:**

  ```
  count(/vm-lenovoi7-zabbix/link.rsl.count,#100,"gt",0)
  ```
* **TSCM - Últimas 100 medições**
  Type: *Calculated* • Key: `link.tscm.last100` • Update: `60s`
  **Formula:**

  ```
  count(/vm-lenovoi7-zabbix/link.tscm.count,#100,"gt",0)
  ```

---

## 5) **Graphs (classic)** no host (FORMA B)

`Data collection → Hosts → vm-lenovoi7-zabbix → Graphs → Create graph`

1. **Velocidade — RSL (Mbps)**

   * Item: `RSL - Download Mbps` • Draw: `Line` • Y: Left • **min 0** • max Auto/1000
2. **Velocidade — TSCM (Mbps)**

   * Item: `TSCM - Download Mbps` • Draw: `Line` • Y: Left • **min 0** • max Auto/1000
3. **Proporção — últimas 100 (RSL x TSCM)** *(empilhado)*

   * Items: `link.rsl.last100` (**Stacked ON**), `link.tscm.last100` (**Stacked ON**)
   * Y: **min 0**, **max 100 (fixo)**
4. **Velocidade — Upload RSL (Mbps)** *(para v2)*

   * Item: `RSL - Upload Mbps` • Draw: `Line` • Y: Left • **min 0** • max Auto/1000
5. **Velocidade — Upload TSCM (Mbps)** *(para v2)*

   * Item: `TSCM - Upload Mbps` • Draw: `Line` • Y: Left • **min 0** • max Auto/1000

---

## 6) Dashboard — Widgets (Graph classic)

`Monitoring → Dashboards → (seu dashboard) → Edit → Add → Graph (classic)`
Adicione widgets apontando para estes graphs, na ordem:

1. **Velocidade — RSL (Mbps)**
2. **Velocidade — TSCM (Mbps)**
3. **Proporção — últimas 100 (RSL x TSCM)**
4. **Velocidade — Upload RSL (Mbps)** *(v2)*
5. **Velocidade — Upload TSCM (Mbps)** *(v2)*

> **Auto refresh** do dashboard: **1m** • **Período**: 6h ou 24h.

---

## 7) Testes rápidos

```bash
# execução manual (v1 e v2)
sudo /usr/local/bin/monitor_link_v1.sh
sudo /usr/local/bin/monitor_link_v2.sh
tail -n 5 /var/log/monitor_links.log

# validar trapper no Zabbix
zabbix_sender -z 192.168.31.35 -s "vm-lenovoi7-zabbix" -k link.rsl.count -o 1
zabbix_sender -z 192.168.31.35 -s "vm-lenovoi7-zabbix" -k link.rsl.upload -o 123.45   # (somente p/ v2)
```

---

## 8) Troubleshooting

* **Download/Upload “0.00”**: ver `/var/log/monitor_links.lastjson`; rodar `/usr/bin/speedtest --accept-license --accept-gdpr -s 61444` manual; checar rota/servidor.
* **Nada no Zabbix**: conferir **Allowed hosts = 192.168.31.35**; `ZBX_HOST` exato; *Latest data* no host.
* **CRON não dispara**: `sudo journalctl -u crond --since "15 min ago" --no-pager`; confirmar sem `flock` externo (script já tem lock).
* **Encher janela 100 rápido (sem banda)**:

  ```bash
  for i in {1..100}; do /usr/local/bin/monitor_link_v1.sh --no-speedtest; sleep 2; done
  ```

---

## 9) (Opcional) Logrotate

```bash
sudo tee /etc/logrotate.d/monitor_links >/dev/null <<'EOF'
/var/log/monitor_links.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0664 root root
}
EOF
```

---

## 🔁 Como alternar v1 ↔ v2 no CRON

```bash
sudo sed -i 's#monitor_link_v1.sh#monitor_link_v2.sh#g' /etc/cron.d/monitor-link
sudo systemctl reload crond 2>/dev/null || true
```

---

## ✅ Checklist final

* [ ] `/usr/bin/speedtest` instalado (repo EL9).
* [ ] **v1** em `/usr/local/bin/monitor_link_v1.sh`; **v2** em `/usr/local/bin/monitor_link_v2.sh`.
* [ ] CRON ativo com janelas 5/5 e 2/2 (v1 por padrão).
* [ ] Zabbix: 4 trapper (download/contagem) **+** 2 trapper (upload, p/ v2) **+** 2 calculated.
* [ ] 5 widgets (Graph classic): 2 download, 2 upload (v2), 1 proporção 100.
* [ ] Logs em `/var/log/monitor_links.log` mostrando Download (e Upload no v2).

---

**Assinatura / Template**
**Autor:** Jeferson “jmsalles” • **Host coletor:** `vm-lenovoi7-zabbix` • **IP:** `192.168.31.35`
**Data:** 26/08/2025 • **TZ:** America/Sao\_Paulo
**Projeto:** Monitoramento de links (RSL × TSCM) + Velocidade — **v1/v2** — Zabbix 7.4
