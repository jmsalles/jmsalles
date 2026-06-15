# Tutorial completo — Integração Zabbix → phpIPAM

## 1. Objetivo

Implementar uma integração unidirecional:

```text
Zabbix
  ├── CPU
  ├── memória
  ├── disco
  ├── sistema operacional
  ├── uptime
  └── status do host
         │
         ▼
Script Python
         │
         ▼
phpIPAM
  └── Campos personalizados dos Devices
```

A integração utiliza apenas dados que **já existem no Zabbix**. Não é necessário criar ou modificar templates, itens, hosts ou agentes.

O Zabbix continua responsável pelo histórico, gráficos e alertas. O phpIPAM recebe somente o último valor disponível de cada métrica.

---

# 2. Ambiente utilizado

```text
Domínio interno: jmsalles.homelab.br

Servidor DNS/AD:
192.168.31.24

Servidor Docker, Nginx e phpIPAM:
192.168.31.37
docker-hml-lenovo-i5

phpIPAM:
https://ipam.jmsalles.homelab.br

Servidor Zabbix:
192.168.31.35
vm-lenovoi7-zabbix

Zabbix:
https://zabbix.jmsalles.homelab.br

API Zabbix:
https://zabbix.jmsalles.homelab.br/api_jsonrpc.php
```

A versão utilizada durante a implantação foi:

```text
phpIPAM: 1.8.2
Zabbix: 7.4.2
```

---

# 3. Arquitetura de acesso ao Zabbix

O container web do Zabbix publica:

```text
192.168.31.35:80 → container zbx-web:8080
```

Ele não publica a porta 443 diretamente.

Por isso, o acesso HTTPS deve seguir este fluxo:

```text
zabbix.jmsalles.homelab.br
            │
            ▼
192.168.31.37:443
Nginx central
            │
            ▼
192.168.31.35:80
Zabbix Web
```

O registro DNS deve apontar para o Nginx:

```text
zabbix.jmsalles.homelab.br → 192.168.31.37
```

Não deve apontar diretamente para:

```text
192.168.31.35
```

porque o servidor Zabbix não possui HTTPS publicado na porta 443.

---

# 4. Configurar o proxy reverso do Zabbix

No servidor `docker-hml-lenovo-i5`, crie ou edite:

```bash
vim /home/jmsalles/nginx/conf.d/zabbix.conf
```

Conteúdo:

```nginx
server {
    listen 80;
    server_name zabbix.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name zabbix.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/zabbix.jmsalles.homelab.access.log;
    error_log  /var/log/nginx/zabbix.jmsalles.homelab.error.log;

    location / {
        proxy_pass http://192.168.31.35:80;

        proxy_http_version 1.1;
        proxy_pass_request_headers on;

        proxy_set_header Host              $host;
        proxy_set_header Authorization     $http_authorization;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Port  443;
        proxy_set_header X-Forwarded-Proto https;

        proxy_connect_timeout 30s;
        proxy_send_timeout    300s;
        proxy_read_timeout    300s;

        proxy_redirect off;
    }
}
```

Validar:

```bash
docker compose \
    -f /home/jmsalles/nginx/docker-compose.yml \
    exec nginx nginx -t
```

Recarregar:

```bash
docker compose \
    -f /home/jmsalles/nginx/docker-compose.yml \
    exec nginx nginx -s reload
```

---

# 5. Configurar o proxy reverso do phpIPAM

Arquivo:

```bash
vim /home/jmsalles/nginx/conf.d/phpipam.conf
```

Conteúdo:

```nginx
server {
    listen 80;
    server_name ipam.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name ipam.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/ipam.jmsalles.homelab.access.log;
    error_log  /var/log/nginx/ipam.jmsalles.homelab.error.log;

    location / {
        proxy_pass http://host.docker.internal:8088;

        proxy_http_version 1.1;
        proxy_pass_request_headers on;

        proxy_set_header Host              $host;
        proxy_set_header Authorization     $http_authorization;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Port  443;
        proxy_set_header X-Forwarded-Proto https;

        proxy_connect_timeout 30s;
        proxy_send_timeout    300s;
        proxy_read_timeout    300s;

        proxy_redirect off;
    }
}
```

A diretiva importante para a autenticação da API é:

```nginx
proxy_set_header Authorization $http_authorization;
```

Sem ela, o usuário e a senha utilizados no HTTP Basic Authentication podem não chegar ao phpIPAM.

Validar e recarregar:

```bash
docker compose \
    -f /home/jmsalles/nginx/docker-compose.yml \
    exec nginx nginx -t
```

```bash
docker compose \
    -f /home/jmsalles/nginx/docker-compose.yml \
    exec nginx nginx -s reload
```

---

# 6. Validar a API do Zabbix

Teste sem utilizar token:

```bash
curl \
    --cacert /etc/pki/ca-trust/source/anchors/jmsalles-homelab-rootCA.crt \
    --header 'Content-Type: application/json-rpc' \
    --data '{
        "jsonrpc": "2.0",
        "method": "apiinfo.version",
        "params": {},
        "id": 1
    }' \
    https://zabbix.jmsalles.homelab.br/api_jsonrpc.php
```

Resultado esperado:

```json
{
    "jsonrpc": "2.0",
    "result": "7.4.2",
    "id": 1
}
```

Validar a resolução DNS:

```bash
getent ahostsv4 zabbix.jmsalles.homelab.br
```

Resultado esperado:

```text
192.168.31.37 STREAM zabbix.jmsalles.homelab.br
```

---

# 7. Criar o usuário de integração no phpIPAM

No phpIPAM, acesse:

