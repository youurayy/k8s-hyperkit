#!/bin/bash
# For usage overview, read the readme.md at https://github.com/youurayy/k8s-hyperkit
# License: https://www.apache.org/licenses/LICENSE-2.0


# ---------------------------SETTINGS------------------------------------

WORKDIR="./tmp"
GUESTUSER=$USER
SSHPATH="$HOME/.ssh/id_rsa.pub"
if ! [ -a $SSHPATH ]; then
  echo -e "\\n please configure $sshpath or place a pubkey at $sshpath \\n"
  exit
fi
SSHPUB=$(cat $SSHPATH)

CONFIG=$(cat .distro 2> /dev/null)
CONFIG=${CONFIG:-"centos"}

case $CONFIG in
  bionic)
    DISTRO="ubuntu"
    VERSION="18.04"
    IMAGE="ubuntu-$VERSION-server-cloudimg-amd64"
    IMAGEURL="https://cloud-images.ubuntu.com/releases/server/$VERSION/release"
    SHA256FILE="SHA256SUMS"
    KERNDIR="unpacked"
    KERNEL="$IMAGE-vmlinuz-generic"
    INITRD="$IMAGE-initrd-generic"
    IMGTYPE="vmdk"
    ARCHIVE=
  ;;
  disco)
    DISTRO="ubuntu"
    VERSION="19.04"
    IMAGE="ubuntu-$VERSION-server-cloudimg-amd64"
    IMAGEURL="https://cloud-images.ubuntu.com/releases/server/$VERSION/release"
    SHA256FILE="SHA256SUMS"
    KERNDIR="unpacked"
    KERNEL="$IMAGE-vmlinuz-generic"
    INITRD="$IMAGE-initrd-generic"
    IMGTYPE="vmdk"
    ARCHIVE=""
  ;;
  centos)
    DISTRO="centos"
    VERSION="1907"
    IMAGE="CentOS-7-x86_64-GenericCloud-$VERSION"
    IMAGEURL="https://cloud.centos.org/centos/7/images"
    SHA256FILE="sha256sum.txt"
    KERNDIR=
    KERNURL="http://mirror.centos.org/centos/7/os/x86_64/Packages/kernel-3.10.0-957.el7.x86_64.rpm"
    KERNEL="vmlinuz-3.10.0-957.el7.x86_64"
    INITRD="$IMAGE-initrd-generic"
    IMGTYPE="raw"
    ARCHIVE=".tar.gz"
  ;;
esac

CIDR="10.10.0"
CMDLINE="earlyprintk=serial console=ttyS0 root=/dev/sda1" # root=LABEL=cloudimg-rootfs
ISO="cloud-init.iso"

CPUS=4
RAM=4GB
HDD=40GB

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
  mkdir -p $WORKDIR && cd $WORKDIR
  if true; then
  # if ! [ -a $IMAGE.$IMGTYPE ]; then
    # curl $IMAGEURL/$IMAGE.$IMGTYPE$ARCHIVE -O
    # shasum -a 256 -c <(curl -s $IMAGEURL/$SHA256FILE | grep "$IMAGE.$IMGTYPE$ARCHIVE")

    # if [ "$ARCHIVE" = ".tar.gz" ]; then
    #   tar xzf $IMAGE.$IMGTYPE$ARCHIVE
    # fi

    if [ -n "$KERNDIR" ]; then
      curl $IMAGEURL/$KERNDIR/$KERNEL -O
      curl $IMAGEURL/$KERNDIR/$INITRD -O
      shasum -a 256 -c <(curl -s $IMAGEURL/$KERNDIR/$SHA256FILE | grep "$KERNEL")
      shasum -a 256 -c <(curl -s $IMAGEURL/$KERNDIR/$SHA256FILE | grep "$INITRD")
    else

      # ls -l $IMAGE.$IMGTYPE
      # hdiutil attach -imagekey diskimage-class=CRawDiskImage -readonly -nomount $IMAGE.$IMGTYPE \
      # PART=$(cat testout \
      #   | tail -n 1 | awk '{ print $1 }')
      # echo "part: $PART"
      # mkdir -p mount
      # ext4fuse $PART $PWD/mount -o allow_other
      # fuse-xfs $PART -- $PWD/mount -o default_permissions,allow_other

      curl $KERNURL -O - | tar xzf - "./boot/$KERNEL"

      # tar tzf tmp/kernel-3.10.0-957.el7.x86_64.rpm './boot/vmlinuz*' | less

    fi
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
  mkdir -p $WORKDIR/$NAME && cd $WORKDIR/$NAME

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
  - name: $GUESTUSER
    ssh_authorized_keys:
      - '$SSHPUB'
    sudo: [ 'ALL=(ALL) NOPASSWD:ALL' ]
    groups: [ sudo, docker ]
    shell: /bin/bash
    # lock_passwd: false # passwd won't work without this
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

