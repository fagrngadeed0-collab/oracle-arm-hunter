terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key" { type = string }
variable "region" { type = string }
variable "compartment_ocid" { type = string }
variable "ssh_public_key" { type = string }

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "arm_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "arm-hunter-vcn"
}

resource "oci_core_internet_gateway" "arm_ig" {
  compartment_id = var.compartment_ocid
  display_name   = "arm-hunter-ig"
  vcn_id         = oci_core_vcn.arm_vcn.id
}

resource "oci_core_route_table" "arm_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.arm_vcn.id
  display_name   = "arm-hunter-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.arm_ig.id
  }
}

resource "oci_core_subnet" "arm_subnet" {
  cidr_block        = "10.0.1.0/24"
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.arm_vcn.id
  route_table_id    = oci_core_route_table.arm_rt.id
  display_name      = "arm-hunter-subnet"
  security_list_ids = [oci_core_vcn.arm_vcn.default_security_list_id]
}

resource "oci_core_instance" "arm_instance" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "Oracle-ARM-4CPU-24GB"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.arm_subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 100
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

output "public_ip" {
  value       = oci_core_instance.arm_instance.public_ip
  description = "Public IP of the created ARM Instance"
}