```text
Administration
→ Users
→ Create user
```

Crie:

```text
Username: svc-zabbix-sync
Authentication: Local/phpIPAM
Status: Active
```

Durante a implantação inicial, o usuário pode ficar com permissão administrativa para validar a integração. Depois, as permissões podem ser reduzidas para permitir somente leitura e atualização dos Devices.

Não utilize uma conta pessoal no script.

---

# 8. Criar a aplicação da API no phpIPAM

Acesse:

```text
Administration
→ API
→ Create API
```

Configure:

```text
App ID: zabbix-sync
App permissions: Leitura / Escrita / Admin
App security: SSL with User token
Transaction lock: Auto
Lock timeout: 30
Nest custom fields: Não
Show links: Não
Descrição: Sincronização de inventário Zabbix para phpIPAM
```

O campo essencial é:

```text
App security: SSL with User token
```

Não utilizar:

```text
SSL with App Code
```

O script realiza este fluxo:

```text
Usuário e senha
      │
      ▼
POST /api/zabbix-sync/user/
      │
      ▼
Token temporário do phpIPAM
      │
      ▼
Consulta e atualização dos Devices
```

O `App code` exibido na interface não é utilizado pelo script nessa modalidade.

---

# 9. Testar a autenticação da API do phpIPAM

Execute:

```bash
curl \
    --cacert /etc/pki/ca-trust/source/anchors/jmsalles-homelab-rootCA.crt \
    --request POST \
    --user svc-zabbix-sync \
    --include \
    https://ipam.jmsalles.homelab.br/api/zabbix-sync/user/
```

Digite a senha quando solicitado.

Resultado esperado:

```text
HTTP/1.1 200 OK
```

Exemplo do JSON:

```json
{
    "code": 200,
    "success": true,
    "data": {
        "token": "TOKEN_TEMPORARIO",
        "expires": "2026-06-15 04:24:51"
    },
    "time": 0.005
}
```

O token é temporário. O script solicita automaticamente um novo token em cada execução.

---

# 10. Criar os campos personalizados no phpIPAM

Acesse:

```text
Administration
→ Custom fields
→ Devices
```

Crie os campos com os nomes exatos abaixo:

| Campo                  | Tipo sugerido   |
| ---------------------- | --------------- |
| `Sincronizar_Zabbix`   | BOOL            |
| `Zabbix_HostID`        | VARCHAR         |
| `CPU_Modelo`           | VARCHAR         |
| `CPU_Cores`            | VARCHAR         |
| `CPU_Uso_Pct`          | VARCHAR         |
| `Memoria_Total_GiB`    | VARCHAR         |
| `Memoria_Uso_Pct`      | VARCHAR         |
| `Disco_SO`             | VARCHAR         |
| `Disco_SO_Total_GiB`   | VARCHAR         |
| `Disco_SO_Uso_Pct`     | VARCHAR         |
| `Sistema_Operacional`  | TEXT ou VARCHAR |
| `Uptime`               | VARCHAR         |
| `Zabbix_Status`        | VARCHAR         |
| `Ultima_Sincronizacao` | VARCHAR         |

O phpIPAM disponibilizará esses campos na API com o prefixo:

```text
custom_
```

Exemplos:

```text
custom_CPU_Cores
custom_Memoria_Total_GiB
custom_Sincronizar_Zabbix
```

---

# 11. Dados utilizados no Zabbix

A integração usa somente os itens já existentes.

| Informação                  | Chave no Zabbix                          |
| --------------------------- | ---------------------------------------- |
| Quantidade de CPUs          | `system.cpu.num`                         |
| Fallback de CPUs Docker     | `docker.ncpu`                            |
| Utilização total de CPU     | `system.cpu.util`                        |
| Memória total               | `vm.memory.size[total]`                  |
| Utilização da memória       | `vm.memory.utilization`                  |
| Fallback memória utilizada  | `vm.memory.size[pused]`                  |
| Fallback memória disponível | `vm.memory.size[pavailable]`             |
| Filesystems                 | `vfs.fs.get`                             |
| Sistema operacional         | `system.sw.os`                           |
| Fallback do sistema         | `system.uname`                           |
| Uptime                      | `system.uptime`                          |
| Status de monitoramento     | Propriedade `status` do host             |
| Modelo da CPU               | Somente se já existir um item compatível |

O disco do sistema operacional é extraído do JSON retornado por:

```text
vfs.fs.get
```

No Linux, o script procura:

```text
/
```

No Windows, procura:

```text
C:
```

Também são suportados como fallback:

```text
vfs.fs.dependent.size[/,total]
vfs.fs.dependent.size[/,pused]
vfs.fs.size[/,total]
vfs.fs.size[/,pused]
```

O campo `CPU_Modelo` só será atualizado se o Zabbix já possuir uma destas chaves:

```text
system.hw.cpu[0,model]
system.hw.cpu[all,model]
system.hw.cpu
```

Caso nenhuma exista, o script não apaga um valor cadastrado manualmente no phpIPAM.

---

# 12. Criar o token da API no Zabbix

No Zabbix, acesse:

```text
Users
→ Users
```

Crie ou utilize um usuário de serviço:

```text
Username: svc-phpipam
```

Esse usuário precisa ter acesso de leitura aos grupos de hosts que serão sincronizados.

Depois acesse:

```text
Users
→ API tokens
→ Create API token
```

Configure:

```text
Name: phpipam-sync
User: svc-phpipam
```

Copie o token no momento da criação.

O script utiliza:

```text
Authorization: Bearer TOKEN
```

---

# 13. Preparar o servidor da integração

