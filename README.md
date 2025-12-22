# Kafka Enterprise Orders

Real-time order processing with Kafka, Couchbase, and AWS.

**Live Demo:** https://orders.jumptotech.net

---

## How It Works

```
Producer → Kafka → 3 Consumers → Couchbase → Backend → Frontend
```

1. **Producer** generates fake orders every 2 seconds
2. **Kafka** distributes to 3 consumer groups
3. **Consumers** process in parallel:
   - Fraud: flags suspicious orders
   - Payment: marks as paid
   - Analytics: saves to database
4. **Backend** queries Couchbase
5. **Frontend** displays live dashboard

---

## Architecture

```
┌──────────────┐         ┌─────────────────┐
│   Producer   │────────►│  Confluent Cloud │
└──────────────┘         │     (Kafka)      │
                         └────────┬─────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
        ┌───────────┐      ┌───────────┐      ┌───────────┐
        │   Fraud   │      │  Payment  │      │ Analytics │
        │  Service  │      │  Service  │      │  Service  │
        └───────────┘      └───────────┘      └─────┬─────┘
                                                    │
                                                    ▼
                                            ┌─────────────┐
                                            │  Couchbase  │
                                            │   Capella   │
                                            └──────┬──────┘
                                                   │
                                            ┌──────┴──────┐
                                            │   Backend   │
                                            │   FastAPI   │
                                            └──────┬──────┘
                                                   │
                                            ┌──────┴──────┐
                                            │  Frontend   │
                                            │    React    │
                                            └─────────────┘
```

---

## Component Connections

| From | To | Protocol | Port |
|------|-----|----------|------|
| Producer | Kafka | SASL_SSL | 9092 |
| Kafka | Consumers | SASL_SSL | 9092 |
| Analytics | Couchbase | TLS | 11207 |
| Backend | Couchbase | TLS | 11207 |
| Frontend | Backend | HTTP | 8000 |
| User | ALB | HTTPS | 443 |

---

## Folder Structure

```
kafka-enterprise-orders/
├── producer/                 # Generates orders → Kafka
├── consumers/
│   ├── fraud-service/        # Detects suspicious orders
│   ├── payment-service/      # Simulates payments
│   └── analytics-service/    # Saves to Couchbase
├── web/
│   ├── backend/              # FastAPI → Couchbase
│   └── frontend/             # React dashboard
├── infra/
│   ├── terraform-ecs/        # AWS ECS deployment
│   └── terraform-eks/        # AWS EKS deployment
├── k8s/charts/webapp/        # Helm chart
└── docs/                     # Documentation
```

---

## Quick Start (Local)

```bash
docker-compose up -d
```

Access:
- Kafdrop: http://localhost:9000
- Couchbase: http://localhost:8091

---

## Deploy to AWS ECS

```bash
cd infra/terraform-ecs

# Set secrets
cp secrets.tfvars.example secrets.tfvars
# Edit secrets.tfvars with your values

# Deploy
terraform init
terraform apply -var-file="secrets.tfvars"
```

---

## Environment Variables

| Variable | Source | Used By |
|----------|--------|---------|
| KAFKA_BOOTSTRAP_SERVERS | Secrets Manager | Producer, Consumers |
| CONFLUENT_API_KEY | Secrets Manager | Producer, Consumers |
| CONFLUENT_API_SECRET | Secrets Manager | Producer, Consumers |
| COUCHBASE_HOST | Secrets Manager | Analytics, Backend |
| COUCHBASE_USERNAME | Secrets Manager | Analytics, Backend |
| COUCHBASE_PASSWORD | Secrets Manager | Analytics, Backend |

---

## Key Code

### Producer sends to Kafka
```python
producer.send("orders", value={"order_id": 1, "amount": 249.99})
```

### Consumer receives from Kafka
```python
for msg in consumer:
    order = msg.value
    # process order
```

### Analytics saves to Couchbase
```python
collection.upsert(doc_id, order)
```

### Backend queries Couchbase
```python
result = cluster.query("SELECT * FROM order_analytics LIMIT 10")
```

### Frontend fetches from Backend
```javascript
fetch('/api/analytics').then(res => res.json())
```

---

## Documentation

| File | Description |
|------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design & connections |
| [CODE-WALKTHROUGH.md](docs/CODE-WALKTHROUGH.md) | Line-by-line code explanation |
| [SECRETS-SETUP.md](docs/SECRETS-SETUP.md) | How to configure secrets |
| [ECS-DEPLOYMENT-FIXES.md](docs/ECS-DEPLOYMENT-FIXES.md) | ECS troubleshooting |
| [EKS-DEPLOYMENT-FIXES.md](docs/EKS-DEPLOYMENT-FIXES.md) | Kubernetes troubleshooting |
| [SSL-HTTPS-SETUP.md](docs/SSL-HTTPS-SETUP.md) | HTTPS configuration |

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Streaming | Confluent Cloud (Kafka) |
| Database | Couchbase Capella |
| Backend | Python + FastAPI |
| Frontend | React |
| Infrastructure | AWS ECS/EKS |
| IaC | Terraform |
