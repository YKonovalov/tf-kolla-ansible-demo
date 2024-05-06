#!/bin/sh
# This script configure and deploy ceph onto compute nodes.

resolve_host() {
  getent ahostsv4 $1|head -1|cut -d ' ' -f1
}

. ~/kayobe.env
ceph_src_path="${SRC}/ceph-ansible"
venv_path="${VENVS}/ceph-ansible"

pdsh -g compute apt-get -y install lvm2
pdsh -g compute pvcreate /dev/sdb
pdsh -g compute vgcreate data /dev/sdb
pdsh -g compute lvcreate -l 100%FREE -n ceph data

chost="$(nodeattr -n control|head -1)"
iface="$(nodeattr -v $chost iface)"

rm -rf ${ceph_src_path} ~/ansible

virtualenv $venv_path
. $venv_path/bin/activate
python -m pip install jinja2==3.0.0
python -m pip install ansible==2.9
pip install six netaddr
git clone -b stable-5.0 https://github.com/ceph/ceph-ansible.git ${ceph_src_path}
pushd ${ceph_src_path}
mv site.yml.sample site.yml

cat > inventory << EOF
[mons]
`nodeattr -n "compute"|while read name; do echo "$(resolve_host $name)"; done`

[osds]
`nodeattr -n "compute"|while read name; do echo "$(resolve_host $name)"; done`

[mgrs]
`nodeattr -n "compute"|while read name; do [[ $name == "compute0" ]] && echo "$(resolve_host $name)"; done`

[rgws]
`nodeattr -n "compute"|while read name; do [[ $name == "compute0" ]] && echo "$(resolve_host $name)"; done`
EOF

cat > group_vars/all.yml <<EOF
---
dummy:
configure_firewall: False
ntp_service_enabled: true
ntp_daemon_type: chronyd
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org
  - 2.pool.ntp.org
  - 3.pool.ntp.org

ceph_repository_type: cdn
ceph_origin: repository
ceph_repository: community
ceph_stable_release: octopus
monitor_interface: vhost0
public_network: $(ip -j r s dev $iface scope link|jq -r '.[0]|.dst')
cluster_network: $(ip -j r s dev $iface scope link|jq -r '.[0]|.dst')
radosgw_interface: vhost0
ceph_conf_overrides:
  global:
    osd_pool_default_size: 2
    osd_pool_default_min_size: 1
os_tuning_params:
  - { name: kernel.pid_max, value: 4194303 }
  - { name: fs.file-max, value: 26234859 }
  - { name: vm.zone_reclaim_mode, value: 0 }
  - { name: vm.vfs_cache_pressure, value: 50 }
  - { name: vm.swappiness, value: 1 }
openstack_config: true
openstack_glance_pool:
  name: "images"
  pg_num: "16"
  pgp_num: "16"
  rule_name: ""
  expected_num_objects: ""
openstack_cinder_pool:
  name: "volumes"
  pg_num: "32"
  pgp_num: "32"
  rule_name: ""
  expected_num_objects: ""
openstack_nova_pool:
  name: "vms"
  pg_num: "16"
  pgp_num: "16"
  rule_name: ""
  expected_num_objects: ""
openstack_cinder_backup_pool:
  name: "backups"
  pg_num: "16"
  pgp_num: "16"
  rule_name: ""
  expected_num_objects: ""
openstack_pools:
  - "{{ openstack_glance_pool }}"
  - "{{ openstack_cinder_pool }}"
  - "{{ openstack_nova_pool }}"
  - "{{ openstack_cinder_backup_pool }}"
openstack_keys:
  - { name: client.glance, caps: { mon: "profile rbd", osd: "profile rbd pool={{ openstack_cinder_pool.name }}, profile rbd pool={{ openstack_glance_pool.name }}"}, mode: "0600" }
  - { name: client.cinder, caps: { mon: "profile rbd", osd: "profile rbd pool={{ openstack_cinder_pool.name }}, profile rbd pool={{ openstack_nova_pool.name }}, profile rbd pool={{ openstack_glance_pool.name }}"}, mode: "0600" }
  - { name: client.cinder-backup, caps: { mon: "profile rbd", osd: "profile rbd pool={{ openstack_cinder_backup_pool.name }}"}, mode: "0600" }
dashboard_enabled: False
EOF

cat > group_vars/osds.yml <<EOF
---
dummy:
copy_admin_key: true
lvm_volumes:
  - data: ceph
    data_vg: data
osd_objectstore: bluestore
delay_wait_osd_up: 30
EOF

ansible-playbook -vvvv -i inventory -u root site.yml

