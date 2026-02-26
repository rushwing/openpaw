# Local Raspberry Pi Deployment

> Single-machine Docker Compose deployment for private local assistant.
> Privacy-first: all data stays on device. No cloud billing.

## Architecture on Pi

```
┌─────────────────────────────────┐
│  Raspberry Pi (ARM64, 4-8GB RAM) │
│                                 │
│  [FastAPI app]    port 8000     │
│  [Telegram bot]   (outbound)    │
│  [Redis]          port 6379     │
│  [Qdrant Lite]    port 6333     │
│  [Postgres]       port 5432     │
│  [MinIO]          port 9000     │
└─────────────────────────────────┘
         ↕ HTTPS (optional)
    [Mobile App / Browser]
```

## Pi-specific Constraints

- `LOCAL_ONLY=true` in `.env` → PolicyEngine always routes to local executor
- LLM calls go to Claude API (outbound only) — no LLM models run locally
- Qdrant Lite (single-node, no cluster)
- No Kubernetes (Docker Compose only)
- No multi-tenant (tenant_id always `"local"`)
- Sync to cloud is opt-in and metadata-only by default

## Files (to implement)

```
deploy/local-pi/
  docker-compose.yml     # All services
  .env.example           # Environment template
  config/
    postgres-init.sql    # DB schema init
    qdrant-config.yaml   # Qdrant settings
  scripts/
    setup.sh             # One-command Pi setup
    backup.sh            # Local backup to USB/cloud
```

## Minimum Pi Hardware

- Raspberry Pi 4 or 5 (4GB RAM minimum, 8GB recommended)
- 64GB microSD or USB SSD
- Ethernet recommended for reliability
