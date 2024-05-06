#!/bin/sh

cloud_config() {
  cat /var/lib/cloud/instance/user-data.txt |
    python3 -c 'import sys, yaml, json; json.dump(yaml.load(sys.stdin), sys.stdout)' |
    jq -r 'with_entries(select(.key == "users"))' |
    python3 -c 'import sys, yaml, json; print(yaml.dump(json.loads(sys.stdin.read())))'
}

if C="$(cloud_config)" && [ -n "$C" ]; then
  C="$(echo -e "#cloud-config\n$C"|pr -to 8)"
  C="$(echo -e "|\n$C\n\n")"
else
  C=
fi

key="$(cat /root/.ssh/id_rsa.pub)"

cat > /tmp/heat.yaml << EOF
heat_template_version: 2018-08-31
description: SDN demo set of resources heat template
resources:
  public:
    type: OS::ContrailV2::VirtualNetwork
    properties:
      name: public
      router_external: true
      is_shared: true
      network_policy_refs:
      - get_resource: permissive
      network_policy_refs_data:
      - network_policy_refs_data_sequence:
          network_policy_refs_data_sequence_major: 0
          network_policy_refs_data_sequence_minor: 0
      network_ipam_refs:
      - get_resource: space
      network_ipam_refs_data:
      - network_ipam_refs_data_ipam_subnets:
        - network_ipam_refs_data_ipam_subnets_subnet_name: public-v4
          network_ipam_refs_data_ipam_subnets_subnet:
            network_ipam_refs_data_ipam_subnets_subnet_ip_prefix: $(getent hosts head0|head -1|cut -d ' ' -f1|awk -F. 'OFS="." {print $1,$2,$4,"0"}')
            network_ipam_refs_data_ipam_subnets_subnet_ip_prefix_len: 24
  space:
    type: OS::ContrailV2::NetworkIpam
    properties:
      name: space
  permissive:
    type: OS::ContrailV2::NetworkPolicy
    properties:
      name: permissive
      network_policy_entries:
        network_policy_entries_policy_rule:
        - network_policy_entries_policy_rule_direction: <>
          network_policy_entries_policy_rule_protocol: any
          network_policy_entries_policy_rule_action_list:
            network_policy_entries_policy_rule_action_list_simple_action: pass
          network_policy_entries_policy_rule_src_addresses:
          - network_policy_entries_policy_rule_src_addresses_subnet:
              network_policy_entries_policy_rule_src_addresses_subnet_ip_prefix: "0.0.0.0"
              network_policy_entries_policy_rule_src_addresses_subnet_ip_prefix_len: 0
          network_policy_entries_policy_rule_src_ports:
          - network_policy_entries_policy_rule_src_ports_start_port: -1
            network_policy_entries_policy_rule_src_ports_end_port: -1
          network_policy_entries_policy_rule_dst_addresses:
          - network_policy_entries_policy_rule_dst_addresses_virtual_network: "any"
          network_policy_entries_policy_rule_dst_ports:
          - network_policy_entries_policy_rule_dst_ports_start_port: -1
            network_policy_entries_policy_rule_dst_ports_end_port: -1
  fabric:
    type: OS::Neutron::SecurityGroup
    properties:
      name: fabric
      rules:
      - direction: ingress
        ethertype: IPv4
        remote_ip_prefix: 0.0.0.0/0
      - direction: egress
        ethertype: IPv4
        remote_ip_prefix: 0.0.0.0/0
  common:
    type: OS::ContrailV2::FloatingIpPool
    properties:
      name: common
      virtual_network: {get_resource: public}

  internal:
    type: OS::Neutron::Net
    properties:
      name: internal
  internal-v4:
    type: OS::Neutron::Subnet
    properties:
      name: internal-v4
      network_id: { get_resource: internal }
      cidr: 10.0.0.0/24

  fip-int-a:
    depends_on: [public,common]
    type: OS::Neutron::FloatingIP
    properties:
      floating_network: { get_resource: public }
  fip-int-b:
    depends_on: [public,common]
    type: OS::Neutron::FloatingIP
    properties:
      floating_network: { get_resource: public }
  fip-int-c:
    depends_on: [public,common]
    type: OS::Neutron::FloatingIP
    properties:
      floating_network: { get_resource: public }

  port-int-a:
    type: OS::Neutron::Port
    properties:
      network: {get_resource: internal}
      security_groups:
      - { get_resource: fabric }
  port-int-b:
    type: OS::Neutron::Port
    properties:
      network: {get_resource: internal}
      security_groups:
      - { get_resource: fabric }
  port-int-c:
    type: OS::Neutron::Port
    properties:
      network: {get_resource: internal}
      security_groups:
      - { get_resource: fabric }

  publiciers:
    type: OS::Nova::ServerGroup
    properties:
      name: publiciers
      policies: [anti-affinity]
  internals:
    type: OS::Nova::ServerGroup
    properties:
      name: internals
      policies: [anti-affinity]

  key:
    type: OS::Nova::KeyPair
    properties:
      name: stack
      public_key: $key

  pub-a:
    type: OS::Nova::Server
    properties:
      name: pub-a
      image: cirros
      flavor: m1.tiny
      key_name: { get_resource: key }
      user_data_format: RAW
      user_data: $C
      networks:
      - network: { get_resource: public }
      security_groups:
      - { get_resource: fabric }
      scheduler_hints:
        group: { get_resource: publiciers }
  pub-b:
    type: OS::Nova::Server
    properties:
      name: pub-b
      image: cirros
      flavor: m1.tiny
      key_name: { get_resource: key }
      user_data_format: RAW
      user_data: $C
      networks:
      - network: { get_resource: public }
      security_groups:
      - { get_resource: fabric }
      scheduler_hints:
        group: { get_resource: publiciers }
  pub-c:
    type: OS::Nova::Server
    properties:
      name: pub-c
      image: fedora
      flavor: m1.tiny
      key_name: { get_resource: key }
      user_data_format: RAW
      user_data: $C
      networks:
      - network: { get_resource: public }
      security_groups:
      - { get_resource: fabric }
      scheduler_hints:
        group: { get_resource: publiciers }

  int-a:
    type: OS::Nova::Server
    depends_on:
     - port-int-a
     - fip-int-a
    properties:
      name: int-a
      image: cirros
      flavor: m1.tiny
      key_name: { get_resource: key }
      user_data_format: RAW
      user_data: $C
      networks:
      - port: { get_resource: port-int-a }
        floating_ip: { get_resource: fip-int-a }
      scheduler_hints:
        group: { get_resource: internals }

  int-b:
    type: OS::Nova::Server
    depends_on:
     - port-int-b
     - fip-int-b
    properties:
      name: int-b
      image: cirros
      flavor: m1.tiny
      key_name: { get_resource: key }
      user_data_format: RAW
      user_data: $C
      networks:
      - port: { get_resource: port-int-b }
        floating_ip: { get_resource: fip-int-b }
      scheduler_hints:
        group: { get_resource: internals }
  int-c:
    type: OS::Nova::Server
    depends_on:
     - port-int-c
     - fip-int-c
    properties:
      name: int-c
      image: fedora
      flavor: m1.tiny
      key_name: { get_resource: key }
      user_data_format: RAW
      user_data: $C
      networks:
      - port: { get_resource: port-int-c }
        floating_ip: { get_resource: fip-int-c }
      scheduler_hints:
        group: { get_resource: internals }
outputs:
  server_networks:
    description: The networks of the deployed server
    value: { get_attr: [public, show] }
EOF

source ~/kayobe.env
source "$KOLLA_CONFIG_PATH/admin-openrc.sh"

openstack stack create --wait -t /tmp/heat.yaml demo