A integração está sendo executada no servidor:

```text
docker-hml-lenovo-i5
192.168.31.37
```

Instale Python e pip:

```bash
sudo dnf install -y python3 python3-pip
```

Crie o usuário:

```bash
sudo useradd \
    --system \
    --home-dir /opt/zabbix-phpipam \
    --shell /sbin/nologin \
    zbxphpipam
```

Crie a estrutura:

```bash
sudo mkdir -p /opt/zabbix-phpipam/{bin,venv}
```

Crie o ambiente virtual:

```bash
sudo python3 -m venv /opt/zabbix-phpipam/venv
```

Instale as dependências:

```bash
sudo /opt/zabbix-phpipam/venv/bin/pip \
    install --upgrade pip requests
```

Ajuste o proprietário:

```bash
sudo chown -R \
    zbxphpipam:zbxphpipam \
    /opt/zabbix-phpipam
```

---

# 14. Criar o arquivo de variáveis

Crie:

```bash
sudo vim /etc/zabbix-phpipam.env
```

Conteúdo:

```bash
ZABBIX_URL="https://zabbix.jmsalles.homelab.br/api_jsonrpc.php"
ZABBIX_TOKEN="COLE_O_TOKEN_ATUAL_DO_ZABBIX"

PHPIPAM_URL="https://ipam.jmsalles.homelab.br"
PHPIPAM_APP_ID="zabbix-sync"
PHPIPAM_USER="svc-zabbix-sync"
PHPIPAM_PASSWORD="COLOQUE_A_SENHA_ATUAL"

VERIFY_TLS="/etc/pki/ca-trust/source/anchors/jmsalles-homelab-rootCA.crt"

HTTP_TIMEOUT="30"
LOG_LEVEL="INFO"
```

Ajuste as permissões:

```bash
sudo chown root:zbxphpipam \
    /etc/zabbix-phpipam.env
```

```bash
sudo chmod 640 \
    /etc/zabbix-phpipam.env
```

Validar se não existem caracteres Windows:

```bash
if grep -q $'\r' /etc/zabbix-phpipam.env; then
    echo "ERRO: arquivo possui CRLF"
else
    echo "OK: arquivo sem CRLF"
fi
```

Para corrigir:

```bash
sudo sed -i 's/\r$//' \
    /etc/zabbix-phpipam.env
```

---

# 15. Criar o script completo

Crie:

```bash
sudo vim /opt/zabbix-phpipam/bin/sync.py
```

Conteúdo completo:

