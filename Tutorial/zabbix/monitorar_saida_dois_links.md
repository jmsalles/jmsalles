# 📈 Tutorial completo — Monitorar saída por link (RSL × TSCM) + velocidade (Rocky 10)

### (Atualizado para usar **apenas `/usr/bin/speedtest`** via repositório EL9 e **servidor fixo 61444**)

> Host coletor: **vm-lenovoi7-zabbix** (IP **192.168.31.35**) — já monitorado via **Zabbix Agent**
> Objetivo: detectar **por qual link** (RSL ou TSCM) cada medição saiu, **medir download em Mbps** e enviar ao Zabbix para ter:
>
> 1. **Velocidade RSL** 2) **Velocidade TSCM** 3) **Proporção nas últimas 100 medições** (ex.: 40×RSL / 60×TSCM)

---

## 🧭 Visão geral

* **Coleta**: script lê IP público → classifica **RSL/TSCM** por faixa → mede **download (Mbps)** com **Ookla CLI** (`/usr/bin/speedtest`, servidor **61444 – Nova Iguaçu**) → envia 4 chaves *trapper* → 2 *calculated* formam o gráfico de proporção 100.
* **Agendamento**: `systemd timer` a cada 3 minutos.
* **Zabbix**: 4 itens *trapper*, 2 *calculated* e 3 widgets **Time series**.

---

## 0) Pausar (se já tinha algo rodando)

```bash
sudo systemctl stop monitor-link.timer monitor-link.service 2>/dev/null || true
sudo systemctl disable monitor-link.timer 2>/dev/null || true
```

---

## 1) Instalar a **Ookla CLI** via repositório **EL9** (compatível no Rocky 10)

### 1.1 Limpeza (opcional, se havia instalações antigas)

```bash
sudo dnf -y remove speedtest 2>/dev/null || true
sudo rm -f /usr/local/sbin/speedtest-cli /usr/local/bin/speedtest-cli /usr/local/bin/speedtest /usr/bin/speedtest /usr/bin/ookla-speedtest
sudo rm -rf /opt/monitor-link/venv
pip3 uninstall -y speedtest-cli 2>/dev/null || true
sudo pip3 uninstall -y speedtest-cli 2>/dev/null || true
sudo rm -f /etc/yum.repos.d/ookla-speedtest.repo /etc/yum.repos.d/ookla_speedtest-cli.repo /etc/yum.repos.d/ookla_speedtest-cli*.repo
sudo dnf clean all && sudo rm -rf /var/cache/dnf
```

### 1.2 Adicionar repo EL9 e instalar

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

### 1.3 Teste rápido

```bash
/usr/bin/speedtest --accept-license --accept-gdpr -V
/usr/bin/speedtest --accept-license --accept-gdpr -L | head
```

---

## 2) Script de coleta + envio ao Zabbix

### 2.1 Criar o script

