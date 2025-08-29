# 📘 Procedimento Padrão – Monitoramento de Saída por Link (RSL × TSCM) + Velocidade

**Plataforma:** Rocky Linux 10 • **Coletor/Zabbix agent:** `vm-lenovoi7-zabbix (192.168.31.35)` • **Zabbix:** 7.4 • **Agendamento:** CRON

---

## 0) Sumário do que será entregue

* Instalação da **Ookla CLI** (`/usr/bin/speedtest`) via **repositório EL9** (compatível no Rocky 10).
* Script `/usr/local/bin/monitor_link.sh` (lock, retries, fallback de parsing, logs, zabbix\_sender tolerante).
* Agendamento **CRON** com janelas:

  * **07:00–17:59** → a **cada 5 min**
  * **18:00–06:59** → a **cada 2 min**
* Criação no **Zabbix 7.4** (host `vm-lenovoi7-zabbix`):

  * 4 **itens trapper** (velocidades e contagens);
  * 2 **itens calculated** (janela das últimas 100 medições);
  * 3 **graphs (classic)** no host e 3 **widgets** no dashboard apontando para esses graphs.
* Testes rápidos, troubleshooting e **logrotate** opcional.

---

## 1) Pré-requisitos no coletor

```bash
sudo dnf -y install curl bind-utils jq zabbix-sender cronie
sudo systemctl enable --now crond
```

> Se existia systemd timer antigo, deixe só o CRON:
> `sudo systemctl disable --now monitor-link.timer 2>/dev/null || true`

---

## 2) Instalação – Ookla CLI (repositório EL9)

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

# Sanidade
/usr/bin/speedtest --accept-license --accept-gdpr -V
/usr/bin/speedtest --accept-license --accept-gdpr -L | head
```

---

## 3) Script de coleta e envio ao Zabbix

> Mede download com `/usr/bin/speedtest` fixando servidor **61444 (Nova Iguaçu)**, detecta link por **faixa de IP**, grava log e envia trapper.

```bash
sudo tee /usr/local/bin/monitor_link.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# /usr/local/bin/monitor_link.sh
# Mede download (Mbps) com /usr/bin/speedtest (Ookla) e envia via zabbix_sender.
# Robustez: lock, retries, fallback de parsing, dump de JSON, zabbix_sender tolerante.

set -u -o pipefail   # (sem -e para não matar por retorno !=0 em zabbix_sender)

# ======= CONFIG =======
ZBX_HOST="${ZBX_HOST:-vm-lenovoi7-zabbix}"
LOGFILE="${LOGFILE:-/var/log/monitor_links.log}"

SPEEDTEST_BIN="/usr/bin/speedtest"
SPEEDTEST_SERVER_ID="${SPEEDTEST_SERVER_ID:-61444}"   # RJ – Nova Iguaçu

# Prefixos por operadora (ajuste se necessário)
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
  local JSON MBPS mode
  # sequência: fixed -> auto -> fixed
  for mode in fixed auto fixed; do
    JSON="$(run_speedtest_json "$mode")"
    MBPS="$(echo "$JSON" | parse_mbps_from_json || true)"
    if [[ -n "${MBPS:-}" ]]; then echo "$MBPS"; return 0; fi
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

echo "$DATE | IP: $IP ($PROV) | Download: ${DL_Mbps} Mbps | Tool:[ookla:/usr/bin/speedtest] | Zabbix: $ZBX_SERVER" | tee -a "$LOGFILE"

# Envio tolerante (não derruba se falhar)
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

sudo chmod +x /usr/local/bin/monitor_link.sh
sudo touch /var/log/monitor_links.log && sudo chmod 664 /var/log/monitor_links.log
```

Teste manual:

```bash
sudo /usr/local/bin/monitor_link.sh
tail -n 5 /var/log/monitor_links.log
```

---

## 4) Agendamento – CRON (janelas 5/5 e 2/2)

```bash
sudo tee /etc/cron.d/monitor-link >/dev/null <<'EOF'
# Monitorar saída por link (RSL x TSCM) com /usr/local/bin/monitor_link.sh
# Janelas:
#  - 07:00–17:59  => a cada 5 min
#  - 18:00–06:59  => a cada 2 min
#
# Observações:
#  - PATH enxuto; o script já usa caminhos absolutos p/ speedtest (/usr/bin/speedtest)
#  - não redirecionamos para o log aqui; o script já grava em /var/log/monitor_links.log

SHELL=/bin/bash
PATH=/usr/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin
MAILTO=""

# 07:00–17:59 (*/5)
*/5 7-17 * * * root /usr/local/bin/monitor_link.sh >/dev/null 2>&1

# 18:00–06:59 (*/2)
*/2 18-23,0-6 * * * root /usr/local/bin/monitor_link.sh >/dev/null 2>&1
EOF

