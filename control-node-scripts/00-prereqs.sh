#!/bin/sh

export PDSH_SSH_ARGS_APPEND='-o StrictHostKeyChecking=no'
echo "export PDSH_RCMD_TYPE=ssh" >/etc/profile.d/99-pdsh.sh
. /etc/profile.d/99-pdsh.sh

. /etc/os-release

case $ID in
  ubuntu)
    apt -y install strace tcpdump bind9-utils tmux git python3-virtualenv jq inotify-tools time pdsh docker.io docker-compose
    pdsh -a 'apt -y install strace tcpdump bind9-utils tmux git python3-virtualenv jq inotify-tools time pdsh docker.io docker-compose'
    pdcp -a -X control /root/.ssh/* /root/.ssh/
    ;;
  centos)
    dnf -y install epel-release strace tcpdump bind-utils tmux git python3-virtualenv jq time
    dnf -y install inotify-tools pdsh pdsh-rcmd-ssh pdsh-mod-genders
    pdsh -a dnf -y install epel-release strace tcpdump bind-utils tmux git python3-virtualenv jq time
    pdsh -a dnf -y install inotify-tools pdsh pdsh-rcmd-ssh pdsh-mod-genders
    pdcp -a -X control /root/.ssh/* /root/.ssh/
    pdsh -g compute 'dnf -y install  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel{,-core,-modules,-tools,-tools-libs}-4.18.0-193.28.1.el8_2.x86_64.rpm'
    pdsh -g compute 'a=`dnf repoquery --installonly --latest-limit=1 -q|grep -v 193.28.1.el8_2`; if [ -n "$a" ]; then rpm -evh $a; fi'
    ;;
  *)
    ;;
esac

chost="$(nodeattr -n control|head -1)"
if [ -z "$chost" ]; then
  echo "Example /etc/genders:"
  cat << EOF
control0 conutrol,os=wallaby,virt=kvm,iface=eth0,tf=R2011-latest,cacheimages
head0 head
compute0 compute
compute1 compute
compute2 compute
EOF
  exit 1
fi

if [ -z "$(getent ahostsv4 $chost|head -1|cut -d ' ' -f1)" ]; then
  echo "Example /etc/hosts:"
  cat << EOF
127.0.0.1 localhost

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts

10.0.213.143 control0
10.0.213.144 head0
10.0.213.146 compute0
10.0.213.145 compute1
10.0.213.148 compute2
EOF
  exit 2
fi
