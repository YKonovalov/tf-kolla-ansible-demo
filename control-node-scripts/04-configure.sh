#!/bin/sh

. ~/kayobe.env
. /etc/os-release

resolve_host() {
  getent ahostsv4 $1|head -1|cut -d ' ' -f1
}


chost="$(nodeattr -n control|head -1)"
os="$(nodeattr -v $chost os)"
tf="$(nodeattr -v $chost tf)"
virt="$(nodeattr -v $chost virt)"
iface="$(nodeattr -v $chost iface)"
tfcustom="$(nodeattr -v $chost tfcustom && echo true || echo false)"
usevip="$(nodeattr -v $chost usevip && echo true || echo false)"
cacheimages="$(nodeattr -v $chost cacheimages && echo true || echo false)"
vip=$(getent hosts head0|head -1|cut -d ' ' -f1|awk -F. 'OFS="." {print $1,$2,"1",$4}')

os="${os:-wallaby}"
tf="${tf:-latest}"
virt="${virt:-kvm}"
iface="${iface:-eth0}"

hhost="$(nodeattr -n head|head -1)"
head_ip=$(resolve_host $hhost)
supported_os="
ussuri
victoria
wallaby
xena
yoga
zed
2023.1
2023.2
"
is_after_xena=`echo "$supported_os"|grep -v '^$'|sed -n "/xena/,$ p"|grep $os`

if [ "$usevip" == "true" ]; then
  vip=$(getent hosts head0|head -1|cut -d ' ' -f1|awk -F. 'OFS="." {print $1,$2,"1",$4}')
else
  vip=$head_ip
fi

docker_registry=""
if [ "$cacheimages" == "true" ]; then
  docker_registry="$chost:4000"
fi

tf_docker_registry="$docker_registry"
tf_namespace=
if [ "$tfcustom" == "true" ]; then
  rhost="$(nodeattr -n build|head -1)"
  rport="$(nodeattr -v $rhost docker_registry_listen_port)"
  tf_docker_registry="$rhost:$rport"
else
  tf_namespace=tungstenfabric
fi

echo "
os $os
tf $tf
virt $virt
iface $iface
docker_registry $docker_registry
tf_docker_registry $tf_docker_registry
is_after_xena $is_after_xena
usevip $usevip
"|column -t

mkdir -p "$KAYOBE_CONFIG_PATH/inventory/group_vars/"{seed,controllers,compute,overcloud} "$KAYOBE_CONFIG_PATH/kolla" "$(dirname "$TF_CONFIG_PATH")"

cat > "$KAYOBE_CONFIG_PATH/inventory/groups" << EOF
[seed]
[controllers]
[compute]

[overcloud:children]
controllers
compute

[docker:children]
seed
controllers
compute

[docker-registry:children]
seed

[container-image-builders:children]
seed

[ntp:children]
seed
overcloud

# we don't use network group yet, but playbooks fail unless we define it:
[network:children]
controllers
[storage]
[monitoring]
EOF

cat > "$KAYOBE_CONFIG_PATH/network-allocation.yml" << EOF
common_ips:
`nodeattr -n "control||head||compute"|while read name; do echo " $name: $(resolve_host $name)"; done`
EOF

cat > "$KAYOBE_CONFIG_PATH/inventory/hosts" << EOF
localhost ansible_connection=local config_file=../tf.yml
[seed]
$chost ansible_connection=local
EOF

cat > "$KAYOBE_CONFIG_PATH/inventory/overcloud" << EOF
[controllers]
`nodeattr -n head   |awk '{print $0, "ansible_host="$0}'`
[compute]
`nodeattr -n compute|awk '{print $0, "ansible_host="$0}'`
EOF

tee "$KAYOBE_CONFIG_PATH/inventory/group_vars"/{seed,controllers}/network-interfaces << EOF
common_interface: $iface
common_bootproto: static
EOF
cat > "$KAYOBE_CONFIG_PATH/inventory/group_vars/compute/network-interfaces" << EOF
common_interface: vhost0
common_bootproto: static
EOF

