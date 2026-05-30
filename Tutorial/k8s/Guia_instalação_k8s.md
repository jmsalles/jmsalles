

---

# 🧭 Guia completo — Kubernetes “puro” com kubeadm no Rocky Linux 10 (libvirt/KVM + LVM)

Este guia descreve **passo a passo** a criação de um ambiente Kubernetes puro, usando **libvirt + LVM** para as máquinas virtuais e **Rocky Linux 10 minimal** como sistema operacional.

A arquitetura proposta é:

* 1 nó **control-plane** com IP **192.168.31.40** e hostname **k8s-cp1**
* 2 nós **workers** com IPs **192.168.31.41** (**k8s-w1**) e **192.168.31.42** (**k8s-w2**)
* Faixa de IPs **192.168.31.43–192.168.31.49** reservada ao **MetalLB** para `Services` do tipo `LoadBalancer`
* Rede de Pods **10.244.0.0/16** e rede de Services interna **10.96.0.0/12**

O guia está dividido em:

1. **Host** (máquina física com libvirt + LVM)
2. **Todas as VMs** (control-plane e workers)
3. **Somente control-plane**
4. **Somente workers**

⚠️ **Atenção importantíssima:** Ao executar `kubeadm init`, serão exibidos um **token** e um **hash do certificado** (**discovery-token-ca-cert-hash**). É **obrigatório** **guardar ambos** imediatamente, pois eles serão usados nos **workers** com `kubeadm join` para ingressar no cluster. Sem eles, você não consegue juntar os workers; se perder, será necessário gerar novamente com `kubeadm token create` e obter o hash de CA.

---

## 1) Host (máquina física com libvirt + LVM)

### 1.1 Criar volumes LVM para as VMs no VG `vg_vms`

```bash
sudo lvcreate -L 60G -n k8s-cp1 vg_vms
sudo lvcreate -L 40G -n k8s-w1 vg_vms
sudo lvcreate -L 40G -n k8s-w2 vg_vms
sudo lvs vg_vms
```

### 1.2 Limpeza completa em caso de domínio existente ou disco em uso

```bash
virsh destroy k8s-cp1 >/dev/null || true
sudo wipefs -a /dev/vg_vms/k8s-cp1
sudo virsh undefine k8s-cp1 --nvram --managed-save --snapshots-metadata
```

> Repita, trocando nomes e caminhos, para `k8s-w1` e `k8s-w2` se necessário.

### 1.3 Criar as VMs com `virt-install` (ISO Rocky 10 minimal já disponível localmente)

#### 1.3.1 Control-plane

```bash
sudo virt-install \
  --name k8s-cp1 \
  --virt-type kvm \
  --osinfo detect=on,name=linux2024 \
  --memory 12288,maxmemory=24576 \
  --vcpus 4,maxvcpus=6 \
  --cpu host-passthrough,cache.mode=passthrough \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/dev/vg_vms/k8s-cp1,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --network bridge=br0,model=virtio \
  --graphics none \
  --location /var/lib/libvirt/images/iso/Rocky-10.0-x86_64-minimal.iso \
  --extra-args 'inst.text console=ttyS0,115200n8' \
  --boot uefi
```

#### 1.3.2 Worker 1

```bash
sudo virt-install \
  --name k8s-w1 \
  --virt-type kvm \
  --osinfo detect=on,name=linux2024 \
  --memory 8192,maxmemory=16384 \
  --vcpus 4,maxvcpus=4 \
  --cpu host-passthrough,cache.mode=passthrough \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/dev/vg_vms/k8s-w1,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --network bridge=br0,model=virtio \
  --graphics none \
  --location /var/lib/libvirt/images/iso/Rocky-10.0-x86_64-minimal.iso \
  --extra-args 'inst.text console=ttyS0,115200n8' \
  --boot uefi
```

#### 1.3.3 Worker 2

```bash
sudo virt-install \
  --name k8s-w2 \
  --virt-type kvm \
  --osinfo detect=on,name=linux2024 \
  --memory 8192,maxmemory=16384 \
  --vcpus 4,maxvcpus=4 \
  --cpu host-passthrough,cache.mode=passthrough \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/dev/vg_vms/k8s-w2,format=raw,bus=scsi,cache=none,io=native,discard=unmap \
  --network bridge=br0,model=virtio \
  --graphics none \
  --location /var/lib/libvirt/images/iso/Rocky-10.0-x86_64-minimal.iso \
  --extra-args 'inst.text console=ttyS0,115200n8' \
  --boot uefi
```

