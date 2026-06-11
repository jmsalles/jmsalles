Perfeito. Então use o arquivo oficial `docker-compose.yml`, que é o modelo com MySQL no quickstart do OpenMetadata. O arquivo `docker-compose-postgres.yml` é somente para quem vai usar PostgreSQL. A documentação oficial do OpenMetadata orienta baixar os arquivos Compose diretamente das releases do GitHub e subir com `docker compose up -d`. ([OpenMetadata][1])

Abaixo está a parte ajustada do tutorial para MySQL.

# Ajuste do tutorial para usar MySQL

# 1. Criar o diretório

```bash
sudo mkdir -p /opt/openmetadata
sudo chown -R $USER:$USER /opt/openmetadata
cd /opt/openmetadata
```

# 2. Baixar o docker-compose.yml com MySQL

```bash
cd /opt/openmetadata

OM_TAG=$(curl -s https://api.github.com/repos/open-metadata/OpenMetadata/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

echo "Release detectada: ${OM_TAG}"
```

Agora baixe o arquivo Compose com MySQL:

```bash
curl -fSL -o docker-compose.yml "https://github.com/open-metadata/OpenMetadata/releases/download/${OM_TAG}/docker-compose.yml"
```

Valide se o arquivo foi baixado:

```bash
ls -lh /opt/openmetadata
```

# 3. Validar o Compose

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml config
```

Se não aparecer erro de sintaxe, pode subir.

# 4. Subir o OpenMetadata com MySQL

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml up -d
```

Acompanhe os containers:

```bash
docker compose -f docker-compose.yml ps
```

Ver logs:

```bash
docker compose -f docker-compose.yml logs -f
```

# 5. Validar containers

```bash
docker ps
```

Você deve ver containers semelhantes a estes:

```bash
openmetadata_server
openmetadata_ingestion
openmetadata_elasticsearch
openmetadata_mysql
```

Os nomes podem variar conforme a versão baixada.

# 6. Acessar o OpenMetadata

Acesse pelo navegador:

```bash
http://IP_DO_SERVIDOR:8585
```

Exemplo:

```bash
http://192.168.31.37:8585
```

Credenciais padrão do quickstart:

```bash
Usuário: admin@open-metadata.org
Senha: admin
```

# 7. Acessar o Airflow

```bash
http://IP_DO_SERVIDOR:8080
```

Credenciais padrão:

```bash
Usuário: admin
Senha: admin
```

# 8. Serviço systemd ajustado para MySQL

Crie o serviço:

```bash
sudo vim /etc/systemd/system/openmetadata.service
```

Conteúdo:

```ini
[Unit]
Description=OpenMetadata Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/openmetadata
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Recarregue e habilite:

```bash
sudo systemctl daemon-reload
sudo systemctl enable openmetadata.service
sudo systemctl start openmetadata.service
sudo systemctl status openmetadata.service
```

# 9. Comandos de operação com MySQL

Subir:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml up -d
```

Parar sem apagar dados:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml stop
```

Iniciar novamente:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml start
```

Reiniciar:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml restart
```

Ver status:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml ps
```

Ver logs:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml logs -f
```

Derrubar sem apagar volumes:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml down
```

Derrubar apagando volumes:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml down --volumes
```

Cuidado com `down --volumes`, pois ele remove os volumes Docker e pode apagar os dados persistidos.

# 10. Backup do MySQL

Primeiro identifique o nome exato do container MySQL:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

Crie o diretório de backup:

```bash
sudo mkdir -p /backup/openmetadata
sudo chown -R $USER:$USER /backup/openmetadata
```

Verifique as variáveis do container para confirmar usuário, senha e banco:

```bash
docker exec -it openmetadata_mysql env | egrep 'MYSQL|DB|DATABASE'
```

Exemplo de backup usando `mysqldump`, ajustando o nome do container e credenciais conforme o Compose:

```bash
docker exec openmetadata_mysql mysqldump -u openmetadata_user -p openmetadata_db > /backup/openmetadata/openmetadata-mysql-$(date +%F_%H%M).sql
```

Se o usuário for `root`:

```bash
docker exec openmetadata_mysql mysqldump -u root -p --all-databases > /backup/openmetadata/openmetadata-mysql-all-$(date +%F_%H%M).sql
```

Compactar:

```bash
gzip /backup/openmetadata/openmetadata-mysql-*.sql
```

# 11. Restore do MySQL

Descompactar o backup:

```bash
gunzip /backup/openmetadata/openmetadata-mysql-YYYY-MM-DD_HHMM.sql.gz
```

Copiar para dentro do container:

```bash
docker cp /backup/openmetadata/openmetadata-mysql-YYYY-MM-DD_HHMM.sql openmetadata_mysql:/tmp/openmetadata.sql
```

Restaurar:

```bash
docker exec -it openmetadata_mysql mysql -u openmetadata_user -p openmetadata_db < /tmp/openmetadata.sql
```

Se for dump completo com `--all-databases`:

```bash
docker exec -i openmetadata_mysql mysql -u root -p < /tmp/openmetadata.sql
```

Depois reinicie o ambiente:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml restart
```

# 12. Nginx opcional para MySQL

O Nginx não muda por causa do banco. Ele continua apontando para o OpenMetadata Server na porta `8585`.

```bash
sudo vim /etc/nginx/conf.d/openmetadata.jmsalles.homelab.br.conf
```
Sem ssl
Conteúdo: 

```nginx
server {
    listen 80;
    server_name openmetadata.jmsalles.homelab.br;

    access_log /var/log/nginx/openmetadata.access.log;
    error_log  /var/log/nginx/openmetadata.error.log;

    location / {
        proxy_pass http://192.168.31.37:8585;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 300s;
    }
}
```
Com ssl 
Conteúdo: 

```nginx
server {
    listen 80;
    server_name openmetadata.jmsalles.homelab.br;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name openmetadata.jmsalles.homelab.br;

    ssl_certificate     /etc/nginx/ssl/jmsalles.homelab.br.crt;
    ssl_certificate_key /etc/nginx/ssl/jmsalles.homelab.br.key;

    access_log /var/log/nginx/openmetada.jmsalles.homelab.br.access.log;
    error_log  /var/log/nginx/openmetada.jmsalles.homelab.br.error.log;

    client_max_body_size 512m;

    location / {
        proxy_pass http://192.168.31.23:8585;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
}

```
Testar:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Se o Nginx estiver em container:

```bash
docker compose exec nginx nginx -t
docker compose restart nginx
```

# 13. Resumo da mudança

Onde no tutorial anterior estava:

```bash
docker-compose-postgres.yml
```

Agora use:

```bash
docker-compose.yml
```

Onde estava:

```bash
docker compose -f docker-compose-postgres.yml up -d
```

Use:

```bash
docker compose -f docker-compose.yml up -d
```

A instalação com MySQL ficará assim:

```bash
cd /opt/openmetadata
docker compose -f docker-compose.yml up -d
```

Para o seu homelab, MySQL atende bem. Só recomendo manter backup periódico do banco e evitar remover volumes com `down --volumes` depois que começar a cadastrar conexões, usuários, glossários e metadados.

[1]: https://docs.open-metadata.org/v1.12.x/quick-start/local-docker-deployment?utm_source=chatgpt.com "Try OpenMetadata in Docker"
