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

locals {
  create_shared_infra = var.environment == "dev" || var.environment == "prod"
}

data "google_project" "current" {}

resource "google_secret_manager_secret" "rabbitmq_connection_string" {
  secret_id = "rabbitmq-connection-string-${var.environment}"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    service     = "rabbitmq"
  }
}

resource "google_secret_manager_secret_iam_member" "cloudrun_access_connection_string" {
  secret_id = google_secret_manager_secret.rabbitmq_connection_string.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  depends_on = [google_secret_manager_secret.rabbitmq_connection_string]
}

resource "google_secret_manager_secret" "rabbitmq_pass" {
  secret_id = "rabbitmq-password-${var.environment}"

  replication {
    auto {}
  }

  labels = {
    environment = var.environment
    service     = "rabbitmq"
  }
}

resource "google_secret_manager_secret_iam_member" "cloudrun_access_pass" {
  secret_id = google_secret_manager_secret.rabbitmq_pass.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  depends_on = [google_secret_manager_secret.rabbitmq_pass]
}

resource "google_storage_bucket" "logging_sink" {
  count         = local.create_shared_infra ? 1 : 0
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
  count         = local.create_shared_infra ? 1 : 0
  name          = "hobio-${var.type}-tfstates-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  logging {
    log_bucket        = google_storage_bucket.logging_sink[0].name
    log_object_prefix = "logs/tf-state/${var.environment}"
  }

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}

resource "google_storage_bucket" "reports_bucket" {
  count         = local.create_shared_infra ? 1 : 0
  name          = "hobio-${var.type}-reports-ue1"
  location      = "US-EAST1"
  force_destroy = false
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  logging {
    log_bucket        = google_storage_bucket.logging_sink[0].name
    log_object_prefix = "logs/reports/${var.environment}"
  }

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"
}

resource "google_compute_router" "router" {
  count   = local.create_shared_infra ? 1 : 0
  name    = "hobio-${var.type}-router-ue1"
  region  = var.region
  network = "default"
}

resource "google_compute_router_nat" "nat" {
  count                              = local.create_shared_infra ? 1 : 0
  name                               = "hobio-${var.type}-nat-ue1"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count         = local.create_shared_infra ? 1 : 0
  name          = "allow-ssh-via-iap"
  network       = "default"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["allow-ssh"]
  description = "Allow SSH access via IAP"
}

resource "google_compute_firewall" "allow_iap_rabbitmq" {
  count         = local.create_shared_infra ? 1 : 0
  name          = "allow-rabbitmq-via-iap"
  network       = "default"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["5672", "15672"]
  }

  target_tags = ["rabbitmq-server"]
  description = "Allow RabbitMQ access via IAP"
}

resource "google_compute_firewall" "allow_rabbitmq" {
  count   = local.create_shared_infra ? 1 : 0
  name    = "allow-rabbitmq-internal"
  network = "default"
  source_ranges = ["10.0.0.0/8"]

  allow {
    protocol = "tcp"
    ports    = ["5672", "15672"]
  }

  target_tags   = ["rabbitmq-server"]
  description   = "Allow RabbitMQ traffic"
}

resource "google_vpc_access_connector" "connector" {
  count         = local.create_shared_infra ? 1 : 0
  name          = "hobio-${var.type}-vpc-ue1"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"

  min_throughput = 200
  max_throughput = 300
}

resource "google_compute_instance" "rabbitmq_instance" {
  name         = "${var.project_id}-${var.environment}-rabbitmq-server"
  machine_type = "e2-micro"
  zone         = "${var.region}-b"
  tags         = ["allow-ssh", "rabbitmq-server"]

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
    sudo apt-get install -y rabbitmq-server
    RABBIT_PASS=$(gcloud secrets versions access latest --secret="rabbitmq-password-${var.environment}")
    sudo systemctl enable rabbitmq-server
    sudo systemctl start rabbitmq-server
    sudo rabbitmq-plugins enable rabbitmq_management
    sudo systemctl restart rabbitmq-server
    sleep 5
    sudo rabbitmqctl add_user admin "$RABBIT_PASS"
    sudo rabbitmqctl set_user_tags admin administrator
    sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
  EOT

  service_account {
    email  = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  labels = {
    environment = var.environment
    service     = "rabbitmq"
  }
}

resource "google_artifact_registry_repository" "docker_repo" {
  count         = local.create_shared_infra ? 1 : 0
  location      = var.region
  repository_id = "hobio-${var.type}-repo-ue1"
  description   = "Docker repository for ${var.type} environment"
  format        = "DOCKER"

  # checkov:skip=CKV_GCP_84: We use GMEK for simplicity
  docker_config {
    immutable_tags = true
  }

  labels = {
    environment = var.type
  }
}