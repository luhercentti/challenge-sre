#!/usr/bin/env python3
from google.cloud import pubsub_v1
import json
import uuid
import time
import datetime
import random
import argparse

def generate_event():
    """Generate a sample event with random data"""
    event_types = ["page_view", "click", "form_submit", "purchase", "login"]
    user_ids = [f"user_{i}" for i in range(1, 11)]
    pages = ["/home", "/products", "/about", "/contact", "/checkout"]
    
    event_id = str(uuid.uuid4())
    event_type = random.choice(event_types)
    user_id = random.choice(user_ids)
    page = random.choice(pages)
    timestamp = datetime.datetime.now().isoformat()
    
    event_data = {
        "user_id": user_id,
        "page": page,
        "event_type": event_type,
        "browser": random.choice(["Chrome", "Firefox", "Safari", "Edge"]),
        "device": random.choice(["desktop", "mobile", "tablet"]),
        "country": random.choice(["US", "CA", "MX", "UK", "FR", "DE", "JP"]),
    }
    
    if event_type == "purchase":
        event_data["amount"] = round(random.uniform(10.0, 500.0), 2)
        event_data["items"] = random.randint(1, 5)
    
    return {
        "event_id": event_id,
        "event_data": event_data,
        "timestamp": timestamp
    }

def publish_messages(project_id, topic_name, num_messages=10, delay=1):
    """Publish a specified number of test messages to the PubSub topic"""
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    print(f"Publishing {num_messages} test events to {topic_path}")
    
    for i in range(num_messages):
        event = generate_event()
        data = json.dumps(event).encode("utf-8")
        
        # Publish message
        future = publisher.publish(topic_path, data=data)
        message_id = future.result()
        
        print(f"Published message {i+1}/{num_messages}: {message_id}")
        print(f"Event data: {json.dumps(event, indent=2)}")
        print("-" * 50)
        
        # Add a small delay between messages
        if i < num_messages - 1:
            time.sleep(delay)
    
    print(f"Successfully published {num_messages} messages to {topic_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Publish test events to PubSub topic")
    parser.add_argument("--project", required=True, help="Your GCP project ID")
    parser.add_argument("--topic", default="data-ingestion-topic", help="PubSub topic name")
    parser.add_argument("--count", type=int, default=10, help="Number of messages to publish")
    parser.add_argument("--delay", type=float, default=1.0, help="Delay between messages in seconds")
    
    args = parser.parse_args()
    
    publish_messages(args.project, args.topic, args.count, args.delay)