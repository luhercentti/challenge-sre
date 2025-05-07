from flask import Flask, jsonify
from google.cloud import bigquery
import os

app = Flask(__name__)
client = bigquery.Client()

@app.route('/events', methods=['GET'])
def get_events():
    query = """
        SELECT * 
        FROM `{}.analytics_data.events`
        ORDER BY timestamp DESC
        LIMIT 100
    """.format(os.getenv('GOOGLE_CLOUD_PROJECT'))
    
    results = client.query(query).to_dataframe()
    return jsonify(results.to_dict('records'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))