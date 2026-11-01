variable "user_pool_name" {
  type        = string
  description = "Name of the Cognito user pool"
}

variable "client_name" {
  type        = string
  description = "Name of the app client"
}

variable "refresh_token_validity_days" {
  type        = number
  default     = 365
  description = "How long a session survives without re-authenticating."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Whether the pool refuses deletion."
}

variable "google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth client id. All three Google variables must be set, or none."
}

variable "google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Google OAuth client secret, read from Secrets Manager by the caller."
}

variable "cognito_domain_prefix" {
  type        = string
  default     = ""
  description = "Hosted-UI domain prefix. Globally unique. Only needed for Google sign-in."
}

variable "oauth_callback_urls" {
  type        = list(string)
  default     = []
  description = "Allowed OAuth redirect targets for the hosted UI."
}
