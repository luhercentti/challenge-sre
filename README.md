<h2><strong>Luis Angelo Hernandez Centti</strong></h2>

<h3>EVENT-DRIVEN-DEMO in GCP</h3>

Expected Flow

POST to /publish → Message goes to Pub/Sub
Dataflow picks up message → Streams to BigQuery
GET /events → Queries BigQuery data
Total latency: 5-10 seconds end-to-end

What You Should See

Health check: Status "healthy" with project info
Publish: Returns message_id and event_id
Events query: Your published data with timestamps
BigQuery: Data visible in console within 10 seconds

The testing script will walk through the entire pipeline automatically. Just update the GOOGLE_CLOUD_PROJECT variable and run it!
This architecture can handle thousands of events per second and auto-scales based on load. Perfect for production analytics workloads

# Set your project
export GOOGLE_CLOUD_PROJECT="your-project-id"
export API_URL="your-cloud-run-url"

# 1. Health check
curl $API_URL/health

# 2. Publish test data
curl -X POST $API_URL/publish \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "12345",
    "action": "page_view", 
    "page": "/home"
  }'

# 3. Wait 30 seconds, then query
sleep 30
curl $API_URL/events


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

for cicd pipeline to work change this in resource "google_cloud_run_service" "data_api":

        image = "gcr.io/${var.gcp_project}/data-api:latest"


locally test:

for i in {1..10}; do
  gcloud pubsub topics publish data-ingestion-topic \
    --message="{\"event_id\":\"test-$i\",\"event_data\":{\"action\":\"batch_test\",\"number\":$i},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  sleep 1
done

//////////

