#!/usr/bin/env python3
from google.cloud import bigquery
import datetime
import uuid
import json
import argparse

def insert_test_data(project_id, dataset_id="analytics_data", table_id="events", num_records=5):
    """Insert test data directly into BigQuery table"""
    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{dataset_id}.{table_id}"
    
    print(f"Inserting {num_records} test records into {table_ref}")
    
    event_types = ["page_view", "click", "form_submit", "purchase", "login"]
    pages = ["/home", "/products", "/about", "/contact", "/checkout"]
    browsers = ["Chrome", "Firefox", "Safari", "Edge"]
    
    rows_to_insert = []
    
    for i in range(num_records):
        # Create a more realistic test record
        event_type = event_types[i % len(event_types)]
        
        event_data = {
            "user_id": f"test_user_{i+1}",
            "page": pages[i % len(pages)],
            "event_type": event_type,
            "browser": browsers[i % len(browsers)],
            "timestamp_client": datetime.datetime.now().isoformat()
        }
        
        # Add purchase-specific data
        if event_type == "purchase":
            event_data["amount"] = 99.99
            event_data["items"] = 3
        
        row = {
            "event_id": str(uuid.uuid4()),
            "event_data": json.dumps(event_data),  # Convert dict to JSON string for BigQuery
            "timestamp": datetime.datetime.now()
        }
        
        rows_to_insert.append(row)
        print(f"Prepared record {i+1}: {json.dumps(row, default=str)}")
    
    # Insert rows
    errors = client.insert_rows_json(table_ref, rows_to_insert)
    
    if errors == []:
        print(f"Successfully inserted {num_records} records into {table_ref}")
    else:
        print(f"Errors encountered while inserting rows: {errors}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Insert test data directly into BigQuery")
    parser.add_argument("--project", required=True, help="Your GCP project ID")
    parser.add_argument("--dataset", default="analytics_data", help="BigQuery dataset ID")
    parser.add_argument("--table", default="events", help="BigQuery table ID")
    parser.add_argument("--count", type=int, default=5, help="Number of records to insert")
    
    args = parser.parse_args()
    
    insert_test_data(args.project, args.dataset, args.table, args.count)