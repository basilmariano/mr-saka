variable "function_name" {
  description = "The function name of the lambda"
  type        = string
}

variable "src_path" {
  description = "The filename path of the function's package"
  type        = string
}

variable "handler" {
  description = "The lambda function code entrypoint"
  type        = string
}

variable "policy" {
  description = "The lambda policy, as a JSON document"
  type        = string
}

variable "env_vars" {
  description = "Lambda environment variables"
  type        = map(string)
  default     = {}
}

variable "aws_cloudwatch_log_retention" {
  description = "How long to keep CloudWatch logs, in days"
  type        = number
  default     = 7
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs22.x"
}

variable "timeout" {
  description = "Seconds before Lambda forcibly terminates the function. Maximum 900."
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Memory in MB"
  type        = number
  default     = 512
}

variable "reserved_concurrent_executions" {
  description = "Caps how much of the account's concurrency this function can take. -1 means unreserved."
  type        = number
  default     = -1
}
