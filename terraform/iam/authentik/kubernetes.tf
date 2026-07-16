# --- Kubernetes Clusters ---
resource "authentik_provider_oauth2" "kubernetes" {
  name               = "Kubernetes"
  client_type        = "public"
  invalidation_flow  = data.authentik_flow.default-authentication-flow.id
  client_id          = "kubernetes"
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
      url           = "http://localhost:8000"
    }
  ]
}

resource "authentik_application" "kubernetes" {
  name              = "Kubernetes"
  slug              = "kubernetes"
  protocol_provider = authentik_provider_oauth2.kubernetes.id
  group             = "Infrastructure"
}