tee "$KAYOBE_CONFIG_PATH/inventory/group_vars"/{seed,overcloud}/ansible_python_interpreter << EOF
ansible_python_interpreter: "{{ virtualenv_path }}/kayobe/bin/python"
EOF

cat >  "$KAYOBE_CONFIG_PATH/networks.yml" << EOF
admin_oc_net_name:                   common
oob_oc_net_name:                     common
oob_wl_net_name:                     common
provision_oc_net_name:               common
provision_wl_net_name:               common
inspection_net_name:                 common
cleaning_net_name:                   common
external_net_names:                 [common]
public_net_name:                     common
internal_net_name:                   common
tunnel_net_name:                     common
storage_mgmt_net_name:               common
storage_net_name:                    common
swift_storage_net_name:              common
swift_storage_replication_net_name:  common
EOF

cat >  "$KAYOBE_CONFIG_PATH/networks-common.yml" << EOF
common_cidr: $(ip -j r s dev $iface scope link|jq -r '.[0]|.dst')
common_gateway: $(ip -j r s dev $iface default|jq -r '.[0]|.gateway')
common_fqdn: $vip
common_vip_address: $vip
EOF

cat > "$KAYOBE_CONFIG_PATH/dns.yml" << EOF
resolv_is_managed: false
EOF

cat > "$KAYOBE_CONFIG_PATH/time.yml" << EOF
timezone: Europe/Moscow
chrony_ntp_servers:
  - server: pool.ntp.org
    type: pool
    options:
      - option: maxsources
        val: 3
EOF

cat > "$KAYOBE_CONFIG_PATH/hosts-vars.yml" << EOF
disable-glean: true
seed_lvm_groups: []
controller_lvm_groups: []
compute_lvm_groups: []
EOF

cat > "$KAYOBE_CONFIG_PATH/docker.yml" << EOF
docker_storage_driver: overlay2
docker_daemon_live_restore: true
tf_docker_registry: "$tf_docker_registry"
EOF

if [ -n "$is_after_xena" ]; then
  cat >> "$KAYOBE_CONFIG_PATH/docker.yml" << EOF
# after xena docker tuned by kayobe
docker_registry_insecure: true
docker_registry: "$docker_registry"
kolla_docker_custom_config: "{{ ({'insecure-registries':[tf_docker_registry]} if tf_docker_registry else {}) | combine({'registry-mirrors':docker_registry_mirrors} if docker_registry_mirrors else {}) }}"
EOF
  if [ "$ID" == "ubuntu" ]; then
    cat >> "$KAYOBE_CONFIG_PATH/docker.yml" << EOF
# prefer docker.io on ubuntu
enable_docker_repo: false
docker_apt_package: docker.io
EOF
  fi
fi

if [ "$cacheimages" == "true" ]; then
cat > "$KAYOBE_CONFIG_PATH/docker-registry.yml" << EOF
docker_registry_enabled: true
docker_registry_port: 4000
docker_registry_datadir_volume: "/opt/registry"
docker_registry_env:
  REGISTRY_PROXY_REMOTEURL: "https://registry-1.docker.io"
docker_registry_mirrors:
  - "http://$docker_registry/"
EOF
fi

cat > "$KAYOBE_CONFIG_PATH/overcloud.yml" << EOF
dev_tools_packages_default:
  - bash-completion
  - tcpdump
  - vim
EOF
if [ "$ID" == "ubuntu" ]; then
cat >> "$KAYOBE_CONFIG_PATH/overcloud.yml" << EOF
  - docker-compose
EOF
fi

cat > "$KAYOBE_CONFIG_PATH/kolla.yml" << EOF
bootstrap_user: "$ID"
openstack_release: "$os"
kolla_ansible_source_url: https://github.com/OpenSDN-io/tf-kolla-ansible.git
kolla_ansible_source_version: "opensdn/$os"
kolla_ansible_custom_passwords:
 keystone_admin_password: admin
 metadata_secret: contrail
 kolla_ssh_key:
  private_key: "{{ lookup('file', ssh_private_key_path) }}"
  public_key: "{{ lookup('file', ssh_public_key_path) }}"
kolla_enable_heat: true
kolla_enable_haproxy: $usevip

