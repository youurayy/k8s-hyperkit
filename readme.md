# Kubernetes CLuster on Hyperkit

Practice real Kubernetes configurations on a local multi-node cluster.

Tested on: Hyperkit 0.20190802 on macOS 10.14.5 w/ APFS, guest images Ubuntu 18.04 and 19.04.

Start by reading the [hyperkit.sh](hyperkit.sh) script.

## Changelog

Current state: pre-release; solving https://github.com/moby/hyperkit/issues/258

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
# you may perform these manually / selectively instead.
./hyperkit.sh install

# (optional)
# replaces /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist,
# while setting a new CIDR (by default 10.10.0.0/24) to avoid colliding with
# defaults of Kubernetes Pod networking plugins.
# (you should examine the vmnet.plist first to see if other apps are using it)
./hyperkit.sh create-vmnet

# (optional)
# only resets the CIDR in /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist,
# while perserving the contents (the file must exist  / or is later auto-created).
./hyperkit.sh set-cidr

# (optional)
# after changing your CIDR, you may want to delete MAC address associations in
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

# show info about existing VMs (size, run state)
./hyperkit.sh info

# ssh to the nodes and install basic Kubernetes cluster here.
# IPs can be found in `/var/db/dhcpd_leases` mapped by MAC address.
# by default, your `.ssh/id_rsa.pub` key was copied into the VMs' ~/.ssh/authorized_keys
# use your host username, e.g.:
ssh $USER@10.10.0.2
ssh $USER@10.10.0.3
ssh $USER@10.10.0.4

# stop all nodes
./hyperkit.sh stop-all

# force-stop all nodes
./hyperkit.sh kill-all

# delete all nodes' data (will not delete image templates)
./hyperkit.sh delete-nodes

# remove everything
rm -rf ./tmp

```

#### License: https://www.apache.org/licenses/LICENSE-2.0
