#!/bin/bash
# For usage overview, read the readme.md at https://github.com/youurayy/k8s-hyperkit
# License: https://www.apache.org/licenses/LICENSE-2.0


# ---------------------------SETTINGS------------------------------------

VERSION=18.04
# VERSION=19.04
IMAGE=ubuntu-$VERSION-server-cloudimg-amd64
IMAGEURL=https://cloud-images.ubuntu.com/releases/server/$VERSION/release
KERNEL="$IMAGE-vmlinuz-generic"
INITRD="$IMAGE-initrd-generic"
IMGTYPE="vmdk"
# IMGTYPE="img" # does not work; https://github.com/moby/hyperkit/issues/258

CIDR="10.10.0"
CMDLINE="earlyprintk=serial console=ttyS0 root=/dev/sda1" # root=LABEL=cloudimg-rootfs
ISO="cloud-init.iso"

FORMAT="raw"
FILEPREFIX=""
DISKOPTS=""

# FORMAT="qcow2"
# FILEPREFIX="file://"
# DISKOPTS=",format=qcow"

DISKDEV="ahci-hd"
# DISKDEV="virtio-blk"

# user for debug/tty:
# BACKGROUND=
# use for prod/ssh:
BACKGROUND='>> output.log 2>&1 &'

# ----------------------------------------------------------------------

set -e

BASEDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

go-to-scriptdir() {
  cd $BASEDIR
}

download-image() {
  go-to-scriptdir
  mkdir -p tmp && cd tmp
  if ! [ -a $IMAGE.$IMGTYPE ]; then
    curl $IMAGEURL/$IMAGE.$IMGTYPE -O
    curl $IMAGEURL/unpacked/$KERNEL -O
    curl $IMAGEURL/unpacked/$INITRD -O
    shasum -a 256 -c <(curl -s $IMAGEURL/SHA256SUMS | grep "$IMAGE.$IMGTYPE")
    shasum -a 256 -c <(curl -s $IMAGEURL/unpacked/SHA256SUMS | grep "$KERNEL")
    shasum -a 256 -c <(curl -s $IMAGEURL/unpacked/SHA256SUMS | grep "$INITRD")
  fi
}

is-machine-running() {
  ps -p $(cat $1/machine.pid 2> /dev/null) > /dev/null 2>&1
}

create-machine() {

  if [ -z $UUID ] || [ -z $NAME ] || [ -z $CPUS ] || [ -z $RAM ] || [ -z $DISK ]; then
    echo "create-machine: invalid params"
    return
  fi

  echo "starting machine $NAME"

  go-to-scriptdir
  mkdir -p tmp/$NAME && cd tmp/$NAME

  if is-machine-running ../$NAME; then
    echo "machine is already running!"
    return
  fi

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
    # lock_passwd: false
    # passwd: '\$6\$rounds=4096\$byY3nxArmvpvOrpV\$2M4C8fh3ZXx10v91yzipFRng1EFXTRNDE3q9PvxiPc3kC7N/NHG8HiwAvhd7QjMgZAXOsuBD5nOs0AJkByYmf/' # 'test'

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
  - docker.io
  - kubelet
  - kubectl
  - kubeadm

runcmd:
  - systemctl enable docker
  - systemctl enable kubelet

power_state:
  timeout: 10
  mode: poweroff
EOF

# write_files:
#   - path: /etc/apt/preferences.d/docker-pin
#     content: |
#       Package: *
#       Pin: origin download.docker.com
#       Pin-Priority: 600
# apt:
#   sources:
#     docker.list:
#       arches: amd64
#       source: "deb https://download.docker.com/linux/ubuntu bionic stable"
#       keyserver: "hkp://keyserver.ubuntu.com:80"
#       keyid: 0EBFCD88
# packages:
#  - docker-ce
#  - docker-ce-cli
#  - containerd.io

  rm -f $ISO
  hdiutil makehybrid -iso -joliet -o $ISO cidata

  DISKFILE="$IMAGE.$FORMAT"

  if ! [ -a $DISKFILE ]; then
    echo Creating $(pwd)/$DISKFILE
    qemu-img convert -O $FORMAT ../$IMAGE.$IMGTYPE $DISKFILE
    qemu-img resize -f $FORMAT $DISKFILE $DISK
  fi

cat << EOF > cmdline
hyperkit -A \
  -H \
  -U $UUID \
  -m $RAM \
  -c $CPUS \
  -s 0:0,hostbridge \
  -s 2:0,virtio-net \
  -s 31,lpc \
  -l com1,stdio \
  -s 1:0,$DISKDEV,$FILEPREFIX$(pwd)/$DISKFILE$DISKOPTS \
  -s 5,ahci-cd,$(pwd)/$ISO \
  -f "kexec,../$KERNEL,../$INITRD,$CMDLINE" $BACKGROUND
echo \$! > machine.pid
EOF

chmod +x cmdline
cat cmdline
sudo ./cmdline

if [ -z "$BACKGROUND" ]; then
  rm -f machine.pid
else
  echo "started PID $(cat machine.pid)"
fi
}

