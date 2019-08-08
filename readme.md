# Kubernetes Cluster on Hyperkit

Practice real Kubernetes configurations on a local multi-node cluster.

Tested on: Hyperkit 0.20190802 on macOS 10.14.5 w/ APFS, guest images Ubuntu 18.04 and 19.04.

Start by reading the [hyperkit.sh](hyperkit.sh) script.

## Changelog

Current state: pre-release; TODO: k8s helm setup

## Example usage:

```bash

# download the script
cd workdir
git clone git@github.com:youurayy/k8s-hyperkit.git && cd k8s-hyperkit
# ---- or -----
curl https://raw.githubusercontent.com/youurayy/k8s-hyperkit/master/hyperkit.sh -O -
chmod +x hyperkit.sh

# examine and customize the script, e.g.:
code hyperkit.sh

# performs `brew install hyperkit qemu kubernetes-cli kubernetes-helm`.
# (qemu is necessary for `qemu-img`)
# you may perform these manually / selectively instead.
./hyperkit.sh install

# (optional)
# replaces /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist,
# while setting a new CIDR (by default 10.10.0.0/24) to avoid colliding with
# default CIDRs of Kubernetes Pod networking plugins (Calico etc.).
# (you should examine the vmnet.plist first to see if other apps are using it)
./hyperkit.sh create-vmnet

# (optional)
# only resets the CIDR in /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist,
# while perserving the contents (the file must exist / or is later auto-created).
./hyperkit.sh set-cidr

# (optional)
# updates /etc/hosts with currently configured CIDR;
# then you can use e.g. `ssh master` or `ssh node1` etc.
# note: if your Mac's vmnet was already used with this CIDR, you will need to
# adjust the /etc/hosts values manually (according to /var/db/dhcpd_leases).
./hyperkit.sh etc-hosts

# (optional)
# after changing your CIDR, you may want to prune the MAC address associations in
# the file /var/db/dhcpd_leases (the file must exist / or is later auto-created)
./hyperkit.sh clean-dhcp

# download, prepare and cache the VM image templates
./hyperkit.sh image

# launch the nodes
./hyperkit.sh master
./hyperkit.sh node1
./hyperkit.sh node2
# ---- or -----
./hyperkit.sh master node1 node2

# note: the initial cloud-config is set to power-down the nodes upon finish.
# use the 'info' command to see when the nodes finished initializing, and
# then run them again to setup k8s.
# you can disable this behavior by commenting out the powerdown in the cloud-init config.

# show info about existing VMs (size, run state)
./hyperkit.sh info

NAME    PID    %CPU  %MEM  RSS   STARTED  TIME     DISK  SPARSE  STATUS
master  36399  0.4   2.1   341M  3:51AM   0:26.30  40G   3.1G    RUNNING
node1   36418  0.3   2.1   341M  3:51AM   0:25.59  40G   3.1G    RUNNING
node2   37799  0.4   2.0   333M  3:56AM   0:16.78  40G   3.1G    RUNNING

# ssh to the nodes and install basic Kubernetes cluster here.
# IPs can be found in `/var/db/dhcpd_leases` mapped by MAC address.
# by default, your `.ssh/id_rsa.pub` key was copied into the VMs' ~/.ssh/authorized_keys
# (note: this works only after `./hyperkit.sh etc-hosts`, otherwise use IP addresses)
# use your host username (which is default), e.g.:
ssh master
ssh node1
ssh node2

# stop all nodes
./hyperkit.sh stop-all

# force-stop all nodes
./hyperkit.sh kill-all

# delete all nodes' data (will not delete image templates)
./hyperkit.sh delete-nodes

# delete only a particular node
rm -rf ./tmp/node1/

# remove everything
rm -rf ./tmp

```

#### License: https://www.apache.org/licenses/LICENSE-2.0
