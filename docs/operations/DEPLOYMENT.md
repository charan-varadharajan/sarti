# Deployment and rollback

**STATUS: DRAFT — Stage 4 required deliverable. All TODO sections must be
completed before any production deployment. ADR-027 selects Google Cloud Run
and Neon Free for beta. Production hosting requires a separate approved ADR.**

---

## Prerequisites

- Google Cloud project with billing enabled and budget alert configured
- Cloud Run API, Secret Manager API, and Artifact Registry API enabled
- Neon project created; connection string stored in Secret Manager
- `gcloud` CLI authenticated with deployment service account
- Docker installed locally for image builds
- `VERSION` and `BUILD_NUMBER` files at repo root are the canonical version

---

## Environment variables and secrets

All secrets are injected at runtime via Google Cloud Secret Manager.
**Never commit secrets, credentials, or `.env` files.**

| Secret name (Secret Manager) | Maps to env var | Description |
|---|---|---|
| `sarti-database-url` | `SARTI_DATABASE_URL` | Neon PostgreSQL connection string |
| `sarti-webauthn-rp-id` | `SARTI_WEBAUTHN_RP_ID` | Production domain (e.g. `api.sarti.app`) |
| `sarti-webauthn-origin` | `SARTI_WEBAUTHN_ORIGIN` | Production origin (e.g. `https://api.sarti.app`) |
| `sarti-email-worker-secret` | `SARTI_EMAIL_WORKER_SECRET` | Cloudflare Worker shared secret |
| `sarti-gemini-api-key` | `SARTI_GEMINI_API_KEY` | Optional Gemini API key |
| `sarti-fcm-credentials` | `SARTI_FCM_CREDENTIALS_FILE` | Path to mounted FCM service account JSON |

TODO — add any additional secrets identified during production hardening.

---

## Build and push

```sh
# Confirm version is correct
python3 scripts/version.py check

# Build image (from repo root)
docker build -t REGION-docker.pkg.dev/PROJECT/sarti/backend:$(cat VERSION) \
  backend/

# Push to Artifact Registry
docker push REGION-docker.pkg.dev/PROJECT/sarti/backend:$(cat VERSION)
```

Replace `REGION` and `PROJECT` with your GCP values.
TODO — add Artifact Registry repository name and region.

---

## Database migration (run before deploying new code)

Migrations must run and complete successfully before new application code
receives traffic. Run as a one-off Cloud Run job:

```sh
gcloud run jobs create sarti-migrate-$(cat VERSION | tr '.' '-') \
  --image REGION-docker.pkg.dev/PROJECT/sarti/backend:$(cat VERSION) \
  --command "alembic" \
  --args "upgrade,head" \
  --set-secrets SARTI_DATABASE_URL=sarti-database-url:latest \
  --region REGION \
  --project PROJECT

gcloud run jobs execute sarti-migrate-$(cat VERSION | tr '.' '-') \
  --region REGION --project PROJECT --wait
```

Confirm the job completed successfully before proceeding. If migration fails,
do not deploy the new image — see Rollback below.

---

## Deploy

```sh
gcloud run deploy sarti-backend \
  --image REGION-docker.pkg.dev/PROJECT/sarti/backend:$(cat VERSION) \
  --region REGION \
  --project PROJECT \
  --platform managed \
  --no-allow-unauthenticated \
  --min-instances 0 \
  --max-instances TODO \
  --set-secrets \
    SARTI_DATABASE_URL=sarti-database-url:latest,\
    SARTI_WEBAUTHN_RP_ID=sarti-webauthn-rp-id:latest,\
    SARTI_WEBAUTHN_ORIGIN=sarti-webauthn-origin:latest,\
    SARTI_EMAIL_WORKER_SECRET=sarti-email-worker-secret:latest,\
    SARTI_GEMINI_API_KEY=sarti-gemini-api-key:latest
```

TODO — confirm `--no-allow-unauthenticated` vs IAP vs custom auth approach.
TODO — set `--max-instances` based on cost review.

---

## Smoke test after deploy

```sh
curl --fail https://TODO_CLOUD_RUN_URL/v1/health/live
curl --fail https://TODO_CLOUD_RUN_URL/v1/health/ready
```

Both must return `{"status":"ok"}` / `{"status":"ok"}` before declaring
the deployment successful.

---

## Rollback

### Application rollback (no schema change)

```sh
# Redeploy the previous image tag
gcloud run deploy sarti-backend \
  --image REGION-docker.pkg.dev/PROJECT/sarti/backend:PREVIOUS_VERSION \
  --region REGION \
  --project PROJECT
```

### Migration rollback

Alembic downgrade is available but must be tested before use in production.
Each migration's `downgrade()` function must be reviewed for data safety before
executing:

```sh
# Run as a one-off Cloud Run job — replace TARGET_REVISION with the target
gcloud run jobs create sarti-downgrade-$(date +%s) \
  --image REGION-docker.pkg.dev/PROJECT/sarti/backend:PREVIOUS_VERSION \
  --command "alembic" \
  --args "downgrade,TARGET_REVISION" \
  --set-secrets SARTI_DATABASE_URL=sarti-database-url:latest \
  --region REGION --project PROJECT

gcloud run jobs execute sarti-downgrade-$(date +%s) \
  --region REGION --project PROJECT --wait
```

**Warning:** Downgrading a migration that drops columns or tables is
destructive. Take a Neon database branch/snapshot before any downgrade.

---

## Neon database backup and restore

TODO — document Neon branch/snapshot procedure before admitting real user data.
The free tier is not treated as a backup (ADR-027). Export and restore testing
is required before real family data is admitted.

```sh
# Create a Neon branch snapshot before any destructive operation
# TODO — add neonctl commands or Neon console steps
```

---

## Monitoring and alerts

TODO — implement per ADR-016 (privacy-preserving monitoring).

Minimum required before production:
- [ ] Billing budget alert configured in GCP
- [ ] Cloud Run error rate alert (5xx > threshold)
- [ ] Cloud Run latency alert (p99 > threshold)
- [ ] Neon connection pool exhaustion alert
- [ ] Secret Manager access audit log enabled
- [ ] No family content, credentials, or keys in any log

---

## Incident response (stub)

TODO — complete before production launch.

1. Identify: alert fires or user report received
2. Assess: check Cloud Run logs (operational fields only — no family content)
3. Contain: if data breach suspected, immediately revoke affected secrets in
   Secret Manager and redeploy
4. Communicate: TODO — define user notification SLA and channel
5. Remediate: fix, test, deploy via standard process
6. Post-mortem: document in `docs/engineering/BUGS.md` as a resolved defect
   with full timeline

---

## Stage 4 completion checklist for this file

- [ ] All TODO items above completed
- [ ] GCP project, region, Artifact Registry repo confirmed
- [ ] Max instances and cost review completed
- [ ] Neon backup/restore procedure tested with real schema
- [ ] Smoke test URLs confirmed
- [ ] Monitoring and alerts configured
- [ ] Incident response procedure reviewed by product owner
- [ ] Rollback tested in a staging environment
- [ ] Product owner sign-off obtained before first production deploy
