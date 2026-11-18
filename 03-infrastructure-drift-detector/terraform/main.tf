terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "use_localstack" {
  type    = bool
  default = true
}
variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "bucket_name" {
  type    = string
  default = "drift-demo-app-data"
}

provider "aws" {
  region                      = var.region
  access_key                  = var.use_localstack ? "test" : null
  secret_key                  = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      s3  = var.localstack_endpoint
      sqs = var.localstack_endpoint
    }
  }
}

locals {
  tags = { Project = "drift-demo", Owner = "platform", ManagedBy = "terraform" }
}

resource "aws_s3_bucket" "data" {
  bucket = var.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_sqs_queue" "jobs" {
  name                       = "drift-demo-jobs"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  tags                       = local.tags
}

output "bucket" { value = aws_s3_bucket.data.id }
output "queue_url" { value = aws_sqs_queue.jobs.url }
