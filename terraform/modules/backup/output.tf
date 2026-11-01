output "vault_name" {
  value = aws_backup_vault.vault.name
}

output "vault_arn" {
  value = aws_backup_vault.vault.arn
}

output "plan_id" {
  value = aws_backup_plan.plan.id
}

output "role_arn" {
  description = "The role AWS Backup assumes. Also carries restore permissions, which is what a restore drill needs."
  value       = aws_iam_role.backup.arn
}
