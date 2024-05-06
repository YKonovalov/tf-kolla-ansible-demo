#!/bin/sh
set -e

. ~/kayobe.venv


# speed up disk writes for testing only
pdsh -g head,compute 'echo "write back" |tee /sys/class/block/*da/queue/write_cache' ||:

chost="$(nodeattr -n compute|head -1)"
iface="$(pdsh -w $chost ip -o -4 route show to default | awk '{print $6}')"
iface="${iface:-eth0}"
echo "FIXME2: Change iface name to $iface, otherwise kolla-ansible will fail to find host ip"
sed -i "s/common_interface: .*/common_interface: $iface/" "$KAYOBE_CONFIG_PATH/inventory/group_vars/compute/network-interfaces"

pdsh -g compute 'ip -j r s default|jq -r ".[]|.dev=\"vhost0\"|[.dst,\"via\",.gateway,\"dev\",.dev]|@tsv"|xargs ip r r' ||:

kayobe overcloud host configure

echo "If we are running after tf vrouter already installed we should move default route back to vhost0"
pdsh -g compute 'ip -j r s default|jq -r ".[]|.dev=\"vhost0\"|[.dst,\"via\",.gateway,\"dev\",.dev]|@tsv"|xargs ip r r' ||:
