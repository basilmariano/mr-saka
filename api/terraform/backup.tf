# FR-053f, second tier. Monthly copies kept 12 months, on top of the table's own
# 35 days of point-in-time recovery.
#
# The two tiers answer different questions. PITR answers "put it back to just
# before the bad release went out", and only works if someone notices inside 35
# days. This answers "put it back to how it was at the end of March", which is
# the question a farmer actually asks -- they find the wrong figure when they
# compare this season against the last one, by which time the PITR window has
# long closed. research.md R12.

module "backup" {
  source = "../../terraform/modules/backup"

  name          = "${local.name}-crop-tracking"
  resource_arns = [module.crop_tracking_table.table_arn]
}
