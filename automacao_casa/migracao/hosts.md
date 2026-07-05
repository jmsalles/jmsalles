Dell  192.168.31.38
Roda a 
vm AD 192.168.31.24
Uso atual de Memoria 6G



lenovo-server-linux 192.168.31.31
Roda o serviço do tailscale que roteia minha rede


Roda NFS
 exportfs
/mnt/nfs        192.168.31.0/24
tree -L 2
.
├── awx
│   ├── awx-projects-claim
│   └── postgres-13-awx-postgres-13-0
├── lost+found
├── otobo2
│   ├── elastic-data
│   ├── mariadb-data
│   └── otobo-files
└── s

9 directories, 1 file
[root@lenovo-server-linux nfs]#


Mauquinas virtuais rodando
 virsh list --all
 Id   Nome                 Estado
---------------------------------------
 1    vm_k8s               executando
 2    k8s-w2               executando
 3    k8s-w1               executando
 4    rocky10_openshift    executando
 5    vm-lenovoi7-zabbix   executando
 6    k8s-cp1              executando

[root@lenovo-server-linux nfs]#
