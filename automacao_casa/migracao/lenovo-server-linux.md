lenovo-server-linux 192.168.31.31


Roda o serviço do tailscale que roteia minha rede
 systemctl status tailscaled.service
● tailscaled.service - Tailscale node agent
     Loaded: loaded (/usr/lib/systemd/system/tailscaled.service; enabled; preset: disabled)
     Active: active (running) since Mon 2026-06-22 14:36:40 -03; 1 week 5 days ago
 Invocation: 3c87aa3360764ecaabc703f26cefeccc
       Docs: https://tailscale.com/docs/
   Main PID: 1256 (tailscaled)
     Status: "Connected; jefersonmattossalles@gmail.com; 100.127.218.112 fd7a:115c:a1e0::c101:da75"
      Tasks: 16 (limit: 406369)
     Memory: 156.5M (peak: 165.9M)
        CPU: 1h 39min 9.611s
     CGroup: /system.slice/tailscaled.service
             └─1256 /usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641

jul 05 09:42:44 lenovo-server-linux tailscaled[1256]: magicsock: derp-11 does not know about peer [nP7Oq], removing route
jul 05 09:42:44 lenovo-server-linux tailscaled[1256]: [RATELIMIT] format("magicsock: derp-%d does not know about peer %s, removing route")
jul 05 09:42:54 lenovo-server-linux tailscaled[1256]: [RATELIMIT] format("magicsock: derp-%d does not know about peer %s, removing route") (2 dropped)
jul 05 09:42:54 lenovo-server-linux tailscaled[1256]: magicsock: derp-11 does not know about peer [cMIuf], removing route
jul 05 09:42:54 lenovo-server-linux tailscaled[1256]: magicsock: derp-11 does not know about peer [nP7Oq], removing route
jul 05 09:42:54 lenovo-server-linux tailscaled[1256]: [RATELIMIT] format("magicsock: derp-%d does not know about peer %s, removing route")
jul 05 09:43:04 lenovo-server-linux tailscaled[1256]: [RATELIMIT] format("magicsock: derp-%d does not know about peer %s, removing route") (2 dropped)
jul 05 09:43:04 lenovo-server-linux tailscaled[1256]: magicsock: derp-11 does not know about peer [cMIuf], removing route
jul 05 09:43:05 lenovo-server-linux tailscaled[1256]: magicsock: derp-11 does not know about peer [nP7Oq], removing route
jul 05 09:43:05 lenovo-server-linux tailscaled[1256]: [RATELIMIT] format("magicsock: derp-%d does not know about peer %s, removing route")
[root@lenovo-server-linux nfs]#


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
