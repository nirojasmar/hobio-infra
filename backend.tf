terraform {
  backend "gcs" {
    bucket = "hobio-nonprod-tfstates-ue1"
    prefix = "terraform/state"
  }
}