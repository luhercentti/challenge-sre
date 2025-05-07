from flask import Flask, jsonify
from google.cloud import bigquery
import os
import logging
import json

app = Flask(__name__)
client = bigquery.Client()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route('/events', methods=['GET'])
def get_events():
    try:
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        query = f"""
            SELECT 
                event_id,
                CAST(event_data AS STRING) AS event_data,
                timestamp
            FROM `{project_id}.analytics_data.events`
            ORDER BY timestamp DESC
            LIMIT 100
        """
        
        logger.info(f"Executing query: {query}")
        df = client.query(query).to_dataframe()

        # Try to parse event_data JSON strings
        def safe_parse(json_str):
            try:
                return json.loads(json_str)
            except (TypeError, json.JSONDecodeError):
                return json_str  # fallback to original string

        if 'event_data' in df.columns:
            df['event_data'] = df['event_data'].apply(safe_parse)

        return jsonify(df.to_dict('records'))

    except Exception as e:
        logger.error(f"Error fetching events: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
