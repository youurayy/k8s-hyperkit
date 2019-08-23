# Kubernetes Cluster on Hyperkit

Practice real Kubernetes configurations on a local multi-node cluster.

Tested on: Hyperkit 0.20190802 on macOS 10.14.5 w/ APFS, guest images Centos 1907 and Ubuntu 18.04.

<sub>For Hyper-V on Windows see [here](https://github.com/youurayy/k8s-hyperv).</sub>

## Changelog

Current state: pre-release; TODO: k8s helm setup

## Example usage:

```bash

# note: `sudo` is necessary for access to macOS Hypervisor and vmnet frameworks, and /etc/hosts config

# download the script
cd workdir
git clone git@github.com:youurayy/k8s-hyperkit.git && cd k8s-hyperkit
# ---- or -----
curl https://raw.githubusercontent.com/youurayy/k8s-hyperkit/master/hyperkit.sh -O
chmod +x hyperkit.sh

# display short synopsis for the available commands
./hyperkit.sh help
'
  Usage: ./hyperkit.sh command+

  Commands:

     install - install basic homebrew packages
      config - show script config vars
       print - print contents of relevant config files
         net - create or reset the vmnet config
        dhcp - append to the dhcp registry
       hosts - append node names to etc/hosts
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
      delete - delete the VM files
'

# performs `brew install hyperkit qemu kubernetes-cli kubernetes-helm`.
# (qemu is necessary for `qemu-img`)
# you may perform these manually / selectively instead.
./hyperkit.sh install

# display configured variables (edit the script to change them)
./hyperkit.sh config
'
    CONFIG: bionic
    DISTRO: ubuntu
    WORKDIR: ./tmp
 GUESTUSER: name
   SSHPATH: /Users/name/.ssh/id_rsa.pub
  IMAGEURL: https://cloud-images.ubuntu.com/releases/server/19.04/release/ubuntu-19.04-server-cloudimg-amd64.vmdk
  DISKFILE: ubuntu-19.04-server-cloudimg-amd64.raw
      CIDR: 10.10.0.0/24
      CPUS: 4
       RAM: 4GB
       HDD: 40GB
       CNI: flannel
    CNINET: 10.244.0.0/16
   CNIYAML: https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
'

# print external configs that this script can change
./hyperkit.sh print

# cleans or creates /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
# and sets the CIDR configured in the script.
# if other apps already use the vmnet framework, then you don't want to change it, in
# which case don't run this command, but instead set the CIDR inside this script
# to the value from the vmnet.plist (as shown by the 'print' command).
./hyperkit.sh net

# appends IPs and MACs from the NODES config to the /var/db/dhcpd_leases.
# this is necessary to have predictable IPs.
# (MACs are generated from UUIDs by the vmnet framework.)
./hyperkit.sh dhcp

# appends IP/hostname pairs from the NODES config to the /etc/hosts.
# (the same hosts entries will also be installed into every node)
./hyperkit.sh hosts

# download, prepare and cache the VM image templates
./hyperkit.sh image

# create/launch the nodes
./hyperkit.sh master
./hyperkit.sh node1
./hyperkit.sh nodeN...
# ---- or -----
./hyperkit.sh master node1 node2 nodeN...

# ssh to the nodes if necessary (e.g. for manual k8s init)
# by default, your `.ssh/id_rsa.pub` key was copied into the VMs' ~/.ssh/authorized_keys
# uses your host username (which is the default), e.g.:
ssh master
ssh node1
ssh node2
...

# performs automated k8s init (will wait for VMs to finish init first)
./hyperkit.sh init

# after init, you can do e.g.:
hyperctl get pods --all-namespaces
'
NAMESPACE     NAME                             READY   STATUS    RESTARTS   AGE
kube-system   coredns-5c98db65d4-b92p9         1/1     Running   1          5m31s
kube-system   coredns-5c98db65d4-dvxvr         1/1     Running   1          5m31s
kube-system   etcd-master                      1/1     Running   1          4m36s
kube-system   kube-apiserver-master            1/1     Running   1          4m47s
kube-system   kube-controller-manager-master   1/1     Running   1          4m46s
kube-system   kube-flannel-ds-amd64-6kj9p      1/1     Running   1          5m32s
kube-system   kube-flannel-ds-amd64-r87qw      1/1     Running   1          5m7s
kube-system   kube-flannel-ds-amd64-wdmxs      1/1     Running   1          4m43s
kube-system   kube-proxy-2p2db                 1/1     Running   1          5m32s
kube-system   kube-proxy-fg8k2                 1/1     Running   1          5m7s
kube-system   kube-proxy-rtjqv                 1/1     Running   1          4m43s
kube-system   kube-scheduler-master            1/1     Running   1          4m38s
'

# reboot the nodes
./hyperkit.sh reboot

# show info about existing VMs (size, run state)
./hyperkit.sh info
'
NAME    PID    %CPU  %MEM  RSS   STARTED  TIME     DISK  SPARSE  STATUS
master  36399  0.4   2.1   341M  3:51AM   0:26.30  40G   3.1G    RUNNING
node1   36418  0.3   2.1   341M  3:51AM   0:25.59  40G   3.1G    RUNNING
node2   37799  0.4   2.0   333M  3:56AM   0:16.78  40G   3.1G    RUNNING
'

# shutdown all nodes thru ssh
.\hyperv.ps1 shutdown

# start all nodes
.\hyperv.ps1 start

# stop all nodes
./hyperkit.sh stop

# force-stop all nodes
./hyperkit.sh kill

# delete all nodes' data (will not delete image templates)
./hyperkit.sh delete

# kill only a particular node
sudo kill -TERM 36418

# delete only a particular node
rm -rf ./tmp/node1/

# remove everything
sudo killall -9 hyperkit
rm -rf ./tmp

```

#### License: https://www.apache.org/licenses/LICENSE-2.0
