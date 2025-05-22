provider "google" {
  project = var.gcp_project
  region  = var.region
  #credentials = file("terraform-key.json")
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "pubsub.googleapis.com",
    "bigquery.googleapis.com", 
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "dataflow.googleapis.com",
    "storage.googleapis.com"  # Still needed for Dataflow staging
  ])
  project = var.gcp_project
  service = each.key

  disable_dependent_services = false
  disable_on_destroy         = false
}

# 1. Pub/Sub for event ingestion
resource "google_pubsub_topic" "data_topic" {
  name = "data-ingestion-topic"
  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "data_subscription" {
  name  = "data-subscription"
  topic = google_pubsub_topic.data_topic.name
}

# Cloud Storage bucket for Dataflow staging (required by Dataflow)
resource "google_storage_bucket" "dataflow_staging" {
  name          = "${var.gcp_project}-dataflow-staging"
  location      = var.region
  force_destroy = true
  
  lifecycle_rule {
    condition {
      age = 7  # Keep staging files for 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# 2. BigQuery for analytical storage
resource "google_bigquery_dataset" "analytics" {
  dataset_id    = "analytics_data"
  friendly_name = "Analytics Dataset"
  description   = "Dataset for analytical data"
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

# Service account for Dataflow
resource "google_service_account" "dataflow_sa" {
  account_id   = "dataflow-service-account"
  display_name = "Service Account for Dataflow"
  depends_on = [google_project_service.required_apis]
}

# This gives Dataflow the ability to create subscriptions
resource "google_project_iam_member" "dataflow_pubsub_editor" {
  project = var.gcp_project
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Grant necessary permissions to Dataflow service account
resource "google_project_iam_member" "dataflow_worker" {
  project = var.gcp_project
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_storage_admin" {
  project = var.gcp_project
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_pubsub_subscriber" {
  project = var.gcp_project
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_pubsub_viewer" {
  project = var.gcp_project
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_bq_editor" {
  project = var.gcp_project
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_project_iam_member" "dataflow_bq_job_user" {
  project = var.gcp_project
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Grant topic-level permissions explicitly
resource "google_pubsub_topic_iam_member" "dataflow_topic_subscriber" {
  topic  = google_pubsub_topic.data_topic.name
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

resource "google_pubsub_topic_iam_member" "dataflow_topic_viewer" {
  topic  = google_pubsub_topic.data_topic.name
  role   = "roles/pubsub.viewer"
  member = "serviceAccount:${google_service_account.dataflow_sa.email}"
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "90s"
}

# Dataflow streaming job - Pub/Sub to BigQuery
resource "google_dataflow_job" "pubsub_to_bq" {
  name                  = "pubsub-to-bigquery-streaming"
  template_gcs_path     = "gs://dataflow-templates-${var.region}/latest/PubSub_to_BigQuery"
  temp_gcs_location     = "gs://${google_storage_bucket.dataflow_staging.name}/temp"
  region                = var.region
  service_account_email = google_service_account.dataflow_sa.email

  zone = "us-central1-b"  # Try different zones: us-central1-b, us-central1-c
  
  parameters = {
    inputTopic      = google_pubsub_topic.data_topic.id
    outputTableSpec = "${var.gcp_project}:${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.events.table_id}"
    
    # Optional: Add transformation via UDF if needed
    # javascriptTextTransformGcsPath = "gs://your-bucket/transform.js"
    # javascriptTextTransformFunctionName = "transform"
  }
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_bigquery_table.events,
    google_project_iam_member.dataflow_worker,
    google_project_iam_member.dataflow_storage_admin,
    google_project_iam_member.dataflow_pubsub_subscriber,
    google_project_iam_member.dataflow_bq_editor,
    google_project_iam_member.dataflow_bq_job_user
  ]
  
  # Optional: Configure autoscaling
  additional_experiments = ["enable_streaming_engine"]
  
  # Optional: Set machine type and scaling
  machine_type = "n1-standard-1"
  max_workers = 5
}

# 3. Cloud Run for HTTP API
resource "google_service_account" "api_sa" {
  account_id   = "api-service-account"
  display_name = "Service Account for Data API"
  depends_on = [google_project_service.required_apis]
}

resource "google_project_iam_member" "api_pubsub_publisher" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "api_bq_access" {
  project = var.gcp_project
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "api_bq_job_user" {
  project = var.gcp_project
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_cloud_run_service" "data_api" {
  name     = "data-api"
  location = var.region

  template {
    spec {
      containers {
        # Using a simple hello-world image for initial deployment
        # Replace with your actual API image once built
        image = "gcr.io/cloudrun/hello"
        
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.gcp_project
        }
        env {
          name  = "PUBSUB_TOPIC"
          value = google_pubsub_topic.data_topic.name
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

# Allow public access to API
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

# Monitoring for Dataflow job
resource "google_monitoring_alert_policy" "dataflow_job_failed" {
  display_name = "Dataflow Job Failed"
  combiner     = "OR"
  
  conditions {
    display_name = "Job State Failed"
    condition_threshold {
      filter          = "resource.type=\"dataflow_job\" AND resource.labels.job_name=\"${google_dataflow_job.pubsub_to_bq.name}\" AND metric.type=\"dataflow.googleapis.com/job/is_failed\""
      threshold_value = 0.5
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring for API errors
resource "google_monitoring_alert_policy" "api_high_errors" {
  display_name = "High API Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Error rate > 5%"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.data_api.name}\" AND metric.type=\"run.googleapis.com/request_count\""
      threshold_value = 5.0
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring for Pub/Sub message backlog
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  display_name = "Pub/Sub Message Backlog"
  combiner     = "OR"
  
  conditions {
    display_name = "Undelivered messages > 1000"
    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.data_subscription.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      threshold_value = 1000
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}