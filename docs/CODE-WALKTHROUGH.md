# Code Walkthrough

Line-by-line explanation of every folder.

---

## Flow

```
producer/ → Kafka "orders" topic → consumers/ (3 services) → Couchbase → web/backend/ → web/frontend/
```

---

## Component Connections

```
┌──────────────┐         ┌─────────────────┐
│   Producer   │────────►│  Kafka (9092)   │
│              │ SASL_SSL│                 │
└──────────────┘         └────────┬────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
   ┌───────────┐           ┌───────────┐           ┌───────────┐
   │   Fraud   │           │  Payment  │           │ Analytics │
   │   Group   │           │   Group   │           │   Group   │
   └───────────┘           └───────────┘           └─────┬─────┘
                                                         │
                                                         ▼ TLS :11207
                                                   ┌───────────┐
                                                   │ Couchbase │
                                                   └─────┬─────┘
                                                         │
                                                         ▼ N1QL
                                                   ┌───────────┐
                                                   │  Backend  │
                                                   │   :8000   │
                                                   └─────┬─────┘
                                                         │
                                                         ▼ proxy
                                                   ┌───────────┐
                                                   │ Frontend  │
                                                   │    :80    │
                                                   └─────┬─────┘
                                                         │
                                                         ▼ HTTPS
                                                   ┌───────────┐
                                                   │   User    │
                                                   └───────────┘
```

### Connection Summary

| From | To | Protocol | Port | Code |
|------|-----|----------|------|------|
| Producer | Kafka | SASL_SSL | 9092 | `KafkaProducer(security_protocol="SASL_SSL")` |
| Kafka | Consumers | SASL_SSL | 9092 | `KafkaConsumer(group_id="...")` |
| Analytics | Couchbase | TLS | 11207 | `couchbases://host` |
| Backend | Couchbase | TLS | 11207 | `cluster.query("SELECT...")` |
| Frontend | Backend | HTTP | 8000 | `fetch('/api/analytics')` |
| nginx | Backend | proxy | 8000 | `proxy_pass http://localhost:8000` |
| User | ALB | HTTPS | 443 | Browser |

---

# producer/

Generates fake orders and sends to Kafka.

## producer/requirements.txt

```
kafka-python==2.0.2
faker==30.3.0
```
- `kafka-python` - Kafka client library
- `faker` - generates fake data (customer IDs)

## producer/Dockerfile

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY producer.py .
ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092
ENV TOPIC_NAME=orders
ENV SLEEP_SECONDS=2
CMD ["python", "producer.py"]
```
- Line 1: Python 3.11 slim image (smaller size)
- Line 2: Set working directory
- Line 3-4: Install dependencies first (Docker layer caching)
- Line 5: Copy code
- Line 6-8: Default env vars (overridden by ECS)
- Line 9: Run the script

## producer/producer.py

```python
import json                      # serialize orders to JSON
import os                        # read environment variables
import random                    # random amounts/countries
import time                      # sleep between orders
from datetime import datetime    # timestamps
from faker import Faker          # fake customer IDs
from kafka import KafkaProducer  # Kafka client
```

```python
BOOTSTRAP_SERVERS = os.environ["KAFKA_BOOTSTRAP_SERVERS"]  # pkc-xxx.confluent.cloud:9092
API_KEY = os.environ["CONFLUENT_API_KEY"]                  # from Secrets Manager
API_SECRET = os.environ["CONFLUENT_API_SECRET"]            # from Secrets Manager
TOPIC_NAME = os.getenv("TOPIC_NAME", "orders")             # default "orders"
SLEEP_SECONDS = float(os.getenv("SLEEP_SECONDS", "2"))     # default 2 seconds
```
- `os.environ[]` - required, crashes if missing
- `os.getenv()` - optional with default

```python
fake = Faker()  # instance for generating fake data
```

```python
def create_producer():
    return KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,     # Kafka broker address
        security_protocol="SASL_SSL",            # Confluent requires SSL + auth
        sasl_mechanism="PLAIN",                  # username/password auth
        sasl_plain_username=API_KEY,             # API key as username
        sasl_plain_password=API_SECRET,          # API secret as password
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),  # dict → JSON bytes
        key_serializer=lambda k: str(k).encode("utf-8"),           # int → string bytes
        linger_ms=10,                            # batch messages for 10ms
        retries=5,                               # retry failed sends 5 times
        acks="all",                              # wait for all replicas to confirm
        api_version=(2, 6, 0),                   # skip auto-detection (faster startup)
    )
