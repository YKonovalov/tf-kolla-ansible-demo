variable "demo" { type = string }
variable "demospec" {
 type    = string
 default = ",os=xena,tf=latest,virt=kvm"
}
variable "userdata" {
 type    = string
 default = "../templates/ubuntu2004.yaml"
}
variable "public_keys" { type = string }
variable "catalog_name" { type = string }
variable "template_name" { type = string }
variable "login_name" { type = string }
variable "storage_policy" {
 type    = string
 default = "ABC-12345-FAS-Standard"
}
variable "network_name" {
 type    = string
 default = "flat"
}
variable "compute_count" {
 type    = number
 default = 3
}
variable "head_count" {
 type    = number
 default = 1
}

variable "deploy_ceph" {
  type    = bool
  default = false
}

variable "backup_on_nfs" {
  type    = bool
  default = false
}

variable "extra_hosts" {
  type = list(object({
    name = string
    ip = string
    role = string
    attrs = string
  }))
  default = [
    {
      name  = "build0"
      ip    = "172.16.0.4"
      role  = "build"
      attrs = "pdsh_all_skip,docker_registry_listen_port=5001"
    }
  ]
}

resource "vcd_vapp" "demo" {
  name          = var.demo
  guest_properties = {
#    "public-keys" = join("\n", [ var.public_keys, tls_private_key.cluster.public_key_openssh ])
    "public-keys" = tls_private_key.cluster.public_key_openssh
    "user-data" = base64encode(templatefile(var.userdata, {
                       user = try(var.login_name,var.vcd_user),
                       sshkey = var.public_keys
                      }))
  }
}

resource "vcd_vapp_org_network" "demo" {
  vapp_name        = vcd_vapp.demo.name
  org_network_name = var.network_name
}

resource "vcd_vapp_vm" "control" {
  count         = 1
  power_on      = true
  vapp_name     = vcd_vapp.demo.name
  name          = "control${count.index}.${var.demo}"
  computer_name = "control${count.index}.${var.demo}"
  catalog_name  = var.catalog_name
  template_name = var.template_name
  memory        = 2048
  cpus          = 1
  cpu_cores     = 1

  customization {
    enabled                    = true
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = "compaq"
  }

  metadata = {
    role    = "control${var.demospec}"
    env     = "demo"
  }
  guest_properties = {
    "hostname"   = "control${count.index}.${var.demo}"
  }
  override_template_disk {
    bus_type         = "paravirtual"
    size_in_mb       = "20480"
    bus_number       = 0
    unit_number      = 0
    iops             = 0
    storage_profile  = var.storage_policy
  }
  network {
    type               = "org"
    name               = vcd_vapp_org_network.demo.org_network_name
    ip_allocation_mode = "POOL"
    is_primary         = true
  }
}

resource "vcd_vapp_vm" "head" {
  count         = var.head_count
  power_on      = true
  vapp_name     = vcd_vapp.demo.name
  name          = "head${count.index}.${var.demo}"
  computer_name = "head${count.index}.${var.demo}"
  catalog_name  = var.catalog_name
  template_name = var.template_name
  memory        = 65536
  cpus          = 16
  cpu_cores     = 1

  customization {
    enabled                    = true
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = "compaq"
  }
  metadata = {
    role    = "head"
    env     = "demo"
  }
  guest_properties = {
    "hostname"   = "head${count.index}.${var.demo}"
  }
  override_template_disk {
    bus_type         = "paravirtual"
    size_in_mb       = "120480"
    bus_number       = 0
    unit_number      = 0
    iops             = 0
    storage_profile  = var.storage_policy
  }
  network {
    type               = "org"
    name               = vcd_vapp_org_network.demo.org_network_name
    ip_allocation_mode = "POOL"
    is_primary         = true
  }
}

resource "vcd_independent_disk" "CephDisk" {
  name            = "cephDisk${count.index}.${var.demo}"
  count           = var.deploy_ceph ? var.compute_count : 0
  size_in_mb      = "30720"
  bus_type        = "SCSI"
  bus_sub_type    = "VirtualSCSI"
  storage_profile = var.storage_policy
}

