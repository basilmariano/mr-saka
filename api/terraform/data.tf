data "aws_region" "current" {}

data "aws_secretsmanager_secret" "google" {
  count = local.google_enabled ? 1 : 0
  name  = var.google_client_secret_name
}

data "aws_secretsmanager_secret_version" "google" {
  count     = local.google_enabled ? 1 : 0
  secret_id = data.aws_secretsmanager_secret.google[0].id
}
