#!/bin/bash
set -e

# this script creates a ubuntu VM which the current user's
# username and ssh public key.

# uncomment the following line to keep temp files
# skip_cleanup=1

# disk size, default to 4096 mb
disk_size=4096 # 4096 MB

# write default config, change if needed
cat <<EOF >vm.conf
kernel=vmlinux
initrd=initrd
cmdline=console=hvc0 irqfixup root=/dev/vda
cpu-count=4
memory-size=4096
disk=disk.img
cdrom=seed.iso
network=nat
EOF

arch="$(/usr/bin/uname -m)"

if [ "$arch" = "x86_64" ]; then
	arch="amd64"
fi

if [ ! -e ~/.ssh/id_rsa.pub ]; then
	echo "cannot find ~/.ssh/id_rsa.pub, stop" >&2
	exit 1
fi

# download files
if [ ! -e vmlinux ]; then
	if [ "$arch" = "amd64" ]; then
		/usr/bin/curl -C - -o vmlinux "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-$arch-vmlinuz-generic"
	else
		/usr/bin/curl -C - -o vmlinux.gz "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-$arch-vmlinuz-generic"
		gunzip vmlinux.gz
	fi
fi

if [ ! -e initrd ]; then
	/usr/bin/curl -C - -o initrd "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-$arch-initrd-generic"
fi

if [ ! -e disk.img ]; then
	/usr/bin/curl -C - -o disk.tar.gz "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-$arch.tar.gz"

	tar xzvf disk.tar.gz
	mv "focal-server-cloudimg-$arch.img" disk.img
	rm README
fi

# create cloudinit config
rm -f seed.iso

if [ ! -e iso_folder ]; then
	mkdir iso_folder
fi

cat <<EOF >iso_folder/meta-data
dsmode: local
EOF

cat <<EOF >iso_folder/network-config
version: 2
ethernets:
  enp0s1:
    addresses: [192.168.64.2/24]
    gateway4: 192.168.64.1
    nameservers:
      addresses: [1.1.1.1, 1.0.0.1]
EOF

cat <<EOF >iso_folder/user-data
#cloud-config
mounts:
  - [ 192.168.64.1:/System/Volumes/Data/Users, /Users, nfs, "auto,nofail,noatime,nolock,intr,tcp,actimeo=1800", 0, 0 ]
runcmd:
  - [ mount, -a ]
apt:
  conf: |
    Acquire::Check-Valid-Until "false";
    Acquire::Check-Date "false";
  sources:
    docker.list:
      source: deb [arch=$arch] https://download.docker.com/linux/ubuntu \$RELEASE stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg-agent
  - software-properties-common
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - nfs-common

# Enable ipv4 forwarding, required on CIS hardened machines
write_files:
  - path: /etc/sysctl.d/enabled_ipv4_forwarding.conf
    content: |
      net.ipv4.conf.all.forwarding=1
  - path: /etc/docker/daemon.json
    content: |
      {"hosts": ["tcp://0.0.0.0:2375", "unix:///var/run/docker.sock"]}
  - path: /etc/systemd/system/docker.service.d/override.conf
    content: |
      [Service]
       ExecStart=
       ExecStart=/usr/bin/dockerd

# create the docker group
groups:
  - docker

# Add default auto created user to docker group
system_info:
  default_user:
    groups: [docker]

users:
  - default
  - name: $USER
    lock_passwd: False
    gecos: $USER
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video, docker]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    ssh-authorized-keys: 
      - $(cat ~/.ssh/id_rsa.pub | head -n 1)
EOF

hdiutil makehybrid -iso -joliet -iso-volume-name cidata -joliet-volume-name cidata -o seed.iso iso_folder
# rm -rf iso_folder

# expand disk to 4GB
/bin/dd if=/dev/null of=disk.img bs=1m count=0 seek="$disk_size"

# perform clean up
if [ "$skip_cleanup" != "" ]; then
	exit 0
fi

if [ -e disk.tar.gz ]; then
	rm disk.tar.gz
fi
