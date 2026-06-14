Segue o tutorial completo atualizado, já com o ajuste visual para o campo `URL` ficar mais limpo, largo e automático dentro dos cards.

# Guia completo: Virtualização Homelab com Nginx em container, página central e proxy reverso para Cockpit

# 1. Objetivo

Criar uma página web chamada `Virtualização Homelab`, hospedada no Nginx em container no host `docker-hml`, com acesso centralizado aos servidores do homelab.

A página principal responderá por:

```text
https://virtualizacao.jmsalles.homelab.br
```

Cada servidor terá uma entrada própria no Nginx, permitindo abrir o Cockpit sem precisar informar `:9090` no final da URL.

Acessos finais:

```text
Página central:
https://virtualizacao.jmsalles.homelab.br

Lenovo server linux:
https://virtualizacao-lenovo.jmsalles.homelab.br

hp-i7:
https://virtualizacao-hpi7.jmsalles.homelab.br

Dell:
https://virtualizacao-dell.jmsalles.homelab.br
```

# 2. Cenário utilizado

```text
Host Nginx / Docker HML:
docker-hml.jmsalles.homelab.br
192.168.31.37

Página central:
virtualizacao.jmsalles.homelab.br
192.168.31.37

Lenovo server linux:
virtualizacao-lenovo.jmsalles.homelab.br
Backend: 192.168.31.31:9090

hp-i7:
virtualizacao-hpi7.jmsalles.homelab.br
Backend: 192.168.31.36:9090

Dell:
virtualizacao-dell.jmsalles.homelab.br
Backend: 192.168.31.38:9090
```

# 3. Fluxo de acesso

```text
Navegador
  |
  | HTTPS 443
  |
Nginx container no docker-hml
  |
  | Proxy reverso interno
  |
Cockpit do servidor na porta 9090
```

# 4. Estrutura final dos arquivos

```text
/home/jmsalles/nginx/
├── conf.d/
│   ├── 00-websocket-map.conf
│   ├── virtualizacao.jmsalles.homelab.br.conf
│   └── virtualizacao-cockpit-proxy.conf
├── html/
│   └── virtualizacao/
│       ├── index.html
│       └── assets/
│           ├── css/
│           │   └── style.css
│           ├── js/
│           │   └── app.js
│           └── img/
│               ├── logo-virtualizacao.svg
│               ├── icon-lenovo.svg
│               ├── icon-hp.svg
│               ├── icon-dell.svg
│               └── icon-cockpit.svg
```

# 5. Criar ou ajustar as entradas DNS

Agora todos os nomes devem apontar para o Nginx, ou seja, para o host `docker-hml`.

No seu DNS do homelab, crie ou ajuste as entradas assim:

```text
virtualizacao          IN    A    192.168.31.37
virtualizacao-lenovo   IN    A    192.168.31.37
virtualizacao-hpi7     IN    A    192.168.31.37
virtualizacao-dell     IN    A    192.168.31.37
```

Resultado esperado:

```text
virtualizacao.jmsalles.homelab.br          -> 192.168.31.37
virtualizacao-lenovo.jmsalles.homelab.br   -> 192.168.31.37
virtualizacao-hpi7.jmsalles.homelab.br     -> 192.168.31.37
virtualizacao-dell.jmsalles.homelab.br     -> 192.168.31.37
```

Validar DNS:

```bash
dig virtualizacao.jmsalles.homelab.br +short
dig virtualizacao-lenovo.jmsalles.homelab.br +short
dig virtualizacao-hpi7.jmsalles.homelab.br +short
dig virtualizacao-dell.jmsalles.homelab.br +short
```

Resultado esperado:

```text
192.168.31.37
192.168.31.37
192.168.31.37
192.168.31.37
```

Também pode validar com:

```bash
nslookup virtualizacao.jmsalles.homelab.br
nslookup virtualizacao-lenovo.jmsalles.homelab.br
nslookup virtualizacao-hpi7.jmsalles.homelab.br
nslookup virtualizacao-dell.jmsalles.homelab.br
```

# 6. Criar as pastas da página

Execute no host `docker-hml`:

```bash
sudo mkdir -p /home/jmsalles/nginx/html/virtualizacao/assets/css
sudo mkdir -p /home/jmsalles/nginx/html/virtualizacao/assets/js
sudo mkdir -p /home/jmsalles/nginx/html/virtualizacao/assets/img
sudo mkdir -p /home/jmsalles/nginx/conf.d
```