# Sanidade
sudo systemctl reload crond 2>/dev/null || true
sudo journalctl -u crond --since "10 min ago" --no-pager
```

---

## 5) Zabbix 7.4 – Itens (Trapper + Calculated)

**Host:** `vm-lenovoi7-zabbix` → **Data collection → Hosts → vm-lenovoi7-zabbix → Items → Create item**

### 5.1 Trapper – velocidades

**RSL - Download Mbps**

* Type: **Zabbix trapper** • Key: `link.rsl.speed` • Info: **Numeric (float)** • Units: `Mbps`
* History: `90d` • Trends: `365d` • **Allowed hosts:** `192.168.31.35`
* (Tags opcio.: `link=RSL`, `tipo=velocidade`) → **Add**

**TSCM - Download Mbps** (igual ao acima com **Key:** `link.tscm.speed`, tag `link=TSCM`)

### 5.2 Trapper – contagem

**RSL - Contagem**

* Type: **Zabbix trapper** • Key: `link.rsl.count` • Info: **Numeric (unsigned)** • History: `30d`
* **Allowed hosts:** `192.168.31.35` → **Add**

**TSCM - Contagem** (Key: `link.tscm.count`)

### 5.3 Calculated – janela das **últimas 100**

**RSL - Últimas 100 medições**

* Type: **Calculated** • Key: `link.rsl.last100` • Info: **Numeric (unsigned)** • Update interval: `60s`
* **Formula:**

```
count(/vm-lenovoi7-zabbix/link.rsl.count,#100,"gt",0)
```

→ **Add**

**TSCM - Últimas 100 medições** (Key: `link.tscm.last100`, fórmula equivalente)

> **Teste rápido trapper:**
> `zabbix_sender -z 192.168.31.35 -s "vm-lenovoi7-zabbix" -k link.rsl.count -o 1`

---

## 6) Zabbix 7.4 – Graphs (classic) no host (FORMA B)

**Caminho:** `Data collection → Hosts → vm-lenovoi7-zabbix → Graphs → Create graph`

### 6.1 Graph: **Velocidade — RSL (Mbps)**

* **Name:** `Velocidade — RSL (Mbps)` • **Graph type:** `Normal`
* **Items → Add item:** `RSL - Download Mbps` (key `link.rsl.speed`)
  Draw: `Line` • Y axis: `Left` • Stacked: **Off** • Width: `1`
* **Y axis:** Left **min 0** • **max** *(Auto ou 1000)*
* **Add**

### 6.2 Graph: **Velocidade — TSCM (Mbps)**

* Itens: `TSCM - Download Mbps` (key `link.tscm.speed`)
  Draw `Line` • Y `Left` • Stacked Off • Width `1`
* **Y:** min 0 • max *(Auto/1000)*
* **Add**

### 6.3 Graph: **Proporção — últimas 100 (RSL x TSCM)** (empilhado)

* **Items (2):**

  1. `RSL - Últimas 100 medições` • Draw `Line` (ou *Filled region*) • Y `Left` • **Stacked ON**
  2. `TSCM - Últimas 100 medições` • Draw `Line` • Y `Left` • **Stacked ON**
* **Y:** Left **min 0**, **max 100** (fixo)
* **Add**

---

## 7) Dashboard – Widgets apontando para os graphs

**Caminho:** `Monitoring → Dashboards → (seu dashboard) → Edit (lápis) → Add → Graph (classic)`
Adicione **3 widgets**, cada um apontando para:

1. **Graph:** `Velocidade — RSL (Mbps)`
2. **Graph:** `Velocidade — TSCM (Mbps)`
3. **Graph:** `Proporção — últimas 100 (RSL x TSCM)`

> **Auto refresh** do dashboard: **1m** | **Período:** 6h ou 24h.

---

## 8) Validações e Troubleshooting

* **Latest data** (host `vm-lenovoi7-zabbix`):

  * `link.rsl.speed` / `link.tscm.speed` com **Mbps** recentes?
  * `link.rsl.last100` + `link.tscm.last100` \~ **100**?
* **Logs e CRON:**

  ```bash
  sudo journalctl -u crond --since "15 min ago" --no-pager
  tail -n 20 /var/log/monitor_links.log
  ```
* **JSON problemático:**
  `sudo sed -n '1,120p' /var/log/monitor_links.lastjson`
* **Allowed hosts** nos trapper: `192.168.31.35`
* **Lock:** o script impede concorrência (não use `flock` no cron).

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

## ✅ Checklist final

* [ ] `/usr/bin/speedtest` instalado (repo EL9) e OK.
* [ ] Script em `/usr/local/bin/monitor_link.sh` (exec) + log em `/var/log/monitor_links.log`.
* [ ] CRON em `/etc/cron.d/monitor-link` com janelas 5/5 e 2/2.
* [ ] Zabbix: 4 **trapper** + 2 **calculated** criados.
* [ ] 3 **graphs (classic)** no host e 3 **widgets** no dashboard.
* [ ] Gráficos mostrando Mbps e proporção 100.

---

**Assinatura / Template**

**Autor:** Jeferson “jmsalles”
**Host coletor:** `vm-lenovoi7-zabbix` • **IP:** `192.168.31.35`
**Data:** 26/08/2025 • **TZ:** America/Sao\_Paulo
**Projeto:** Monitoramento de links (RSL × TSCM) + Velocidade — Zabbix 7.4

---

Se quiser, preparo um **apêndice** com “servidor speedtest diferente por operadora” (um ID para RSL e outro para TSCM, autodetectado pelo IP).
