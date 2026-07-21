# --- LDAP Configuration ---

# Service Account for LDAP Binding
resource "authentik_user" "ldap_bind" {
  username  = "ldap-bind"
  name      = "LDAP Bind Service Account"
  type      = "service_account"
  password  = var.ldap_bind_password
  is_active = true
}

resource "authentik_provider_ldap" "ldap_provider" {
  name        = "Internal LDAP Provider"
  base_dn     = var.ldap_base_dn
  bind_flow   = data.authentik_flow.default-authentication-flow.id
  unbind_flow = data.authentik_flow.default-authentication-flow.id
}

resource "authentik_application" "ldap" {
  name              = "Internal LDAP"
  slug              = "ldap"
  protocol_provider = authentik_provider_ldap.ldap_provider.id
}

resource "authentik_outpost" "ldap_outpost" {
  name               = "Internal LDAP Outpost"
  type               = "ldap"
  protocol_providers = [authentik_provider_ldap.ldap_provider.id]
  service_connection = data.authentik_service_connection_kubernetes.local.id

  config = jsonencode({
    authentik_host                   = var.authentik_internal_host
    authentik_host_insecure          = false
    kubernetes_replicas              = 1
    kubernetes_namespace             = var.cluster_namespace
    kubernetes_service_type          = "ClusterIP"
    object_naming_template           = var.resource_naming_template
    kubernetes_disabled_components   = []
    kubernetes_httproute_annotations = {}
    kubernetes_httproute_parent_refs = []
    kubernetes_image_pull_secrets    = []
    kubernetes_ingress_annotations   = {}
    kubernetes_ingress_class_name    = null
    kubernetes_service_annotations   = {}
  })
}