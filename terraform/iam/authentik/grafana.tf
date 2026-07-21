# --- Grafana ---
resource "authentik_provider_oauth2" "grafana" {
  name               = "Grafana"
  client_type        = "confidential"
  invalidation_flow  = data.authentik_flow.default-authentication-flow.id
  client_id          = "grafana"
  client_secret      = var.grafana_client_secret
  authorization_flow = data.authentik_flow.default-authorization-flow.id
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