from fastapi import FastAPI
import os
from couchbase.cluster import Cluster, ClusterOptions
from couchbase.auth import PasswordAuthenticator
from couchbase.options import ClusterTimeoutOptions

app = FastAPI()

# -------------------------------
# Environment variables
# -------------------------------
COUCHBASE_HOST = os.getenv("COUCHBASE_HOST")
COUCHBASE_BUCKET = os.getenv("COUCHBASE_BUCKET")
COUCHBASE_USER = os.getenv("COUCHBASE_USERNAME")
COUCHBASE_PASS = os.getenv("COUCHBASE_PASSWORD")


# ---------------------------------------------------------
# REQUIRED BY AWS ALB — DEFAULT HEALTH CHECK ENDPOINT
# ALB calls GET "/" → MUST return 200 OK
# ---------------------------------------------------------
@app.get("/")
def root():
    return {"status": "ok", "service": "backend"}


# ---------------------------------------------------------
# Kubernetes / ECS custom health check
# ---------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"status": "ok"}


# ---------------------------------------------------------
# Couchbase Analytics API
# GET last 10 orders from Couchbase bucket
# ---------------------------------------------------------
@app.get("/api/analytics")
def get_analytics():
    try:
        # Connect to Couchbase cluster
        cluster = Cluster(
            f"couchbase://{COUCHBASE_HOST}",
            ClusterOptions(
                PasswordAuthenticator(COUCHBASE_USER, COUCHBASE_PASS),
                timeout_options=ClusterTimeoutOptions(kv_timeout=5),
            )
        )

        bucket = cluster.bucket(COUCHBASE_BUCKET)
        collection = bucket.default_collection()

        # Query last 10 orders
        result = cluster.query(
            f"SELECT * FROM `{COUCHBASE_BUCKET}` LIMIT 10;"
        )

        orders = [row for row in result]

        return {"status": "ok", "count": len(orders), "orders": orders}

    except Exception as e:
        return {"status": "error", "message": str(e)}

