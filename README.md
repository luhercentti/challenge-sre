<h2><strong>Luis Angelo Hernandez Centti</strong></h2>

1) Pub/Sub (Ingesta de Datos)
2) Cloud Run (API)
3) BigQuery (Procesamiento)
4) Almacenamiento (Cloud Storage)

![alt text](diagrama.png)

////////


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

wait 15 minutes and then check cloud run url /events for samples

/////////

///////
mejoras:

Solución propuesta: Implementar un flujo alternativo directo con Dataflow

La transferencia de datos desde PubSub a BigQuery mediante el bucket de Storage puede tener latencia significativa
Potencial pérdida de datos si hay problemas en algún punto del flujo


for cicd pipeline to work change this in resource "google_cloud_run_service" "data_api":

        image = "gcr.io/${var.gcp_project}/data-api:latest"


locally test:

gcloud builds submit --tag gcr.io/lhc-demo-1/data-api:latest
