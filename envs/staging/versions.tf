terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Partial backend config: bucket/table come from backend.hcl (see backend.hcl.example),
  # so account-specific names never get committed.
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key     = "staging/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = "staging"
      Owner     = var.owner
      ManagedBy = "terraform"
      # scripts/cost-check.sh looks for these tags
      TTL = "manual"
    }
  }
}
