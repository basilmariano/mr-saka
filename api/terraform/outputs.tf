# What the Flutter app needs to talk to this environment.

output "api_base_url" {
  description = "Base URL for the API, including the stage."
  value       = module.saka_apigateway.invoke_url
}

output "user_pool_id" {
  value = module.cognito.user_pool_id
}

output "user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "table_name" {
  value = module.crop_tracking_table.table_name
}

output "region" {
  value = var.region
}

output "cognito_hosted_ui_domain" {
  description = "The hosted UI the app redirects through. Null means sign-in is not configured for this environment."
  value       = module.cognito.hosted_ui_domain == null ? null : "${module.cognito.hosted_ui_domain}.auth.${var.region}.amazoncognito.com"
}
