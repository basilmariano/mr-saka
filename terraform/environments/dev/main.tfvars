aws_account_num = "251978470165"

# ap-southeast-1 (Singapore) is the closest region to the Philippines.
region = "ap-southeast-1"

environment           = "dev"
log_retention_in_days = 7

default_tags = {
  "owner"       = "saka"
  "saka:team"   = "saka"
  "saka:env"    = "saka-dev"
  "saka:system" = "crop-tracking"
}

# The hosted UI the app redirects through for EVERY sign-in, email and password
# included. The prefix is globally unique across all of AWS, so an apply can fail
# here on someone else's name -- change it rather than assuming a broken config.
cognito_domain_prefix = "saka-dev-login"

# Must match the app's own scheme exactly. ph.saka.saka is the Android
# applicationId and the iOS bundle id; AppAuth listens on it for the redirect.
oauth_callback_urls = ["ph.saka.saka://callback"]

# Google sign-in additionally needs these two. Until they are set the pool offers
# email and password only, through the same hosted UI.
# google_client_id          = "....apps.googleusercontent.com"
# google_client_secret_name = "saka/dev/google-oauth"
