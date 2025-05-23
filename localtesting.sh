#!/bin/bash

# Complete Testing Script for GCP Data Pipeline
# Run this step by step to test your architecture

echo "🚀 Starting GCP Data Pipeline Testing"

# Set your project ID
export GOOGLE_CLOUD_PROJECT="your-project-id-here"
export REGION="us-central1"

echo "📋 Project: $GOOGLE_CLOUD_PROJECT"
echo "📍 Region: $REGION"

# 1. Deploy Infrastructure
echo "🏗️  Step 1: Deploying Terraform infrastructure..."
terraform init
terraform apply -var="gcp_project=$GOOGLE_CLOUD_PROJECT" -var="region=$REGION" -auto-approve

# 2. Build and Deploy API
echo "🐳 Step 2: Building and deploying API..."
gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/data-api:latest .

gcloud run deploy data-api \
  --image gcr.io/$GOOGLE_CLOUD_PROJECT/data-api:latest \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT,PUBSUB_TOPIC=data-ingestion-topic \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10

# 3. Get API URL
export API_URL=$(gcloud run services describe data-api --region=$REGION --format="value(status.url)")
echo "🌐 API URL: $API_URL"

# 4. Test Health Check
echo "❤️  Step 3: Testing health check..."
curl -s $API_URL/health | jq .

# 5. Test API Documentation
echo "📚 Step 4: Testing API documentation..."
curl -s $API_URL/ | jq .

# 6. Check Dataflow Job Status
echo "🌊 Step 5: Checking Dataflow job status..."
gcloud dataflow jobs list --region=$REGION --filter="name:pubsub-to-bigquery-streaming"

# 7. Test Data Publishing
echo "📤 Step 6: Publishing test events..."

# Publish multiple test events
for i in {1..5}; do
  echo "Publishing event $i..."
  curl -X POST $API_URL/publish \
    -H "Content-Type: application/json" \
    -d "{
      \"user_id\": \"user_$i\",
      \"action\": \"test_event\",
      \"page\": \"/test-page-$i\",
      \"properties\": {
        \"browser\": \"Chrome\",
        \"device\": \"desktop\",
        \"test_run\": true,
        \"sequence\": $i
      }
    }" | jq .
  
  sleep 1
done

echo "⏳ Waiting 30 seconds for data to flow through pipeline..."
sleep 30

# 8. Test Event Querying
echo "📊 Step 7: Querying events from BigQuery..."
curl -s "$API_URL/events?limit=10" | jq .

# 9. Check Event Count
echo "🔢 Step 8: Getting total event count..."
curl -s $API_URL/events/count | jq .

# 10. Direct BigQuery Query
echo "🗄️  Step 9: Direct BigQuery query..."
bq query --use_legacy_sql=false \
"SELECT 
  event_id, 
  JSON_EXTRACT_SCALAR(TO_JSON_STRING(event_data), '$.action') as action,
  JSON_EXTRACT_SCALAR(TO_JSON_STRING(event_data), '$.user_id') as user_id,
  timestamp 
FROM \`$GOOGLE_CLOUD_PROJECT.analytics_data.events\` 
ORDER BY timestamp DESC 
LIMIT 5"

# 11. Load Test
echo "🚀 Step 10: Running load test (50 concurrent events)..."
for i in {1..50}; do
  curl -X POST $API_URL/publish \
    -H "Content-Type: application/json" \
    -d "{
      \"user_id\": \"load_test_user_$i\",
      \"action\": \"load_test\",
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"batch\": \"load_test_batch\"
    }" > /dev/null 2>&1 &
done

wait
echo "Load test completed. Waiting for processing..."
sleep 45

# Final count check
echo "📈 Final Results:"
curl -s $API_URL/events/count | jq .

# 12. Monitor Logs
echo "📝 Step 11: Checking recent logs..."
echo "Cloud Run logs:"
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=data-api" --limit=10 --format="table(timestamp,textPayload)"

echo "Dataflow logs:"
gcloud logs read "resource.type=dataflow_job" --limit=5 --format="table(timestamp,textPayload)"

# 13. Check Monitoring
echo "📊 Step 12: Checking Pub/Sub metrics..."
gcloud pubsub topics describe data-ingestion-topic
gcloud pubsub subscriptions describe data-subscription

echo "✅ Testing Complete!"
echo "🌐 Your API is available at: $API_URL"
echo "📊 Check BigQuery console: https://console.cloud.google.com/bigquery?project=$GOOGLE_CLOUD_PROJECT"
echo "🌊 Check Dataflow console: https://console.cloud.google.com/dataflow?project=$GOOGLE_CLOUD_PROJECT"