Segue o procedimento direto para instalar Docker Engine no Rocky Linux 10 usando o repositório oficial. A documentação do Rocky Linux 10 orienta usar o repo `https://download.docker.com/linux/rhel/docker-ce.repo`, e o Docker já lista RHEL 10 como versão suportada para Docker Engine. ([Rocky Linux Docs][1]) ([Docker Documentation][2])

1. Atualizar o sistema

```bash
sudo dnf update -y
sudo reboot
```

2. Remover pacotes conflitantes, se existirem

A documentação oficial recomenda remover pacotes antigos/conflitantes antes de instalar o Docker Engine. ([Docker Documentation][2])

```bash
sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc
```

Observação: se você usa Podman nessa máquina, não execute essa remoção sem avaliar antes.

3. Instalar plugin do DNF

```bash
sudo dnf install -y dnf-plugins-core
```

4. Adicionar o repositório oficial do Docker para RHEL/Rocky 10

```bash
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
```

5. Instalar Docker Engine, containerd, Buildx e Docker Compose v2

O pacote `docker-compose-plugin` instala o comando moderno `docker compose`, sem hífen. ([Rocky Linux Docs][1])

```bash
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

6. Habilitar e iniciar o serviço

```bash
sudo systemctl enable --now docker
```

7. Validar o serviço

```bash
sudo systemctl status docker
```

```bash
sudo docker version
```

```bash
sudo docker compose version
```

8. Testar com container de validação

```bash
sudo docker run hello-world
```

9. Opcional: permitir seu usuário executar Docker sem sudo

A documentação do Rocky mostra essa etapa como opcional para adicionar o usuário ao grupo `docker`. ([Rocky Linux Docs][1])

```bash
sudo usermod -aG docker $USER
```

Depois faça logout/login ou execute:

```bash
newgrp docker
```

Teste sem sudo:

```bash
docker ps
```

10. Teste prático com Nginx

```bash
docker run -d --name teste-nginx -p 8080:80 nginx
```

```bash
curl http://localhost:8080
```

Para remover o teste:

```bash
docker rm -f teste-nginx
```

Se der erro no comando `dnf config-manager`, use este método alternativo criando o arquivo do repositório manualmente:

```bash
sudo curl -fsSL https://download.docker.com/linux/rhel/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
sudo dnf makecache
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

[1]: https://docs.rockylinux.org/10/gemstones/containers/docker/ "Docker - Install Engine - Documentation"
[2]: https://docs.docker.com/engine/install/rhel/ "Install Docker Engine on RHEL | Docker Docs"
