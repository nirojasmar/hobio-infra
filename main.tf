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
  name          = "hobio-${var.type}-logging-ue1"
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
  name          = "hobio-${var.type}-tfstates-ue1"
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

resource "google_compute_router" "router" {
  name    = "hobio-${var.type}-router-ue1"
  region  = var.region
  network = "default"
}

resource "google_compute_router_nat" "nat" {
  name                               = "hobio-${var.type}-nat-ue1"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-ssh-via-iap"
  network = "default"

  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["allow-ssh"]
  description = "Allow SSH access via IAP"
}

resource "google_compute_instance" "rabbitmq_instance" {
  name         = "${var.project_id}-${var.environment}-rabbitmq-server"
  machine_type = "e2-micro"
  zone         = "${var.region}-b"
  tags = ["allow-ssh"]

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 30
    }
    # checkov:skip=CKV_GCP_38: We use GMEK for simplicity
  }

  network_interface {
    network = "default"
  }

  metadata = {
    block-project-ssh-keys = true
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