#!/bin/bash

unset SSH_AUTH_SOCK
export PDSH_RCMD_TYPE=ssh
export PDSH_SSH_ARGS_APPEND='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

if which cloud-init >/dev/null 2>&1; then
  echo "Wait for cloud-init to finnish"
  cloud-init status --wait
fi

if ! [ -f /root/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
  echo "Please copy common ssh key to /root/.ssh/id_rsa"
fi
ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa root@localhost

echo "Wait for cloud-init to finnish on all nodes"
while true; do
  A="$(nodeattr -n "~(control||pdsh_all_skip)"|sort)" #"
  B="$(pdsh -a -X control 'if which cloud-init >/dev/null 2>&1; then cloud-init status --wait; else echo status: done; fi'|awk -F: '/status: done/{print $1}'|sort)"
  C=`comm -23 <(echo "$A") <(echo "$B")`
  if [ "$A" == "$B" ]; then
    break
  fi
  echo "Waiting for: "$A
  echo " already ready: "$B
  echo " still waiting: "$C
  sleep 6
done

echo "Sharing ssh cluster user identities and inventory"
pdcp -a -X control /root/.ssh/* /root/.ssh/
pdcp -a -X control /etc/hosts /etc/hosts
pdcp -a -X control /etc/genders /etc/genders
pdsh -a -X control 'hostname -f'

echo "Accepting all ssh hostkeys"
echo -e "host *\n  StrictHostKeyChecking no\n" >> ~/.ssh/config
pdsh -a date
echo "Setting hostnames"
pdsh -a 'hostnamectl set-hostname %h'
