# Scheduled copies of a durable store, kept long enough to outlive the window in
# which nobody has noticed the damage yet.
#
# This is the SECOND restore tier. Point-in-time recovery on the table itself
# covers the first 35 days continuously; it is the right tool when someone spots
# a bad release the same week. It cannot help when a wrong figure is found a
# season later, because by then the window has closed -- and a season here runs
# about four months. Hence FR-053f, and hence this module.

resource "aws_backup_vault" "vault" {
  name = "${var.name}-vault"

  # Deliberately NOT force_destroy. The vault refuses to be deleted while it
  # still holds recovery points, so a `terraform destroy` cannot quietly take the
  # backups with it -- which is the failure this whole module exists to prevent.
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Restore permissions live on the same role on purpose. A backup nobody has ever
# restored is a belief, not a backup, and SC-019 is written as a drill rather
# than as a setting -- so the role that takes the copies must also be able to
# put them back.
resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "plan" {
  name = "${var.name}-monthly"

  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.vault.name
    schedule          = var.schedule

    start_window      = var.start_window_minutes
    completion_window = var.completion_window_minutes

    lifecycle {
      delete_after = var.retention_days
    }
  }
}

resource "aws_backup_selection" "selection" {
  name         = "${var.name}-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.plan.id

  # Named ARNs rather than a tag selector. A tag selector is more flexible and
  # fails open: mistype the tag on a new table and it is silently unprotected,
  # with nothing in the plan to show it. Listing the ARNs means an unprotected
  # table is visible in a diff.
  resources = var.resource_arns
}