```python
#!/usr/bin/env python3

import json
import logging
import os
import sys
from datetime import datetime

import requests


# ============================================================
# LOG
# ============================================================

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
)

LOG = logging.getLogger("zabbix-phpipam")


# ============================================================
# VARIÁVEIS DE AMBIENTE
# ============================================================

ZABBIX_URL = os.environ["ZABBIX_URL"].rstrip("/")
ZABBIX_TOKEN = os.environ["ZABBIX_TOKEN"]

PHPIPAM_URL = os.environ["PHPIPAM_URL"].rstrip("/")
PHPIPAM_APP_ID = os.environ["PHPIPAM_APP_ID"]
PHPIPAM_USER = os.environ["PHPIPAM_USER"]
PHPIPAM_PASSWORD = os.environ["PHPIPAM_PASSWORD"]

HTTP_TIMEOUT = int(
    os.getenv("HTTP_TIMEOUT", "30")
)

VERIFY_TLS_CONFIG = os.getenv(
    "VERIFY_TLS",
    "true",
).strip()


# ============================================================
# CAMPOS PERSONALIZADOS DO PHPIPAM
# ============================================================

FIELD_SYNC = "custom_Sincronizar_Zabbix"
FIELD_HOSTID = "custom_Zabbix_HostID"

FIELD_CPU_MODEL = "custom_CPU_Modelo"
FIELD_CPU_CORES = "custom_CPU_Cores"
FIELD_CPU_USAGE = "custom_CPU_Uso_Pct"

FIELD_MEMORY_TOTAL = "custom_Memoria_Total_GiB"
FIELD_MEMORY_USAGE = "custom_Memoria_Uso_Pct"

FIELD_DISK_NAME = "custom_Disco_SO"
FIELD_DISK_TOTAL = "custom_Disco_SO_Total_GiB"
FIELD_DISK_USAGE = "custom_Disco_SO_Uso_Pct"

FIELD_OPERATING_SYSTEM = "custom_Sistema_Operacional"
FIELD_UPTIME = "custom_Uptime"
FIELD_ZABBIX_STATUS = "custom_Zabbix_Status"
FIELD_LAST_SYNC = "custom_Ultima_Sincronizacao"


# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

def get_verify_tls():
    value = VERIFY_TLS_CONFIG.lower()

    if value in {
        "false",
        "0",
        "no",
        "não",
    }:
        return False

    if value in {
        "true",
        "1",
        "yes",
        "sim",
    }:
        return True

    return VERIFY_TLS_CONFIG


VERIFY_TLS = get_verify_tls()


def truthy(value):
    return str(value).strip().lower() in {
        "1",
        "true",
        "yes",
        "sim",
        "on",
    }


def has_value(value):
    return (
        value is not None
        and str(value).strip() != ""
    )


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def bytes_to_gib(value):
    number = to_float(value)

    if number is None:
        return ""

    return f"{number / (1024 ** 3):.2f}"


def format_percent(value):
    number = to_float(value)

    if number is None:
        return ""

    return f"{number:.2f}"


def format_uptime(value):
    number = to_float(value)

    if number is None:
        return ""

    seconds = int(number)

    days, remainder = divmod(
        seconds,
        86400,
    )

    hours, remainder = divmod(
        remainder,
        3600,
    )

    minutes, _ = divmod(
        remainder,
        60,
    )

    return (
        f"{days}d "
        f"{hours:02d}h "
        f"{minutes:02d}m"
    )


def normalize_mountpoint(value):
    mountpoint = str(
        value or ""
    ).strip()

    if mountpoint == "/":
        return "/"

    return mountpoint.rstrip("/\\")


# ============================================================
# API DO ZABBIX
# ============================================================

class ZabbixAPI:

    def __init__(self):
        self.request_id = 0
        self.session = requests.Session()

        self.session.headers.update(
            {
                "Content-Type": (
                    "application/json-rpc"
                ),
                "Authorization": (
                    f"Bearer {ZABBIX_TOKEN}"
                ),
            }
        )

    def call(self, method, params):
        self.request_id += 1

        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": self.request_id,
        }

        response = self.session.post(
            ZABBIX_URL,
            json=payload,
            timeout=HTTP_TIMEOUT,
            verify=VERIFY_TLS,
        )

        if not response.ok:
            raise RuntimeError(
                "Falha HTTP na API Zabbix "
                f"| método={method} "
                f"| HTTP={response.status_code} "
                f"| resposta={response.text[:1000]}"
            )

        try:
            result = response.json()
        except ValueError as error:
            raise RuntimeError(
                "A API do Zabbix não retornou JSON válido "
                f"| método={method} "
                f"| HTTP={response.status_code} "
                f"| resposta={response.text[:1000]}"
            ) from error

        if "error" in result:
            raise RuntimeError(
                "Erro na API Zabbix "
                f"| método={method} "
                f"| erro={result['error']}"
            )

        return result.get(
            "result",
            [],
        )

    def get_hosts(self):
        return self.call(
            "host.get",
            {
                "output": [
                    "hostid",
                    "host",
                    "name",
                    "status",
                    "inventory_mode",
                ],
                "selectInterfaces": [
                    "ip",
                    "dns",
                    "main",
                    "useip",
                ],
                "selectInventory": [
                    "type",
                    "type_full",
                    "model",
                    "hardware",
                    "hardware_full",
                    "os",
                    "os_full",
                ],
            },
        )

    def get_items(self, hostid):
        return self.call(
            "item.get",
            {
                "hostids": str(hostid),
                "output": [
                    "itemid",
                    "name",
                    "key_",
                    "lastvalue",
                    "lastclock",
                    "units",
                    "status",
                    "state",
                    "error",
                    "type",
                    "value_type",
                    "flags",
                ],
                "monitored": True,
            },
        )


# ============================================================
# API DO PHPIPAM
# ============================================================

class PhpIPAMAPI:

    def __init__(self):
        self.base_url = (
            f"{PHPIPAM_URL}/api/"
            f"{PHPIPAM_APP_ID}"
        )

        self.session = requests.Session()

    def authenticate(self):
        response = self.session.post(
            f"{self.base_url}/user/",
            auth=(
                PHPIPAM_USER,
                PHPIPAM_PASSWORD,
            ),
            timeout=HTTP_TIMEOUT,
            verify=VERIFY_TLS,
        )

        if not response.ok:
            raise RuntimeError(
                "Falha na autenticação do phpIPAM "
                f"| HTTP={response.status_code} "
                f"| resposta={response.text[:1000]}"
            )

        try:
            body = response.json()
        except ValueError as error:
            raise RuntimeError(
                "O phpIPAM não retornou JSON válido "
                f"| HTTP={response.status_code} "
                f"| resposta={response.text[:1000]}"
            ) from error

        if not body.get("success"):
            raise RuntimeError(
                "Falha na autenticação do phpIPAM "
                f"| resposta={body}"
            )

        token = body["data"]["token"]

        self.session.headers.update(
            {
                "phpipam-token": token,
                "Content-Type": (
                    "application/json"
                ),
            }
        )

    def get_devices(self):
        response = self.session.get(
            f"{self.base_url}/devices/all/",
            params={
                "links": "false",
            },
            timeout=HTTP_TIMEOUT,
            verify=VERIFY_TLS,
        )

        if not response.ok:
            raise RuntimeError(
                "Falha HTTP ao consultar Devices "
                f"| HTTP={response.status_code} "
                f"| resposta={response.text[:1000]}"
            )

        try:
            body = response.json()
        except ValueError as error:
            raise RuntimeError(
                "O phpIPAM não retornou JSON válido "
                "ao consultar Devices "
                f"| resposta={response.text[:1000]}"
            ) from error

        if not body.get("success"):
            raise RuntimeError(
                "Falha ao consultar Devices "
                f"| resposta={body}"
            )

        return body.get("data") or []

    def update_device(self, payload):
        response = self.session.patch(
            f"{self.base_url}/devices/",
            json=payload,
            timeout=HTTP_TIMEOUT,
            verify=VERIFY_TLS,
        )

        if not response.ok:
            raise RuntimeError(
                "Falha HTTP ao atualizar Device "
                f"| device_id={payload.get('id')} "
                f"| HTTP={response.status_code} "
                f"| resposta={response.text[:1000]}"
            )

        try:
            body = response.json()
        except ValueError as error:
            raise RuntimeError(
                "O phpIPAM não retornou JSON válido "
                "ao atualizar Device "
                f"| device_id={payload.get('id')} "
                f"| resposta={response.text[:1000]}"
            ) from error

        if not body.get("success"):
            raise RuntimeError(
                "Falha ao atualizar Device "
                f"| device_id={payload.get('id')} "
                f"| resposta={body}"
            )


# ============================================================
# PROCESSAMENTO DOS ITENS DO ZABBIX
# ============================================================

def build_item_index(items):
    result = {}

    for item in items:
        key = item.get("key_")

        if not key:
            continue

        if str(
            item.get("lastclock", "0")
        ) == "0":
            continue

        result[key] = item

    return result


def get_item_value(index, keys):
    for key in keys:
        item = index.get(key)

        if not item:
            continue

        value = item.get("lastvalue")

        if has_value(value):
            return value

    return None


def parse_vfs_fs_get(index):
    raw_value = get_item_value(
        index,
        [
            "vfs.fs.get",
        ],
    )

    if not raw_value:
        return []

    try:
        data = json.loads(raw_value)
    except (TypeError, ValueError):
        LOG.warning(
            "A chave vfs.fs.get não retornou JSON válido"
        )

        return []

    if isinstance(data, list):
        return [
            filesystem
            for filesystem in data
            if isinstance(
                filesystem,
                dict,
            )
        ]

    if isinstance(data, dict):
        nested_data = data.get("data")

        if isinstance(nested_data, list):
            return [
                filesystem
                for filesystem in nested_data
                if isinstance(
                    filesystem,
                    dict,
                )
            ]

        return [data]

    return []


def get_operating_system_disk(index):
    discovered_filesystems = (
        parse_vfs_fs_get(index)
    )

    preferred_mountpoints = [
        "/",
        "C:",
    ]

    for preferred in preferred_mountpoints:
        for filesystem in discovered_filesystems:
            fsname = normalize_mountpoint(
                filesystem.get("fsname")
                or filesystem.get("mountpoint")
                or filesystem.get("name")
            )

            if fsname != preferred:
                continue

            bytes_data = (
                filesystem.get("bytes")
                or {}
            )

            if not isinstance(
                bytes_data,
                dict,
            ):
                bytes_data = {}

            total = bytes_data.get("total")
            used = bytes_data.get("used")
            free = bytes_data.get("free")
            pused = bytes_data.get("pused")

            total_number = to_float(total)
            used_number = to_float(used)
            free_number = to_float(free)
            pused_number = to_float(pused)

            if (
                used_number is None
                and total_number is not None
                and free_number is not None
            ):
                used_number = max(
                    0.0,
                    total_number - free_number,
                )

                used = str(used_number)

            if (
                free_number is None
                and total_number is not None
                and used_number is not None
            ):
                free_number = max(
                    0.0,
                    total_number - used_number,
                )

                free = str(free_number)

            if (
                pused_number is None
                and total_number is not None
                and total_number > 0
                and used_number is not None
            ):
                pused = str(
                    used_number
                    / total_number
                    * 100
                )

            return {
                "filesystem": fsname,
                "fstype": str(
                    filesystem.get("fstype")
                    or filesystem.get("type")
                    or ""
                ),
                "total": total,
                "used": used,
                "free": free,
                "pused": pused,
            }

    for filesystem in [
        "/",
        "C:",
        "C:\\",
    ]:
        total = get_item_value(
            index,
            [
                (
                    "vfs.fs.dependent.size"
                    f"[{filesystem},total]"
                ),
                (
                    "vfs.fs.size"
                    f"[{filesystem},total]"
                ),
            ],
        )

        used = get_item_value(
            index,
            [
                (
                    "vfs.fs.dependent.size"
                    f"[{filesystem},used]"
                ),
                (
                    "vfs.fs.size"
                    f"[{filesystem},used]"
                ),
            ],
        )

        free = get_item_value(
            index,
            [
                (
                    "vfs.fs.dependent.size"
                    f"[{filesystem},free]"
                ),
                (
                    "vfs.fs.size"
                    f"[{filesystem},free]"
                ),
            ],
        )

        pused = get_item_value(
            index,
            [
                (
                    "vfs.fs.dependent.size"
                    f"[{filesystem},pused]"
                ),
                (
                    "vfs.fs.size"
                    f"[{filesystem},pused]"
                ),
            ],
        )

        if total is None:
            continue

        total_number = to_float(total)
        used_number = to_float(used)
        free_number = to_float(free)

        if (
            used_number is None
            and total_number is not None
            and free_number is not None
        ):
            used_number = max(
                0.0,
                total_number - free_number,
            )

            used = str(used_number)

        if (
            pused is None
            and total_number is not None
            and total_number > 0
            and used_number is not None
        ):
            pused = str(
                used_number
                / total_number
                * 100
            )

        return {
            "filesystem": (
                normalize_mountpoint(
                    filesystem
                )
            ),
            "fstype": "",
            "total": total,
            "used": used,
            "free": free,
            "pused": pused,
        }

    return {
        "filesystem": "",
        "fstype": "",
        "total": None,
        "used": None,
        "free": None,
        "pused": None,
    }


# ============================================================
# CORRELAÇÃO PHPIPAM X ZABBIX
# ============================================================

def build_host_index(hosts):
    result = {}

    for host in hosts:
        candidates = [
            host.get("hostid"),
            host.get("host"),
            host.get("name"),
        ]

        for interface in host.get(
            "interfaces",
            [],
        ):
            candidates.extend(
                [
                    interface.get("ip"),
                    interface.get("dns"),
                ]
            )

        for candidate in candidates:
            if not candidate:
                continue

            normalized = str(
                candidate
            ).strip().lower()

            result[normalized] = host

            short_name = normalized.split(
                ".",
                1,
            )[0]

            if short_name:
                result.setdefault(
                    short_name,
                    host,
                )

    return result


def find_zabbix_host(device, host_index):
    explicit_hostid = str(
        device.get(
            FIELD_HOSTID,
            "",
        )
    ).strip()

    if explicit_hostid:
        host = host_index.get(
            explicit_hostid.lower()
        )

        if host:
            return host

    candidates = [
        device.get("hostname"),
        device.get("name"),
        device.get("description"),
        device.get("ip"),
        device.get("ip_addr"),
    ]

    for candidate in candidates:
        if not candidate:
            continue

        normalized = str(
            candidate
        ).strip().lower()

        host = host_index.get(normalized)

        if host:
            return host

        short_hostname = normalized.split(
            ".",
            1,
        )[0]

        host = host_index.get(
            short_hostname
        )

        if host:
            return host

    return None


# ============================================================
# PAYLOAD PARA O PHPIPAM
# ============================================================

def build_update_payload(
    device_id,
    host,
    items,
):
    index = build_item_index(items)

    cpu_cores = get_item_value(
        index,
        [
            "system.cpu.num",
            "docker.ncpu",
        ],
    )

    cpu_usage = get_item_value(
        index,
        [
            "system.cpu.util",
        ],
    )

    cpu_model = get_item_value(
        index,
        [
            "system.hw.cpu[0,model]",
            "system.hw.cpu[all,model]",
            "system.hw.cpu",
        ],
    )

    memory_total = get_item_value(
        index,
        [
            "vm.memory.size[total]",
        ],
    )

    memory_pused = get_item_value(
        index,
        [
            "vm.memory.utilization",
            "vm.memory.size[pused]",
        ],
    )

    if memory_pused is None:
        memory_pavailable = to_float(
            get_item_value(
                index,
                [
                    "vm.memory.size[pavailable]",
                ],
            )
        )

        if memory_pavailable is not None:
            memory_pused = str(
                max(
                    0.0,
                    min(
                        100.0,
                        100.0
                        - memory_pavailable,
                    ),
                )
            )

    operating_system = get_item_value(
        index,
        [
            "system.sw.os",
            "system.uname",
        ],
    )

    uptime = get_item_value(
        index,
        [
            "system.uptime",
        ],
    )

    disk = get_operating_system_disk(
        index
    )

    payload = {
        "id": str(device_id),

        FIELD_HOSTID: str(
            host["hostid"]
        ),

        FIELD_ZABBIX_STATUS: (
            "Monitorado"
            if str(
                host.get("status")
            ) == "0"
            else "Desabilitado"
        ),

        FIELD_LAST_SYNC: (
            datetime.now()
            .astimezone()
            .isoformat(
                timespec="seconds"
            )
        ),
    }

    if has_value(cpu_model):
        payload[FIELD_CPU_MODEL] = str(
            cpu_model
        )[:250]

    if has_value(cpu_cores):
        payload[FIELD_CPU_CORES] = str(
            cpu_cores
        )

    if has_value(cpu_usage):
        payload[FIELD_CPU_USAGE] = (
            format_percent(
                cpu_usage
            )
        )

    if has_value(memory_total):
        payload[FIELD_MEMORY_TOTAL] = (
            bytes_to_gib(
                memory_total
            )
        )

    if has_value(memory_pused):
        payload[FIELD_MEMORY_USAGE] = (
            format_percent(
                memory_pused
            )
        )

    if has_value(operating_system):
        payload[
            FIELD_OPERATING_SYSTEM
        ] = str(
            operating_system
        )[:500]

    if has_value(uptime):
        payload[FIELD_UPTIME] = (
            format_uptime(
                uptime
            )
        )

    if disk.get("filesystem"):
        payload[FIELD_DISK_NAME] = (
            disk["filesystem"]
        )

        if has_value(
            disk.get("total")
        ):
            payload[
                FIELD_DISK_TOTAL
            ] = bytes_to_gib(
                disk["total"]
            )

        if has_value(
            disk.get("pused")
        ):
            payload[
                FIELD_DISK_USAGE
            ] = format_percent(
                disk["pused"]
            )

    return payload


# ============================================================
# EXECUÇÃO PRINCIPAL
# ============================================================

def main():
    zabbix = ZabbixAPI()
    phpipam = PhpIPAMAPI()

    phpipam.authenticate()

    zabbix_hosts = zabbix.get_hosts()

    LOG.info(
        "Hosts encontrados no Zabbix: %d",
        len(zabbix_hosts),
    )

    host_index = build_host_index(
        zabbix_hosts
    )

    devices = phpipam.get_devices()

    LOG.info(
        "Devices encontrados no phpIPAM: %d",
        len(devices),
    )

    updated = 0
    skipped = 0
    failed = 0

    for device in devices:
        device_id = str(
            device.get(
                "id",
                "",
            )
        ).strip()

        device_name = (
            device.get("hostname")
            or device.get("name")
            or device.get("description")
            or device_id
            or "Device sem nome"
        )

        if not device_id:
            LOG.warning(
                "Device sem ID ignorado: %s",
                device_name,
            )

            failed += 1
            continue

        if not truthy(
            device.get(FIELD_SYNC)
        ):
            skipped += 1
            continue

        host = find_zabbix_host(
            device,
            host_index,
        )

        if not host:
            LOG.warning(
                "Device %s não possui "
                "correspondência no Zabbix",
                device_name,
            )

            failed += 1
            continue

        try:
            items = zabbix.get_items(
                str(
                    host["hostid"]
                )
            )

            payload = build_update_payload(
                device_id,
                host,
                items,
            )

            phpipam.update_device(
                payload
            )

            LOG.info(
                "Atualizado: "
                "phpIPAM=%s "
                "| Zabbix=%s "
                "| hostid=%s "
                "| campos=%d",
                device_name,
                host.get("host"),
                host.get("hostid"),
                len(payload) - 1,
            )

            updated += 1

        except Exception:
            LOG.exception(
                "Falha ao sincronizar %s",
                device_name,
            )

            failed += 1

    LOG.info(
        "Resumo: "
        "atualizados=%d "
        "ignorados=%d "
        "falhas=%d",
        updated,
        skipped,
        failed,
    )

    return 1 if failed else 0


# ============================================================
# INÍCIO
# ============================================================

if __name__ == "__main__":
    try:
        sys.exit(main())

    except KeyError as error:
        LOG.error(
            "Variável obrigatória ausente: %s",
            error,
        )

        sys.exit(2)

    except requests.exceptions.ConnectionError as error:
        LOG.error(
            "Falha de conexão com uma das APIs: %s",
            error,
        )

        sys.exit(1)

    except requests.exceptions.Timeout as error:
        LOG.error(
            "Timeout ao acessar uma das APIs: %s",
            error,
        )

        sys.exit(1)

    except Exception:
        LOG.exception(
            "Erro fatal na sincronização"
        )

        sys.exit(1)
```

