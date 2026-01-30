variable "project_id" {
    type = string
    description = "project id (e.g hobio-nonprod, hobio-prod)"
}

variable "region" {
    type = string
    description = "region (e.g us-central1)"
}

variable "environment" {
    type = string
    description = "environment (e.g dev, qa, prod, etc)"
}