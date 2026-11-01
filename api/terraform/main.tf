terraform {
  # bucket, region, encrypt and use_lockfile come from
  # terraform/environments/<env>/backend.hcl, passed with -backend-config, so each
  # environment keeps its state in its own bucket.
  backend "s3" {
    key = "saka-api/terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46.0"
    }
  }
}

provider "aws" {
  region = var.region

  # mr-billing assumes a deploy role into the target account. Saka currently
  # authenticates as an IAM user via AWS_PROFILE, so the block is conditional: set
  # aws_role_name once a deploy role exists and nothing else changes.
  dynamic "assume_role" {
    for_each = var.aws_role_name == "" ? [] : [1]
    content {
      role_arn = "arn:aws:iam::${var.aws_account_num}:role/${var.aws_role_name}"
    }
  }

  default_tags {
    tags = var.default_tags
  }
}