---

# 16. Ajustar as permissões do script

```bash
sudo chown \
    zbxphpipam:zbxphpipam \
    /opt/zabbix-phpipam/bin/sync.py
```

```bash
sudo chmod 750 \
    /opt/zabbix-phpipam/bin/sync.py
```

---

# 17. Validar a sintaxe

```bash
sudo -u zbxphpipam \
    /opt/zabbix-phpipam/venv/bin/python \
    -m py_compile \
    /opt/zabbix-phpipam/bin/sync.py
```

Quando a sintaxe estiver correta, o comando não exibirá nenhuma mensagem.

---

# 18. Habilitar a sincronização em um Device

No phpIPAM, abra:

```text
Tools
→ Devices
→ docker-hml-lenovo-i5
→ Edit
```

Configure:

```text
Sincronizar_Zabbix: true
```

O campo abaixo pode ficar inicialmente vazio:

```text
Zabbix_HostID
```

O script tentará localizar o host por:

```text
HostID já cadastrado
Hostname
Nome do Device
Descrição
IP
DNS da interface do Zabbix
Nome curto
```

Depois de encontrar o host, o script grava automaticamente:

```text
Zabbix_HostID: 10819
```

Nas próximas execuções, o relacionamento será feito pelo `hostid`, que é mais seguro do que depender apenas do hostname.

