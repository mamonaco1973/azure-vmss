# ================================================================================
# Provider Configuration
# Pins the AWS provider to the 5.x major version. The ~> constraint allows
# minor-version upgrades (5.1, 5.2...) but blocks 6.x, preventing breaking
# changes from entering the build silently.
# ================================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# ================================================================================
# AMI Lookup
# Queries AWS for the latest Amazon Linux 2023 AMI at plan time, eliminating
# the need to hard-code an AMI ID or maintain a Packer pipeline. The filters
# narrow results to x86_64 HVM EBS-backed images published by Amazon, ensuring
# only official, production-grade images are selected.
# ================================================================================

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  # al2023-ami-2023* matches official AL2023 releases; excludes minimal/ECS
  # variants that ship without the package manager configured for httpd
  filter {
    name   = "name"
    values = ["al2023-ami-2023*arm64"]
  }

  # HVM (hardware virtual machine) is required for current-gen instance types;
  # paravirtual is a legacy mode not supported on t2/t3 and newer
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  # EBS-backed instances support stop/start and snapshot; instance-store
  # instances are ephemeral and cannot be stopped — EBS is the safe default
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
