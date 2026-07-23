# ========================================
# Networking Resources
# ========================================

resource "oci_core_vcn" "k8s_vcn" {
  compartment_id = var.compartment_id
  display_name   = "cloud-k8s-vcn"
  cidr_blocks    = [var.cloud_cluster_cidr]
}

resource "oci_core_internet_gateway" "k8s_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-igw"
}

resource "oci_core_route_table" "k8s_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "cloud-to-onprem-rt"

  # Default route to Internet
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.k8s_igw.id
  }

  # Route to On-Premise VIP via the DRG
  route_rules {
    destination       = "${var.vpn_vip}/32"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.vpn_drg.id
  }

  route_rules {
    destination       = var.onprem_nodes_cidr
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.vpn_drg.id
  }
}

resource "oci_core_subnet" "k8s_subnet" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.k8s_vcn.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "k8s-subnet"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.k8s_rt.id
  security_list_ids          = [oci_core_security_list.k8s_sl.id]
}

resource "oci_core_security_list" "k8s_sl" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.k8s_vcn.id
  display_name   = "k8s-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "all"
    source   = var.cloud_cluster_cidr
  }

  # Allow incoming traffic from the On-Premise VIP (required for Istio/VPN)
  ingress_security_rules {
    protocol    = "all"
    source      = "${var.vpn_vip}/32"
    description = "Allow On-Premise VIP Traffic"
  }

  # Ingress: Admin Access
  ingress_security_rules {
    protocol = "6"
    source   = var.admin_source_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = var.admin_source_cidr
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress: HTTP/HTTPS Public
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress: Istio East-West (VPN Specific)
  ingress_security_rules {
    protocol    = "6"
    source      = "${var.vpn_vip}/32"
    description = "Istio Multi-cluster mTLS"
    tcp_options {
      min = 15443
      max = 15443
    }
  }

  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    description = "Allow ICMP Fragmentation Needed"
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol    = "all"
    source      = var.onprem_nodes_cidr
    description = "Allow On-Premise Nodes Traffic"
  }
}

# ========================================
# VPN Site-to-Site (Cloud <-> On-Premise)
# ========================================

resource "oci_core_cpe" "local_cluster" {
  compartment_id = var.compartment_id
  ip_address     = var.onprem_cpe_ip
  display_name   = "onprem-cpe-strongswan"
}

resource "oci_core_drg" "vpn_drg" {
  compartment_id = var.compartment_id
  display_name   = "vpn-drg"
}

resource "oci_core_drg_attachment" "vpn_drg_attachment" {
  drg_id       = oci_core_drg.vpn_drg.id
  vcn_id       = oci_core_vcn.k8s_vcn.id
  display_name = "vpn-drg-attachment"
}

resource "oci_core_ipsec" "vpn_connection" {
  compartment_id = var.compartment_id
  cpe_id         = oci_core_cpe.local_cluster.id
  drg_id         = oci_core_drg.vpn_drg.id
  static_routes  = ["${var.vpn_vip}/32", var.onprem_nodes_cidr]
  display_name   = "cloud-to-onprem-ipsec"
}

resource "oci_core_ipsec_connection_tunnel_management" "vpn_tunnel_1" {
  ipsec_id  = oci_core_ipsec.vpn_connection.id
  tunnel_id = data.oci_core_ipsec_connection_tunnels.vpn_tunnels.ip_sec_connection_tunnels[0].id

  # POLICY-BASED ROUTING: Required to manage multiple encryption domains
  routing     = "POLICY"
  ike_version = "V2"

  nat_translation_enabled = "ENABLED"

  encryption_domain_config {
    # List the encryption domains offered by the CPE (StrongSwan)
    cpe_traffic_selector    = ["${var.vpn_vip}/32", var.onprem_nodes_cidr, var.onprem_pods_cidr]
    oracle_traffic_selector = [var.cloud_nodes_cidr, var.cloud_pods_cidr]
  }
}

resource "oci_core_ipsec_connection_tunnel_management" "vpn_tunnel_2" {
  ipsec_id    = oci_core_ipsec.vpn_connection.id
  tunnel_id   = data.oci_core_ipsec_connection_tunnels.vpn_tunnels.ip_sec_connection_tunnels[1].id
  routing     = "POLICY"
  ike_version = "V2"

  nat_translation_enabled = "ENABLED"

  encryption_domain_config {
    cpe_traffic_selector    = ["${var.vpn_vip}/32", var.onprem_nodes_cidr, var.onprem_pods_cidr]
    oracle_traffic_selector = [var.cloud_nodes_cidr, var.cloud_pods_cidr]
  }
}

# ========================================
# Data sources & Outputs
# ========================================

data "oci_core_ipsec_config" "vpn_config" {
  ipsec_id = oci_core_ipsec.vpn_connection.id
}

data "oci_core_ipsec_connection_tunnels" "vpn_tunnels" {
  ipsec_id = oci_core_ipsec.vpn_connection.id
}

output "vpn_tunnel_1_ip" {
  value = data.oci_core_ipsec_config.vpn_config.tunnels[0].ip_address
}

output "vpn_tunnel_1_psk" {
  value     = data.oci_core_ipsec_config.vpn_config.tunnels[0].shared_secret
  sensitive = true
}