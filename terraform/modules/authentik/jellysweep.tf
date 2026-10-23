# --- Jellysweep ---
resource "authentik_provider_oauth2" "jellysweep" {
  name                = "Jellysweep"
  client_type         = "confidential"
  authentication_flow = data.authentik_flow.default-authentication-flow.id
  authorization_flow  = data.authentik_flow.default-authorization-flow.id
  invalidation_flow   = data.authentik_flow.default-invalidation-flow.id
  client_id           = "jellysweep"
  client_secret       = var.jellysweep_client_secret
  property_mappings = [
    data.authentik_property_mapping_provider_scope.scope_openid.id,
    data.authentik_property_mapping_provider_scope.scope_profile.id,
    data.authentik_property_mapping_provider_scope.scope_email.id
  ]
  signing_key = data.authentik_certificate_key_pair.default.id
  allowed_grant_types = [
    "authorization_code",
    "refresh_token"
  ]
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = var.jellysweep_redirect_uri
    }
  ]
}

resource "authentik_application" "jellysweep" {
  name              = "Jellysweep"
  slug              = "jellysweep"
  protocol_provider = authentik_provider_oauth2.jellysweep.id
  group             = "Infrastructure"
}

resource "authentik_policy_binding" "jellysweep_admins" {
  target = authentik_application.jellysweep.uuid
  group  = authentik_group.admins.id
  order  = 0
}

resource "authentik_policy_binding" "jellysweep_standard_users" {
  target = authentik_application.jellysweep.uuid
  group  = authentik_group.standard_users.id
  order  = 1
}

