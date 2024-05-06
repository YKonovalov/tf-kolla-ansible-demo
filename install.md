# TF kayobe demo (manual install)

tungstenfabric + openstack installation scripts (using tf-ansible-deployer and kayobe)

## prereqs

  - one control node 2G RAM
  - one or three head node 64G RAM
  - tree or more compute node 8G RAM
  - root user on control node must have passwordless root ssh access to all nodes
  - all hosts must have pdsh,git,tmux packages preinstalled. Please see templates/centos8.yml and templates/ubuntu2004.yml for exact predeployment reqs.

## configure (on control node)

Populate __/etc/hosts__ and __/etc/genders__ files and give names and roles to nodes

__/etc/hosts__:
```
10.0.1.2 build0
10.0.1.3 control0
10.0.1.4 head0
10.0.1.5 compute0
10.0.1.6 compute1
10.0.1.7 compute2
```

__/etc/genders__:
```
build0 build,pdsh_all_skip,docker_registry_listen_port=5001
control0 control,os=wallaby,virt=qemu,iface=ens192,tf=R2011-latest**
head0 head
compute0 compute
compute1 compute
compute2 compute
```

For hosts with role control you can optionally specify demo specification attributes as a coma separated string with attributes (no spaces).

  - __os__ - OpenStack version (ussuri,victoria, etc)
  - __virt__ - virtualization type (kvm or qemu)
  - __iface__ - name of the network interface to configure
  - __tfcustom__ - if present, then custom docker registry will be used for TF containers as specified in build node attributes
  - __tf__ - tungsten fabric container tag (latest will be used by default)
  - __cacheimages__ - enable caching docker registry on control node

Example for ussuri on centos8 with custom build TF: **os=ussuri,virt=kvm,iface=eth0,tfcustom,tf=dev,cacheimages**

Example for wallaby on ubuntu2004 with public build TF: **os=wallaby,virt=kvm,iface=ens192,tf=R2011-latest,cacheimages**


### install

  - copy **control-node-scripts** to control node
  - run __cluster-do-setup.sh__ as root
  - watch for installation process /root/logs/ or in tmux

### reinstall

  - run __cluster-delete.sh__ as root
  - to deploy other version set it in /etc/genders
  - run __cluster-do-setup.sh__ as root
  - watch for installation process /root/logs/ or in tmux


## use web UIs at head node

openstack: admin/admin http://{head0_ip}

tungsten:  admin/admin https://{head0_ip}:8143
