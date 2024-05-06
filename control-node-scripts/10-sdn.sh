#!/bin/bash
set -e
. ~/kayobe.venv

chost="$(nodeattr -n control|head -1)"
tfcustom="$(nodeattr -v $chost tfcustom && echo True || echo False)"

source "$TF_VENV_PATH/bin/activate"
  ansible-playbook -i "$KOLLA_CONFIG_PATH/inventory" \
    -e config_file="$TF_CONFIG_PATH" \
    -e ansible_python_interpreter=$TF_VENV_PATH/bin/python \
    "$TF_SOURCE_PATH/playbooks/install_contrail.yml"
deactivate

source ~/kayobe.venv
  tf_net="$(kayobe configuration dump --hosts localhost --var tunnel_net_name|jq -r '.[]')"
  echo "FIXME2: Change iface name to vhost0, otherwise kolla-ansible will fail to find host ip"
  sed -i "s/${tf_net}_interface: .*/${tf_net}_interface: vhost0/" "$KAYOBE_CONFIG_PATH/inventory/group_vars/compute/network-interfaces"
deactivate

echo "Wait for vrouter kernel to compile on all nodes"
while true; do
  A="$(nodeattr -n "compute"|sort)"
  B="$(pdsh -g compute 'ip -o r s default dev vhost0'|awk -F: '/default/{print $1}'|sort)"
#  Fixme C executed with error on script
#  C=`comm -23 <(echo "$A") <(echo "$B")`
  if [ "$A" == "$B" ]; then
    break
  fi
  echo "Waiting for: "$A
  echo " already ready: "$B
#  echo " still waiting: "$C
  sleep 6
done