Ajuste as permissões:

```bash
sudo chown -R root:root /home/jmsalles/nginx/html/virtualizacao
sudo chmod -R 755 /home/jmsalles/nginx/html/virtualizacao
```

# 7. Fazer backup caso já exista uma versão anterior

```bash
sudo cp /home/jmsalles/nginx/html/virtualizacao/index.html /home/jmsalles/nginx/html/virtualizacao/index.html.bkp.$(date +%F_%H%M) 2>/dev/null || true
sudo cp /home/jmsalles/nginx/html/virtualizacao/assets/css/style.css /home/jmsalles/nginx/html/virtualizacao/assets/css/style.css.bkp.$(date +%F_%H%M) 2>/dev/null || true
```

# 8. Criar a página index.html

Abra o arquivo:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/index.html
```

Cole o conteúdo abaixo:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Virtualização Homelab | Jeferson Salles</title>
  <link rel="stylesheet" href="assets/css/style.css?v=3">
  <link rel="icon" href="assets/img/logo-virtualizacao.svg" type="image/svg+xml">
</head>

<body>
  <main class="page">

    <section class="hero">
      <div class="hero-card">
        <img src="assets/img/logo-virtualizacao.svg" alt="Virtualização Homelab" class="logo">

        <div>
          <p class="eyebrow">JMSalles Homelab</p>
          <h1>Virtualização Homelab</h1>
          <p class="subtitle">
            Painel central para acesso rápido aos servidores físicos e consoles de administração do ambiente.
          </p>
        </div>
      </div>
    </section>

    <section class="info-bar">
      <div>
        <span class="info-label">DNS da página</span>
        <span class="info-value">virtualizacao.jmsalles.homelab.br</span>
      </div>

      <div>
        <span class="info-label">Host Nginx</span>
        <span class="info-value">docker-hml.jmsalles.homelab.br</span>
      </div>

      <div>
        <span class="info-label">Ambiente</span>
        <span class="info-value">Homelab / HML</span>
      </div>
    </section>

    <section class="cards">

      <article class="server-card">
        <div class="server-header">
          <div class="icon-box">
            <img src="assets/img/icon-lenovo.svg" alt="Lenovo">
          </div>
          <div>
            <h2>Lenovo server linux</h2>
            <p>Servidor principal Linux do homelab</p>
          </div>
        </div>

        <div class="server-details">
          <div class="url-row">
            <span>URL</span>
            <a class="url-value" href="https://virtualizacao-lenovo.jmsalles.homelab.br" target="_blank" rel="noopener noreferrer">
              virtualizacao-lenovo.jmsalles.homelab.br
            </a>
          </div>

          <div>
            <span>Backend</span>
            <strong>192.168.31.31:9090</strong>
          </div>

          <div>
            <span>Acesso</span>
            <strong>HTTPS 443 via Nginx</strong>
          </div>

          <div>
            <span>Console</span>
            <strong>Cockpit</strong>
          </div>
        </div>

        <div class="actions">
          <a href="https://virtualizacao-lenovo.jmsalles.homelab.br" target="_blank" rel="noopener noreferrer" class="btn primary">
            Abrir console
          </a>
          <button class="btn secondary" onclick="copyText('https://virtualizacao-lenovo.jmsalles.homelab.br')">
            Copiar link
          </button>
        </div>
      </article>

      <article class="server-card">
        <div class="server-header">
          <div class="icon-box">
            <img src="assets/img/icon-hp.svg" alt="HP">
          </div>
          <div>
            <h2>hp-i7</h2>
            <p>Servidor auxiliar / nó de virtualização</p>
          </div>
        </div>

        <div class="server-details">
          <div class="url-row">
            <span>URL</span>
            <a class="url-value" href="https://virtualizacao-hpi7.jmsalles.homelab.br" target="_blank" rel="noopener noreferrer">
              virtualizacao-hpi7.jmsalles.homelab.br
            </a>
          </div>

          <div>
            <span>Backend</span>
            <strong>192.168.31.36:9090</strong>
          </div>

          <div>
            <span>Acesso</span>
            <strong>HTTPS 443 via Nginx</strong>
          </div>

          <div>
            <span>Console</span>
            <strong>Cockpit</strong>
          </div>
        </div>

        <div class="actions">
          <a href="https://virtualizacao-hpi7.jmsalles.homelab.br" target="_blank" rel="noopener noreferrer" class="btn primary">
            Abrir console
          </a>
          <button class="btn secondary" onclick="copyText('https://virtualizacao-hpi7.jmsalles.homelab.br')">
            Copiar link
          </button>
        </div>
      </article>

      <article class="server-card">
        <div class="server-header">
          <div class="icon-box">
            <img src="assets/img/icon-dell.svg" alt="Dell">
          </div>
          <div>
            <h2>dell</h2>
            <p>Servidor Dell OptiPlex para serviços do homelab</p>
          </div>
        </div>

        <div class="server-details">
          <div class="url-row">
            <span>URL</span>
            <a class="url-value" href="https://virtualizacao-dell.jmsalles.homelab.br" target="_blank" rel="noopener noreferrer">
              virtualizacao-dell.jmsalles.homelab.br
            </a>
          </div>

          <div>
            <span>Backend</span>
            <strong>192.168.31.38:9090</strong>
          </div>

          <div>
            <span>Acesso</span>
            <strong>HTTPS 443 via Nginx</strong>
          </div>

          <div>
            <span>Console</span>
            <strong>Cockpit</strong>
          </div>
        </div>

        <div class="actions">
          <a href="https://virtualizacao-dell.jmsalles.homelab.br" target="_blank" rel="noopener noreferrer" class="btn primary">
            Abrir console
          </a>
          <button class="btn secondary" onclick="copyText('https://virtualizacao-dell.jmsalles.homelab.br')">
            Copiar link
          </button>
        </div>
      </article>

    </section>

    <section class="note">
      <img src="assets/img/icon-cockpit.svg" alt="Cockpit">
      <div>
        <h3>Observação</h3>
        <p>
          Os acessos aos servidores passam pelo Nginx em HTTPS 443 e são encaminhados internamente para o Cockpit na porta 9090.
        </p>
      </div>
    </section>

    <footer>
      <p>Criado por Jeferson Salles</p>
      <p>Homelab JMSalles • Virtualização • Linux • Docker • Nginx • Cockpit</p>
    </footer>

  </main>

  <div id="toast" class="toast">Link copiado</div>

  <script src="assets/js/app.js"></script>
</body>
</html>
```

