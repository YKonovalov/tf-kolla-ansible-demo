# TF kayobe demo (terraform install)

tungstenfabric plus openstack installation demo

## prereqs

  - user account at vcloud
  - vpn access to vcloud virtual network
  - terraform binary (https://www.terraform.io/downloads.html)
  - ssh private and public key for remote access (https://www.ssh.com/ssh/keygen/)
  - ssh agent. Check and run if don't have one (https://www.ssh.com/ssh/agent)
```bash
    if [ -z "$SSH_AUTH_SOCK"]; then eval `ssh-agent`; fi
    if [ -z "$(ssh-add -l)" ]; then ssh-add ~/.ssh/id_rsa; fi
    ssh-add -l # must list your key
```

## configuring

  - copy directory *terraform.example* and all it's content to new folder (named after your demo) in the current directory. You may wish to have several such directories each for different stand. Perform configurations inside this new folder.
  - **terraform.tfvars** -- create file and set your username, password (use terraform.tfvars.example as example);
  - **demo.auto.tfvars** -- create file and set following vars (use demo.auto.tfvars.example as example):
    - __demo__ - unique vapp name
    - __demospec__ coma separated string with attributes (no spaces and starting with coma). Example: ",os=wallaby,virt=kvm,iface=ens192,tf=R2011-latest,cacheimages"
      - __os__ OpenStack version (ussuri,victoria, etc)
      - __virt__ virtualization type (kvm or qemu)
      - __iface__ name of the network interface to configure
      - __tfcustom__ - if present, then custom docker registry will be used for TF containers as specified in build node attributes
      - __tf__ tungsten fabric container tag (latest will be used by default)
      - __cacheimages__ - enable caching docker registry on control node
    - __login_name__ - user name to create in instances for your convinience
    - __public_keys__ - ssh public key to add (to both root and your user). Public key will be used to connect to the host, so you must have corresponding private key in your ssh-agent.
    - __head_count__ - default 1 (tested with 1 and 3)
    - __compute_count__ - default 3 (3 minimum)
    - __deploy_ceph__ - add ceph deployment. Default false

### Advanced config

To run in network other then default (*flat*) edit file *demo.auto.tfvars* and add an existing org network name in __network_name__ variable
To install custom built TF add *tfcustom* attribute to *demospec* variable and add your build server see example in *demo.auto.tfvars.example.advanced*

## deploy

```bash
    terraform init # and probably run suggested terraform upgrade command
    terraform apply
```

**note:** it will take about 40 min or more

## use web UIs at head node

openstack: admin/admin http://{head0_ip}

tungsten:  admin/admin https://{head0_ip}:8143

## Notes on stages of deploy

  - **resources** - creation of vms in the cloud
  - **cluster** -  running multi-stage setup of tungstenfabric + openstack (see control-node-scripts/cluster-setup.sh)
  - **wait** - wait for previous stage to finnish. At this stage terraform could be interrupted at any time. Simply run terraform apply to proceed and show the result.

While deploying (or after deploy is finnished) it's possible to connect to control0 host with your user account, become root, and type **tmux a** to see what's happening or see logs in /root/ directory.

## Notes on accessing virtual networks from underlay network

  - Open tungsten UI:  admin/admin https://{head0_ip}:8143
  - Navigate to _Configure -> Networking -> Security Groups_. Choose *Edit* on *default* security group. Change ingress rule source from *default* to CIDR *0.0.0.0/0*. Click *Save* button.
  - Navigate to _Configure -> Networking -> Policies_. Add new policy (Lets name it *all*). Add rule with source CIDR *0.0.0.0/0* and all other options set by default. Click *Save* button.
  - Navigate to _Configure -> Networking -> Networks_. Choose *Edit* on **public** network. Add *all* policy in *Network Policy(s)* field, open *Advanced Options* and checkbox *IP Fabric Forwarding*, click on *Save* button.

Now all public addresses should be accessible from within any routed network.
