# --- Headlamp Dashboard ---
resource "authentik_provider_oauth2" "headlamp" {
  name               = "Headlamp"
  client_type         = "confidential"
  authentication_flow = data.authentik_flow.default-authentication-flow.id
  authorization_flow  = data.authentik_flow.default-authorization-flow.id
  invalidation_flow   = data.authentik_flow.default-invalidation-flow.id
  client_id           = "headlamp"
  client_secret       = var.headlamp_client_secret
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

resource "authentik_policy_binding" "headlamp_admins" {
  target = authentik_application.headlamp.uuid
  group  = authentik_group.admins.id
  order  = 0
}