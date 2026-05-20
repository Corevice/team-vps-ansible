terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
  backend "s3" {
    bucket  = "codens-tfstate-prod"
    key     = "team-vps/aws.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "codens-vps"
      ManagedBy = "terraform"
      Repo      = "codens-main/plans/team-vps-setup"
    }
  }
}
