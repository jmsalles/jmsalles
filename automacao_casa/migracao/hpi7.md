hpi7 192.168.31.36

[root@hpi7 jmsalles]# ip -br a
lo               UNKNOWN        127.0.0.1/8 ::1/128
eno1             UP
br0              UP             192.168.31.36/24 fe80::3e52:82ff:fe99:cdc6/64
vnet1            UNKNOWN        fe80::fc54:ff:fe6c:f941/64
vnet2            UNKNOWN        fe80::fc54:ff:fec9:1cee/64
vnet3            UNKNOWN        fe80::fc54:ff:fe8b:a78b/64
virbr0           DOWN           192.168.122.1/24
vnet4            UNKNOWN        fe80::fc54:ff:fec9:bc67/64
vnet5            UNKNOWN        fe80::fc54:ff:fefd:b0b1/64
vnet7            UNKNOWN        fe80::fc54:ff:fe4d:48ef/64
[root@hpi7 jmsalles]# free -h
               total        used        free      shared  buff/cache   available
Mem:            30Gi        21Gi       894Mi       638Mi       9,3Gi       9,1Gi
Swap:          7,8Gi       3,2Gi       4,6Gi
[root@hpi7 jmsalles]# df -hT
Sist. Arq.                 Tipo      Tam. Usado Disp. Uso% Montado em
/dev/mapper/rl-root        xfs        70G   11G   60G  15% /
devtmpfs                   devtmpfs  4,0M     0  4,0M   0% /dev
tmpfs                      tmpfs      16G     0   16G   0% /dev/shm
efivarfs                   efivarfs  150K   76K   70K  53% /sys/firmware/efi/efivars
tmpfs                      tmpfs     6,2G  640M  5,6G  11% /run
tmpfs                      tmpfs     1,0M     0  1,0M   0% /run/credentials/systemd-journald.service
/dev/mapper/dados-nfs--hml ext4      196G   28K  186G   1% /mnt/nfs-hml
/dev/mapper/dados-vms      ext4      492G   95G  372G  21% /mnt/vms
/dev/sda2                  xfs       960M  395M  566M  42% /boot
/dev/mapper/rl-home        xfs       159G  3,1G  156G   2% /home
/dev/sda1                  vfat      599M  8,4M  591M   2% /boot/efi
192.168.31.31:/mnt/nfs     nfs4      295G  759M  279G   1% /mnt/nfs-client
tmpfs                      tmpfs     1,0M     0  1,0M   0% /run/credentials/getty@tty1.service
tmpfs                      tmpfs     3,1G   48K  3,1G   1% /run/user/1000
[root@hpi7 jmsalles]# fdisk -l
Disk /dev/nvme0n1: 931,51 GiB, 1000204886016 bytes, 1953525168 sectors
Disk model: KINGSTON SNV3S1000G
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 5367608F-0B33-4CB5-B001-CAB6C66C9147

Device         Start        End    Sectors   Size Type
/dev/nvme0n1p1  2048 1953525134 1953523087 931,5G Linux LVM


Disk /dev/sda: 238,47 GiB, 256060514304 bytes, 500118192 sectors
Disk model: SSD
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 8ED5C397-12A6-4035-849C-0033A01C0691

Device       Start       End   Sectors   Size Type
/dev/sda1     2048   1230847   1228800   600M EFI System
/dev/sda2  1230848   3327999   2097152     1G Linux extended boot
/dev/sda3  3328000 500117503 496789504 236,9G Linux LVM


Disk /dev/mapper/rl-root: 70 GiB, 75161927680 bytes, 146800640 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/rl-swap: 7,81 GiB, 8388608000 bytes, 16384000 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/dados-vms: 500 GiB, 536870912000 bytes, 1048576000 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/dados-nfs--hml: 200 GiB, 214748364800 bytes, 419430400 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/mapper/rl-home: 159,07 GiB, 170804641792 bytes, 333602816 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
[root@hpi7 jmsalles]# virsh list accounts
accounts/  accounts,/
[root@hpi7 jmsalles]# virsh list
 Id   Nome              Estado
------------------------------------
 2    k8s_w2_HML        executando
 3    k8s_cp1_hm        executando
 4    haos              executando
 5    k8s_w1_hml        executando
 6    Minio             executando
 8    observabilidade   executando
