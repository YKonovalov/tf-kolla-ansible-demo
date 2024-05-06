variable "vcd_user" {
  type        = string
}
variable "vcd_pass" {
  type        = string
}
variable "vcd_org" {
  type        = string
}
variable "vcd_vdc" {
  type        = string
}
variable "vcd_url" {
  type        = string
}
variable "vcd_max_retry_timeout" {
  type        = number
}
variable "vcd_allow_unverified_ssl" {
  type        = bool
}

terraform {
  required_providers {
    vcd = {
      source = "vmware/vcd"
      version = "3.8.2"
    }
  }
}

provider "vcd" {
  user                 = var.vcd_user
  password             = var.vcd_pass
  auth_type            = "integrated"
  org                  = var.vcd_org
  vdc                  = var.vcd_vdc
  url                  = var.vcd_url
  max_retry_timeout    = var.vcd_max_retry_timeout
  allow_unverified_ssl = var.vcd_allow_unverified_ssl
}