resource "vcd_vapp_vm" "compute" {
  count         = var.compute_count
  power_on      = true
  vapp_name     = vcd_vapp.demo.name
  name          = "compute${count.index}.${var.demo}"
  computer_name = "compute${count.index}.${var.demo}"
  catalog_name  = var.catalog_name
  template_name = var.template_name
  memory        = 9192
  cpus          = 4
  cpu_cores     = 1
  memory_hot_add_enabled = false
  cpu_hot_add_enabled = false
  expose_hardware_virtualization = true

  customization {
    enabled                    = true
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = "somepassword"
  }
  metadata = {
    role    = "compute"
    env     = "demo"
  }
  guest_properties = {
    "hostname"   = "compute${count.index}.${var.demo}"
  }
  override_template_disk {
    bus_type         = "paravirtual"
    size_in_mb       = "50480"
    bus_number       = 0
    unit_number      = 0
    iops             = 0
    storage_profile  = var.storage_policy
  }
  network {
    type               = "org"
    name               = vcd_vapp_org_network.demo.org_network_name
    ip_allocation_mode = "POOL"
    is_primary         = true
  }
  dynamic disk {
    for_each = var.deploy_ceph == true ? [1] : []
    content {
      name  = vcd_independent_disk.CephDisk[count.index].name
      bus_number  = 1
      unit_number = 0
    }
  }
  depends_on = ["vcd_independent_disk.CephDisk"]
}

locals {
  hosts_vms = concat(vcd_vapp_vm.control[*],vcd_vapp_vm.head[*],vcd_vapp_vm.compute[*])
  hosts = templatefile("../templates/hosts", {
    hosts = join("\n", concat(
                 [for o in var.extra_hosts[*] : "${o.ip} ${o.name}"],
                 [for o in local.hosts_vms : "${o.network[0].ip} ${split(".", o.name)[0]} # ${o.name}"]
                 ))
    })
  genders = "${join("\n", concat(
                 [for o in var.extra_hosts[*] : "${o.name} ${o.role},${o.attrs}"],
                 [for o in local.hosts_vms : "${split(".", o.name)[0]} ${o.metadata.role}"]
                 ))}\n"
}

resource "local_file" "hosts" {
  file_permission      = "0644"
  filename             = "hosts"
  content              = local.hosts
}

resource "local_file" "genders" {
  file_permission      = "0644"
  filename             = "genders"
  content              = local.genders
}

resource "tls_private_key" "cluster" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "null_resource" "cluster" {
  triggers = {
    hostgenders = "${local.hosts}${local.genders}"
  }
  connection {
    host = vcd_vapp_vm.control[0].network[0].ip
    private_key = tls_private_key.cluster.private_key_pem
    agent = false
  }
  provisioner "file" {
    content     = local.hosts
    destination = "/etc/hosts"
  }
  provisioner "file" {
    content     = local.genders
    destination = "/etc/genders"
  }
  provisioner "file" {
    source     = "../control-node-scripts"
    destination = "/root/"
  }
  provisioner "remote-exec" {
    inline = [
      "echo '${tls_private_key.cluster.private_key_pem}'|install -m 600 /dev/stdin /root/.ssh/id_rsa",
      "echo '${tls_private_key.cluster.public_key_openssh}' > /root/.ssh/id_rsa.pub",
      "/bin/sh control-node-scripts/cluster-setup.sh ${var.deploy_ceph} ${var.backup_on_nfs}",
    ]
  }
}

resource "null_resource" "wait" {
  depends_on = [null_resource.cluster]
  triggers = {
    hostgenders = "${local.hosts}${local.genders}"
  }
  connection {
    host = vcd_vapp_vm.control[0].network[0].ip
    private_key = tls_private_key.cluster.private_key_pem
    agent = false
  }
  provisioner "remote-exec" {
    inline = [
      "/bin/sh control-node-scripts/cluster-up.sh",
    ]
  }
}

output "hosts" {
  value                = local.hosts
}
output "genders" {
  value                = local.genders
}
output "banner" {
  value                = templatefile("../templates/banner.txt", { head = vcd_vapp_vm.head[0].network[0].ip})
}
