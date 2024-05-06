terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
    null = {
      source = "hashicorp/null"
    }
    vcd = {
      source = "vmware/vcd"
    }
  }
  required_version = ">= 0.13"
}
