from flask import Flask, jsonify, request
from google.cloud import bigquery, pubsub_v1
import os
import logging
import json
import uuid
from datetime import datetime

app = Flask(__name__)
client = bigquery.Client()
publisher = pubsub_v1.PublisherClient()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route('/publish', methods=['POST'])
def publish_event():
    """Publish event data to Pub/Sub topic"""
    try:
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        topic_name = os.getenv('PUBSUB_TOPIC', 'data-ingestion-topic')
        topic_path = publisher.topic_path(project_id, topic_name)
        
        # Get event data from request
        event_data = request.get_json()
        
        if not event_data:
            return jsonify({"error": "No JSON data provided"}), 400
        
        # Create message with required BigQuery schema
        message_data = {
            "event_id": str(uuid.uuid4()),
            "event_data": event_data,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
        
        # Publish to Pub/Sub
        message_json = json.dumps(message_data)
        future = publisher.publish(topic_path, message_json.encode('utf-8'))
        message_id = future.result()  # Wait for publish to complete
        
        logger.info(f"Published message {message_id} to topic {topic_name}")
        return jsonify({
            "message_id": message_id, 
            "status": "published",
            "event_id": message_data["event_id"]
        }), 200
        
    except Exception as e:
        logger.error(f"Error publishing event: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/events', methods=['GET'])
def get_events():
    """Query events from BigQuery"""
    try:
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        
        # Get optional query parameters
        limit = request.args.get('limit', 100, type=int)
        limit = min(limit, 1000)  # Cap at 1000 for performance
        
        query = f"""
            SELECT 
                event_id,
                event_data,
                timestamp
            FROM `{project_id}.analytics_data.events`
            ORDER BY timestamp DESC
            LIMIT {limit}
        """

        logger.info(f"Executing query with limit {limit}")
        query_job = client.query(query)
        results = query_job.result()
        
        # Convert to list of dictionaries
        events = []
        for row in results:
            event = {
                "event_id": row.event_id,
                "event_data": row.event_data,  # Already parsed as JSON by BigQuery
                "timestamp": row.timestamp.isoformat() if row.timestamp else None
            }
            events.append(event)
        
        logger.info(f"Retrieved {len(events)} events")
        return jsonify({
            "events": events,
            "count": len(events)
        })

    except Exception as e:
        logger.error(f"Error fetching events: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/events/count', methods=['GET'])
def get_events_count():
    """Get total count of events in BigQuery"""
    try:
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        query = f"""
            SELECT COUNT(*) as total_events
            FROM `{project_id}.analytics_data.events`
        """
        
        query_job = client.query(query)
        results = query_job.result()
        
        for row in results:
            total_count = row.total_events
            
        return jsonify({
            "total_events": total_count
        })
        
    except Exception as e:
        logger.error(f"Error getting event count: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        # Test BigQuery connection
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        query = f"SELECT 1 as health_check"
        client.query(query).result()
        
        # Test Pub/Sub connection
        topic_name = os.getenv('PUBSUB_TOPIC', 'data-ingestion-topic')
        topic_path = publisher.topic_path(project_id, topic_name)
        
        return jsonify({
            "status": "healthy",
            "project_id": project_id,
            "pubsub_topic": topic_name,
            "timestamp": datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 500

@app.route('/', methods=['GET'])
def root():
    """Root endpoint with API documentation"""
    return jsonify({
        "service": "Data Ingestion API",
        "version": "1.0",
        "endpoints": {
            "POST /publish": "Publish event data to Pub/Sub",
            "GET /events": "Retrieve events from BigQuery (optional ?limit=N)",
            "GET /events/count": "Get total event count",
            "GET /health": "Health check"
        },
        "example_publish": {
            "url": "/publish",
            "method": "POST",
            "body": {
                "user_id": "12345",
                "action": "page_view",
                "page": "/home",
                "properties": {
                    "browser": "Chrome",
                    "device": "desktop"
                }
            }
        }
    })

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)), debug=True)