# 9. Criar o CSS atualizado da página

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/css/style.css
```

Cole:

```css
:root {
  --bg-1: #07111f;
  --bg-2: #0d1f36;
  --card: rgba(255, 255, 255, 0.10);
  --card-border: rgba(255, 255, 255, 0.18);
  --text: #f4f7fb;
  --muted: #b8c7d9;
  --accent: #4fd1c5;
  --accent-2: #63b3ed;
  --shadow: 0 25px 70px rgba(0, 0, 0, 0.35);
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-height: 100vh;
  font-family: Arial, Helvetica, sans-serif;
  color: var(--text);
  background:
    radial-gradient(circle at top left, rgba(79, 209, 197, 0.22), transparent 30%),
    radial-gradient(circle at top right, rgba(99, 179, 237, 0.22), transparent 35%),
    linear-gradient(135deg, var(--bg-1), var(--bg-2));
}

body::before {
  content: "";
  position: fixed;
  inset: 0;
  background-image:
    linear-gradient(rgba(255, 255, 255, 0.035) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255, 255, 255, 0.035) 1px, transparent 1px);
  background-size: 42px 42px;
  pointer-events: none;
}

.page {
  width: min(1480px, calc(100% - 40px));
  margin: 0 auto;
  padding: 42px 0 28px;
  position: relative;
}

.hero {
  margin-bottom: 24px;
}

.hero-card {
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 34px;
  border: 1px solid var(--card-border);
  background: linear-gradient(135deg, rgba(255,255,255,0.14), rgba(255,255,255,0.06));
  border-radius: 28px;
  box-shadow: var(--shadow);
  backdrop-filter: blur(18px);
}

.logo {
  width: 110px;
  height: 110px;
  flex: 0 0 auto;
  filter: drop-shadow(0 18px 28px rgba(0,0,0,0.35));
}

.eyebrow {
  margin: 0 0 8px;
  color: var(--accent);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  font-size: 13px;
}

h1 {
  margin: 0;
  font-size: clamp(38px, 6vw, 68px);
  line-height: 1;
}

.subtitle {
  max-width: 760px;
  margin: 16px 0 0;
  color: var(--muted);
  font-size: 18px;
  line-height: 1.55;
}

