data "aws_region" "current" {}

data "aws_secretsmanager_secret" "google" {
  count = local.google_enabled ? 1 : 0
  name  = var.google_client_secret_name
}

data "aws_secretsmanager_secret_version" "google" {
  count     = local.google_enabled ? 1 : 0
  secret_id = data.aws_secretsmanager_secret.google[0].id

  lifecycle {
    # The usable shapes are a bare secret or a single-key JSON object (see locals.tf).
    # Anything else is caught here, at plan time, rather than becoming an opaque
    # `invalid_client` from Google that looks like a Cognito misconfiguration.
    #
    # nonsensitive() wraps only the verdict, never the secret: whether a stored value
    # has a usable SHAPE is not itself a secret, and without the wrapper the condition
    # taints the plan the same way google_enabled once did.
    postcondition {
      condition = nonsensitive(
        length(trimspace(self.secret_string)) > 0 &&
        try(length(tomap(jsondecode(self.secret_string))) == 1, true)
      )
      error_message = <<-EOT
        Secret ${var.google_client_secret_name} is empty, or is a JSON object with
        more than one key, so there is no way to tell which entry is the Google
        client secret. Store the bare secret (Secrets Manager console -> Plaintext),
        or a JSON object holding exactly one key.
      EOT
    }
  }
}
