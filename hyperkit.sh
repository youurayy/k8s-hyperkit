# Kubernetes Cluster on Hyper-V
# ---------------------------------
# Practice real Kubernetes configurations on a local multi-node cluster.
# Tested on: Hyperkit 0.20190802 on macOS 10.14.5 w/ APFS, guest images Ubuntu 18.04 and 19.04.

# - try background kill
# - try full cloud init
# - try go from zero

# PREPARATION
#
# brew install hyperkit qemu kubernetes-cli kubernetes-helm
#
#
#
#
#
#

# NOTE the DHCP database is stored in (i.e. clean it when changing CIDRs or MACs): /var/db/dhcpd_leases
# TODO fcntl(F_PUNCHHOLE) failed: host filesystem does not support sparse files: Operation not permitted
# TODO generate random MACs if not present and store in a side file (plutil)

set -e

BASEDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

VERSION=18.04
#VERSION=19.04
IMAGE=ubuntu-$VERSION-server-cloudimg-amd64
IMAGEURL=http://cloud-images.ubuntu.com/releases/server/$VERSION/release
KERNEL="$IMAGE-vmlinuz-generic"
INITRD="$IMAGE-initrd-generic"

CIDR="10.10.0.1"

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

echo "starting machine $NAME"

go_to_scriptdir
mkdir -p tmp/$NAME && cd tmp/$NAME

mkdir -p cidata

cat << EOF > cidata/meta-data
instance-id: id-$NAME
local-hostname: $NAME
EOF

# tmp test init
# cat << EOF > cidata/user-data
# #cloud-config
# password: test
# chpasswd: { expire: False }
# ssh_pwauth: True
# EOF

cat << EOF > cidata/user-data
#cloud-config

mounts:
  - [ swap ]

groups:
  - docker

users:
  - name: $USER
    ssh_authorized_keys:
      - '$(cat $HOME/.ssh/id_rsa.pub)'
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

# user for debug/tty:
BACKGROUND=
# use for prod/ssh:
# BACKGROUND='>> output.log 2>&1 &'

cat << EOF > cmdline
hyperkit -A \
  -H \
  -P \
  -U $UUID \
  -m $RAM \
  -c $CPUS \
  -s 0:0,hostbridge \
  -s 2:0,virtio-net \
  -s 31,lpc \
  -l com1,stdio \
  -s 1:0,ahci-hd,$(pwd)/$IMAGE.raw \
  -s 5,ahci-cd,$(pwd)/$ISO \
  -f "kexec,../$KERNEL,../$INITRD,$CMDLIN" $BACKGROUND
EOF
chmod +x cmdline

cat cmdline
sudo ./cmdline

if [ -z $BACKGROUND ]; then
  rm -f machine.pid
else
  echo $! > machine.pid
fi
}

create-vmnet()
{
cat << EOF | sudo tee /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Shared_Net_Address</key>
  <string>$CIDR</string>
  <key>Shared_Net_Mask</key>
  <string>255.255.255.0</string>
</dict>
</plist>
EOF
}

help()
{
  echo "use ./hyperkit.sh [install|create-vmnet|set-cidr|clean-dhcp]+"
  echo "use ./hyperkit.sh [master|node1|node2|stop-all|kill-all|delete-nodes|info]+"
}

proc_list()
{
  echo $1
  ps auxw | grep hyperkit
}

download_image

echo

if [ -z "$@" ]; then help; fi

for arg in "$@"; do
  case $arg in
    install)
      brew install hyperkit qemu kubernetes-cli kubernetes-helm
    ;;
    set-cidr)
      sudo plutil \
        -replace Shared_Net_Address \
        -string $CIDR \
        /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
      sudo cat /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
    ;;
    create-vmnet)
      create-vmnet
    ;;
    clean-dhcp)
      echo | sudo tee /var/db/dhcpd_leases
    ;;
    master)
      UUID=24AF0C19-3B96-487C-92F7-584C9932DD96 NAME=master CPUS=2 RAM=4G DISK=40G create_machine
    ;;
    node1)
      UUID=B0F97DC5-5E9F-40FC-B829-A1EF974F5640 NAME=node1 CPUS=2 RAM=4G DISK=40G create_machine
    ;;
    node2)
      UUID=0BD5B90C-E00C-4E1B-B3CF-117D6FF3C09F NAME=node2 CPUS=2 RAM=4G DISK=40G create_machine
    ;;
    stop-all)
      proc_list "before:"
      go_to_scriptdir
      sudo find tmp -name machine.pid -exec kill sh -c 'kill -SIGUSR1 $(cat $1)' sh {} ';'
      proc_list "after:"
    ;;
    kill-all)
      go_to_scriptdir
      proc_list "before:"
      sudo find tmp -name machine.pid -exec kill sh -c 'kill -9 $(cat $1)' sh {} ';'
      proc_list "after:"
    ;;
    delete-nodes)
      go_to_scriptdir
      cd tmp
      rm -rf master node1 node2
    ;;
    info)
      go_to_scriptdir
      find tmp -name '*.raw' -exec du -h {} ';'
      sudo find tmp -name machine.pid -exec sh -c 'echo $(dirname $1) is $(if kill -0 \
        $(cat $1) > /dev/null 2>&1; then echo "RUNNING"; else echo "NOT RUNNING"; fi)' sh {} ';'
    ;;
    help)
      help
    ;;
    *)
      echo "unknown argument: $arg (try 'help')"
    ;;
  esac
done

echo

go_to_scriptdir
# ls -lR tmp