---

## 2) Todas as VMs (control-plane e workers)

### 2.1 Definir hostname exclusivo em cada VM

```bash
# No control-plane:
sudo hostnamectl set-hostname k8s-cp1

# No worker 1:
sudo hostnamectl set-hostname k8s-w1

# No worker 2:
sudo hostnamectl set-hostname k8s-w2
```

### 2.2 Configurar IP estático em cada VM com NetworkManager (ajuste o nome da conexão)

**Descobrir o nome da conexão de rede:**

```bash
nmcli con show
```

Se a conexão ativa se chamar, por exemplo, **“System eth0”** ou **“Wired connection 1”**, use esse nome **exatamente** nos comandos abaixo.

**No control-plane (k8s-cp1, 192.168.31.40/24, gateway 192.168.31.1):**

```bash
sudo nmcli con mod "System eth0" ipv4.method manual ipv4.addresses 192.168.31.40/24 ipv4.gateway 192.168.31.1 ipv4.dns "1.1.1.1 8.8.8.8"
sudo nmcli con up "System eth0"
```

**No worker 1 (k8s-w1, 192.168.31.41/24, gateway 192.168.31.1):**

```bash
sudo nmcli con mod "System eth0" ipv4.method manual ipv4.addresses 192.168.31.41/24 ipv4.gateway 192.168.31.1 ipv4.dns "1.1.1.1 8.8.8.8"
sudo nmcli con up "System eth0"
```

**No worker 2 (k8s-w2, 192.168.31.42/24, gateway 192.168.31.1):**

```bash
sudo nmcli con mod "System eth0" ipv4.method manual ipv4.addresses 192.168.31.42/24 ipv4.gateway 192.168.31.1 ipv4.dns "1.1.1.1 8.8.8.8"
sudo nmcli con up "System eth0"
```

> Se o nome não for “System eth0”, substitua pelo nome verdadeiro mostrado pelo `nmcli con show`.

### 2.3 Preencher `/etc/hosts` com todos os nós

```bash
sudo vim /etc/hosts
```

Conteúdo completo do arquivo:

```
127.0.0.1       localhost
192.168.31.40   k8s-cp1
192.168.31.41   k8s-w1
192.168.31.42   k8s-w2
```

### 2.4 Instalar pacotes básicos do sistema

```bash
sudo dnf -y update
sudo dnf -y install vim curl wget bash-completion socat conntrack iproute-tc jq lvm2 device-mapper-persistent-data nftables ebtables ethtool
```

### 2.5 Desabilitar **permanentemente** o SWAP

```bash
sudo swapoff -a
sudo vim /etc/fstab
```

No editor `vim`, **comente** a linha da entrada `swap`. Exemplo:

```
# /dev/mapper/rl-swap   swap   swap   defaults   0 0
```

Salvar e sair: pressione `Esc`, digite `:wq` e pressione `Enter`.

Validar:

```bash
swapon --show
free -h
```

A linha `Swap:` deve mostrar `0B` de uso e de total.

### 2.6 (Opcional, se desejar) Desabilitar SELinux

```bash
sudo setenforce 0 || true
sudo vim /etc/selinux/config
```

No arquivo, configure:

```
SELINUX=disabled
```

Salvar e sair. Um **reboot** garante a aplicação completa:

```bash
sudo reboot
```

> Faça o reboot de cada VM por vez, se optar por desabilitar SELinux. Após voltar, siga os próximos passos.

### 2.7 Carregar módulos de kernel e sysctl para Kubernetes

**Criar `/etc/modules-load.d/k8s.conf`:**

```bash
sudo vim /etc/modules-load.d/k8s.conf
```

Conteúdo:

```
overlay
br_netfilter
```

**Criar `/etc/sysctl.d/99-kubernetes.conf`:**

```bash
sudo vim /etc/sysctl.d/99-kubernetes.conf
```

Conteúdo:

```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

**Aplicar imediatamente:**

```bash
sudo sysctl --system
```

### 2.8 Instalar `containerd` via DNF (repositório Docker) e `runc` via binário oficial

**Adicionar repositório Docker e instalar `containerd.io`:**

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install containerd.io
```

**Instalar `runc` diretamente do projeto (última versão estável):**

