terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
  # Bootstrap is the one stack that uses LOCAL state: it creates the bucket + lock table
  # every other stack stores its state in. Keep bootstrap/terraform.tfstate safe (it is gitignored).
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = "shared"
      Owner     = var.owner
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
