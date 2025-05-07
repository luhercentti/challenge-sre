# Luis Hernandez Centti

├── scripts/
│   ├── publish_test_events.py    # Script para enviar eventos de prueba
│   └── insert_test_data.py       # Script para insertar datos directamente en BigQuery


////////

Intrucciones de entrega.

curl -X POST https://advana-challenge-check-api-cr-k4hdbggvoq-uc.a.run.app/devops \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Luis Hernandez",
    "mail": "luisangelo.hernandez@globant.com",
    "github_url": "https://github.com/luhercentti/challenge-sre"
  }'


gcloud projects add-iam-policy-binding lhc-demo-1 \
  --member="serviceAccount:terraform@lhc-demo-1.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder"

gcloud projects add-iam-policy-binding lhc-demo-1 \
  --member="serviceAccount:terraform@lhc-demo-1.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding lhc-demo-1 \
  --member="serviceAccount:terraform@lhc-demo-1.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"



para finops ver costs:
cd /infra
infracost breakdown --path=tfplan.json  


python -m venv challengelhc

source challengelhc/bin/activate

pip install google-cloud-pubsub
gcloud auth application-default login

python3 scripts/publish_test_events.py --project=lhc-demo-1

wait 15 minutes and then check cloud run url /events for samples:

[{"event_data":{"browser":"Edge","country":"FR","device":"tablet","event_type":"form_submit","page":"/contact","user_id":"user_2"},"event_id":"eef63cfb-70e0-4621-9c25-912408656a72","timestamp":"Wed, 07 May 2025 08:25:14 GMT"},{"event_data":{"browser":"Safari","country":"FR","device":"tablet","event_type":"page_view","page":"/checkout","user_id":"user_6"},"event_id":"33e41f93-0d7e-4fa8-9a3e-a74ff0b6f53f","timestamp":"Wed, 07 May 2025 08:25:13 GMT"},{"event_data":{"amount":333.82,"browser":"Edge","country":"FR","device":"desktop","event_type":"purchase","items":1,"page":"/products","user_id":"user_9"},"event_id":"9a997c98-9bf9-41e8-adec-fdae44aaa94b","timestamp":"Wed, 07 May 2025 08:25:11 GMT"},{"event_data":{"amount":138.94,"browser":"Firefox","country":"FR","device":"tablet","event_type":"purchase","items":5,"page":"/about","user_id":"user_1"},"event_id":"f0f9b8d8-4da9-4ec5-852d-567838c06ce8","timestamp":"Wed, 07 May 2025 08:25:10 GMT"},{"event_data":{"browser":"Edge","country":"US","device":"mobile","event_type":"page_view","page":"/products","user_id":"user_7"},"event_id":"897ea353-9a62-4186-bfd8-36eacf9e598e","timestamp":"Wed, 07 May 2025 08:25:09 GMT"},{"event_data":{"browser":"Firefox","country":"MX","device":"mobile","event_type":"form_submit","page":"/home","user_id":"user_10"},"event_id":"e9f9e2cf-cb7f-43e4-a8d2-70f14500d574","timestamp":"Wed, 07 May 2025 08:25:08 GMT"},{"event_data":{"amount":204.28,"browser":"Firefox","country":"UK","device":"desktop","event_type":"purchase","items":1,"page":"/about","user_id":"user_7"},"event_id":"f6ba54cd-fcc3-4fa9-bbbc-eb4f7c91bd9b","timestamp":"Wed, 07 May 2025 08:25:07 GMT"},{"event_data":{"browser":"Safari","country":"US","device":"tablet","event_type":"click","page":"/about","user_id":"user_6"},"event_id":"1ae4b162-9458-4a97-b18a-e270f2b6e8b5","timestamp":"Wed, 07 May 2025 08:25:06 GMT"},{"event_data":{"browser":"Chrome","country":"CA","device":"mobile","event_type":"login","page":"/checkout","user_id":"user_2"},"event_id":"7db4e4a7-8b39-4e1e-a2ef-ad388281b72e","timestamp":"Wed, 07 May 2025 08:25:05 GMT"},{"event_data":{"browser":"Safari","country":"MX","device":"mobile","event_type":"click","page":"/about","user_id":"user_5"},"event_id":"05388390-a3de-4091-9dcf-cd4877871943","timestamp":"Wed, 07 May 2025 08:25:03 GMT"}]


/////////

El sistema consta de los siguientes componentes:

Ingesta de Datos:

Pub/Sub recibe los datos
Una suscripción exporta automáticamente los mensajes a Cloud Storage
BigQuery Data Transfer importa los datos desde Cloud Storage a una tabla de BigQuery


API HTTP:

Una API REST implementada con Flask y ejecutada en Cloud Run
La API consulta los datos almacenados en BigQuery
Expone un endpoint GET /events que devuelve los datos en formato JSON


CI/CD:

GitHub Actions automatiza el despliegue
Construye y publica la imagen Docker a Google Container Registry
Aplica la infraestructura usando Terraform



////

Flujo de Datos End-to-End

Ingesta:

Los datos se publican en el tópico de Pub/Sub data-ingestion-topic
La suscripción export-to-storage exporta los mensajes automáticamente a Cloud Storage
El servicio de transferencia de BigQuery carga periódicamente los archivos desde Cloud Storage a la tabla analytics_data.events


Consulta:

El cliente hace una solicitud GET al endpoint /events de la API
La API de Cloud Run ejecuta una consulta a BigQuery para obtener los eventos más recientes
Los resultados se transforman y se devuelven como JSON al cliente



Implementación
El despliegue se realiza automáticamente cuando se hace push a las ramas main o develop:

GitHub Actions ejecuta el workflow de CI/CD
Se construye y publica la imagen Docker de la API
Terraform aplica la configuración de infraestructura
El sistema completo queda operativo



Pruebas
Para probar el sistema, puede:

Publicar eventos de prueba:
python scripts/publish_test_events.py --project YOUR_PROJECT_ID --topic data-ingestion-topic

Insertar datos directamente en BigQuery (para pruebas rápidas):
python scripts/insert_test_data.py --project YOUR_PROJECT_ID

Consultar la API:
bashcurl https://data-api-xxxxxxxxxxxx.run.app/events



///// mejoras

Solución propuesta: Implementar un flujo alternativo directo con Dataflow

La transferencia de datos desde PubSub a BigQuery mediante el bucket de Storage puede tener latencia significativa
Potencial pérdida de datos si hay problemas en algún punto del flujo

# Crear un job de Dataflow para streaming directo de Pub/Sub a BigQuery
resource "google_dataflow_job" "pubsub_to_bigquery" {
  name                  = "pubsub-to-bigquery-streaming"
  template_gcs_path     = "gs://dataflow-templates/latest/PubSub_to_BigQuery"
  temp_gcs_location     = "${google_storage_bucket.pubsub_export.url}/temp"
  service_account_email = google_service_account.bq_transfer_sa.email
  
  parameters = {
    inputTopic          = google_pubsub_topic.data_topic.id
    outputTableSpec     = "${var.gcp_project}:${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.events.table_id}"
    messageFormat       = "JSON"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_bigquery_table.events,
    google_pubsub_topic.data_topic
  ]
}