```bash
curl -L -o runc.amd64 https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64
sudo install -m 755 runc.amd64 /usr/local/sbin/runc
runc --version
```

### 2.9 Configurar o `containerd` com `SystemdCgroup=true` e `pause:3.9`

**Gerar configuração e editar:**

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo vim /etc/containerd/config.toml
```

No editor `vim`, faça **dois ajustes**:

1. Em `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]`, assegure:

```
SystemdCgroup = true
```

2. Em `[plugins."io.containerd.grpc.v1.cri"]`, assegure:

```
sandbox_image = "registry.k8s.io/pause:3.9"
```

**Salvar e reiniciar o serviço:**

```bash
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable --now containerd
systemctl status containerd --no-pager
```

### 2.10 Instalar `kubelet`, `kubeadm` e `kubectl` do repositório oficial do Kubernetes (com **caminho correto da chave GPG — “opção 1”**)

**Criar o repositório com o caminho correto da chave (note o `repodata/repomd.xml.key`):**

```bash
sudo vim /etc/yum.repos.d/kubernetes.repo
```

Conteúdo completo:

```
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
```

**Atualizar cache e instalar os pacotes, habilitando o kubelet:**

```bash
sudo dnf clean all
sudo dnf makecache
sudo dnf -y install kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

### 2.11 Configurar o `firewalld`

**No nó control-plane (executar no control-plane):**

```bash
sudo firewall-cmd --add-port=6443/tcp --permanent        # API server
sudo firewall-cmd --add-port=2379-2380/tcp --permanent   # etcd
sudo firewall-cmd --add-port=10250/tcp --permanent       # kubelet
sudo firewall-cmd --add-port=10257/tcp --permanent       # controller-manager
sudo firewall-cmd --add-port=10259/tcp --permanent       # scheduler
sudo firewall-cmd --add-port=4789/udp --permanent        # Calico VXLAN
sudo firewall-cmd --reload
```

**Nos nós workers (executar em cada worker):**

```bash
sudo firewall-cmd --add-port=10250/tcp --permanent       # kubelet
sudo firewall-cmd --add-port=4789/udp --permanent        # Calico VXLAN
sudo firewall-cmd --reload
```

> Em laboratório é possível desativar o firewalld, se desejado (não recomendado para produção):
>
> ```bash
> sudo systemctl disable --now firewalld
> ```

### 2.12 Habilitar **autocompletar do kubectl** e definir **KUBECONFIG** em todas as VMs (control-plane e workers)

**Instalar o script de completion no diretório do sistema:**

```bash
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl >/dev/null
kubeadm completion bash | tee /etc/bash_completion.d/kubadm >/dev/null
```

**Ativar o autocompletar para o seu usuário (shell Bash):**

```bash
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc
```

> Se você usa outro shell (por exemplo `zsh`), troque para:
> `echo 'source <(kubectl completion zsh)' >> ~/.zshrc`

---

## 3) Somente no control-plane

### 3.1 (Opcional) Pré-baixar as imagens do Kubernetes para a versão exata dos binários

```bash
sudo kubeadm config images pull \
  --kubernetes-version v1.30.14 \
  --cri-socket unix:///run/containerd/containerd.sock
```

### 3.2 Inicializar o cluster com `kubeadm init` (versão 1.30.14)

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.31.40 \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --kubernetes-version v1.30.14 \
  --cri-socket unix:///run/containerd/containerd.sock
