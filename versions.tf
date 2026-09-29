terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source = "hashicorp/google"
      # 7.33.0 added deletion_policy to google_service_account.
      version = ">= 7.33.0, < 9.0.0"
    }
  }
}