etc-hosts() {
cat << EOF | sudo tee -a /etc/hosts

$CIDR.2 master
$CIDR.3 node1
$CIDR.4 node2

EOF
}

create-vmnet() {
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

help() {
cat << EOF
  Practice real Kubernetes configurations on a local multi-node cluster.
  Inspect and optionally customize this script before use.

  Usage: ./hyperkit.sh command+

  Commands:

     install - install basic chocolatey packages
      config - show script config vars
       print - print contents of relevant config files
         net - create or reset the vmnet config
        cidr - update CIDR in the vmnet config
       hosts - append node names to etc/hosts
        dhcp - clean the dhcp registry
       image - download the VM image
      master - create and launch master node
       nodeN - create and launch worker node (node1, node2, ...)
        info - display info about nodes
        init - initialize k8s and setup host kubectl
      reboot - soft-reboot the nodes
    shutdown - soft-shutdown the nodes
        stop - stop the VMs
       start - start the VMs
        kill - force-stop the VMs
      delete - delete the VMs files

  For more info, see: https://github.com/youurayy/k8s-hyperkit
EOF
}

proc-list() {
  echo $1
  ps auxw | grep hyperkit
}

node-info() {
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
      brew cask install osxfuse
      brew install hyperkit qemu kubernetes-cli kubernetes-helm ext4fuse
    ;;
    config)
      echo "    CONFIG: $CONFIG"
      echo "    DISTRO: $DISTRO"
      echo "   WORKDIR: $WORKDIR"
      echo " GUESTUSER: $GUESTUSER"
      echo "   SSHPATH: $SSHPATH"
      echo "  IMAGEURL: $IMAGEURL/$IMAGE.$IMGTYPE$ARCHIVE"
      echo "  DISKFILE: $IMAGE.$FORMAT"
      echo "      CIDR: $CIDR"
      echo "      CPUS: $CPUS"
      echo "       RAM: $RAM"
      echo "       HDD: $HDD"
      echo "       CNI: $CNI"
      echo "    CNINET: $CNINET"
      echo "   CNIYAML: $CNIYAML"
    ;;
    print)
      sudo echo

      echo "***** com.apple.vmnet.plist *****"
      sudo cat /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist

      echo "***** /var/db/dhcpd_leases *****"
      cat /var/db/dhcpd_leases

      # TODO uuids
    ;;
    net)
      create-vmnet
    ;;
    cidr)
      sudo plutil \
        -replace Shared_Net_Address \
        -string $CIDR.1 \
        /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
    ;;
    hosts)
      etc-hosts
    ;;
    dhcp)
      echo | sudo tee /var/db/dhcpd_leases
    ;;
    image)
      download-image
    ;;
    master)
      UUID=24AF0C19-3B96-487C-92F7-584C9932DD96 NAME=master CPUS=$CPUS RAM=$RAM DISK=$HDD create-machine
    ;;
    node1)
      UUID=B0F97DC5-5E9F-40FC-B829-A1EF974F5640 NAME=node1 CPUS=$CPUS RAM=$RAM DISK=$HDD create-machine
    ;;
    node2)
      UUID=0BD5B90C-E00C-4E1B-B3CF-117D6FF3C09F NAME=node2 CPUS=$CPUS RAM=$RAM DISK=$HDD create-machine
    ;;
    info)
      go-to-scriptdir
      { echo -e 'NAME\tPID\t%CPU\t%MEM\tRSS\tSTARTED\tTIME\tDISK\tSPARSE\tSTATUS' &
      find $WORKDIR/* -maxdepth 0 -type d | while read node; do node-info "$node"; done } | column -ts $'\t'
    ;;
    stop)
      go-to-scriptdir
      sudo find $WORKDIR -name machine.pid -exec sh -c 'kill -TERM $(cat $1)' sh {} ';'
    ;;
    kill)
      go-to-scriptdir
      sudo find $WORKDIR -name machine.pid -exec sh -c 'kill -9 $(cat $1)' sh {} ';'
    ;;
    delete)
      go-to-scriptdir
      find $WORKDIR/* -maxdepth 0 -type d -exec rm -rf {} ';'
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
