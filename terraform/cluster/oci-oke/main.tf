terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
}

provider "oci" {
  region = var.region
  # Credentials are read automatically from ~/.oci/config
}

locals {
  node_pool_target_version = var.kubernetes_version # Node Pool must target the version defined in var.kubernetes_version
  k8s_version_short = trimprefix(local.node_pool_target_version, "v") # Image version must match the Node Pool version
  oke_image_id = [ # This logic guarantees that the correct image is selected
    for source in data.oci_containerengine_node_pool_option.node_pool_option.sources : source.image_id
    if strcontains(source.source_name, "aarch64") && strcontains(source.source_name, local.k8s_version_short)
  ][0]
}

# ========================================
# Reserved Public IP for Load Balancer (Always Free)
# ========================================

resource "oci_core_public_ip" "nlb_public_ip" {
  compartment_id = var.compartment_id
  lifetime       = "RESERVED"
  display_name   = "k8s-nlb-ip"

  lifecycle {
    ignore_changes = [private_ip_id]
  }
}

# ========================================
# OKE Cluster (Free Tier: 1 control plane)
# ========================================

resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "k8s-cluster"
  vcn_id             = oci_core_vcn.k8s_vcn.id

  endpoint_config {
    subnet_id            = oci_core_subnet.k8s_subnet.id
    is_public_ip_enabled = true
  }

  options {
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
  }
}

# ========================================
# Node Pool (Free Tier: Ampere A1, 2-3 nodes)
# ========================================

resource "oci_containerengine_node_pool" "node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version # Use var.kubernetes_version for the Node Pool
  name               = "k8s-node-pool"

  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.k8s_subnet.id
    }

    size = var.node_pool_size
  }

  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.oke_image_id
  }

  initial_node_labels {
    key   = "k8s-environment"
    value = "free-tier"
  }

  ssh_public_key = file(var.ssh_public_key_path)
}

# ========================================
# Data sources
# ========================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_containerengine_node_pool_option" "node_pool_option" {
  compartment_id      = var.compartment_id
  node_pool_option_id = oci_containerengine_cluster.k8s_cluster.id
}

data "oci_containerengine_cluster_kube_config" "cluster_kube_config" {
  cluster_id = oci_containerengine_cluster.k8s_cluster.id
}

# ========================================
# Object Storage
# ========================================

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "logs_storage" {
  compartment_id = var.compartment_id
  name           = "logs-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  storage_tier   = "Standard"
}

resource "oci_objectstorage_bucket" "metrics_storage" {
  compartment_id = var.compartment_id
  name           = "metrics-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  storage_tier   = "Standard"
}

resource "oci_identity_customer_secret_key" "monitoring_s3_key" {
  display_name = "monitoring-monitoring-key"
  user_id      = var.user_ocid
}