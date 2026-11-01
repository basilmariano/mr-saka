variable "api_gateway_name" {
  type        = string
  description = "The name of the API Gateway"
}

variable "api_gateway_body" {
  type        = string
  description = "The OpenAPI specification of the API Gateway, including the x-amazon-apigateway-* extensions that bind operations to integrations."
}

variable "api_gateway_endpoint_configuration_types" {
  type        = list(string)
  default     = null
  description = "The endpoint configuration types of the API Gateway."
  validation {
    condition     = try(length(var.api_gateway_endpoint_configuration_types), 0) > 0
    error_message = "api_gateway_endpoint_configuration_types must be provided."
  }
}

variable "api_gateway_stage_name" {
  type        = string
  description = "The name of the API Gateway stage"
}

variable "api_gateway_log_group_retention_in_days" {
  type        = number
  default     = 7
  description = "How long to keep API Gateway access logs, in days"
  validation {
    condition     = var.api_gateway_log_group_retention_in_days >= 0
    error_message = "The retention period must be 0 or greater."
  }
}

# ms-transactions puts a single Lambda behind its whole API. This one fans out to
# four, so the permission is granted per function rather than once.
variable "lambda_function_names" {
  type        = list(string)
  description = "Names of the Lambda functions this API may invoke"
  default     = []
}

variable "api_gateway_policy" {
  type        = string
  description = "API Gateway resource policy. Required for private APIs to restrict access."
  default     = null
}

variable "throttling_burst_limit" {
  type        = number
  default     = 100
  description = "Stops a bad client or a loop running up an unbounded bill."
}

variable "throttling_rate_limit" {
  type        = number
  default     = 50
  description = "Steady-state requests per second across the stage."
}
