output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "hosted_ui_domain" {
  description = "Set whenever a domain prefix is configured. Null means the app has no sign-in flow to redirect through."
  value       = local.hosted_ui_enabled ? aws_cognito_user_pool_domain.main[0].domain : null
}
