
set -e

# brew install hyperkit qemu

BASEDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

IMAGE=ubuntu-18.04-server-cloudimg-amd64
KERNEL="$IMAGE-vmlinuz-generic"
INITRD="$IMAGE-initrd-generic"
IMAGEURL=http://cloud-images.ubuntu.com/releases/server/18.04/release

go_to_scriptdir()
{
cd $BASEDIR
}

download_image()
{
go_to_scriptdir
mkdir -p tmp && cd tmp
if ! [ -a $IMAGE.img ]; then
  curl $IMAGEURL/$IMAGE.img -O
  curl $IMAGEURL/unpacked/$KERNEL -O
  curl $IMAGEURL/unpacked/$INITRD -O
fi
}

create_machine()
{

if [ -z $UUID ] || [ -z $NAME ] || [ -z $CPUS ] || [ -z $RAM ] || [ -z $DISK ]; then
  echo "create_machine: invalid params"
  return
fi

go_to_scriptdir
mkdir -p tmp/$NAME && cd tmp/$NAME

mkdir -p cidata

cat << EOF > cidata/meta-data
instance-id: id-$NAME
local-hostname: $NAME
EOF

# tmp test init
cat << EOF > cidata/user-data
#cloud-config
password: test
chpasswd: { expire: False }
ssh_pwauth: True
EOF

cat << EOF > dummy
#cloud-config

mounts:
  - [ swap ]

groups:
  - docker

users:
  - name: $USER
    ssh_authorized_keys:
      - $(cat $HOME/.ssh/id_rsa.pub)
    sudo: [ 'ALL=(ALL) NOPASSWD:ALL' ]
    groups: [ sudo, docker ]
    shell: /bin/bash

write_files:
  - path: /etc/resolv.conf
    content: |
      nameserver 8.8.4.4
      nameserver 8.8.8.8
  - path: /etc/systemd/resolved.conf
    content: |
      [Resolve]
      DNS=8.8.4.4
      FallbackDNS=8.8.8.8
  - path: /etc/modules-load.d/bridge.conf
    content: |
      br_netfilter
  - path: /etc/sysctl.d/bridge.conf
    content: |
      net.bridge.bridge-nf-call-ip6tables = 1
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-arptables = 1

apt:
  sources:
    kubernetes:
      source: "deb http://apt.kubernetes.io/ kubernetes-xenial main"
      keyserver: "hkp://keyserver.ubuntu.com:80"
      keyid: BA07F4FB
      file: kubernetes.list

package_upgrade: true

packages:
  - linux-tools-virtual
  - linux-cloud-tools-virtual
  - docker.io
  - kubelet
  - kubectl
  - kubeadm

runcmd:
  # https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1766857
  - mkdir -p /usr/libexec/hypervkvpd && ln -s /usr/sbin/hv_get_dns_info /usr/sbin/hv_get_dhcp_info /usr/libexec/hypervkvpd
  - systemctl enable docker
  - systemctl enable kubelet

power_state:
  timeout: 10
  mode: poweroff

EOF

CMDLIN="earlyprintk=serial console=ttyS0 root=/dev/sda1"
ISO="cloud-init.iso"

rm -f $ISO
hdiutil makehybrid -iso -joliet -o $ISO cidata

RAW="$IMAGE.raw"

if ! [ -a $RAW ]; then
  echo Creating $(pwd)/$RAW
  qemu-img convert -O raw ../$IMAGE.img $RAW
  qemu-img resize -f raw $RAW $DISK
fi

# /var/db/dhcpd_leases
# /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist

sudo hyperkit -A \
  -U $UUID \
  -m $RAM \
  -c $CPUS \
  -s 0:0,hostbridge \
  -s 2:0,virtio-net \
  -s 31,lpc \
  -l com1,stdio \
  -s 1:0,ahci-hd,$(pwd)/$IMAGE.raw \
  -s 5,ahci-cd,$(pwd)/$ISO \
  -f "kexec,../$KERNEL,../$INITRD,$CMDLIN"

# TODO determine why this doesn't work on (encrypted) APFS / why aren't .raw images shrinking
# (may also be that deleted files aren't zeroes -- try to force zeroing of unlinked fs?)
# fcntl(F_PUNCHHOLE) failed: host filesystem does not support sparse files: Operation not permitted

# TODO redir to logfile
}

# TODO pre-change vmnet CIDR (w/ warning)
# TODO delete machine (kill first)
# TODO hosts gen

# TODO create-machine --> launch-machine ?
# TODO editable create/delete scripts which include hyperkit.sh ?

download_image

# use preset UUIDs to keep IP allocation across VM deletes
UUID=24AF0C19-3B96-487C-92F7-584C9932DD96 NAME=master CPUS=2 RAM=4G DISK=50G create_machine
#UUID=B0F97DC5-5E9F-40FC-B829-A1EF974F5640 NAME=node1 CPUS=2 RAM=4G DISK=50G create_machine
#UUID=0BD5B90C-E00C-4E1B-B3CF-117D6FF3C09F NAME=node2 CPUS=2 RAM=4G DISK=50G create_machine

go_to_scriptdir
# ls -lR tmp
