# --- Grafana ---
resource "authentik_provider_oauth2" "grafana" {
  name                = "Grafana"
  client_type         = "confidential"
  authentication_flow = data.authentik_flow.default-authentication-flow.id
  authorization_flow  = data.authentik_flow.default-authorization-flow.id
  invalidation_flow   = data.authentik_flow.default-invalidation-flow.id
  client_id           = "grafana"
  client_secret       = var.grafana_client_secret
  property_mappings = [
    data.authentik_property_mapping_provider_scope.scope_openid.id,
    data.authentik_property_mapping_provider_scope.scope_profile.id,
    data.authentik_property_mapping_provider_scope.scope_email.id
  ]
  signing_key = data.authentik_certificate_key_pair.default.id
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = var.grafana_redirect_uri
    }
  ]
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  group             = "Infrastructure"
}

resource "authentik_policy_binding" "grafana_admins" {
  target = authentik_application.grafana.uuid
  group  = authentik_group.admins.id
  order  = 0
}

resource "authentik_policy_binding" "grafana_standard_users" {
  target = authentik_application.grafana.uuid
  group  = authentik_group.standard_users.id
  order  = 1
}