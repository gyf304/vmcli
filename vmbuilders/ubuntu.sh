#!/bin/bash
set -e

# this script creates a ubuntu VM which the current user's
# username and ssh public key.

# uncomment the following line to keep temp files
# skip_cleanup=1

# disk size, default to 4096 mb
disk_size=4096 # 4096 MB

# write default config, change if needed
cat << EOF > vm.conf
kernel=vmlinux
initrd=initrd
cmdline=console=hvc0 irqfixup root=/dev/vda
cpu-count=1
memory-size=1024
disk=disk.img
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
/usr/bin/curl -o vmlinux.gz "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-$arch-vmlinuz-generic"
gunzip vmlinux.gz
fi

if [ ! -e initrd ]; then
/usr/bin/curl -o initrd "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-$arch-initrd-generic"
fi

if [ ! -e disk.tar.gz ]; then
/usr/bin/curl -o disk.tar.gz "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-$arch.tar.gz"
fi

tar xzvf disk.tar.gz
mv "focal-server-cloudimg-$arch.img" disk.img
rm README

# create cloudinit config
cat << EOF > user.yaml
users:
  - name: $USER
    lock_passwd: False
    gecos: $USER
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    ssh-authorized-keys: 
      - $(cat ~/.ssh/id_rsa.pub | head -n 1)
EOF

# boot into initramfs to modify the disk image
cat << EOFOUTER | expect | sed 's/[^[:print:]]//g'
set timeout 60
spawn vmcli -k vmlinux --initrd=initrd -d disk.img "--cmdline=console=hvc0 irqfixup"

expect "(initramfs) "
send -- "mkdir /mnt\r"
expect "(initramfs) "
send -- "mount /dev/vda /mnt\r"
expect "(initramfs) "
send -- "cat << EOF > /mnt/etc/cloud/cloud.cfg.d/99_user.cfg\r"
send [exec cat user.yaml]
send -- "\rEOF\r"
expect "(initramfs) "
send -- "chroot /mnt\r"
expect "# "
send -- "sudo apt-get remove -y irqbalance\r"
expect "# "
send -- "exit\r"
expect "(initramfs) "
send -- "umount /mnt\r"
expect "(initramfs) "
send -- "poweroff\r"
EOFOUTER

# expand disk to 4GB
/bin/dd if=/dev/null of=disk.img bs=1m count=0 seek="$disk_size"

# perform clean up
if [ "$skip_cleanup" != "" ]; then
	exit 0
fi

rm user.yaml
rm disk.tar.gz