```bash
sudo tee /usr/local/bin/monitor_link_v1.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# /usr/local/bin/monitor_link.sh
# Usa SOMENTE /usr/bin/speedtest (Ookla CLI) para medir download (Mbps)
# e envia métricas para o Zabbix via zabbix_sender.

set -euo pipefail

# ======= CONFIG =======
ZBX_HOST="${ZBX_HOST:-vm-lenovoi7-zabbix}"
LOGFILE="${LOGFILE:-/var/log/monitor_links.log}"

SPEEDTEST_BIN="/usr/bin/speedtest"
SPEEDTEST_SERVER_ID="${SPEEDTEST_SERVER_ID:-61444}"   # RJ – Nova Iguaçu

# Prefixos por operadora
TSCM_PREFIXES=("181.191.")
RSL_PREFIXES=("168.121.")

# Modo rápido (sem speedtest): chame com --no-speedtest
FAST_ONLY=false
[[ "${1:-}" == "--no-speedtest" ]] && FAST_ONLY=true

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

get_download_mbps() {
  # Usa SOMENTE /usr/bin/speedtest; tenta 2 formas de extrair
  local args=(-f json --accept-license --accept-gdpr -s "$SPEEDTEST_SERVER_ID")
  local JSON BW_BYTES BYTES ELAPSED

  JSON=$("$SPEEDTEST_BIN" "${args[@]}" 2>/dev/null || true)

  # 1) caminho normal: bandwidth (Bytes/s) -> Mbps
  BW_BYTES=$(echo "$JSON" | jq -r '.download.bandwidth // empty')
  if [[ -n "$BW_BYTES" && "$BW_BYTES" != "null" && "$BW_BYTES" != "0" ]]; then
    awk -v b="$BW_BYTES" 'BEGIN {printf "%.2f", (b*8)/1000000}'
    return 0
  fi
  BYTES=$(jq -r '.download.bytes // empty')
  ELAPSED=$(jq -r '.download.elapsed // empty')
  if [[ -n "$BYTES" && -n "$ELAPSED" && "$BYTES" != "null" && "$ELAPSED" != "null" && "$ELAPSED" != "0" ]]; then
    awk -v bytes="$BYTES" -v ms="$ELAPSED" 'BEGIN {printf "%.2f", (bytes*8)/(ms*1000)}'
    return
  fi

  # 3) debug: salvar JSON quando falhar
  echo "$JSON" > /var/log/monitor_links.lastjson 2>/dev/null || true
  echo "0.00"
}

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

## 3) Service/Timer do systemd (PATH “limpo”, sem venv)

```bash
# service
sudo tee /etc/systemd/system/monitor-link.service >/dev/null <<'EOF'
[Unit]
Description=Monitorar saída de link (RSL x TSCM) + velocidade -> Zabbix

[Service]
Type=oneshot
Environment="PATH=/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin"
ExecStart=/usr/local/bin/monitor_link.sh
EOF

# timer (3 min)
sudo tee /etc/systemd/system/monitor-link.timer >/dev/null <<'EOF'
[Unit]
Description=Agendar monitor-link.service a cada 3 minutos

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
Unit=monitor-link.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now monitor-link.timer

