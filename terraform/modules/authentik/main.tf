terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.5.0"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

# --- Shared Data ---
data "authentik_flow" "default-authorization-flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default-authentication-flow" {
  slug = "default-authentication-flow"
}

data "authentik_service_connection_kubernetes" "local" {
  name = var.cluster_service_connection_name
}

data "authentik_property_mapping_provider_scope" "scope_email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "scope_openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "scope_profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# --- Common Resources ---
resource "authentik_group" "admins" {
  name         = "Admins"
  is_superuser = true
}

resource "authentik_user" "admin" {
  username = var.admin_username
  name     = var.admin_full_name
  email    = var.admin_email
  password = var.initial_admin_password
  groups   = [authentik_group.admins.id]
}
