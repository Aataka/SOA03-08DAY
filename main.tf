terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.region
}

# Route 53 ヘルスチェックの CloudWatch メトリクス(HealthCheckStatus) は
# us-east-1 にのみ発行される。アラームはこのエイリアスで作る。
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name = "${var.name_prefix}-${random_id.suffix.hex}"
  tags = {
    Project = "SOA03-08DAY"
    Purpose = "high-availability-alb-asg-rds"
  }
}
