# Quick Demo Commands

## Local Testing (Docker)
```powershell
cd D:\AJ\kafka-enterprise-orders

# Start all services
docker-compose up -d --build

# Check logs
docker-compose logs -f producer
docker-compose logs -f analytics-service

# Open browser
# Frontend: http://localhost:3000
# Kafdrop:  http://localhost:9000
# Backend:  http://localhost:8000/api/analytics

# Stop
docker-compose down
```

**Note:** Local Couchbase needs manual bucket setup:
1. Open http://localhost:8091
2. Login: Administrator / password
3. Create bucket: `order_analytics`

---

## EKS Deploy
```powershell
cd D:\AJ\kafka-enterprise-orders\infra\terraform-eks
terraform init
terraform apply -var="ghcr_pat=YOUR_GHCR_TOKEN" -var="couchbase_password=AppPass123!" -var="certificate_arn=arn:aws:acm:us-east-2:343218219153:certificate/00353776-9755-4283-98f8-e05c1e337b28"
```

## EKS Verify
```powershell
aws eks update-kubeconfig --name keo-eks --region us-east-2
kubectl get nodes
kubectl get pods
kubectl get pods -n argocd
kubectl get ingress
```

## EKS Cleanup
```powershell
cd D:\AJ\kafka-enterprise-orders\infra\terraform-eks
terraform destroy -var="ghcr_pat=x" -var="couchbase_password=x"
```

---

## ECS Deploy
```powershell
cd D:\AJ\kafka-enterprise-orders\infra\terraform-ecs
terraform init
terraform apply -var-file="values.auto.tfvars" -var="ghcr_pat=YOUR_GHCR_TOKEN" -var="confluent_api_key=LUTQDYGP3XTVJE5V" -var="confluent_api_secret=YOUR_CONFLUENT_SECRET" -var="couchbase_password=AppPass123!"
```

## ECS Verify (AWS Console)
- ECS → Clusters → kafka-enterprise-orders-cluster
- Check running tasks count
- CloudWatch → Log groups → /ecs/kafka-enterprise-orders-*

## ECS Cleanup
```powershell
cd D:\AJ\kafka-enterprise-orders\infra\terraform-ecs
terraform destroy -var-file="values.auto.tfvars" -var="ghcr_pat=x" -var="confluent_api_key=x" -var="confluent_api_secret=x" -var="couchbase_password=x"
```

---

## Test URLs

### EKS (after deploy)
```powershell
curl https://orders.jumptotech.net/healthz
curl https://orders.jumptotech.net/api/analytics
```

### ECS (get ALB URL from terraform output)
```powershell
terraform output
curl http://ALB_URL/healthz
curl http://ALB_URL/api/analytics
```

---

## Couchbase Query (Capella UI)
```sql
SELECT * FROM order_analytics LIMIT 10;
SELECT COUNT(*) FROM order_analytics;
```

## ArgoCD Access
```powershell
# Get password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
# Decode: use base64 decoder or PowerShell
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("PASTE_HERE"))

# Get ArgoCD URL
kubectl get svc -n argocd argocd-server
```

---

## Your Values Reference
| Key | Value |
|-----|-------|
| GHCR Username | aisalkyn85 |
| Couchbase Host | cb.2s2wqp2fpzi0hanx.cloud.couchbase.com |
| Couchbase User | appuser |
| Couchbase Pass | AppPass123! |
| Confluent Bootstrap | pkc-921jm.us-east-2.aws.confluent.cloud:9092 |
| Confluent API Key | LUTQDYGP3XTVJE5V |
| Domain | orders.jumptotech.net |
| ACM Cert ARN | arn:aws:acm:us-east-2:343218219153:certificate/00353776-9755-4283-98f8-e05c1e337b28 |
