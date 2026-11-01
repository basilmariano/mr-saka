locals {
  # Google sign-in needs all three: the client id, the secret, and a hosted-UI
  # domain to redirect through. Partial configuration is a mistake rather than a
  # half-feature, so it is caught here instead of producing a pool that advertises a
  # provider it cannot complete.
  #
  # nonsensitive() wraps only the EMPTINESS CHECK, never the secret. Without it
  # Terraform propagates the secret's sensitivity through google_enabled into
  # every resource and output that branches on it, and `terraform plan` fails with
  # "Output refers to sensitive values" on hosted_ui_domain -- a public redirect
  # URL the app needs in its .env. Whether a secret was supplied is not itself a
  # secret; its value never leaves this expression.
  # The hosted UI is what the app redirects through for EVERY sign-in, including
  # plain email and password -- it is not a Google-only feature. It exists as soon
  # as there is a domain prefix to host it on.
  hosted_ui_enabled = var.cognito_domain_prefix != ""

  # Google needs all three: the client id, the secret, and a hosted UI to redirect
  # through. Partial configuration is a mistake rather than a half-feature, so it
  # is caught here instead of producing a pool that advertises a provider it cannot
  # complete.
  google_enabled = (
    var.google_client_id != "" &&
    nonsensitive(var.google_client_secret != "") &&
    local.hosted_ui_enabled
  )
}

resource "aws_cognito_user_pool" "main" {
  name = var.user_pool_name

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Deliberately permissive on composition and strict on length. Someone typing on a
  # phone keyboard in a field will not produce a symbol-and-uppercase password from
  # memory; they will write it down or give up. Length is what resists guessing.
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = false
    temporary_password_validity_days = 7
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"
}

resource "aws_cognito_identity_provider" "google" {
  count = local.google_enabled ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "email profile openid"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }

  lifecycle {
    # Cognito fills in Google's own endpoint URLs the moment the provider is
    # created. They are not ours to declare, so Terraform sees keys it did not set
    # and plans to delete them; AWS puts them straight back. Left alone that is a
    # diff on EVERY plan forever, which is worse than untidy: it buries real drift
    # in noise, and a drift check that always reports a change reports nothing.
    #
    # Ignoring the whole map would also stop us noticing a changed client_id or a
    # rotated secret, so each server-owned key is named individually. The three
    # keys we actually set stay under management.
    ignore_changes = [
      provider_details["attributes_url"],
      provider_details["attributes_url_add_attributes"],
      provider_details["authorize_url"],
      provider_details["oidc_issuer"],
      provider_details["token_request_method"],
      provider_details["token_url"],
    ]
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  count = local.hosted_ui_enabled ? 1 : 0

  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "app" {
  name         = var.client_name
  user_pool_id = aws_cognito_user_pool.main.id

  # Public mobile client: it ships on the handset, so it cannot hold a secret.
  generate_secret = false

  # SRP never puts the password on the wire. REFRESH_AUTH is what makes the long
  # refresh token usable.
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  refresh_token_validity = var.refresh_token_validity_days
  access_token_validity  = 1
  id_token_validity      = 1

  token_validity_units {
    refresh_token = "days"
    access_token  = "hours"
    id_token      = "hours"
  }

  # Does not reveal whether an email is registered, so the pool cannot be used to
  # enumerate who uses the app.
  prevent_user_existence_errors = "ENABLED"

  supported_identity_providers = local.google_enabled ? ["COGNITO", "Google"] : ["COGNITO"]

  # Authorization code + PKCE, which is what a public mobile client must use: the
  # app ships on the handset and holds no secret, so the implicit flow would put a
  # token in a redirect URL. Gated on the hosted UI rather than on Google, because
  # email and password sign-in goes through the same flow.
  allowed_oauth_flows                  = local.hosted_ui_enabled ? ["code"] : []
  allowed_oauth_scopes                 = local.hosted_ui_enabled ? ["email", "openid", "profile"] : []
  allowed_oauth_flows_user_pool_client = local.hosted_ui_enabled
  callback_urls                        = var.oauth_callback_urls

  depends_on = [aws_cognito_identity_provider.google]
}
