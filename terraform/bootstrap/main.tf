# Terraform state storage, one bucket per environment.
#
# Applied ONCE per environment, before anything in api/terraform. It keeps its own
# state on local disk because it is the thing that creates remote state — it cannot
# store state in a bucket that does not exist yet. That local file matters far less
# than the real one: everything here is re-creatable from this config, and
# `terraform import` recovers it in a minute.
#
#   terraform -chdir=terraform/bootstrap apply -var environment=dev

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = var.default_tags
  }
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be dev, stg or prd."
  }
}

variable "default_tags" {
  type = map(string)
  default = {
    "owner"       = "saka"
    "saka:team"   = "saka"
    "saka:system" = "crop-tracking"
  }
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.environment}-saka-terraformstate"

  # Losing this loses Terraform's record of every deployed resource, including the
  # table holding farmers' records. Destroying it must take a deliberate code
  # change, not a stray `terraform destroy`.
  lifecycle {
    prevent_destroy = true
  }
}

# What makes a corrupted or truncated state recoverable: the previous object
# version is still there to roll back to.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State holds resource attributes in plain text. None of it should be reachable
# from the internet.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

# ---------------------------------------------------------------------------
# API Gateway account-level logging role.
#
# REST APIs refuse to enable stage logging until this is set, and it is a SINGLETON
# per account and region -- not per API, not per stage. So it cannot live in the
# apigateway module: a second service using that module would fight this one for
# ownership of the same global setting, and whichever applied last would win.
#
# It belongs here for the same reason the state bucket does: this is the module
# that runs once per account, before anything else.
#
# Discovered the hard way on 2026-11-02 -- `terraform validate` and `terraform plan`
# both pass without it, and the apply fails partway through with "CloudWatch Logs
# role ARN must be set in account settings", after the REST API and its Lambda
# permissions have already been created.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "apigateway_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigateway_cloudwatch" {
  name               = "${var.environment}-saka-apigateway-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume.json
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch" {
  role       = aws_iam_role.apigateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch.arn
}
