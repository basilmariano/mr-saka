variable "name" {
  type        = string
  description = "Prefix for the vault, plan and role. Workspace-qualified by the caller, as everywhere else."
}

variable "resource_arns" {
  type        = list(string)
  description = "ARNs to back up. A list rather than a single ARN because a second table would otherwise need a second plan, vault and role for no reason."
}

variable "schedule" {
  type        = string
  default     = "cron(0 16 L * ? *)"
  description = <<-EOT
    When the monthly recovery point is taken. The default is 16:00 UTC on the last
    day of the month, which is midnight in Asia/Manila at the turn of the month --
    so the copy holds the farmer's month-end state in the farmer's own timezone,
    which is what SC-019 is written in terms of.
  EOT
}

variable "retention_days" {
  type        = number
  default     = 370
  description = <<-EOT
    How long each monthly copy is kept. FR-053f asks for 12 months; this is 370
    days rather than 365 so twelve copies are always present, instead of the
    oldest expiring days before its replacement is taken.
  EOT
}

variable "start_window_minutes" {
  type        = number
  default     = 60
  description = "How long AWS Backup may wait before starting the job. 60 is the AWS minimum."
}

variable "completion_window_minutes" {
  type        = number
  default     = 360
  description = "How long the job may take once started. Must exceed start_window_minutes."
}
