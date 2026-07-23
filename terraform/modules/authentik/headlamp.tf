# --- Headlamp Dashboard ---
resource "authentik_provider_oauth2" "headlamp" {
  name               = "Headlamp"
  client_type        = "confidential"
  invalidation_flow  = data.authentik_flow.default-authentication-flow.id
  client_id          = "headlamp"
  client_secret      = var.headlamp_client_secret
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
      url           = var.headlamp_redirect_uri
    }
  ]
}

resource "authentik_application" "headlamp" {
  name              = "Headlamp"
  slug              = "headlamp"
  protocol_provider = authentik_provider_oauth2.headlamp.id
  group             = "Infrastructure"
}