resource "aws_dynamodb_table" "dynamodb_table" {
  name         = var.table_name
  billing_mode = var.billing_mode

  hash_key  = var.hash_key
  range_key = var.range_key

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = coalesce(global_secondary_index.value.projection_type, "ALL")
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.deletion_protection

  # A SECOND, independent guard. The two fail differently and that is the point:
  # deletion_protection_enabled refuses a delete issued through the AWS API, while
  # prevent_destroy stops Terraform planning one in the first place -- including
  # the replacements Terraform decides on by itself when an immutable attribute
  # such as hash_key changes.
  #
  # Not driven by a variable, because a lifecycle block cannot reference one. That
  # is a Terraform limitation rather than a choice, and it means every table built
  # from this module is protected. For a module whose purpose is durable stores,
  # that default is the right way round.
  lifecycle {
    prevent_destroy = true
  }
}
