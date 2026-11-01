variable "aws_account_num" {
  type        = string
  description = "Account this environment deploys into."
}

variable "aws_role_name" {
  type        = string
  default     = ""
  description = "Deploy role to assume in the target account. Empty means use the caller's own credentials (AWS_PROFILE)."
}

variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "ap-southeast-1 (Singapore) is the closest region to the Philippines."
}

variable "environment" {
  type        = string
  description = "Environment name. Must match the selected Terraform workspace."
}

variable "default_tags" {
  type        = map(string)
  description = "Tags applied to every resource in this configuration."
}

variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "CloudWatch retention. Logs are not the system of record and cost money to keep forever."
}

# ---------------------------------------------------------------- Google sign-in
#
# Optional. research.md R4 wants Google first, because every Android phone is
# already signed into one — but the credentials come from a Google Cloud project set
# up separately, so the stack has to deploy without them. All three must be set, or
# none; see terraform/modules/cognito.
#
# The secret is read from Secrets Manager at apply time and never written to a
# tfvars file, the repository, or an environment variable.

variable "google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth client id."
}

variable "google_client_secret_name" {
  type        = string
  default     = ""
  description = "Name or ARN of the Secrets Manager secret holding the Google OAuth client secret."
}

variable "cognito_domain_prefix" {
  type        = string
  default     = ""
  description = "Hosted-UI domain prefix. Globally unique."
}

variable "oauth_callback_urls" {
  type        = list(string)
  default     = []
  description = "Allowed OAuth redirect targets for the hosted UI."
}
