# --- Homarr Dashboard ---
resource "authentik_provider_oauth2" "homarr" {
  name               = "Homarr"
  client_type        = "confidential"
  invalidation_flow  = data.authentik_flow.default-authentication-flow.id
  client_id          = "homarr"
  client_secret      = var.homarr_client_secret
  authorization_flow = data.authentik_flow.default-authorization-flow.id
  property_mappings  = [
    data.authentik_property_mapping_provider_scope.scope_openid.id,
    data.authentik_property_mapping_provider_scope.scope_profile.id,
    data.authentik_property_mapping_provider_scope.scope_email.id
  ]
  signing_key        = data.authentik_certificate_key_pair.default.id
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://homarr.internal.delva-home.fr/api/auth/callback/oidc"
    }
  ]
}

resource "authentik_application" "homarr" {
  name              = "Homarr"
  slug              = "homarr"
  protocol_provider = authentik_provider_oauth2.homarr.id
  group             = "Infrastructure"
}