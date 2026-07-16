variable "authentik_url" {
  description = "The URL of the Authentik instance"
  type        = string
}

variable "authentik_token" {
  description = "Authentik API Token (Bootstrap Token)"
  type        = string
  sensitive   = true
}

variable "initial_admin_password" {
  description = "Password for the administrator user"
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Administrator's username"
  type        = string
}

variable "admin_full_name" {
  description = "Administrator's full name"
  type        = string
}

variable "admin_email" {
  description = "Administrator's email"
  type        = string
}

variable "grafana_redirect_uri" {
  type = string
}

variable "headscale_redirect_uri" {
  type = string
}

variable "headlamp_redirect_uri" {
  type = string
}

variable "grafana_client_secret" {
  type      = string
  sensitive = true
}

variable "headscale_client_secret" {
  type      = string
  sensitive = true
}

variable "headlamp_client_secret" {
  type      = string
  sensitive = true
}

variable "homarr_client_secret" {
  type      = string
  sensitive = true
}

variable "ldap_base_dn" {
  description = "The Base DN for the LDAP provider"
  type        = string
}

variable "ldap_bind_password" {
  description = "Password for the LDAP bind user"
  type        = string
  sensitive   = true
}

variable "cluster_namespace" {
  description = "Target namespace for cluster resources"
  type        = string
}

variable "authentik_internal_host" {
  description = "Internal URL for the Authentik server"
  type        = string
}

variable "cluster_service_connection_name" {
  description = "Name of the cluster service connection in Authentik"
  type        = string
}

variable "resource_naming_template" {
  description = "Naming template for created cluster resources"
  type        = string
}