```

```python
def generate_order(order_id):
    return {
        "order_id": order_id,                                    # 1, 2, 3...
        "customer_id": fake.random_int(min=1000, max=9999),     # random 4-digit
        "amount": round(random.uniform(10, 500), 2),            # $10.00 - $500.00
        "currency": "USD",
        "country": random.choice(["US", "CA", "DE", "IN", "GB", "FR", "CN", "BR"]),
        "status": random.choice(["CREATED", "CONFIRMED", "CANCELLED"]),
        "created_at": datetime.utcnow().isoformat() + "Z",      # 2024-01-15T10:30:00Z
        "source": "order-service",
    }
```

```python
def main():
    print(f"Connecting to {BOOTSTRAP_SERVERS}...")
    producer = create_producer()                                  # connect to Kafka
    print(f"Producer ready. Publishing to '{TOPIC_NAME}'")

    order_id = 1
    while True:                                                   # infinite loop
        order = generate_order(order_id)
        future = producer.send(TOPIC_NAME, key=order["order_id"], value=order)
        # send() is async, returns Future

        try:
            meta = future.get(timeout=20)                         # wait for confirmation
            print(f"order={order_id} topic={meta.topic} partition={meta.partition} offset={meta.offset}")
        except Exception as e:
            print(f"Error: {e}")

        order_id += 1
        time.sleep(SLEEP_SECONDS)                                 # wait 2 seconds

if __name__ == "__main__":
    main()
```

---

# consumers/fraud-service/

Detects suspicious orders.

## fraud_consumer.py

```python
ORDERS_TOPIC = "orders"        # reads from here
ALERTS_TOPIC = "fraud-alerts"  # writes alerts here
```

```python
KAFKA_CONFIG = {
    "bootstrap_servers": BOOTSTRAP_SERVERS,
    "security_protocol": "SASL_SSL",
    "sasl_mechanism": "PLAIN",
    "sasl_plain_username": API_KEY,
    "sasl_plain_password": API_SECRET,
}
```
Reusable config dict for consumer and producer.

```python
consumer = KafkaConsumer(
    ORDERS_TOPIC,                                              # subscribe to "orders"
    **KAFKA_CONFIG,                                            # spread config dict
    group_id="fraud-group",                                    # consumer group name
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),# JSON bytes → dict
    auto_offset_reset="earliest",                              # start from beginning if new
    enable_auto_commit=True,                                   # auto-save progress
    api_version=(2, 6, 0),
)
```
- `group_id` - Kafka delivers each message to ONE consumer per group
- `auto_offset_reset="earliest"` - read all messages if this is a new group
- `enable_auto_commit=True` - Kafka saves which messages we've read

```python
producer = KafkaProducer(
    **KAFKA_CONFIG,
    value_serializer=lambda v: json.dumps(v).encode("utf-8"),
    api_version=(2, 6, 0),
)
```
For sending fraud alerts.

```python
def is_fraud(order):
    return order.get("amount", 0) > 300 and order.get("country") not in ["US", "CA"]
```
Rule: amount > $300 AND country not US/CA = suspicious.

```python
print("Fraud service started...")

for msg in consumer:                           # blocks waiting for messages
    order = msg.value                          # deserialized dict
    print(f"[fraud] order_id={order.get('order_id')}")

    if is_fraud(order):
        alert = {
            "order_id": order["order_id"],
            "reason": "HIGH_AMOUNT_RISKY_COUNTRY",
            "amount": order["amount"],
            "country": order["country"],
        }
        producer.send(ALERTS_TOPIC, value=alert)
        print(f"[fraud] ALERT: {alert}")
