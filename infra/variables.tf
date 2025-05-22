variable "gcp_project" {
  description = "The GCP project ID"
  type        = string
  default     = "lhc-demo-1" 
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
