provider "google" {
  project = var.gcp_project
  region  = var.region
  credentials = file("terraform-key.json")
}

# 1. Pub/Sub para ingesta
resource "google_pubsub_topic" "data_topic" {
  name = "data-ingestion-topic"
}

resource "google_pubsub_subscription" "data_subscription" {
  name  = "data-subscription"
  topic = google_pubsub_topic.data_topic.name
}

# 2. BigQuery para almacenamiento analítico
resource "google_bigquery_dataset" "analytics" {
  dataset_id    = "analytics_data"
  friendly_name = "Analytics Dataset"
  description   = "Dataset para datos analíticos"
  location      = var.region
}

resource "google_bigquery_table" "events" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "events"

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

# 3. Cloud Run para API HTTP
resource "google_service_account" "api_sa" {
  account_id   = "api-service-account"
  display_name = "Service Account for Data API"
}

resource "google_project_iam_member" "bq_access" {
  project = var.gcp_project
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_cloud_run_service" "data_api" {
  name     = "data-api"
  location = var.region

  template {
    spec {
      containers {
        image = "gcr.io/${var.gcp_project}/data-api:latest"
      }
      service_account_name = google_service_account.api_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
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

# Configuración de Cloud Build
resource "google_cloudbuild_trigger" "api_deploy" {
  name        = "data-api-deploy"
  description = "Despliegue automático de la API"

  github {
    owner = "tu-usuario"
    name  = "tu-repositorio"
    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"
}