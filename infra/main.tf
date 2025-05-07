provider "google" {
  project = var.gcp_project
  region  = var.region
  credentials = file("terraform-key.json")
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "pubsub.googleapis.com",
    "bigquery.googleapis.com", 
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "monitoring.googleapis.com",
    "dataflow.googleapis.com",
    "storage.googleapis.com"  # Added Storage API for the bucket
  ])
  project = var.gcp_project
  service = each.key

  disable_dependent_services = false
  disable_on_destroy         = false
}

# 1. Pub/Sub para ingesta
resource "google_pubsub_topic" "data_topic" {
  name = "data-ingestion-topic"
  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "data_subscription" {
  name  = "data-subscription"
  topic = google_pubsub_topic.data_topic.name
}

# Add Cloud Storage bucket for storing PubSub exports
resource "google_storage_bucket" "pubsub_export" {
  name          = "${var.gcp_project}-pubsub-exports"
  location      = var.region
  force_destroy = true  # Allow terraform to delete the bucket even if it contains files
  
  lifecycle_rule {
    condition {
      age = 30  # Keep files for 30 days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Grant the Pub/Sub service account access to the bucket
data "google_project" "project" {
}

resource "google_storage_bucket_iam_member" "pubsub_storage_admin" {
  bucket = google_storage_bucket.pubsub_export.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "pubsub_storage_viewer" {
  bucket = google_storage_bucket.pubsub_export.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# 2. BigQuery para almacenamiento analítico
resource "google_bigquery_dataset" "analytics" {
  dataset_id    = "analytics_data"
  friendly_name = "Analytics Dataset"
  description   = "Dataset para datos analíticos"
  location      = var.region
  depends_on = [google_project_service.required_apis]
}

resource "google_bigquery_table" "events" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "events"

  deletion_protection = false 

  schema = <<EOF
[
  {
    "name": "event_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "event_data",
    "type": "JSON"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  }
]
EOF
}

# 3. Cloud Run for API HTTP
resource "google_service_account" "api_sa" {
  account_id   = "api-service-account"
  display_name = "Service Account for Data API"
  depends_on = [google_project_service.required_apis]
}

resource "google_project_iam_member" "permissions" {
  project = var.gcp_project
  role   = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "bq_access" {
  project = var.gcp_project
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "bq_job_user" {
  project = var.gcp_project
  role    = "roles/bigquery.jobUser"  # Required to run queries
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_cloud_run_service" "data_api" {
  name     = "data-api"
  location = var.region

  template {
    spec {
      containers {
        image = "gcr.io/${var.gcp_project}/data-api:latest"
         env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.gcp_project
         }
      }
      service_account_name = google_service_account.api_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Permite acceso público a la API
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = ["allUsers"]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.data_api.location
  project     = google_cloud_run_service.data_api.project
  service     = google_cloud_run_service.data_api.name
  policy_data = data.google_iam_policy.noauth.policy_data
}

# Service account for BigQuery Data Transfer Service
resource "google_service_account" "bq_transfer_sa" {
  account_id   = "bq-transfer-service-account"
  display_name = "Service Account for BigQuery Data Transfer"
  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the transfer service account
resource "google_project_iam_member" "transfer_pubsub_subscriber" {
  project = var.gcp_project
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.bq_transfer_sa.email}"
}

resource "google_project_iam_member" "transfer_bq_editor" {
  project = var.gcp_project
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.bq_transfer_sa.email}"
}

resource "google_project_iam_member" "transfer_storage_admin" {
  project = var.gcp_project
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.bq_transfer_sa.email}"
}

resource "google_pubsub_topic_iam_member" "allow_transfer_sa" {
  topic  = google_pubsub_topic.data_topic.name
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.bq_transfer_sa.email}"
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "90s"
}

# Create a Pub/Sub subscription with Cloud Storage export
resource "google_pubsub_subscription" "export_to_storage" {
  name  = "export-to-storage"
  topic = google_pubsub_topic.data_topic.name
  
  cloud_storage_config {
    bucket = google_storage_bucket.pubsub_export.name
    filename_prefix = "events-"
    filename_suffix = ".json"
    max_duration = "60s"  # 5 minutes in seconds format
    max_bytes = 1000000  # 1MB
  }
  
  depends_on = [
    google_pubsub_topic.data_topic,
    google_storage_bucket.pubsub_export,
    google_storage_bucket_iam_member.pubsub_storage_admin,
    google_storage_bucket_iam_member.pubsub_storage_viewer
  ]
}

# BigQuery Data Transfer Config from Cloud Storage
resource "google_bigquery_data_transfer_config" "storage_to_bq" {
  display_name           = "storage-to-bq"
  location               = var.region
  data_source_id         = "google_cloud_storage"
  schedule               = "every 15 minutes"
  destination_dataset_id = google_bigquery_dataset.analytics.dataset_id
  service_account_name   = google_service_account.bq_transfer_sa.email
  params = {
    destination_table_name_template = google_bigquery_table.events.table_id
    data_path_template = "gs://${google_storage_bucket.pubsub_export.name}/*.json" 
    file_format        = "JSON"
    write_disposition  = "APPEND"
  }
  depends_on = [
    time_sleep.wait_for_apis,
    google_bigquery_table.events,
    google_project_iam_member.transfer_storage_admin,
    google_project_iam_member.transfer_bq_editor,
    google_storage_bucket.pubsub_export
  ]
}

# Monitoreo básico
resource "google_monitoring_alert_policy" "api_high_errors" {
  display_name = "High API Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Error rate > 5%"
    condition_threshold {
      filter     = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.data_api.name}\" AND metric.type=\"run.googleapis.com/request_count\""
      threshold_value = 5.0
      duration   = "300s"
      comparison = "COMPARISON_GT"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}