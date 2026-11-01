# Sign-in. research.md R4, FR-058, FR-065, FR-066.
#
# Google first, because every Android phone is already signed into a Google account
# — sign-up is two taps with nothing to remember, and account recovery (FR-066) is
# Google's problem rather than ours. A farmer who forgets a password must never lose
# a season of records. Email and password is the fallback.

module "cognito" {
  source = "../../terraform/modules/cognito"

  user_pool_name = "${local.name}-users"
  client_name    = "${local.name}-app"

  # FR-065: a signed-in farmer must keep working offline. A year-long refresh token
  # means a session survives weeks in the field with no connection. Expiring it
  # sooner would lock a farmer out exactly when they are furthest from signal.
  refresh_token_validity_days = 365

  # The pool is the only route to a farmer's records. Deleting it orphans every
  # partition in DynamoDB, because the partition key IS the Cognito sub (FR-062) and
  # a rebuilt pool issues different ones.
  deletion_protection = true

  google_client_id      = var.google_client_id
  google_client_secret  = local.google_client_secret
  cognito_domain_prefix = var.cognito_domain_prefix
  oauth_callback_urls   = var.oauth_callback_urls
}
