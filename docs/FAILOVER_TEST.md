# Failover test plan

## Local demonstration

Start the stack with `make local-up`, then call the gateway several times:

```bash
for i in 1 2 3 4 5 6; do curl -s http://localhost:8080/health; echo; done
```

Stop the first application and repeat the calls:

```bash
docker compose -f local/docker-compose.yml stop app-aws
curl -s http://localhost:8080/health
```

Nginx should route to an Azure- or GCP-labelled container. Restore it with:

```bash
docker compose -f local/docker-compose.yml start app-aws
```

## Cloud DNS demonstration

1. Confirm each provider-specific `/health` URL returns HTTP 200.
2. Query `app.multicloud.durgesh.space` repeatedly and record returned addresses.
3. Stop application instances in one provider without destroying its DNS record.
4. Wait for three failed Route 53 health checks plus DNS cache expiry.
5. Confirm new DNS answers and requests use healthy providers.
6. Restore the provider and record recovery time.

Capture timestamps, `dig` output, Route 53 health-check status, and HTTP responses in the project report. Do not test by deleting production data.
