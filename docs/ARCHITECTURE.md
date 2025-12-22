# Architecture

## System Overview

```
Producer → Kafka → Consumers (3) → Couchbase → Backend → Frontend → User
```

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS ECS                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌──────────────┐         ┌─────────────────────────────────┐          │
│   │   Producer   │────────►│      Confluent Cloud (Kafka)    │          │
│   │              │  SASL   │                                 │          │
│   │ producer.py  │  SSL    │   Topic: "orders"               │          │
│   └──────────────┘  :9092  │   ┌───────┬───────┬───────┐     │          │
│                            │   │Part 0 │Part 1 │Part 2 │     │          │
│                            │   └───┬───┴───┬───┴───┬───┘     │          │
│                            └───────│───────│───────│─────────┘          │
│                                    │       │       │                    │
│                                    ▼       ▼       ▼                    │
│                     ┌──────────────────────────────────────┐            │
│                     │         3 Consumer Groups            │            │
│                     ├────────────┬───────────┬─────────────┤            │
│                     │            │           │             │            │
│                     ▼            ▼           ▼             │            │
│              ┌───────────┐ ┌───────────┐ ┌───────────┐     │            │
│              │  Fraud    │ │  Payment  │ │ Analytics │     │            │
│              │  Service  │ │  Service  │ │  Service  │     │            │
│              └─────┬─────┘ └─────┬─────┘ └─────┬─────┘     │            │
│                    │             │             │           │            │
│                    ▼             ▼             │           │            │
│              "fraud-alerts" "payments"         │           │            │
│                 topic         topic            │           │            │
│                                                │           │            │
│                                                ▼           │            │
│                              ┌─────────────────────────┐   │            │
│                              │   Couchbase Capella     │   │            │
│                              │                         │   │            │
│                              │  Bucket: order_analytics│   │            │
│                              └────────────▲────────────┘   │            │
│                                           │                │            │
│                                           │ N1QL Query     │            │
│                              ┌────────────┴────────────┐   │            │
│                              │      Backend API        │   │            │
│                              │   FastAPI :8000         │   │            │
│                              └────────────▲────────────┘   │            │
│                                           │                │            │
│                                           │ proxy_pass     │            │
│                              ┌────────────┴────────────┐   │            │
│                              │       Frontend          │   │            │
│                              │     nginx :80           │   │            │
│                              └────────────▲────────────┘   │            │
│                                           │                │            │
└───────────────────────────────────────────│────────────────┘            │
                                            │                             │
                              ┌─────────────┴─────────────┐               │
                              │      AWS ALB :443         │               │
                              └─────────────▲─────────────┘               │
                                            │                             │
                              ┌─────────────┴─────────────┐               │
                              │      User Browser         │               │
                              │  orders.jumptotech.net    │               │
                              └───────────────────────────┘               │
```

---

## Connection Details

### 1. Producer → Kafka

| Setting | Value |
|---------|-------|
| Protocol | SASL_SSL (encrypted + authenticated) |
| Port | 9092 |
| Auth | API Key + Secret |

```python
producer = KafkaProducer(
    bootstrap_servers="pkc-xxx.confluent.cloud:9092",
    security_protocol="SASL_SSL",
    sasl_mechanism="PLAIN",
    sasl_plain_username=API_KEY,
    sasl_plain_password=API_SECRET,
)
producer.send("orders", value=order)
```

### 2. Kafka → Consumers

Each service has its own consumer group:

| Service | Group ID | Receives |
|---------|----------|----------|
| Fraud | fraud-group | ALL orders |
| Payment | payments-group | ALL orders |
| Analytics | analytics-group | ALL orders |

```python
consumer = KafkaConsumer(
    "orders",
    group_id="fraud-group",  # unique per service
    ...
)
```

### 3. Analytics → Couchbase

| Setting | Value |
|---------|-------|
| Protocol | TLS (couchbases://) |
| Port | 11207 |
| Auth | Username + Password |

```python
cluster = Cluster(
    "couchbases://cb.xxx.cloud.couchbase.com",
    ClusterOptions(PasswordAuthenticator(user, password))
)
collection.upsert(doc_id, order)
```

### 4. Backend → Couchbase

Same connection as Analytics:

```python
result = cluster.query("SELECT * FROM order_analytics LIMIT 10")
return {"orders": list(result)}
```

### 5. Frontend → Backend

Nginx proxies API calls:

```nginx
location /api/ {
    proxy_pass http://localhost:8000/;
}
```

### 6. User → Frontend

| Layer | Protocol | Port |
|-------|----------|------|
| Browser → ALB | HTTPS | 443 |
| ALB → Frontend | HTTP | 80 |
| Frontend → Backend | HTTP | 8000 |

---

## Secrets Flow

```
AWS Secrets Manager
        │
        │ ECS fetches at startup
        ▼
ECS Task Definition (secrets=[...])
        │
        │ Injected as env vars
        ▼
Container Environment
        │
        │ os.environ["..."]
        ▼
Application Code
```

### Secrets Stored

| Secret Name | Keys |
|-------------|------|
| confluent-credentials | bootstrap_servers, api_key, api_secret |
| couchbase-credentials | host, bucket, username, password |
| ghcr-credentials | username, password |

---

## Data Flow Example

```
1. Producer creates order:
   {"order_id": 1, "amount": 249.99, "country": "US"}

2. Sends to Kafka topic "orders", partition 2, offset 1500

3. Three consumers receive (each has own group):
   
   Fraud Service:
   - Checks: amount > 300 AND country not US/CA?
   - No → skip
   
   Payment Service:
   - Waits 100ms
   - Sends to "payments" topic: {"order_id": 1, "status": "PAID"}
   
   Analytics Service:
   - Connects to Couchbase
   - Upserts document with key "1"

4. User opens https://orders.jumptotech.net

5. Frontend loads, calls GET /api/analytics

6. Backend queries: SELECT * FROM order_analytics LIMIT 10

7. Returns JSON: {"orders": [{"order_id": 1, ...}, ...]}

8. Frontend renders table with orders
```

---

## Port Summary

| Component | Port | Protocol |
|-----------|------|----------|
| Kafka | 9092 | SASL_SSL |
| Couchbase | 11207 | TLS |
| Backend | 8000 | HTTP |
| Frontend | 80 | HTTP |
| ALB | 443 | HTTPS |

---

## Technology Choices

| Component | Technology | Why |
|-----------|------------|-----|
| Message Queue | Confluent Cloud | Managed Kafka, no ops |
| Database | Couchbase Capella | JSON docs, N1QL queries |
| Backend | FastAPI | Fast, async, auto-docs |
| Frontend | React | Component-based, hooks |
| Container | AWS ECS Fargate | Serverless, no EC2 |
| IaC | Terraform | Declarative, reproducible |
