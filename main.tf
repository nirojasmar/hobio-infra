terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.16.0"
    }
  }
}

provider "google" {
  project = "hobio-nonprod"
  region  = "us-east1"
}

resource "google_storage_bucket" "terraform_state" {
  name          = "hobio-nonprod-tfstates-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}
