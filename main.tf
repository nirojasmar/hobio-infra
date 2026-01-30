terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "logging_sink" {
  name          = "hobio-nonprod-logging-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  # checkov:skip=CKV_GCP_62: This is the destination bucket for GCS access logs; logging it would create a loop.
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
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

resource "google_storage_bucket" "logging_sink_prod" {
  name          = "hobio-prod-logging-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  # checkov:skip=CKV_GCP_62: This is the destination bucket for GCS access logs; logging it would create a loop.
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}

resource "google_storage_bucket" "terraform_state_prod" {
  name          = "hobio-prod-tfstates-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  logging {
    log_bucket = google_storage_bucket.logging_sink_prod.name
    log_object_prefix = "logs/tf-state"
  }

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}

resource "google_compute_instance" "rabbitmq_instance" {
  name         = "${var.project_id}-${var.environment}-rabbitmq"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 30
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y erlang
    sudo apt-get install -y rabbitmq-server
    sudo systemctl enable rabbitmq-server
    sudo systemctl start rabbitmq-server
  EOT

  labels = {
    environment = var.environment
    service     = "rabbitmq"
  }
}