---

# 19. Executar manualmente

```bash
sudo -u zbxphpipam bash -c '
set -a
source /etc/zabbix-phpipam.env
set +a

/opt/zabbix-phpipam/venv/bin/python \
    /opt/zabbix-phpipam/bin/sync.py
'
```

Resultado obtido no ambiente:

```text
INFO Hosts encontrados no Zabbix: ...
INFO Devices encontrados no phpIPAM: 3
INFO Atualizado: phpIPAM=docker-hml-lenovo-i5 | Zabbix=docker-hml.jmsalles.homelab.br | hostid=10819 | campos=...
INFO Resumo: atualizados=1 ignorados=2 falhas=0
```

A indicação:

```text
ignorados=2
```

significa que dois Devices não estão marcados com:

```text
Sincronizar_Zabbix: true
```

Isso é esperado.

---

# 20. Resultado esperado no phpIPAM

Exemplo:

```text
Sincronizar_Zabbix: true
Zabbix_HostID: 10819

CPU_Cores: 4
CPU_Uso_Pct: 2.71

Memoria_Total_GiB: 15.25
Memoria_Uso_Pct: 28.34

Disco_SO: /
Disco_SO_Total_GiB: valor coletado
Disco_SO_Uso_Pct: valor coletado

Sistema_Operacional: Linux version 6.12...
Uptime: 15d 03h 05m
Zabbix_Status: Monitorado
Ultima_Sincronizacao: 2026-06-14T22:45:06-03:00
```

