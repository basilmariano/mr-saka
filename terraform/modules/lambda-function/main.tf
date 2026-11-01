data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = var.function_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "main" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.iam_for_lambda.id
  policy = var.policy
}

# Declared rather than left to Lambda's implicit creation, so retention is set and
# the group is destroyed with the stack instead of lingering and billing forever.
resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.aws_cloudwatch_log_retention
}

resource "aws_lambda_function" "main" {
  function_name = var.function_name
  role          = aws_iam_role.iam_for_lambda.arn

  filename = var.src_path
  # Without this Terraform compares only the filename and never notices the code
  # inside changed — so `apply` reports no changes and quietly deploys nothing.
  source_code_hash = filebase64sha256(var.src_path)

  runtime                        = var.runtime
  handler                        = var.handler
  timeout                        = var.timeout
  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions

  dynamic "environment" {
    for_each = length(var.env_vars) > 0 ? [1] : []
    content {
      variables = var.env_vars
    }
  }

  depends_on = [aws_cloudwatch_log_group.main]
}
