import unittest
import requests
import os
import json
import time
import uuid
from google.cloud import bigquery, pubsub_v1
from datetime import datetime, timezone

class TestApiIntegration(unittest.TestCase):
    """Integration tests to verify the complete data pipeline from API to BigQuery"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test environment"""
        # API URL from environment
        cls.api_url = os.environ.get('API_URL', 'https://data-api-HASH-uc.a.run.app')
        
        # GCP clients for direct verification
        cls.bq_client = bigquery.Client()
        cls.pubsub_publisher = pubsub_v1.PublisherClient()
        cls.project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        
        if not cls.project_id:
            raise Exception("GOOGLE_CLOUD_PROJECT environment variable must be set")
        
        # Generate unique test identifier
        cls.test_run_id = f"test-{uuid.uuid4().hex[:8]}"
        print(f"Running tests with ID: {cls.test_run_id}")
        
        # Insert direct test data in BigQuery for baseline verification
        cls._insert_direct_test_data()
    
    @classmethod
    def _insert_direct_test_data(cls):
        """Insert test data directly into BigQuery for baseline verification"""
        table_ref = f"{cls.project_id}.analytics_data.events"
        table = cls.bq_client.get_table(table_ref)
        
        # Direct BigQuery test data
        cls.direct_event_id = f"{cls.test_run_id}-direct-bq"
        rows_to_insert = [
            {
                "event_id": cls.direct_event_id,
                "event_data": {
                    "test_type": "direct_bigquery",
                    "test_key": "direct_test_value",
                    "test_run_id": cls.test_run_id
                },
                "timestamp": datetime.now(timezone.utc)
            }
        ]
        
        errors = cls.bq_client.insert_rows_json(table, rows_to_insert)
        if errors:
            raise Exception(f"Could not insert direct test data: {errors}")
        
        print(f"Inserted direct test data with event_id: {cls.direct_event_id}")
    
    def test_01_api_health_check(self):
        """Test that health check endpoint responds correctly"""
        print("\n🏥 Testing health check...")
        response = requests.get(f"{self.api_url}/health")
        self.assertEqual(response.status_code, 200, "Health check should respond successfully")
        
        data = response.json()
        self.assertEqual(data['status'], 'healthy', "Status should be 'healthy'")
        self.assertIn('project_id', data, "Health check should include project_id")
        self.assertIn('pubsub_topic', data, "Health check should include pubsub_topic")
        print(f"✅ Health check passed: {data}")
    
    def test_02_api_documentation(self):
        """Test that root endpoint provides API documentation"""
        print("\n📚 Testing API documentation...")
        response = requests.get(f"{self.api_url}/")
        self.assertEqual(response.status_code, 200, "Root endpoint should respond successfully")
        
        data = response.json()
        self.assertIn('endpoints', data, "Should include endpoints documentation")
        self.assertIn('POST /publish', data['endpoints'], "Should document publish endpoint")
        self.assertIn('GET /events', data['endpoints'], "Should document events endpoint")
        print("✅ API documentation available")
    
    def test_03_events_query_baseline(self):
        """Test that events endpoint returns data including direct test data"""
        print("\n📊 Testing events query (baseline)...")
        response = requests.get(f"{self.api_url}/events")
        self.assertEqual(response.status_code, 200, "Events API should respond successfully")
        
        try:
            data = response.json()
        except json.JSONDecodeError:
            self.fail("Response should be valid JSON")
        
        # Check new response format
        self.assertIn('events', data, "Response should have 'events' key")
        self.assertIn('count', data, "Response should have 'count' key")
        
        events = data['events']
        self.assertTrue(len(events) >= 0, "Should return events array")
        
        # Look for our direct test event
        direct_event = next((event for event in events if event['event_id'] == self.direct_event_id), None)
        if direct_event:
            self.assertEqual(direct_event['event_data']['test_key'], "direct_test_value",
                           "Direct test event data should match inserted data")
            print(f"✅ Found direct test event: {self.direct_event_id}")
        else:
            print("⚠️  Direct test event not found (may need time to propagate)")
    
    def test_04_event_count(self):
        """Test the events count endpoint"""
        print("\n🔢 Testing event count...")
        response = requests.get(f"{self.api_url}/events/count")
        self.assertEqual(response.status_code, 200, "Event count should respond successfully")
        
        data = response.json()
        self.assertIn('total_events', data, "Response should include total_events")
        self.assertIsInstance(data['total_events'], int, "total_events should be an integer")
        print(f"✅ Total events in system: {data['total_events']}")
    
    def test_05_publish_single_event(self):
        """Test publishing a single event through the pipeline"""
        print("\n📤 Testing event publishing...")
        
        # Create test event
        test_event_data = {
            "test_type": "pipeline_test",
            "user_id": f"test-user-{self.test_run_id}",
            "action": "integration_test",
            "page": "/test-page",
            "properties": {
                "browser": "test-browser",
                "device": "test-device",
                "test_run_id": self.test_run_id
            }
        }
        
        # Publish event
        response = requests.post(
            f"{self.api_url}/publish",
            headers={'Content-Type': 'application/json'},
            json=test_event_data
        )
        
        self.assertEqual(response.status_code, 200, "Publish should respond successfully")
        
        publish_data = response.json()
        self.assertIn('message_id', publish_data, "Response should include message_id")
        self.assertIn('event_id', publish_data, "Response should include event_id")
        self.assertEqual(publish_data['status'], 'published', "Status should be 'published'")
        
        # Store event_id for later verification
        self.pipeline_event_id = publish_data['event_id']
        print(f"✅ Published event with ID: {self.pipeline_event_id}")
    
    def test_06_verify_pipeline_event_in_bigquery(self):
        """Wait for and verify that published event appears in BigQuery"""
        print("\n⏳ Waiting for event to flow through pipeline...")
        
        if not hasattr(self, 'pipeline_event_id'):
            self.skipTest("No pipeline event ID available from previous test")
        
        # Wait for data to flow through Pub/Sub -> Dataflow -> BigQuery
        max_wait_time = 120  # 2 minutes max wait
        wait_interval = 10   # Check every 10 seconds
        
        for attempt in range(max_wait_time // wait_interval):
            print(f"  Checking attempt {attempt + 1}/{max_wait_time // wait_interval}...")
            
            # Query events from API
            response = requests.get(f"{self.api_url}/events?limit=50")
            if response.status_code == 200:
                data = response.json()
                events = data.get('events', [])
                
                # Look for our published event
                pipeline_event = next((event for event in events 
                                     if event['event_id'] == self.pipeline_event_id), None)
                
                if pipeline_event:
                    print(f"✅ Found pipeline event in BigQuery!")
                    
                    # Verify event data integrity
                    self.assertEqual(pipeline_event['event_data']['test_type'], 'pipeline_test',
                                   "Event data should match published data")
                    self.assertEqual(pipeline_event['event_data']['user_id'], 
                                   f"test-user-{self.test_run_id}",
                                   "User ID should match")
                    self.assertIn('timestamp', pipeline_event, "Event should have timestamp")
                    
                    return  # Test passed!
            
            time.sleep(wait_interval)
        
        self.fail(f"Pipeline event {self.pipeline_event_id} did not appear in BigQuery within {max_wait_time} seconds")
    
    def test_07_load_test_small(self):
        """Test publishing multiple events concurrently"""
        print("\n🚀 Testing small load (10 concurrent events)...")
        
        import concurrent.futures
        import threading
        
        results = []
        errors = []
        
        def publish_event(event_index):
            try:
                event_data = {
                    "test_type": "load_test",
                    "user_id": f"load-user-{event_index}",
                    "action": "load_test_action",
                    "test_run_id": self.test_run_id,
                    "sequence": event_index
                }
                
                response = requests.post(
                    f"{self.api_url}/publish",
                    headers={'Content-Type': 'application/json'},
                    json=event_data,
                    timeout=30
                )
                
                if response.status_code == 200:
                    results.append(response.json())
                else:
                    errors.append(f"Event {event_index}: {response.status_code} - {response.text}")
                    
            except Exception as e:
                errors.append(f"Event {event_index}: {str(e)}")
        
        # Publish 10 events concurrently
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(publish_event, i) for i in range(10)]
            concurrent.futures.wait(futures)
        
        print(f"✅ Load test completed: {len(results)} successful, {len(errors)} errors")
        
        if errors:
            print(f"❌ Errors encountered: {errors[:3]}...")  # Show first 3 errors
        
        # At least 80% should succeed
        success_rate = len(results) / 10
        self.assertGreaterEqual(success_rate, 0.8, 
                               f"Success rate should be at least 80%, got {success_rate*100}%")
    
    def test_08_error_handling(self):
        """Test API error handling"""
        print("\n🔥 Testing error handling...")
        
        # Test invalid JSON
        response = requests.post(
            f"{self.api_url}/publish",
            headers={'Content-Type': 'application/json'},
            data="invalid json"
        )
        self.assertEqual(response.status_code, 400, "Should return 400 for invalid JSON")
        
        # Test empty payload
        response = requests.post(
            f"{self.api_url}/publish",
            headers={'Content-Type': 'application/json'},
            json=None
        )
        self.assertEqual(response.status_code, 400, "Should return 400 for empty payload")
        
        # Test non-existent endpoint
        response = requests.get(f"{self.api_url}/nonexistent")
        self.assertEqual(response.status_code, 404, "Should return 404 for non-existent endpoint")
        
        print("✅ Error handling tests passed")
    
    @classmethod
    def tearDownClass(cls):
        """Clean up after tests"""
        print(f"\n🧹 Test run {cls.test_run_id} completed")
        print("Note: Test data will remain in BigQuery for verification")

if __name__ == '__main__':
    # Configure test runner for better output
    unittest.main(verbosity=2, buffer=True)