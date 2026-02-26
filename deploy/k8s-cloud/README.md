# Cloud Kubernetes Deployment (Alibaba Cloud ACK)

> Auto-scaling multi-tenant deployment on Alibaba Cloud ACK (Kubernetes).

## Architecture on Cloud

```
[iOS/Android App]  [Telegram Bot]  [Web API]
         ↓               ↓              ↓
    [API Gateway — ACK Ingress + Kong/Nginx]
                    ↓
         [apps/api_gateway pods] (HPA: 2-20)
                    ↓
    [apps/worker_orchestrator pods] (HPA: 2-50)
                    ↓
    ┌──────────────────────────────────────┐
    │  Managed Services (Alibaba Cloud)    │
    │  ApsaraDB PostgreSQL (HA)            │
    │  Qdrant cluster (3 nodes)            │
    │  Redis (ApsaraCache)                 │
    │  OSS (Object Storage Service)        │
    │  ACR (Container Registry)            │
    └──────────────────────────────────────┘
```

## Files (to implement)

```
deploy/k8s-cloud/
  helm/
    openpaw/             # Main Helm chart
      Chart.yaml
      values.yaml        # Default values
      values-prod.yaml   # Production overrides
      templates/
        api-gateway.yaml
        worker.yaml
        telegram-bot.yaml
        configmap.yaml
        secrets.yaml     # Uses sealed-secrets or Aliyun KMS
        hpa.yaml
  terraform/
    main.tf              # ACK cluster + RDS + Redis + OSS provisioning
    variables.tf
```

## Key Cloud Decisions

- **HPA** on CPU/memory for api_gateway and worker pods
- **Separate node pool** for video generation workers (higher CPU)
- **Qdrant cluster** with 3 replicas for HA
- **Postgres** via ApsaraDB (managed, HA, automated backup)
- **Secrets** via Aliyun KMS + sealed-secrets operator
- **Ingress** via ALB (Application Load Balancer) with SSL termination