# teste manual imediato
sudo systemctl start monitor-link.service
tail -n 5 /var/log/monitor_links.log
```

---

## 4) Configuração no **Zabbix Server**

### 4.1 Itens **Trapper** (no host **vm-lenovoi7-zabbix**)

Caminho: **Data collection → Hosts → vm-lenovoi7-zabbix → Items → Create item** (um por vez):

1. **RSL - Download Mbps**

* Type: **Zabbix trapper** | Key: `link.rsl.speed` | Type of information: **Numeric (float)** | Units: **Mbps** | **Allowed hosts**: `192.168.31.35`

2. **TSCM - Download Mbps**

* Type: **Zabbix trapper** | Key: `link.tscm.speed` | Type of information: **Numeric (float)** | Units: **Mbps** | **Allowed hosts**: `192.168.31.35`

3. **RSL - Contagem**

* Type: **Zabbix trapper** | Key: `link.rsl.count` | Type of information: **Numeric (unsigned)** | Allowed hosts: `192.168.31.35`

4. **TSCM - Contagem**

* Type: **Zabbix trapper** | Key: `link.tscm.count` | Type of information: **Numeric (unsigned)** | Allowed hosts: `192.168.31.35`

### 4.2 Itens **Calculated** (proporção nas **últimas 100** medições)

Crie mais dois itens:

5. **RSL - Últimas 100 medições**

* Type: **Calculated** | Key: `link.rsl.last100` | Type of information: **Numeric (unsigned)** | Update interval: **60s** |
* **Formula**:

```
count(/vm-lenovoi7-zabbix/link.rsl.count,#100,"gt",0)
```

6. **TSCM - Últimas 100 medições**

* Type: **Calculated** | Key: `link.tscm.last100` | Type of information: **Numeric (unsigned)** | Update interval: **60s** |
* **Formula**:

```
count(/vm-lenovoi7-zabbix/link.tscm.count,#100,"gt",0)
```

---

## 5) Dashboard — 3 widgets **Time series**

### 5.1 Abrir/crear dashboard

**Monitoring → Dashboards → Create dashboard**
Name: `Links RSL x TSCM` | Auto refresh: `1m` | Period: `6h` (exemplo) | **Save**

### 5.2 Widget 1 — **Velocidade — RSL (Mbps)**

**Add widget → Time series**

* Title: `Velocidade — RSL (Mbps)`
* Data set: Host `vm-lenovoi7-zabbix` | Item `link.rsl.speed` | Legend `RSL` | Stacking `None`
* Axes: Y **Min 0**, **Max Auto**
* Display: **Show legend** → **Add**

### 5.3 Widget 2 — **Velocidade — TSCM (Mbps)**

Clone o widget anterior e troque o item para `link.tscm.speed`, Title `Velocidade — TSCM (Mbps)`, Legend `TSCM`.

### 5.4 Widget 3 — **Proporção — últimas 100 (RSL x TSCM)** (empilhado)

**Add widget → Time series**

* Title: `Proporção — últimas 100 (RSL x TSCM)`
* Data set 1: `link.rsl.last100` (Legend `RSL`, **Stacked**)
* Data set 2: `link.tscm.last100` (Legend `TSCM`, **Stacked**)
* Axes: Y **Min 0**, **Max 100**
* Display: **Show legend** → **Add** → **Save** o dashboard

> Esse gráfico mostra, a cada instante, um par de valores que **soma 100** (ex.: 40/60).

---

## 6) Testes rápidos

```bash
# Rodar manualmente no mesmo contexto do service
sudo /usr/local/bin/monitor_link.sh

# Ver o log (deve mostrar Tool:[ookla:/usr/bin/speedtest] e Mbps > 0)
tail -n 10 /var/log/monitor_links.log

# Teste de envio simples (trapper):
zabbix_sender -z "$(grep -E '^(ServerActive|Server)=' /etc/zabbix/zabbix_agent*.conf 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d ' ' | cut -d, -f1)" \
  -s "vm-lenovoi7-zabbix" -k link.rsl.count -o 1
```

Em **Monitoring → Latest data**, confirme valores chegando. Veja os três widgets no dashboard.

---

## 7) Troubleshooting

* **Download 0.00 Mbps**:

  1. Rode manual: `/usr/bin/speedtest --accept-license --accept-gdpr -s 61444` (se OK, binário está bom).
  2. Veja `/var/log/monitor_links.lastjson` — se existir, me envie o início (retorno do JSON).
  3. Confirme PATH do service (tem **/usr/bin** primeiro) e se o script tem `SPEEDTEST_SERVER_ID="61444"`.

* **Itens trapper sem dados**: cheque `ZBX_HOST` no script e **Allowed hosts = 192.168.31.35** nos itens.

* **Gráfico “Proporção 100” parado**: dispare um *burst* sem speedtest (só contagem) para encher a janela:

  ```bash
  for i in {1..100}; do /usr/local/bin/monitor_link.sh --no-speedtest; sleep 2; done
  ```

* **Quero menos impacto de banda**: mantenha o timer de 3 min (só contagem) e crie um **segundo timer 1×/hora** que roda o script (sem `--no-speedtest`) para atualizar velocidades.

---

## ☑️ Checklist final

* [ ] `/usr/bin/speedtest` instalado pelo repo EL9.
* [ ] Script **/usr/local/bin/monitor\_link.sh** com `SPEEDTEST_SERVER_ID="61444"`.
* [ ] Service/Timer ativos com `PATH=/usr/bin:...` (sem venv).
* [ ] 4 itens *trapper* + 2 *calculated* criados no Zabbix.
* [ ] 3 widgets **Time series** exibindo dados.

Se quiser, depois adapto o script para **usar um ID diferente por operadora** (RSL vs TSCM), caso você identifique servidores específicos que performam melhor para cada link.
