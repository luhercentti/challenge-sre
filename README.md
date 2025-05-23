<h2><strong>Luis Angelo Hernandez Centti</strong></h2>

GCP Data Pipeline Architecture & Testing Guide
Architecture Overview
This is a real-time data ingestion and analytics pipeline on Google Cloud Platform with the following components:
Data Flow Architecture
[Data Sources] → [Cloud Run API] → [Pub/Sub Topic] → [Dataflow] → [BigQuery] → [Analytics/Queries]
                      ↓
                 [HTTP Endpoints for Queries]

Components Breakdown
1. Cloud Run API Service (data-api)

Purpose: HTTP gateway for data ingestion and querying
Functionality:

Receives data via HTTP POST requests
Publishes messages to Pub/Sub topic
Provides /events endpoint to query BigQuery data
Health check endpoint at /health


Technology: Python Flask app running in containers

2. Pub/Sub Topic (data-ingestion-topic)

Purpose: Message queue for decoupling ingestion from processing
Benefits:

Handles traffic spikes
Ensures no data loss
Enables async processing


Subscription: data-subscription consumed by Dataflow

3. Dataflow Streaming Job (pubsub-to-bigquery-streaming)

Purpose: Real-time data processing pipeline
Template: Uses Google's pre-built PubSub_to_BigQuery template
Function:

Continuously reads from Pub/Sub
Transforms/validates data
Streams to BigQuery in real-time


Scaling: Auto-scales based on message volume

4. BigQuery (analytics_data.events)

Purpose: Data warehouse for analytics
Schema:

event_id (STRING, REQUIRED)
event_data (JSON)
timestamp (TIMESTAMP, REQUIRED)


Benefits:

Columnar storage for fast queries
SQL interface
Handles petabyte-scale data



5. Cloud Storage (dataflow-staging)

Purpose: Temporary storage for Dataflow operations
Contains: Staging files, temp data during processing
Lifecycle: Auto-deletes files after 7 days

6. Monitoring & Alerting

Dataflow job failure alerts
API error rate monitoring (>5%)
Pub/Sub message backlog alerts (>1000 messages)



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

for i in {1..10}; do
  gcloud pubsub topics publish data-ingestion-topic \
    --message="{\"event_id\":\"test-$i\",\"event_data\":{\"action\":\"batch_test\",\"number\":$i},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  sleep 1
done

//////////

Testing the Data Pipeline
1. Test API Health Check
bash# Get the Cloud Run service URL
export API_URL=$(gcloud run services describe data-api --region=us-central1 --format="value(status.url)")

# Test health endpoint
curl $API_URL/health
Expected Response:
json{"status": "healthy"}
2. Test Data Ingestion (Pub/Sub Publishing)
First, you'll need to add a POST endpoint to your Flask app for publishing messages:
python# Add this to your main.py
from google.cloud import pubsub_v1
import uuid
from datetime import datetime

publisher = pubsub_v1.PublisherClient()

@app.route('/publish', methods=['POST'])
def publish_event():
    try:
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        topic_name = os.getenv('PUBSUB_TOPIC')
        topic_path = publisher.topic_path(project_id, topic_name)
        
        # Get event data from request
        event_data = request.get_json()
        
        # Create message with required schema
        message_data = {
            "event_id": str(uuid.uuid4()),
            "event_data": event_data,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
        
        # Publish to Pub/Sub
        message_json = json.dumps(message_data)
        future = publisher.publish(topic_path, message_json.encode('utf-8'))
        message_id = future.result()
        
        logger.info(f"Published message {message_id}")
        return jsonify({"message_id": message_id, "status": "published"}), 200
        
    except Exception as e:
        logger.error(f"Error publishing event: {str(e)}")
        return jsonify({"error": str(e)}), 500
Then test message publishing:
bash# Rebuild and redeploy with the new endpoint
gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/data-api:latest .
gcloud run deploy data-api --image gcr.io/$GOOGLE_CLOUD_PROJECT/data-api:latest --region us-central1

# Test publishing a message
curl -X POST $API_URL/publish \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "12345",
    "action": "page_view",
    "page": "/home",
    "properties": {
      "browser": "Chrome",
      "device": "desktop"
    }
  }'
Expected Response:
json{"message_id": "1234567890", "status": "published"}
3. Verify Pub/Sub Message Flow
bash# Check if messages are in the topic
gcloud pubsub topics list

# Check subscription metrics
gcloud pubsub subscriptions describe data-subscription
4. Monitor Dataflow Job
bash# Check Dataflow job status
gcloud dataflow jobs list --region=us-central1

# Get detailed job info
gcloud dataflow jobs describe pubsub-to-bigquery-streaming --region=us-central1
5. Verify Data in BigQuery
bash# Query the data directly
bq query --use_legacy_sql=false \
"SELECT 
  event_id, 
  JSON_EXTRACT_SCALAR(event_data, '$.action') as action,
  timestamp 
FROM \`$GOOGLE_CLOUD_PROJECT.analytics_data.events\` 
ORDER BY timestamp DESC 
LIMIT 10"
6. Test Query API Endpoint
bash# Test the events endpoint
curl $API_URL/events
Expected Response:
json[
  {
    "event_id": "uuid-here",
    "event_data": {
      "user_id": "12345",
      "action": "page_view",
      "page": "/home",
      "properties": {
        "browser": "Chrome",
        "device": "desktop"
      }
    },
    "timestamp": "2025-05-22T10:30:00Z"
  }
]
Load Testing
bash# Install Apache Bench for load testing
brew install httpd

# Send multiple requests quickly
for i in {1..10}; do
  curl -X POST $API_URL/publish \
    -H "Content-Type: application/json" \
    -d "{\"user_id\": \"user_$i\", \"action\": \"test_event\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" &
done
wait

# Check if all messages processed
sleep 30
curl $API_URL/events | jq length  # Should show 10+ events
Monitoring Commands
bash# Check Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=data-api" --limit=50

# Check Dataflow job logs
gcloud logs read "resource.type=dataflow_job" --limit=50

# Check Pub/Sub metrics
gcloud logging read "resource.type=pubsub_topic OR resource.type=pubsub_subscription" --limit=20
Expected Behavior & Troubleshooting
Normal Flow Timeline:

0-1 sec: Message published to Pub/Sub
1-5 sec: Dataflow picks up and processes message
5-10 sec: Data appears in BigQuery
Immediate: Query API returns the new data

Common Issues:
Dataflow Job Not Starting
bash# Check IAM permissions
gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT

# Verify APIs are enabled
gcloud services list --enabled
No Data in BigQuery
bash# Check Dataflow job errors
gcloud dataflow jobs describe pubsub-to-bigquery-streaming --region=us-central1

# Check message format - must match BigQuery schema exactly
API Errors
bash# Check Cloud Run service account permissions
gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT --flatten="bindings[].members" --filter="bindings.members:api-service-account@*"
Performance Expectations

Latency: 5-10 seconds end-to-end (Pub/Sub → BigQuery)
Throughput: 1000+ messages/second (can scale higher)
API Response: < 200ms for queries
Cost: ~$50-100/month for moderate usage

This architecture provides a robust, scalable real-time data pipeline suitable for production analytics workloads.
