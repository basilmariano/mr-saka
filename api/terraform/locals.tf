locals {
  # terraform.workspace drives every resource name, as in mr-billing, so two
  # environments cannot collide even if they share an account.
  name = "${terraform.workspace}-saka"

  google_enabled = (
    var.google_client_id != "" &&
    var.google_client_secret_name != "" &&
    var.cognito_domain_prefix != ""
  )

  # Secrets Manager stores whatever shape whoever created the secret chose. The
  # console's default "Key/value" tab writes {"<name>":"<secret>"}; its "Plaintext"
  # tab writes the bare secret. Google accepts only the bare secret, and handing it
  # the JSON fails as `invalid_client` at the farmer's first tap on "Continue with
  # Google" -- long after the apply reported success. Which tab someone happened to
  # click must not decide whether sign-in works.
  google_secret_raw = local.google_enabled ? data.aws_secretsmanager_secret_version.google[0].secret_string : ""

  # tomap() rejects a decoded number or bare string, so only a real JSON object takes
  # this path. A multi-key object deliberately falls through to the raw value, which
  # the postcondition in data.tf then rejects by name: with several entries there is
  # no way to know which one Google wants, and guessing would fail silently.
  google_secret_map = try(tomap(jsondecode(local.google_secret_raw)), null)

  google_client_secret = (
    local.google_secret_map != null && length(local.google_secret_map) == 1
    ? values(local.google_secret_map)[0]
    : local.google_secret_raw
  )

  # The routing source of truth. Operations, which require auth and which do not,
  # and the Cognito authorizer all live in this document — changing a route means
  # changing the contract rather than hand-editing resources.
  api_gateway_body = templatefile("../src/docs/saka-api.json", {
    api_name             = "${local.name}-api"
    user_pool_arn        = module.cognito.user_pool_arn
    mutations_invoke_arn = module.lambda["mutations"].invoke_arn
    snapshot_invoke_arn  = module.lambda["snapshot"].invoke_arn
    account_invoke_arn   = module.lambda["account"].invoke_arn
    reference_invoke_arn = module.lambda["reference"].invoke_arn
  })
}
