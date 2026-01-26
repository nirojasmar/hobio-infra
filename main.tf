terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
  }
}

provider "google" {
  project = "hobio-nonprod"
  region  = "us-east1"
}

resource "google_storage_bucket" "logging_sink" {
  name          = "hobio-nonprod-logging-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  public_access_prevention = "enforced"
}

resource "google_storage_bucket" "terraform_state" {
  name          = "hobio-nonprod-tfstates-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  logging {
    log_bucket = google_storage_bucket.logging_sink.name
    log_object_prefix = "logs/tf-state"
  }

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}