```

**Ação obrigatória:**
Assim que o comando terminar, **copie e guarde** com segurança:

* O **token** exibido (campo `--token ...`)
* O **hash do certificado** exibido (campo `--discovery-token-ca-cert-hash sha256:...`)

Exemplo do trecho que você deve **guardar**:

```
kubeadm join 192.168.31.40:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:111122223333444455556666777788889999aaaabbbbccccddddeeeeffff0000
```

> Se perder, gere novamente com:
>
> * `kubeadm token create --print-join-command`
> * Se precisar do hash separado:
>
>   ```bash
>   openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
>   openssl rsa -pubin -outform der 2>/dev/null | \
>   openssl dgst -sha256 -hex | sed 's/^.* //'
>   ```

### 3.3 Configurar `kubectl` para o usuário atual e definir **variável KUBECONFIG**

**Opção A — Usar o kubeconfig no diretório do usuário (recomendado):**

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

**Opção B — Usar o kubeconfig do sistema como root:**

```bash
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /root/.bashrc
source /root/.bashrc
```

### 3.4 Instalar a CNI (Calico)

```bash
curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml -o calico.yaml
sudo vim calico.yaml
kubectl apply -f calico.yaml
```

**Verificar o status até os pods de rede ficarem prontos:**

```bash
kubectl -n kube-system get pods -w
```

---

## 4) Somente nos workers

### 4.1 Ingressar os workers no cluster com o **token** e o **hash** que você guardou

**No worker 1 (k8s-w1):**

```bash
sudo kubeadm join 192.168.31.40:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --cri-socket unix:///run/containerd/containerd.sock
```

**No worker 2 (k8s-w2):**

```bash
sudo kubeadm join 192.168.31.40:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --cri-socket unix:///run/containerd/containerd.sock
```

**Verificar a entrada dos nós (rodar no control-plane):**

```bash
kubectl get nodes -o wide
```

---

## 5) Testes e componentes opcionais (executar no control-plane)

### 5.1 Teste rápido com `NodePort`

```bash
kubectl create deploy hello --image=nginx --replicas=2
kubectl expose deploy hello --port=80 --type=NodePort
kubectl get svc hello
```

**Acessar:**
Anote a porta `NodePort` mostrada (faixa 30000–32767) e acesse por `http://192.168.31.41:<PORTA>` ou `http://192.168.31.42:<PORTA>`.

### 5.2 Instalar Ingress NGINX (opcional)

```bash
curl -fsSL https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml -o ingress-nginx.yaml
sudo vim ingress-nginx.yaml
kubectl apply -f ingress-nginx.yaml
kubectl -n ingress-nginx get pods -w
```

### 5.3 Instalar MetalLB (opcional)

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
```

**Criar o pool de IPs e anúncio L2 para a faixa 192.168.31.43–192.168.31.49:**

```bash
sudo vim metallb-pool.yaml
```

Conteúdo completo:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.31.43-192.168.31.49
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lab-pool
```

Aplicar:

```bash
kubectl apply -f metallb-pool.yaml
```

**Testar um Service `LoadBalancer`:**

```bash
kubectl create deploy nginx-lb --image=nginx --replicas=2
kubectl expose deploy nginx-lb --port=80 --type=LoadBalancer
kubectl get svc nginx-lb -w
```

Quando o `EXTERNAL-IP` aparecer (por exemplo, **192.168.31.43**), acesse `http://192.168.31.43/`.

---

## 6) Portas e conectividade (referência completa)

**No control-plane:**

* **6443/tcp** — Kubernetes API Server
* **2379–2380/tcp** — etcd server e client API
* **10250/tcp** — Kubelet API
* **10257/tcp** — Controller Manager
* **10259/tcp** — Scheduler
* **4789/udp** — VXLAN (Calico, se usado)

**Nos workers:**

* **10250/tcp** — Kubelet API
* **4789/udp** — VXLAN (Calico, se usado)

**NodePort (acesso a serviços sem MetalLB):**

* **30000–32767/tcp** — Portas de NodePort

---

## 7) Observações finais estritamente operacionais

* Sempre **garanta** que **swap** esteja **desativado** em todos os nós, inclusive após reboots.
* Mantenha o `containerd` com `SystemdCgroup=true` e `sandbox_image = "registry.k8s.io/pause:3.9"`.
* **Guarde** o **token** e o **hash da CA** gerados pelo `kubeadm init`. Sem eles, não é possível executar o `kubeadm join` nos workers sem gerar novos.
* A variável **KUBECONFIG** deve estar configurada conforme a sua preferência (arquivo do usuário em `$HOME/.kube/config` ou `/etc/kubernetes/admin.conf` para root).
* O **autocompletar do kubectl** deve estar ativo via `bash-completion` e `kubectl completion bash` como mostrado.
* Caso precise recriar uma VM, use **exatamente** o bloco de **limpeza** com `virsh destroy`, `wipefs` e `virsh undefine` antes de reinstalar.
* A faixa do **MetalLB** **192.168.31.43–192.168.31.49** deve estar **fora** do DHCP e **sem conflitos** com outros hosts na LAN.
* O arquivo `/etc/hosts` deve ser **idêntico** em todas as VMs, e o `hostnamectl` deve ser **exclusivo** em cada uma.

---

**Fim do guia.**
