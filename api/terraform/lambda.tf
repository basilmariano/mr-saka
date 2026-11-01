# The four handlers, and the IAM that decides what each may touch.
#
# Permissions are per-function rather than one shared role, because the blast radius
# of a bug differs sharply between them: `snapshot` only ever reads, and `reference`
# serves public agronomic data and has no business seeing the table at all.

locals {
  lambda_functions = {
    mutations = {
      table = "write"
    }
    snapshot = {
      table = "read"
    }
    account = {
      table = "write"
    }
    reference = {
      table = "none"
    }
  }

  dynamodb_write_actions = [
    "dynamodb:GetItem",
    "dynamodb:Query",
    "dynamodb:PutItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem",
    "dynamodb:BatchWriteItem",
    "dynamodb:BatchGetItem",
  ]

  dynamodb_read_actions = [
    "dynamodb:GetItem",
    "dynamodb:Query",
    "dynamodb:BatchGetItem",
  ]
}

module "lambda" {
  source   = "../../terraform/modules/lambda-function"
  for_each = local.lambda_functions

  function_name = "${local.name}-${each.key}"
  src_path      = "../build/${each.key}.zip"
  handler       = "index.handler"

  runtime = "nodejs22.x"

  # Generous for this workload. The slow path is a farmer's whole offline backlog
  # arriving at once after a week without signal, and timing out mid-batch would
  # leave the outbox stalled at the same entry on every retry.
  timeout     = 30
  memory_size = 512

  aws_cloudwatch_log_retention = var.log_retention_in_days

  env_vars = {
    TABLE_NAME  = module.crop_tracking_table.table_name
    ENVIRONMENT = var.environment
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = "arn:aws:logs:*:*:*"
        }
      ],
      each.value.table == "none" ? [] : [
        {
          Effect   = "Allow"
          Action   = each.value.table == "write" ? local.dynamodb_write_actions : local.dynamodb_read_actions
          Resource = module.crop_tracking_table.table_arn
        }
      ]
    )
  })
}
