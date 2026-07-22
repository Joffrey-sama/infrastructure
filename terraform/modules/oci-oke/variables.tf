variable "region" {
  description = "OCI region (e.g., us-phoenix-1, eu-frankfurt-1)"
  type        = string
  default     = "eu-paris-1"
}

variable "compartment_id" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "v1.35.2"
}

variable "node_pool_size" {
  description = "Number of nodes in the node pool (free tier max: 3 Ampere A1 instances)"
  type        = number
  default     = 2
  validation {
    condition     = var.node_pool_size >= 1 && var.node_pool_size <= 3
    error_message = "Node pool size must be between 1 and 3 for free tier."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}


# --- Cloud Configuration ---
variable "cloud_cluster_cidr" {
  description = "VCN CIDR (Cloud Nodes)"
  type        = string
  default     = "10.0.0.0/16"
}


variable "cloud_nodes_cidr" {
  description = "CIDR block for the Cloud nodes on OCI"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cloud_pods_cidr" {
  description = "CIDR block for the Cloud pods on OCI"
  type        = string
  default     = "10.244.0.0/16"
}

# --- On-Premise Configuration ---
variable "onprem_cpe_ip" {
  description = "Public IP of the local box/VPN gateway"
  type        = string
}

variable "onprem_nodes_cidr" {
  description = "Nodes CIDR of the On-Premise cluster"
  type        = string
}

variable "onprem_pods_cidr" {
  description = "Pods CIDR of the On-Premise cluster"
  type        = string
}

variable "vpn_vip" {
  description = "VIP used for the Site-to-Site VPN (must be a static IP)"
  type        = string
}

variable "admin_source_cidr" {
  description = "Your public IP for SSH/API administrative access"
  type        = string
}

variable "user_ocid" {
  description = "Your OCID user to generate Customer Secret Keys"
  type        = string
}