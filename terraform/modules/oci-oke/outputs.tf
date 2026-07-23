output "kubernetes_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = oci_containerengine_cluster.k8s_cluster.endpoints[0].kubernetes
}

output "cluster_id" {
  description = "OKE Cluster OCID"
  value       = oci_containerengine_cluster.k8s_cluster.id
}

output "node_pool_id" {
  description = "Node pool OCID"
  value       = oci_containerengine_node_pool.node_pool.id
}

output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = data.oci_containerengine_cluster_kube_config.cluster_kube_config.content
  sensitive   = true
}

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.k8s_vcn.id
}

output "subnet_id" {
  description = "Subnet OCID"
  value       = oci_core_subnet.k8s_subnet.id
}

output "nlb_public_ip" {
  description = "Reserved Public IP for Load Balancer (Always Free)"
  value       = oci_core_public_ip.nlb_public_ip.ip_address
}

output "nlb_public_ip_id" {
  description = "Reserved Public IP OCID for Load Balancer"
  value       = oci_core_public_ip.nlb_public_ip.id
}

output "monitoring_s3_access_key" {
  value     = oci_identity_customer_secret_key.monitoring_s3_key.id
  sensitive = true
}

output "monitoring_s3_secret_key" {
  value     = oci_identity_customer_secret_key.monitoring_s3_key.key
  sensitive = true
}

output "oci_storage_namespace" {
  value = data.oci_objectstorage_namespace.ns.namespace
}