.info-bar {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px;
  margin-bottom: 24px;
}

.info-bar > div {
  padding: 18px 20px;
  border: 1px solid var(--card-border);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.08);
  backdrop-filter: blur(14px);
}

.info-label {
  display: block;
  color: var(--muted);
  font-size: 13px;
  margin-bottom: 8px;
}

.info-value {
  display: block;
  font-size: 16px;
  overflow-wrap: anywhere;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
  gap: 22px;
}

.server-card {
  padding: 24px;
  border: 1px solid var(--card-border);
  border-radius: 26px;
  background: var(--card);
  box-shadow: var(--shadow);
  backdrop-filter: blur(18px);
  transition: transform 0.22s ease, border-color 0.22s ease, background 0.22s ease;
}

.server-card:hover {
  transform: translateY(-6px);
  border-color: rgba(79, 209, 197, 0.55);
  background: rgba(255, 255, 255, 0.14);
}

.server-header {
  display: flex;
  gap: 16px;
  align-items: center;
  margin-bottom: 22px;
}

.icon-box {
  width: 68px;
  height: 68px;
  border-radius: 20px;
  display: grid;
  place-items: center;
  background: linear-gradient(135deg, rgba(79,209,197,0.25), rgba(99,179,237,0.20));
  border: 1px solid rgba(255, 255, 255, 0.18);
}

.icon-box img {
  width: 42px;
  height: 42px;
}

h2 {
  margin: 0;
  font-size: 22px;
}

.server-header p {
  margin: 6px 0 0;
  color: var(--muted);
  line-height: 1.35;
}

.server-details {
  display: grid;
  gap: 10px;
  margin-bottom: 22px;
}

.server-details div {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border-radius: 14px;
  background: rgba(0, 0, 0, 0.18);
}

.server-details span {
  color: var(--muted);
  flex: 0 0 auto;
}

.server-details strong {
  font-weight: 600;
  text-align: right;
  overflow-wrap: anywhere;
  min-width: 0;
  font-size: 14px;
}

.url-row {
  flex-direction: column;
  align-items: flex-start !important;
}

.url-row span {
  margin-bottom: 6px;
}

.url-value {
  display: block;
  width: 100%;
  color: var(--accent);
  text-decoration: none;
  font-size: 14px;
  line-height: 1.35;
  text-align: left;
  overflow-wrap: anywhere;
  word-break: break-word;
}

.url-value:hover {
  text-decoration: underline;
}

.actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.btn {
  border: 0;
  border-radius: 14px;
  padding: 13px 14px;
  text-align: center;
  text-decoration: none;
  cursor: pointer;
  font-size: 15px;
  transition: transform 0.18s ease, opacity 0.18s ease;
}

.btn:hover {
  transform: translateY(-2px);
}

.primary {
  color: #04111f;
  background: linear-gradient(135deg, var(--accent), var(--accent-2));
}

.secondary {
  color: var(--text);
  background: rgba(255, 255, 255, 0.12);
  border: 1px solid rgba(255,255,255,0.16);
}

.note {
  display: flex;
  gap: 16px;
  align-items: center;
  margin-top: 24px;
  padding: 22px;
  border: 1px solid rgba(79,209,197,0.30);
  border-radius: 22px;
  background: rgba(79,209,197,0.08);
}

.note img {
  width: 48px;
  height: 48px;
}

.note h3 {
  margin: 0 0 6px;
}

.note p {
  margin: 0;
  color: var(--muted);
  line-height: 1.5;
}

footer {
  margin-top: 28px;
  text-align: center;
  color: var(--muted);
  font-size: 14px;
}

footer p {
  margin: 6px 0;
}