```
- `for msg in consumer` - infinite loop, blocks until message arrives
- Checks fraud rule
- Sends alert to separate topic if triggered

---

# consumers/payment-service/

Simulates payment processing.

## payment_consumer.py

```python
ORDERS_TOPIC = "orders"     # reads from here
PAYMENTS_TOPIC = "payments" # writes here
```

```python
consumer = KafkaConsumer(
    ORDERS_TOPIC,
    **KAFKA_CONFIG,
    group_id="payments-group",   # different group than fraud
    ...
)
```
Different `group_id` so this service also gets ALL orders (not shared with fraud).

```python
for msg in consumer:
    order = msg.value
    print(f"[payment] order_id={order.get('order_id')}")

    time.sleep(0.1)  # simulate 100ms processing time

    payment = {
        "order_id": order["order_id"],
        "status": "PAID",
        "amount": order["amount"],
        "country": order["country"],
        "timestamp": time.time(),         # unix timestamp
    }
    producer.send(PAYMENTS_TOPIC, key=payment["order_id"], value=payment)
    print(f"[payment] processed: {payment['order_id']}")
```
- Reads order
- Waits 100ms (simulates real payment processing)
- Sends "PAID" status to payments topic

---

# consumers/analytics-service/

Stores orders to Couchbase for the dashboard.

## analytics_consumer.py

```python
from couchbase.cluster import Cluster
from couchbase.options import ClusterOptions, ClusterTimeoutOptions
from couchbase.auth import PasswordAuthenticator
```
Couchbase Python SDK.

```python
COUCHBASE_HOST = os.environ.get("COUCHBASE_HOST", "localhost")
COUCHBASE_BUCKET = os.environ.get("COUCHBASE_BUCKET", "order_analytics")
COUCHBASE_USER = os.environ.get("COUCHBASE_USERNAME", "Administrator")
COUCHBASE_PASS = os.environ.get("COUCHBASE_PASSWORD", "password")
```
Defaults for local dev, overridden by ECS secrets in production.

```python
ORDERS_TOPIC = "orders"
ANALYTICS_TOPIC = "order-analytics"
```

```python
consumer = KafkaConsumer(
    ORDERS_TOPIC,
    **KAFKA_CONFIG,
    group_id="analytics-group",  # third group, also gets ALL orders
    ...
)
```

```python
print(f"Connecting to Couchbase at {COUCHBASE_HOST}...")
collection = None
try:
    # couchbases:// for Capella (TLS), couchbase:// for local
    conn_str = f"couchbases://{COUCHBASE_HOST}" if "cloud.couchbase.com" in COUCHBASE_HOST else f"couchbase://{COUCHBASE_HOST}"
    
    cluster = Cluster(
        conn_str,
        ClusterOptions(
            PasswordAuthenticator(COUCHBASE_USER, COUCHBASE_PASS),
            timeout_options=ClusterTimeoutOptions(kv_timeout=timedelta(seconds=10))
        )
    )
    bucket = cluster.bucket(COUCHBASE_BUCKET)      # get bucket
    collection = bucket.default_collection()        # get default collection
    print(f"Connected to Couchbase bucket: {COUCHBASE_BUCKET}")
except Exception as e:
    print(f"Couchbase connection failed: {e}")
```
- Auto-detect cloud vs local based on hostname
- `couchbases://` = TLS (required for Capella)
- 10 second timeout for operations

```python
total_sales = 0.0
order_count = 0
```
Running totals (in memory).

```python
for msg in consumer:
    order = msg.value
    amount = float(order.get("amount", 0))
    total_sales += amount
    order_count += 1

    analytics = {
        "total_sales": round(total_sales, 2),
        "order_count": order_count,
    }

    producer.send(ANALYTICS_TOPIC, value=analytics)  # publish stats to Kafka
```

```python
    if collection:
        try:
            doc_id = str(order.get("order_id", uuid.uuid4()))  # document key
            order_doc = {
                **order,                                        # copy all fields
                "processed_at": str(msg.timestamp) if msg.timestamp else None,
                "kafka_offset": msg.offset,
                "kafka_partition": msg.partition,
            }
            collection.upsert(doc_id, order_doc)               # insert or update
            print(f"[analytics] order {doc_id} saved | {analytics}")
        except Exception as e:
            print(f"[analytics] couchbase error: {e}")
    else:
        print(f"[analytics] {analytics}")
```
- `upsert` = insert if new, update if exists (handles duplicates)
- Uses order_id as document key
- Adds Kafka metadata for debugging

