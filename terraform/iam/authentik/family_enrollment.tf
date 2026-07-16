# --- Group for Jellyfin Users ---
resource "authentik_group" "jellyfin_users" {
  name = "jellyfin-users"
}

# --- Family Enrollment Flow ---
resource "authentik_flow" "family_enrollment" {
  name        = "Family Enrollment Flow"
  slug        = "family-enrollment"
  title       = "Create your Delva-Home Account"
  designation = "enrollment"
}

# --- Stages ---

# 1. Invitation Stage
resource "authentik_stage_invitation" "family_enrollment_invitation" {
  name                             = "family-invitation"
  continue_flow_without_invitation = false # Strictly require a valid invitation token
}

# 2. Prompt Stage (User Input Fields)
resource "authentik_stage_prompt_field" "username" {
  name      = "family-field-username"
  field_key = "username"
  label     = "Username"
  type      = "username"
  required  = true
  order     = 0
}

resource "authentik_stage_prompt_field" "name" {
  name      = "family-field-name"
  field_key = "name"
  label     = "Full Name"
  type      = "text"
  required  = true
  order     = 1
}

resource "authentik_stage_prompt_field" "email" {
  name      = "family-field-email"
  field_key = "email"
  label     = "Email Address"
  type      = "email"
  required  = true
  order     = 2
}

resource "authentik_stage_prompt_field" "password" {
  name      = "family-field-password"
  field_key = "password"
  label     = "Password"
  type      = "password"
  required  = true
  order     = 3
}

resource "authentik_stage_prompt_field" "password_repeat" {
  name      = "family-field-password-repeat"
  field_key = "password_repeat"
  label     = "Confirm Password"
  type      = "password"
  required  = true
  order     = 4
}

resource "authentik_stage_prompt" "family_enrollment_prompt" {
  name   = "family-prompt"
  fields = [
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.name.id,
    authentik_stage_prompt_field.email.id,
    authentik_stage_prompt_field.password.id,
    authentik_stage_prompt_field.password_repeat.id
  ]
}

# 3. User Write Stage
resource "authentik_stage_user_write" "family_enrollment_write" {
  name                     = "family-write"
  create_users_as_inactive = false
  create_users_group       = authentik_group.jellyfin_users.id
}

# --- Stage Bindings ---

resource "authentik_flow_stage_binding" "bind_invitation" {
  target = authentik_flow.family_enrollment.uuid
  stage  = authentik_stage_invitation.family_enrollment_invitation.id
  order  = 0
}

resource "authentik_flow_stage_binding" "bind_prompt" {
  target = authentik_flow.family_enrollment.uuid
  stage  = authentik_stage_prompt.family_enrollment_prompt.id
  order  = 10
}

resource "authentik_flow_stage_binding" "bind_write" {
  target = authentik_flow.family_enrollment.uuid
  stage  = authentik_stage_user_write.family_enrollment_write.id
  order  = 20
}