# in ussuri ironic is enabled by default
kolla_enable_ironic: false
kolla_enable_fluentd: false
kolla_enable_openvswitch: false
kolla_enable_neutron_provider_networks: false

kolla_base_distro: ubuntu
EOF
if ! [ -n "$is_after_xena" ]; then
  cat >> "$KAYOBE_CONFIG_PATH/kolla.yml" << EOF
# before zed (xena) we need this
kolla_install_type: source
EOF
fi

cat > "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF
tf_tag: "$tf"
tf_namespace: "$tf_namespace"
tf_docker_registry: "{{ tf_docker_registry }}"

contrail_ca_file: /etc/contrail/ssl/certs/ca-cert.pem
contrail_dm_integration: false
enable_opencontrail_rbac: false
enable_opencontrail_trunk: true

neutron_plugin_agent: opencontrail
neutron_fwaas_version: v2

opencontrail_api_server_ip: $head_ip
opencontrail_collector_ip:  $head_ip
opencontrail_webui_ip:      $head_ip

customize_etc_hosts: false
computes_need_external_bridge: false

nova_compute_virt_type: $virt
openstack_service_workers: "1"

# for 2023.1 on 20.04 we needs this:
prechecks_enable_host_os_checks: false

enable_docker_repo: false
docker_apt_package: docker.io
EOF

cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF
# after xena we needs this (to override kayobe)
# we use docker_mirror for tf images but not for kolla
docker_registry_insecure: false
docker_registry: "quay.io"
# end after xena
EOF

if [ "$os" == "wallaby" ]; then
cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF
# ubuntu image for rabbit is broken
rabbitmq_image: "quay.io/openstack.kolla/centos-source-rabbitmq"
EOF
fi

if ! [ -n "$is_after_xena" -a "$ID" != "ubuntu" ]; then
cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF
# for ussuri there is no suffix images available
openstack_tag_suffix: ""
docker_disable_ip_forward: true
EOF
fi

if [ "$ID" == "ubuntu" ]; then
cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF
enable_docker_repo: false
docker_apt_package: docker.io
EOF
fi

if ! [ -n "$is_after_xena" ]; then
cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF
# also before xena for above to work we need this
docker_namespace: "openstack.kolla"

# up to xena - docker is tuned by kolla-ansible
docker_custom_config:
  debug: true
  insecure-registries: {{ (["$docker_registry"] + [tf_docker_registry]) | unique }}
  registry-mirrors: {{ docker_registry_mirrors }}
# end up to xena
EOF
fi

cat > "$TF_CONFIG_PATH" << EOF
provider_config:
  bms:
    domainsuffix: local
instances:
EOF
for name in `nodeattr -n head`; do
cat >> "$TF_CONFIG_PATH" << EOF
  $name:
    provider: bms
    ip: $(resolve_host $name)
    roles:
      config_database:
      config:
      control:
      analytics_database:
      analytics:
      webui:
      openstack:
EOF
done
for name in `nodeattr -n compute`; do
cat >> "$TF_CONFIG_PATH" << EOF
  $name:
    provider: bms
    ip: $(resolve_host $name)
    roles:
      vrouter:
      openstack_compute:
EOF
done

cat >> "$TF_CONFIG_PATH" << EOF
global_configuration:
  CONTAINER_REGISTRY: $(echo $tf_docker_registry $tf_namespace|tr ' ' '/')
  REGISTRY_PRIVATE_INSECURE: true
contrail_configuration:
  CLOUD_ORCHESTRATOR: openstack
  OPENSTACK_VERSION: "$os"
  CONTRAIL_VERSION: "$tf"
  AUTH_MODE: keystone
  KEYSTONE_AUTH_URL_VERSION: /v3
  ANALYTICS_STATISTICS_TTL: 2
  CONFIG_API_WORKER_COUNT: 5
  API__DEFAULTS__enable_api_stats_log: true
  RABBITMQ_NODE_PORT: 5673
kolla_config:
  kolla_passwords:
    keystone_admin_password: admin
    metadata_secret: contrail
  kolla_globals:
    enable_haproxy: false
EOF