---

# web/backend/

FastAPI serving the dashboard API.

## requirements.txt

```
fastapi
uvicorn
couchbase==4.3.0
psycopg2-binary
```
- `fastapi` - web framework
- `uvicorn` - ASGI server
- `couchbase` - database client
- `psycopg2-binary` - PostgreSQL (unused currently)

## Dockerfile

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```
- Runs uvicorn on port 8000
- `app:app` = module `app`, variable `app`

## app.py

```python
from fastapi import FastAPI
from datetime import timedelta
import os

from couchbase.cluster import Cluster, ClusterOptions
from couchbase.auth import PasswordAuthenticator
from couchbase.options import ClusterTimeoutOptions

app = FastAPI()
```

```python
COUCHBASE_HOST = os.getenv("COUCHBASE_HOST")
COUCHBASE_BUCKET = os.getenv("COUCHBASE_BUCKET")
COUCHBASE_USER = os.getenv("COUCHBASE_USERNAME")
COUCHBASE_PASS = os.getenv("COUCHBASE_PASSWORD")
```
From ECS secrets.

```python
@app.get("/healthz")
def healthz():
    return {"status": "ok"}
```
Health check endpoint. ALB calls this every 30 seconds.

```python
@app.get("/api/analytics")
def get_analytics():
    try:
        conn_str = f"couchbases://{COUCHBASE_HOST}" if "cloud.couchbase.com" in COUCHBASE_HOST else f"couchbase://{COUCHBASE_HOST}"
        
        cluster = Cluster(
            conn_str,
            ClusterOptions(
                PasswordAuthenticator(COUCHBASE_USER, COUCHBASE_PASS),
                timeout_options=ClusterTimeoutOptions(kv_timeout=timedelta(seconds=5))
            )
        )

        bucket = cluster.bucket(COUCHBASE_BUCKET)
        result = cluster.query(f"SELECT * FROM `{COUCHBASE_BUCKET}` LIMIT 10;")
        # N1QL query - SQL-like syntax for Couchbase

        return {"status": "ok", "orders": [row for row in result]}

    except Exception as e:
        return {"error": str(e)}
```
- Connects to Couchbase
- Runs N1QL query to get last 10 orders
- Returns JSON array

---

# infra/terraform-ecs/

Infrastructure as code.

## variables.tf

```hcl
variable "ghcr_pat" {
  type        = string
  sensitive   = true                    # hidden in logs
  description = "GitHub PAT with read:packages scope"
}
```
No default = Terraform prompts for it.

```hcl
variable "confluent_api_key" {
  type        = string
  sensitive   = true
  description = "Confluent Cloud API key"
}

variable "confluent_api_secret" {
  type        = string
  sensitive   = true
  description = "Confluent Cloud API secret"
}
```

```hcl
variable "couchbase_password" {
  type        = string
  sensitive   = true
  description = "Couchbase database password"
}
```

## secrets.tf

```hcl
resource "aws_secretsmanager_secret" "ghcr" {
  name = "${var.project_name}-ghcr-credentials"
}

resource "aws_secretsmanager_secret_version" "ghcr" {
  secret_id = aws_secretsmanager_secret.ghcr.id
  secret_string = jsonencode({
    username = var.ghcr_username
    password = var.ghcr_pat
  })
}
```
Creates secret, stores as JSON.

```hcl
resource "aws_secretsmanager_secret" "confluent" {
  name = "${var.project_name}-confluent-credentials"
}

resource "aws_secretsmanager_secret_version" "confluent" {
  secret_id = aws_secretsmanager_secret.confluent.id
  secret_string = jsonencode({
    bootstrap_servers = var.confluent_bootstrap_servers
    api_key           = var.confluent_api_key
    api_secret        = var.confluent_api_secret
  })
}
```

```hcl
resource "aws_secretsmanager_secret" "couchbase" {
  name = "${var.project_name}-couchbase-credentials"
}