ansible mgrs -i inventory -u root -b -m fetch -a 'src=/etc/ceph/ceph.client.glance.keyring dest=/tmp/ flat=yes'
ansible mgrs -i inventory -u root -b -m fetch -a 'src=/etc/ceph/ceph.client.cinder.keyring dest=/tmp/ flat=yes'
ansible mgrs -i inventory -u root -b -m fetch -a 'src=/etc/ceph/ceph.client.cinder-backup.keyring dest=/tmp/ flat=yes'
ansible mgrs -i inventory -u root -b -m fetch -a 'src=/etc/ceph/ceph.conf dest=/tmp/ flat=yes'
popd

mkdir -p ${KAYOBE_CONFIG_PATH}/kolla/config/nova/
cp -fv /tmp/ceph.client.cinder.keyring ${KAYOBE_CONFIG_PATH}/kolla/config/nova/
cp -fv /tmp/ceph.conf ${KAYOBE_CONFIG_PATH}/kolla/config/nova/

mkdir -p ${KAYOBE_CONFIG_PATH}/kolla/config/cinder/cinder-backup/
mkdir -p ${KAYOBE_CONFIG_PATH}/kolla/config/cinder/cinder-volume/


cp -fv /tmp/ceph.client.cinder.keyring ${KAYOBE_CONFIG_PATH}/kolla/config/cinder/cinder-backup/
mv -fv /tmp/ceph.client.cinder.keyring ${KAYOBE_CONFIG_PATH}/kolla/config/cinder/cinder-volume/
mv -fv /tmp/ceph.client.cinder-backup.keyring ${KAYOBE_CONFIG_PATH}/kolla/config/cinder/cinder-backup/
cp -fv /tmp/ceph.conf ${KAYOBE_CONFIG_PATH}/kolla/config/cinder/


mkdir -p ${KAYOBE_CONFIG_PATH}/kolla/config/glance/
mv -fv /tmp/ceph.client.glance.keyring ${KAYOBE_CONFIG_PATH}/kolla/config/glance/
mv -fv /tmp/ceph.conf ${KAYOBE_CONFIG_PATH}/kolla/config/glance/

cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF

glance_backend_swift: false
# CEPH for Glance
glance_backend_ceph: true
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"
ceph_glance_keyring: "ceph.client.glance.keyring"

# CEPH for Cinder
cinder_backend_ceph: true
ceph_cinder_user: "cinder"
ceph_cinder_pool_name: "volumes"
ceph_cinder_keyring: "ceph.client.cinder.keyring"

# CEPH for Nova
nova_backend_ceph: true
ceph_nova_user: "cinder"
ceph_nova_pool_name: "vms"
ceph_nova_keyring: "ceph.client.cinder.keyring"
cinder_backends:
  - name: "rbd-1"
    enabled: "{{ '{{' }} cinder_backend_ceph | bool {{ '}}' }}"
  - name: "lvm-1"
    enabled: "{{ '{{' }} enable_cinder_backend_lvm | bool {{ '}}' }}"
  - name: "nfs-1"
    enabled: "{{ '{{' }} enable_cinder_backend_nfs | bool {{ '}}' }}"
  - name: "hnas-nfs"
    enabled: "{{ '{{' }} enable_cinder_backend_hnas_nfs | bool {{ '}}' }}"
  - name: "vmwarevc-vmdk"
    enabled: "{{ '{{' }} cinder_backend_vmwarevc_vmdk | bool {{ '}}' }}"
  - name: "QuobyteHD"
    enabled: "{{ '{{' }} enable_cinder_backend_quobyte | bool {{ '}}' }}"
EOF

if [ "${USE_NFS_CINDER_BACKUP}" = "true" ]
then
  cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF

# NFS for Cinder-Backup
cinder_backup_driver: "nfs"
cinder_backup_share: "10.8.27.52:/mnt/nfs"
EOF
else
  cat >> "$KAYOBE_CONFIG_PATH/kolla/globals.yml" << EOF

# CEPH for Cinder-Backup
ceph_cinder_backup_keyring: "ceph.client.cinder-backup.keyring"
ceph_cinder_backup_user: "cinder-backup"
ceph_cinder_backup_pool_name: "backups"
EOF
fi

cat >> "$KAYOBE_CONFIG_PATH/kolla.yml" << EOF
kolla_enable_cinder: true
kolla_enable_cinder_backup: true
EOF

cat > "$KAYOBE_CONFIG_PATH/inventory/groups" << EOF
[seed]
[controllers]
[compute]

[storage:children]
compute

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
