#!/bin/sh

unset SSH_AUTH_SOCK
vip=$(getent hosts head0|head -1|cut -d ' ' -f1|awk -F. 'OFS="." {print $1,$2,"1",$4}')
iface="$(nodeattr -v $chost iface)"

set -x

rm -rf ~/src ~/venvs
pdsh -a 'docker ps -a -q|xargs docker rm -f -v'
pdsh -a 'docker volume prune -a -f'
pdsh -a 'docker image ls -q|xargs docker image rm -f'
pdsh -a 'rm -rf /opt/kayobe/ /etc/kolla/ /etc/contrail/ /var/log/kolla /var/log/contrail /etc/kayobe'
pdsh -g compute 'rm -f /var/run/libvirt/libvirt-sock'
pdsh -g compute 'pkill -9 -f qemu-kvm'
pdsh -g compute 'pkill -9 -f qemu-system'
pdsh -g head ip a d $vip/32 dev $iface