resource "aws_secretsmanager_secret_version" "couchbase" {
  secret_id = aws_secretsmanager_secret.couchbase.id
  secret_string = jsonencode({
    host     = var.couchbase_host
    bucket   = var.couchbase_bucket
    username = var.couchbase_username
    password = var.couchbase_password
  })
}
```

## ecs.tf (key parts)

```hcl
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}
```
Creates ECS cluster.

```hcl
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.ghcr.arn,
        aws_secretsmanager_secret.confluent.arn,
        aws_secretsmanager_secret.couchbase.arn
      ]
    }]
  })
}
```
Allows ECS tasks to read secrets.

```hcl
secrets = [
  { name = "COUCHBASE_HOST", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:host::" },
  { name = "COUCHBASE_BUCKET", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:bucket::" },
  { name = "COUCHBASE_USERNAME", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:username::" },
  { name = "COUCHBASE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.couchbase.arn}:password::" }
]
```
ECS injects these as environment variables. Format: `{arn}:{json_key}::`.

---

# web/frontend/

React dashboard that displays orders.

## package.json (dependencies)

```json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
```
Standard React app, no extra libraries.

## Dockerfile

```dockerfile
FROM node:20 AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:latest
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```
- Line 1-6: Build stage - install deps, run `npm run build`
- Line 8-12: Production stage - copy built files to nginx

## src/App.js

```javascript
import React, { useState, useEffect } from 'react';
import './App.css';
```

```javascript
function App() {
  const [orders, setOrders] = useState([]);      // array of orders
  const [loading, setLoading] = useState(true);   // show spinner
  const [error, setError] = useState(null);       // error message
  const [lastUpdated, setLastUpdated] = useState(null);
```
React state hooks.

```javascript
  const fetchAnalytics = async () => {
    try {
      const response = await fetch('/api/analytics');  // calls backend
      const data = await response.json();
      
      if (data.error) {
        setError(data.error);
      } else {
        setOrders(data.orders || []);
        setError(null);
      }
      setLastUpdated(new Date().toLocaleTimeString());
    } catch (err) {
      setError('Failed to fetch data: ' + err.message);
    } finally {
      setLoading(false);
    }
  };
```
- `fetch('/api/analytics')` - relative URL, nginx proxies to backend
- Handles both API errors (`data.error`) and network errors (`catch`)

```javascript
  useEffect(() => {
    fetchAnalytics();                              // fetch on mount
    const interval = setInterval(fetchAnalytics, 5000);  // refresh every 5 seconds
    return () => clearInterval(interval);          // cleanup on unmount
  }, []);
```
Auto-refresh every 5 seconds.

```javascript
  // Calculate stats from orders array
  const totalOrders = orders.length;
  const totalSales = orders.reduce((sum, order) => {
    const amount = order?.order_analytics?.amount || order?.amount || 0;
    return sum + parseFloat(amount);
  }, 0);
  const avgOrderValue = totalOrders > 0 ? (totalSales / totalOrders).toFixed(2) : 0;
```
Client-side aggregation from the orders array.

```javascript
  return (
    <div className="dashboard">
      <header className="header">
        <h1>Kafka Enterprise Orders</h1>
        <span className="status-badge">Live</span>
      </header>

      <section className="stats-section">
        <div className="stat-card">
          <span className="stat-label">Total Orders</span>
          <span className="stat-value">{totalOrders}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Total Sales</span>
          <span className="stat-value">${totalSales.toFixed(2)}</span>
        </div>
      </section>
```

```javascript
      {orders.map((item, index) => {
        const order = item?.order_analytics || item;  // handle nested structure
        return (
          <tr key={index}>
            <td>#{order.order_id}</td>
            <td>{order.customer_id}</td>
            <td>${parseFloat(order.amount).toFixed(2)}</td>
            <td>{order.country}</td>
            <td>{order.status}</td>
          </tr>
        );
      })}
```
- Couchbase returns `{order_analytics: {...}}` wrapper
- Fallback handles both wrapped and unwrapped

## nginx.conf (routing)

```nginx
location /api/ {
    proxy_pass http://localhost:8000/;
}

location / {
    root /usr/share/nginx/html;
    try_files $uri /index.html;
}
```
- `/api/*` → backend (port 8000)
- Everything else → React app (SPA routing)

---

# docker-compose.yml

For local development with all services.

```yaml
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.1
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
```
Kafka needs Zookeeper for coordination.

```yaml
  kafka:
    image: confluentinc/cp-kafka:7.6.1
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
```
Single-node Kafka broker.

```yaml
  schema-registry:
    image: confluentinc/cp-schema-registry:7.6.1
    environment:
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: PLAINTEXT://kafka:9092
```
Stores Avro/JSON schemas (optional).

```yaml
  connect:
    image: confluentinc/cp-kafka-connect:7.6.1
    environment:
      CONNECT_BOOTSTRAP_SERVERS: kafka:9092
      CONNECT_PLUGIN_PATH: /usr/share/java,/connectors
    volumes:
      - ./kafka-connect-jars:/connectors
```
Kafka Connect with Couchbase connector loaded.

```yaml
  couchbase:
    image: couchbase:community-7.2.0
    ports:
      - "8091-8096:8091-8096"
    volumes:
      - couchbase_data:/opt/couchbase/var
```
Local Couchbase for development.

```yaml
  order-producer:
    build: ./producer
    depends_on:
      - kafka
    environment:
      KAFKA_BOOTSTRAP: kafka:9092
```
Producer service (local mode uses plain Kafka, no SSL).

---

# k8s/charts/webapp/

Helm chart for Kubernetes deployment.

## Chart.yaml

```yaml
apiVersion: v2
name: webapp
version: 1.0.0
```
Helm chart metadata.

## values.yaml

```yaml
frontendImage: ghcr.io/username/web-frontend:latest
backendImage: ghcr.io/username/web-backend:latest
backendPort: 8000

couchbase:
  host: cb.xxxxx.cloud.couchbase.com
  bucket: order_analytics
  username: admin
  password: ""   # pass via --set or secrets
```
Default values, override with `--set` or `-f values-prod.yaml`.

## templates/deployment.yaml

```yaml
spec:
  containers:
    - name: frontend
      image: {{ .Values.frontendImage }}
      ports:
        - containerPort: 80
```
Templated values use `{{ .Values.xxx }}` syntax.

```yaml
    - name: backend
      image: {{ .Values.backendImage }}
      env:
        - name: COUCHBASE_HOST
          value: "{{ .Values.couchbase.host }}"
        - name: COUCHBASE_PASSWORD
          value: "{{ .Values.couchbase.password }}"
```
Environment variables from Helm values.

```yaml
      readinessProbe:
        httpGet:
          path: /healthz
          port: 8000
        initialDelaySeconds: 5
```
Kubernetes checks `/healthz` before routing traffic.

## templates/service.yaml

```yaml
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
```
Internal service, exposed via Ingress.

## templates/ingress.yaml

```yaml
spec:
  rules:
    - host: orders.jumptotech.net
      http:
        paths:
          - path: /
            backend:
              service:
                name: webapp
                port: 80
```
Maps domain to service.

---

# Complete Flow

```
1. terraform apply
   └── Creates secrets in AWS Secrets Manager
   └── Creates ECS cluster, services, ALB

2. ECS starts containers
   └── Pulls images from GHCR (using ghcr secret)
   └── Injects env vars from secrets

3. Producer starts
   └── Reads KAFKA_BOOTSTRAP_SERVERS, CONFLUENT_API_KEY, CONFLUENT_API_SECRET
   └── Connects to Confluent Cloud
   └── Generates order {order_id: 1, amount: 249.99, country: "US"}
   └── Sends to "orders" topic, partition 3, offset 1000

4. Fraud service receives (group: fraud-group)
   └── Checks: amount > 300 AND country not in [US, CA]?
   └── No → skip

5. Payment service receives (group: payments-group)
   └── Waits 100ms
   └── Sends {status: "PAID"} to "payments" topic

6. Analytics service receives (group: analytics-group)
   └── Updates total_sales, order_count
   └── Connects to Couchbase Capella
   └── Upserts document with key "1"

7. User opens https://orders.jumptotech.net
   └── Frontend loads
   └── Calls GET /api/analytics
   └── Backend connects to Couchbase
   └── Runs: SELECT * FROM order_analytics LIMIT 10
   └── Returns JSON array
   └── Frontend renders dashboard
```
