variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "billing_mode" {
  description = "Billing mode: PROVISIONED or PAY_PER_REQUEST"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "hash_key" {
  description = "Primary key hash key name"
  type        = string
}

variable "range_key" {
  description = "Primary key range (sort) key name, if the table needs a composite key"
  type        = string
  default     = null
}

variable "attributes" {
  description = "Key attribute definitions. Only key attributes belong here — DynamoDB is schemaless for the rest, and declaring a non-key attribute is an error rather than a hint."
  type = list(object({
    name = string
    type = string
  }))
}

variable "global_secondary_indexes" {
  description = "List of global secondary indexes"
  type = list(object({
    name            = string
    hash_key        = string
    range_key       = optional(string)
    projection_type = optional(string)
  }))
  default = []
}

variable "point_in_time_recovery" {
  description = "Continuous backups. On by default because the table is usually the system of record."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Refuses an API-side delete. Leave on for any table holding data that cannot be regenerated."
  type        = bool
  default     = true
}
