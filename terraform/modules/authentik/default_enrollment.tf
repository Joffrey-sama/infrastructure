# --- Group for Standard Users ---
resource "authentik_group" "standard_users" {
  name = var.default_user_group_name
}

# --- Default Enrollment Flow ---
resource "authentik_flow" "default_enrollment" {
  name        = "Default Enrollment Flow"
  slug        = "default-enrollment"
  title       = "Create your ${var.brand_name} Account"
  designation = "enrollment"
}

# --- Stages ---

# 1. Invitation Stage
resource "authentik_stage_invitation" "default_enrollment_invitation" {
  name                             = "default-invitation"
  continue_flow_without_invitation = false # Strictly require a valid invitation token
}

# 2. Prompt Stage (User Input Fields)
resource "authentik_stage_prompt_field" "username" {
  name      = "default-field-username"
  field_key = "username"
  label     = "Username"
  type      = "username"
  required  = true
  order     = 0
}

resource "authentik_stage_prompt_field" "name" {
  name      = "default-field-name"
  field_key = "name"
  label     = "Full Name"
  type      = "text"
  required  = true
  order     = 1
}

resource "authentik_stage_prompt_field" "email" {
  name      = "default-field-email"
  field_key = "email"
  label     = "Email Address"
  type      = "email"
  required  = true
  order     = 2
}

resource "authentik_stage_prompt_field" "password" {
  name      = "default-field-password"
  field_key = "password"
  label     = "Password"
  type      = "password"
  required  = true
  order     = 3
}

resource "authentik_stage_prompt_field" "password_repeat" {
  name      = "default-field-password-repeat"
  field_key = "password_repeat"
  label     = "Confirm Password"
  type      = "password"
  required  = true
  order     = 4
}

resource "authentik_stage_prompt" "default_enrollment_prompt" {
  name = "default-prompt"
  fields = [
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.name.id,
    authentik_stage_prompt_field.email.id,
    authentik_stage_prompt_field.password.id,
    authentik_stage_prompt_field.password_repeat.id
  ]
}

# 3. User Write Stage
resource "authentik_stage_user_write" "default_enrollment_write" {
  name                     = "default-write"
  create_users_as_inactive = false
  create_users_group       = authentik_group.standard_users.id
}

# --- Stage Bindings ---

resource "authentik_flow_stage_binding" "bind_invitation" {
  target = authentik_flow.default_enrollment.uuid
  stage  = authentik_stage_invitation.default_enrollment_invitation.id
  order  = 0
}

resource "authentik_flow_stage_binding" "bind_prompt" {
  target = authentik_flow.default_enrollment.uuid
  stage  = authentik_stage_prompt.default_enrollment_prompt.id
  order  = 10
}

resource "authentik_flow_stage_binding" "bind_write" {
  target = authentik_flow.default_enrollment.uuid
  stage  = authentik_stage_user_write.default_enrollment_write.id
  order  = 20
}