.toast {
  position: fixed;
  right: 22px;
  bottom: 22px;
  padding: 14px 18px;
  border-radius: 14px;
  background: rgba(4, 17, 31, 0.92);
  color: var(--text);
  border: 1px solid rgba(79,209,197,0.45);
  opacity: 0;
  transform: translateY(12px);
  pointer-events: none;
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.toast.show {
  opacity: 1;
  transform: translateY(0);
}

@media (max-width: 980px) {
  .cards {
    grid-template-columns: 1fr;
  }

  .info-bar {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .hero-card {
    flex-direction: column;
    text-align: center;
    padding: 26px;
  }

  .actions {
    grid-template-columns: 1fr;
  }

  .server-details div {
    flex-direction: column;
    align-items: flex-start;
  }

  .server-details strong {
    text-align: left;
  }
}
```

# 10. Criar o JavaScript

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/js/app.js
```

Cole:

```javascript
function copyText(text) {
  navigator.clipboard.writeText(text).then(function () {
    const toast = document.getElementById("toast");
    toast.classList.add("show");

    setTimeout(function () {
      toast.classList.remove("show");
    }, 1800);
  });
}
```

# 11. Criar os ícones SVG

# 11.1 Logo principal

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/img/logo-virtualizacao.svg
```

Cole:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240">
  <defs>
    <linearGradient id="g" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0%" stop-color="#4fd1c5"/>
      <stop offset="100%" stop-color="#63b3ed"/>
    </linearGradient>
  </defs>
  <rect width="240" height="240" rx="56" fill="#07111f"/>
  <circle cx="120" cy="120" r="82" fill="none" stroke="url(#g)" stroke-width="14"/>
  <rect x="68" y="76" width="104" height="62" rx="14" fill="url(#g)" opacity="0.92"/>
  <rect x="82" y="94" width="76" height="10" rx="5" fill="#07111f"/>
  <rect x="82" y="114" width="48" height="10" rx="5" fill="#07111f"/>
  <path d="M88 158h64M120 138v38" stroke="url(#g)" stroke-width="12" stroke-linecap="round"/>
</svg>
```

# 11.2 Ícone Lenovo

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/img/icon-lenovo.svg
```

Cole:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <rect x="18" y="22" width="84" height="58" rx="12" fill="#4fd1c5"/>
  <rect x="28" y="34" width="64" height="10" rx="5" fill="#07111f"/>
  <rect x="28" y="52" width="44" height="10" rx="5" fill="#07111f"/>
  <path d="M42 94h36M60 80v14" stroke="#63b3ed" stroke-width="9" stroke-linecap="round"/>
</svg>
```

# 11.3 Ícone HP

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/img/icon-hp.svg
```

Cole:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <circle cx="60" cy="60" r="44" fill="#63b3ed"/>
  <path d="M35 75V44h10v12h30V44h10v31H75V64H45v11H35z" fill="#07111f"/>
</svg>
```

# 11.4 Ícone Dell

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/img/icon-dell.svg
```

Cole:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <rect x="22" y="18" width="76" height="84" rx="18" fill="#4fd1c5"/>
  <circle cx="60" cy="42" r="9" fill="#07111f"/>
  <rect x="40" y="60" width="40" height="9" rx="4.5" fill="#07111f"/>
  <rect x="40" y="76" width="40" height="9" rx="4.5" fill="#07111f"/>
</svg>
```

# 11.5 Ícone Cockpit

Abra:

```bash
sudo vim /home/jmsalles/nginx/html/virtualizacao/assets/img/icon-cockpit.svg
```

Cole:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <rect x="16" y="24" width="88" height="62" rx="14" fill="#63b3ed"/>
  <path d="M32 47h18M32 63h36M32 79h50" stroke="#07111f" stroke-width="8" stroke-linecap="round"/>
  <circle cx="85" cy="46" r="8" fill="#4fd1c5"/>
</svg>
```

# 12. Criar o map para WebSocket no Nginx

O Cockpit precisa de suporte correto a WebSocket no proxy reverso.

Abra:

```bash
sudo vim /home/jmsalles/nginx/conf.d/00-websocket-map.conf
```

Cole:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

# 13. Criar a configuração da página principal

Abra:

```bash
sudo vim /home/jmsalles/nginx/conf.d/virtualizacao.jmsalles.homelab.br.conf
```

Cole:

```nginx
server {
    listen 80;
    server_name virtualizacao.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name virtualizacao.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/virtualizacao.jmsalles.homelab.br.access.log;
    error_log  /var/log/nginx/virtualizacao.jmsalles.homelab.br.error.log;

    location / {
        root /usr/share/nginx/html/virtualizacao;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(css|js|svg|png|jpg|jpeg|gif|ico)$ {
        root /usr/share/nginx/html/virtualizacao;
        expires 30d;
        add_header Cache-Control "public, no-transform";
        try_files $uri =404;
    }

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}
```

# 14. Criar as entradas Nginx para os três servidores

Abra:

```bash
sudo vim /home/jmsalles/nginx/conf.d/virtualizacao-cockpit-proxy.conf
```

Cole:

```nginx
server {
    listen 80;
    server_name virtualizacao-lenovo.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name virtualizacao-lenovo.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/virtualizacao-lenovo.access.log;
    error_log  /var/log/nginx/virtualizacao-lenovo.error.log;

    location / {
        proxy_pass https://192.168.31.31:9090;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header Origin https://$host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_redirect off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}

server {
    listen 80;
    server_name virtualizacao-hpi7.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name virtualizacao-hpi7.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/virtualizacao-hpi7.access.log;
    error_log  /var/log/nginx/virtualizacao-hpi7.error.log;

    location / {
        proxy_pass https://192.168.31.36:9090;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header Origin https://$host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_redirect off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}

server {
    listen 80;
    server_name virtualizacao-dell.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name virtualizacao-dell.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/virtualizacao-dell.access.log;
    error_log  /var/log/nginx/virtualizacao-dell.error.log;

    location / {
        proxy_pass https://192.168.31.38:9090;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header Origin https://$host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_redirect off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
```

# 15. Configurar Cockpit nos servidores

Essa etapa deve ser feita em cada servidor backend.

# 15.1 Lenovo server linux

No servidor `192.168.31.31`, abra:

```bash
sudo vim /etc/cockpit/cockpit.conf
```

Cole ou ajuste:

```ini
[WebService]
Origins = https://virtualizacao-lenovo.jmsalles.homelab.br
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
```

Reinicie o Cockpit:

```bash
sudo systemctl restart cockpit.socket
```

Valide:

```bash
sudo systemctl status cockpit.socket
```

# 15.2 hp-i7

No servidor `192.168.31.36`, abra:

```bash
sudo vim /etc/cockpit/cockpit.conf
```

Cole ou ajuste:

```ini
[WebService]
Origins = https://virtualizacao-hpi7.jmsalles.homelab.br
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
```

Reinicie:

```bash
sudo systemctl restart cockpit.socket
```

Valide:

```bash
sudo systemctl status cockpit.socket
```

# 15.3 Dell

No servidor `192.168.31.38`, abra:

```bash
sudo vim /etc/cockpit/cockpit.conf
```

Cole ou ajuste:

```ini
[WebService]
Origins = https://virtualizacao-dell.jmsalles.homelab.br
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
```

Reinicie:

```bash
sudo systemctl restart cockpit.socket
```

Valide:

```bash
sudo systemctl status cockpit.socket
```

# 16. Validar Cockpit nos servidores

Em cada servidor, valide se a porta 9090 está ativa:

```bash
sudo ss -lntp | grep 9090
```

Caso o Cockpit não esteja ativo:

```bash
sudo systemctl enable --now cockpit.socket
```

Liberar no firewall, se necessário:

```bash
sudo firewall-cmd --add-service=cockpit --permanent
sudo firewall-cmd --reload
```

Validar firewall:

```bash
sudo firewall-cmd --list-all
```

# 17. Validar se o Nginx alcança os backends

No host `docker-hml`, teste acesso direto aos Cockpits pela porta 9090:

```bash
curl -k -I https://192.168.31.31:9090
curl -k -I https://192.168.31.36:9090
curl -k -I https://192.168.31.38:9090
```

Também teste porta com `nc`:

```bash
nc -vz 192.168.31.31 9090
nc -vz 192.168.31.36 9090
nc -vz 192.168.31.38 9090
```

Caso não tenha `nc` instalado:

```bash
sudo dnf install -y nmap-ncat
```

# 18. Validar os arquivos criados

No host `docker-hml`, execute:

```bash
ls -lah /home/jmsalles/nginx/conf.d/
```

Resultado esperado:

```text
00-websocket-map.conf
virtualizacao.jmsalles.homelab.br.conf
virtualizacao-cockpit-proxy.conf
```

Validar a estrutura da página:

```bash
find /home/jmsalles/nginx/html/virtualizacao -type f -print
```

Resultado esperado:

```text
/home/jmsalles/nginx/html/virtualizacao/index.html
/home/jmsalles/nginx/html/virtualizacao/assets/css/style.css
/home/jmsalles/nginx/html/virtualizacao/assets/js/app.js
/home/jmsalles/nginx/html/virtualizacao/assets/img/logo-virtualizacao.svg
/home/jmsalles/nginx/html/virtualizacao/assets/img/icon-lenovo.svg
/home/jmsalles/nginx/html/virtualizacao/assets/img/icon-hp.svg
/home/jmsalles/nginx/html/virtualizacao/assets/img/icon-dell.svg
/home/jmsalles/nginx/html/virtualizacao/assets/img/icon-cockpit.svg
```

# 19. Validar configuração do Nginx

Execute:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

Resultado esperado:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Se estiver tudo certo, recarregue:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

# 20. Validar se o Nginx carregou as entradas

Execute:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -T | grep -E "server_name|proxy_pass|virtualizacao"
```

Você deve ver entradas como:

```text
server_name virtualizacao.jmsalles.homelab.br;
server_name virtualizacao-lenovo.jmsalles.homelab.br;
proxy_pass https://192.168.31.31:9090;
server_name virtualizacao-hpi7.jmsalles.homelab.br;
proxy_pass https://192.168.31.36:9090;
server_name virtualizacao-dell.jmsalles.homelab.br;
proxy_pass https://192.168.31.38:9090;
```

Validar o map do WebSocket:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -T | grep -A5 "map \$http_upgrade"
```

# 21. Testar a página central

Teste:

```bash
curl -k -I https://virtualizacao.jmsalles.homelab.br
```

Resultado esperado:

```text
HTTP/2 200
```

ou:

```text
HTTP/1.1 200 OK
```

Acesse no navegador:

```text
https://virtualizacao.jmsalles.homelab.br
```

# 22. Testar os acessos sem porta 9090

Teste cada entrada:

```bash
curl -k -I https://virtualizacao-lenovo.jmsalles.homelab.br
curl -k -I https://virtualizacao-hpi7.jmsalles.homelab.br
curl -k -I https://virtualizacao-dell.jmsalles.homelab.br
```

O retorno pode ser `200`, `301` ou `302`, dependendo do comportamento do Cockpit.

Acesse no navegador:

```text
https://virtualizacao-lenovo.jmsalles.homelab.br
```

```text
https://virtualizacao-hpi7.jmsalles.homelab.br
```

```text
https://virtualizacao-dell.jmsalles.homelab.br
```

# 23. Testar pela página principal

Acesse:

```text
https://virtualizacao.jmsalles.homelab.br
```

Clique nos cards:

```text
Lenovo server linux
hp-i7
dell
```

Os botões devem abrir:

```text
https://virtualizacao-lenovo.jmsalles.homelab.br
https://virtualizacao-hpi7.jmsalles.homelab.br
https://virtualizacao-dell.jmsalles.homelab.br
```

Sem precisar digitar `:9090`.

# 24. Limpar cache do navegador

Como o CSS foi atualizado e o arquivo tem cache, atualize a página com:

```text
CTRL + F5
```

Se ainda aparecer o layout antigo, valide se o HTML está usando:

```html
<link rel="stylesheet" href="assets/css/style.css?v=3">
```

Teste o CSS:

```bash
curl -k -I https://virtualizacao.jmsalles.homelab.br/assets/css/style.css?v=3
```

# 25. Troubleshooting

# 25.1 Erro 502 Bad Gateway

O erro `502 Bad Gateway` indica que o Nginx não conseguiu falar com o backend.

Teste do host `docker-hml`:

```bash
curl -k -I https://192.168.31.31:9090
curl -k -I https://192.168.31.36:9090
curl -k -I https://192.168.31.38:9090
```

Teste porta:

```bash
nc -vz 192.168.31.31 9090
nc -vz 192.168.31.36 9090
nc -vz 192.168.31.38 9090
```

Verifique Cockpit no servidor afetado:

```bash
sudo systemctl status cockpit.socket
```

Ative, se necessário:

```bash
sudo systemctl enable --now cockpit.socket
```

# 25.2 Erro de Origin no Cockpit

No servidor afetado, confira:

```bash
sudo cat /etc/cockpit/cockpit.conf
```

Exemplo Lenovo:

```ini
[WebService]
Origins = https://virtualizacao-lenovo.jmsalles.homelab.br
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For
```

Depois reinicie:

```bash
sudo systemctl restart cockpit.socket
```

Veja logs:

```bash
sudo journalctl -u cockpit.socket -u cockpit.service -n 100 --no-pager
```

# 25.3 Página carrega, mas login ou terminal não funciona

Esse comportamento normalmente indica problema com WebSocket.

Valide se o arquivo existe:

```bash
ls -lah /home/jmsalles/nginx/conf.d/00-websocket-map.conf
```

Valide se o Nginx carregou:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -T | grep -A5 "map \$http_upgrade"
```

Valide os headers:

```bash
grep -n "Upgrade\|Connection\|X-Forwarded-Proto\|Origin" /home/jmsalles/nginx/conf.d/virtualizacao-cockpit-proxy.conf
```

Revalide e recarregue:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

# 25.4 CSS ou imagens da página central não carregam

Validar arquivos:

```bash
find /home/jmsalles/nginx/html/virtualizacao -type f -print
```

Validar permissão:

```bash
sudo chmod -R 755 /home/jmsalles/nginx/html/virtualizacao
```

Testar CSS:

```bash
curl -k -I https://virtualizacao.jmsalles.homelab.br/assets/css/style.css?v=3
```

Testar logo:

```bash
curl -k -I https://virtualizacao.jmsalles.homelab.br/assets/img/logo-virtualizacao.svg
```

# 25.5 Warning do HTTP/2 no Nginx

Se aparecer:

```text
the "listen ... http2" directive is deprecated
```

Não use:

```nginx
listen 443 ssl http2;
```

Use:

```nginx
listen 443 ssl;
http2 on;
```

Depois valide:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -t
```

E recarregue:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx nginx -s reload
```

# 25.6 Ver logs do Nginx

Logs gerais do container:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml logs -f nginx
```

Logs específicos dentro do container:

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx tail -f /var/log/nginx/virtualizacao-lenovo.error.log
```

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx tail -f /var/log/nginx/virtualizacao-hpi7.error.log
```

```bash
docker compose -f /home/jmsalles/nginx/docker-compose.yml exec nginx tail -f /var/log/nginx/virtualizacao-dell.error.log
```

# 26. Checklist final

```text
[ ] DNS virtualizacao.jmsalles.homelab.br aponta para 192.168.31.37
[ ] DNS virtualizacao-lenovo.jmsalles.homelab.br aponta para 192.168.31.37
[ ] DNS virtualizacao-hpi7.jmsalles.homelab.br aponta para 192.168.31.37
[ ] DNS virtualizacao-dell.jmsalles.homelab.br aponta para 192.168.31.37

[ ] Pasta /home/jmsalles/nginx/html/virtualizacao criada
[ ] Arquivo index.html criado
[ ] Arquivo style.css criado
[ ] Arquivo app.js criado
[ ] Ícones SVG criados

[ ] Campo URL ajustado para bloco próprio nos cards
[ ] Cards usando layout automático com minmax(360px, 1fr)
[ ] Página ajustada para largura máxima de 1480px

[ ] Arquivo 00-websocket-map.conf criado
[ ] Arquivo virtualizacao.jmsalles.homelab.br.conf criado
[ ] Arquivo virtualizacao-cockpit-proxy.conf criado

[ ] cockpit.conf configurado no Lenovo
[ ] cockpit.conf configurado no hp-i7
[ ] cockpit.conf configurado no Dell

[ ] Cockpit ativo no Lenovo
[ ] Cockpit ativo no hp-i7
[ ] Cockpit ativo no Dell

[ ] Porta 9090 liberada nos três servidores
[ ] Nginx alcança 192.168.31.31:9090
[ ] Nginx alcança 192.168.31.36:9090
[ ] Nginx alcança 192.168.31.38:9090

[ ] nginx -t executado com sucesso
[ ] nginx -s reload executado com sucesso

[ ] Página principal abre em https://virtualizacao.jmsalles.homelab.br
[ ] Lenovo abre em https://virtualizacao-lenovo.jmsalles.homelab.br
[ ] hp-i7 abre em https://virtualizacao-hpi7.jmsalles.homelab.br
[ ] Dell abre em https://virtualizacao-dell.jmsalles.homelab.br
```

# 27. Resumo final dos acessos

```text
Página central:
https://virtualizacao.jmsalles.homelab.br

Lenovo server linux:
https://virtualizacao-lenovo.jmsalles.homelab.br

hp-i7:
https://virtualizacao-hpi7.jmsalles.homelab.br

Dell:
https://virtualizacao-dell.jmsalles.homelab.br
```

Criado por Jeferson Salles
LinkedIn: [https://www.linkedin.com/in/jmsalles/](https://www.linkedin.com/in/jmsalles/)
E-mail: [jefersonmattossalles@gmail.com](mailto:jefersonmattossalles@gmail.com)
GitHub: [https://github.com/jmsalles/](https://github.com/jmsalles/)

