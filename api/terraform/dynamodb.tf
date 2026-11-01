# The single table. research.md R7, contracts/sync-protocol.md.
#
# PK = ACCOUNT#<cognito sub>, SK = entity-specific. Every access pattern the feature
# needs is satisfied without a secondary index: a full restore is one Query on PK,
# everything in one cropping is a Query with begins_with(SK, "CROP#<id>"), and a
# single record is a GetItem. Adding a GSI later is additive; designing one in now
# would be guessing.

module "crop_tracking_table" {
  source = "../../terraform/modules/dynamodb"

  table_name = "${local.name}-crop-tracking"

  # On-demand because usage is spiky — a burst when a farmer comes back into signal
  # after a week offline — and far too low to justify provisioned throughput.
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "PK"
  range_key = "SK"

  attributes = [
    { name = "PK", type = "S" },
    { name = "SK", type = "S" },
  ]

  # This table IS the farmer's durable copy (FR-053). Losing it loses the history
  # the app exists to protect.
  point_in_time_recovery = true
  deletion_protection    = true
}
