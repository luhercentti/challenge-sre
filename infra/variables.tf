variable "gcp_project" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "redshift_password" {
  description = "Password for BigQuery service account"
  type        = string
  sensitive   = true
}