O campo `CPU_Modelo` poderá permanecer vazio porque o template atual não coleta essa informação. O script não modifica o Zabbix e não apaga um valor manual existente.

---

# 21. Criar o serviço systemd

Crie:

```bash
sudo vim \
    /etc/systemd/system/zabbix-phpipam-sync.service
```

Conteúdo:

```ini
[Unit]
Description=Sincronização de inventário do Zabbix para o phpIPAM
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot

User=zbxphpipam
Group=zbxphpipam

EnvironmentFile=/etc/zabbix-phpipam.env

ExecStart=/opt/zabbix-phpipam/venv/bin/python /opt/zabbix-phpipam/bin/sync.py

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

---

# 22. Criar o timer systemd

Crie:

```bash
sudo vim \
    /etc/systemd/system/zabbix-phpipam-sync.timer
```

Conteúdo:

```ini
[Unit]
Description=Executa periodicamente a sincronização Zabbix para phpIPAM

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

Unit=zabbix-phpipam-sync.service

[Install]
WantedBy=timers.target
```

O script será executado:

```text
2 minutos após o boot
A cada 15 minutos
```

---

# 23. Habilitar o timer

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl enable --now \
    zabbix-phpipam-sync.timer
```

Validar:

```bash
systemctl status \
    zabbix-phpipam-sync.timer
```

Listar a próxima execução:

```bash
systemctl list-timers \
    zabbix-phpipam-sync.timer
```

---

# 24. Testar pelo systemd

Executar imediatamente:

