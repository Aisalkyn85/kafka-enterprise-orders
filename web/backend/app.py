from fastapi import FastAPI
from datetime import timedelta
import os

from couchbase.cluster import Cluster
from couchbase.auth import PasswordAuthenticator
from couchbase.options import ClusterOptions, ClusterTimeoutOptions

app = FastAPI()

COUCHBASE_HOST = os.getenv("COUCHBASE_HOST")
COUCHBASE_BUCKET = os.getenv("COUCHBASE_BUCKET")
COUCHBASE_USER = os.getenv("COUCHBASE_USERNAME")
COUCHBASE_PASS = os.getenv("COUCHBASE_PASSWORD")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/api/analytics")
def get_analytics():
    try:
        # Build connection string - for local Couchbase, use couchbase:// protocol
        # For Couchbase Cloud, use couchbases:// (SSL)
        if "cloud.couchbase.com" in COUCHBASE_HOST:
            conn_str = f"couchbases://{COUCHBASE_HOST}"
        else:
            # Local Couchbase - use couchbase:// protocol
            # The SDK will use default ports (8091 for management, 11210 for data)
            conn_str = f"couchbase://{COUCHBASE_HOST}"
        
        cluster = Cluster(
            conn_str,
            ClusterOptions(
                PasswordAuthenticator(COUCHBASE_USER, COUCHBASE_PASS),
                timeout_options=ClusterTimeoutOptions(
                    kv_timeout=timedelta(seconds=10),
                    connect_timeout=timedelta(seconds=10)
                )
            )
        )

        # Wait for the bucket to be ready
        bucket = cluster.bucket(COUCHBASE_BUCKET)
        bucket.wait_until_ready(timedelta(seconds=5))
        
        # Get latest 10 orders sorted by order_id descending
        # Query returns documents directly
        query = f"SELECT * FROM `{COUCHBASE_BUCKET}` ORDER BY order_id DESC LIMIT 10"
        result = cluster.query(query)

        # Extract row values from query result
        # Handle different result structures from Couchbase SDK
        orders = []
        for row in result.rows():
            # Check if row has a 'value' attribute (QueryRow object)
            if hasattr(row, 'value'):
                row_data = row.value
            # If row is already a dict, use it directly
            elif isinstance(row, dict):
                row_data = row
            else:
                # Try to get value as dict
                row_data = row
            
            # If the result has the bucket name as a key, extract it
            # Otherwise use the data as-is
            if isinstance(row_data, dict):
                # Check for nested bucket name key
                if COUCHBASE_BUCKET in row_data:
                    orders.append(row_data[COUCHBASE_BUCKET])
                else:
                    orders.append(row_data)
            else:
                orders.append(row_data)

        return {"status": "ok", "orders": orders}

    except Exception as e:
        error_msg = str(e)
        # Provide helpful error message for common issues
        if "authentication_failure" in error_msg or "authentication" in error_msg.lower():
            if "cloud.couchbase.com" not in (COUCHBASE_HOST or ""):
                error_msg += " | For local Couchbase: 1) Open http://localhost:8091, 2) Login (Administrator/password), 3) Create bucket 'order_analytics'"
        elif "bucket" in error_msg.lower() and "not found" in error_msg.lower():
            error_msg += " | Bucket 'order_analytics' not found. Please create it in Couchbase Admin UI (http://localhost:8091)"
        
        return {"error": error_msg, "details": {
            "host": COUCHBASE_HOST,
            "bucket": COUCHBASE_BUCKET,
            "user": COUCHBASE_USER
        }}
