from flask import Flask, jsonify
from google.cloud import bigquery
import os
import logging

app = Flask(__name__)
client = bigquery.Client()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route('/events', methods=['GET'])
def get_events():
    try:
        project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        query = """
            SELECT * 
            FROM `{}.analytics_data.events`
            ORDER BY timestamp DESC
            LIMIT 100
        """.format(project_id)
        
        logger.info(f"Executing query: {query}")
        results = client.query(query).to_dataframe()
        return jsonify(results.to_dict('records'))
    
    except Exception as e:
        logger.error(f"Error fetching events: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))