```bash
sudo systemctl start \
    zabbix-phpipam-sync.service
```

Consultar o status:

```bash
systemctl status \
    zabbix-phpipam-sync.service
```

Consultar os logs:

```bash
journalctl \
    -u zabbix-phpipam-sync.service \
    -n 100 \
    --no-pager
```

Acompanhar em tempo real:

```bash
journalctl \
    -u zabbix-phpipam-sync.service \
    -f
```

---

# 25. Validar os itens utilizados

Para verificar o item de filesystems:

```bash
sudo -u zbxphpipam bash -c '
set -a
source /etc/zabbix-phpipam.env
set +a

curl -s \
    --cacert "$VERIFY_TLS" \
    --header "Content-Type: application/json-rpc" \
    --header "Authorization: Bearer $ZABBIX_TOKEN" \
    --data '"'"'{
        "jsonrpc": "2.0",
        "method": "item.get",
        "params": {
            "hostids": "10819",
            "output": [
                "name",
                "key_",
                "lastvalue",
                "lastclock",
                "units",
                "state",
                "error"
            ],
            "filter": {
                "key_": [
                    "vfs.fs.get"
                ]
            }
        },
        "id": 1
    }'"'"' \
    "$ZABBIX_URL" |
python3 -m json.tool
'
```

Para validar CPU e memória:

```bash
sudo -u zbxphpipam bash -c '
set -a
source /etc/zabbix-phpipam.env
set +a

curl -s \
    --cacert "$VERIFY_TLS" \
    --header "Content-Type: application/json-rpc" \
    --header "Authorization: Bearer $ZABBIX_TOKEN" \
    --data '"'"'{
        "jsonrpc": "2.0",
        "method": "item.get",
        "params": {
            "hostids": "10819",
            "output": [
                "name",
                "key_",
                "lastvalue",
                "lastclock",
                "units"
            ],
            "filter": {
                "key_": [
                    "system.cpu.num",
                    "system.cpu.util",
                    "vm.memory.size[total]",
                    "vm.memory.utilization",
                    "system.uname",
                    "system.uptime"
                ]
            }
        },
        "id": 1
    }'"'"' \
    "$ZABBIX_URL" |
python3 -m json.tool
'
```

---

# 26. Troubleshooting

## Falha de conexão com o Zabbix

Erro:

```text
No route to host
```

Validar DNS:

```bash
getent ahostsv4 \
    zabbix.jmsalles.homelab.br
```

O domínio deve apontar para:

```text
192.168.31.37
```

Validar a porta:

```bash
nc -vz -w 5 \
    192.168.31.37 \
    443
```

Validar o backend:

```bash
nc -vz -w 5 \
    192.168.31.35 \
    80
```

---

## phpIPAM retorna `SSL connection is required for API`

Isso ocorre quando a API é acessada diretamente por HTTP:

```text
http://192.168.31.37:8088
```

Utilize:

```text
https://ipam.jmsalles.homelab.br
```

---

## phpIPAM retorna `401 Unauthorized`

Confirme:

```text
App security: SSL with User token
```

E valide que o Nginx possui:

```nginx
proxy_set_header Authorization $http_authorization;
```

---

## phpIPAM retorna `Please provide token`

Acessar `/user/` pelo navegador realiza um `GET`, que espera um token existente.

A autenticação inicial deve utilizar:

```text
POST
HTTP Basic Authentication
```

Exemplo:

```bash
curl \
    --request POST \
    --user svc-zabbix-sync \
    https://ipam.jmsalles.homelab.br/api/zabbix-sync/user/
```

---

## Device não encontrado no Zabbix

Confirme:

```text
Sincronizar_Zabbix: true
```

Verifique se o IP do Device no phpIPAM corresponde à interface do host no Zabbix.

O relacionamento pode ser forçado preenchendo:

```text
Zabbix_HostID: ID numérico do host
```

---

## Disco não aparece

Confirme se o item existe e possui valor:

```text
vfs.fs.get
```

O script ignora itens com:

```text
lastclock = 0
```

Isso significa que o item ainda não recebeu nenhum valor.

---

## CPU_Modelo vazio

O template atual possui:

```text
system.cpu.num
system.cpu.util
```

Essas chaves informam quantidade e utilização, mas não o modelo físico do processador.

Como a decisão foi não alterar o Zabbix, esse campo permanecerá vazio, a menos que algum item existente passe a fornecer essa informação.

---

# 27. Segurança

Como credenciais foram utilizadas durante os testes, mantenha:

```text
/etc/zabbix-phpipam.env
```

com:

```text
Owner: root
Group: zbxphpipam
Permission: 640
```

Revogue e recrie qualquer credencial que tenha sido exibida em terminal compartilhado, imagem, documentação ou conversa:

```text
Token do Zabbix
Senha de svc-zabbix-sync
App Code do phpIPAM
Tokens temporários do phpIPAM
```

O token temporário do phpIPAM não precisa ser armazenado.

---

# 28. Fluxo final

```text
Zabbix 7.4.2
192.168.31.35
      │
      │ API JSON-RPC
      ▼
https://zabbix.jmsalles.homelab.br
Nginx 192.168.31.37
      │
      ▼
sync.py
Executado a cada 15 minutos
      │
      │ API REST
      ▼
https://ipam.jmsalles.homelab.br
phpIPAM 1.8.2
      │
      ▼
Campos personalizados dos Devices
```

A integração ficou unidirecional e não invasiva:

```text
Zabbix → phpIPAM
```

Nenhum item, template, agente ou configuração de monitoramento do Zabbix é alterado pelo script.