etc-hosts()
{
cat << EOF | sudo tee -a /etc/hosts

$CIDR.2 master
$CIDR.3 node1
$CIDR.4 node2

EOF
}

create-vmnet()
{
cat << EOF | sudo tee /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Shared_Net_Address</key>
  <string>$CIDR.1</string>
  <key>Shared_Net_Mask</key>
  <string>255.255.255.0</string>
</dict>
</plist>
EOF
}

help()
{
  echo
  echo "Practice real Kubernetes configurations on a local multi-node cluster."
  echo "Inspect and optionally customize this script before use."
  echo
  echo "Usage: ./hyperkit.sh [ install | create-vmnet | cidr | hosts | clean-dhcp | image "
  echo "        master | node1 | node2 | info | stop | kill | delete ]+"
  echo
  echo "For more info, see: https://github.com/youurayy/k8s-hyperkit"
  echo
}

proc-list()
{
  echo $1
  ps auxw | grep hyperkit
}

node-info()
{
  if is-machine-running $1; then
    etc=$(ps uxw -p $(cat $1/machine.pid 2> /dev/null) 2> /dev/null | tail -n 1 | awk '{ printf("%s\t%s\t%s\t%s\t%s\t%s", $2, $3, $4, int($6/1024)"M", $9, $10); }')
  else
    etc='-\t-\t-\t-\t-\t-'
  fi
  name=$(basename $1)
  disk=$(ls -lh $1/*.$FORMAT | awk '{print $5}')
  sparse=$(du -h $1/*.$FORMAT | awk '{print $1}')
  status=$(if is-machine-running $1; then echo "RUNNING"; else echo "NOT RUNNING"; fi)
  echo -e "$name\\t$etc\\t$disk\\t$sparse\\t$status"
}

echo

if [ $# -eq 0 ]; then help; fi

for arg in "$@"; do
  case $arg in
    install)
      brew install hyperkit qemu kubernetes-cli kubernetes-helm
    ;;
    config)
      # TODO
    ;;
    net)
      create-vmnet
    ;;
    cidr)
      sudo plutil \
        -replace Shared_Net_Address \
        -string $CIDR.1 \
        /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
      sudo cat /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
    ;;
    hosts)
      etc-hosts
    ;;
    clean-dhcp)
      echo | sudo tee /var/db/dhcpd_leases
    ;;
    image)
      download-image
    ;;
    master)
      UUID=24AF0C19-3B96-487C-92F7-584C9932DD96 NAME=master CPUS=2 RAM=4G DISK=40G create-machine
    ;;
    node1)
      UUID=B0F97DC5-5E9F-40FC-B829-A1EF974F5640 NAME=node1 CPUS=2 RAM=4G DISK=40G create-machine
    ;;
    node2)
      UUID=0BD5B90C-E00C-4E1B-B3CF-117D6FF3C09F NAME=node2 CPUS=2 RAM=4G DISK=40G create-machine
    ;;
    stop)
      go-to-scriptdir
      sudo find tmp -name machine.pid -exec sh -c 'kill -TERM $(cat $1)' sh {} ';'
    ;;
    kill)
      go-to-scriptdir
      sudo find tmp -name machine.pid -exec sh -c 'kill -9 $(cat $1)' sh {} ';'
    ;;
    delete)
      go-to-scriptdir
      find ./tmp/* -maxdepth 0 -type d -exec rm -rf {} ';'
    ;;
    info)
      go-to-scriptdir
      { echo -e 'NAME\tPID\t%CPU\t%MEM\tRSS\tSTARTED\tTIME\tDISK\tSPARSE\tSTATUS' &
      find ./tmp/* -maxdepth 0 -type d | while read node; do node-info "$node"; done } | column -ts $'\t'
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

go-to-scriptdir
