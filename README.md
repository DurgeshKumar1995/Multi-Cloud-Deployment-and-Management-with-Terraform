# Multi-Cloud Deployment and Management with Terraform

This repository implements the project brief as a safe, staged reference deployment across AWS, Azure, and Google Cloud. It includes a small containerized health service, cloud-specific infrastructure modules, Route 53 health-checked DNS failover, monitoring, storage, optional MongoDB application integration, optional managed PostgreSQL infrastructure, HCP Terraform remote runs, and a no-cloud local environment using Docker and Floci.

## Safety first

All real-cloud switches default to `false`. A normal plan creates **no paid cloud resources** until you deliberately enable a provider. Managed databases are a separate opt-in because they are among the most expensive resources in this demonstration.

Never commit access keys, client secrets, service-account keys, or HCP Terraform tokens. This project uses HCP Terraform OIDC dynamic credentials instead.

## Architecture

```text
app.multicloud.example.com (Route 53 weighted records + HTTP health checks)
             |                    |                    |
          AWS ALB             Azure LB             GCP HTTP LB
             |                    |                    |
        2 EC2 instances       2 Linux VMs        regional MIG (2 VMs)
             |                    |                    |
       S3 / optional RDS   Blob / optional PG   GCS / optional Cloud SQL
```

The demo application listens on port `8080`; `/health` is the load-balancer and DNS health endpoint; `/metrics` is scraped by the local Prometheus stack.

## Repository layout

- `app/` – dependency-free Python demo service and tests
- `Dockerfile` – production-style non-root image
- `local/` – Docker Compose, Floci emulators, Nginx failover, Prometheus, Grafana
- `environments/local/` – Terraform smoke test against local Floci S3
- `environments/cloud/` – HCP Terraform root configuration
- `environments/cloud/modules/` – AWS, Azure, and GCP modules
- `docs/` – setup, permissions, operations, failover, cost, and troubleshooting

## Quick local run

Docker Desktop must be running.

```bash
make deps
make local-up
curl http://localhost:8080/health
open http://localhost:3000
```

Local endpoints:

| Service | URL |
|---|---|
| Nginx failover gateway | `http://localhost:8080` |
| AWS-labelled app | `http://localhost:8081` |
| Azure-labelled app | `http://localhost:8082` |
| GCP-labelled app | `http://localhost:8083` |
| Local MongoDB | `mongodb://localhost:27017` (authenticated; use through the app) |
| Prometheus | `http://localhost:9090` |
| Grafana | `http://localhost:3000` (`admin` / `local-only-change-me`) |
| Floci AWS | `http://localhost:14566` (container port `4566`) |
| Floci Azure | `http://localhost:4577` |
| Floci GCP | `http://localhost:4588` |

Run the local Terraform smoke test after the Floci AWS endpoint is listening:

```bash
make local-terraform
```

Verify MongoDB and write/read test data:

```bash
curl -fsS http://localhost:8081/db/health
curl -fsS -H 'Content-Type: application/json' -d '{"message":"test"}' http://localhost:8081/db/items
curl -fsS http://localhost:8082/db/items
```

For Atlas setup and secure credential handling, follow the [MongoDB test guide](docs/MONGODB_SETUP.md).

## Real-cloud deployment

1. Complete the [end-to-end GitHub, HCP Terraform, and AWS guide](docs/COMPLETE_AWS_SETUP_GUIDE.md), or use the shorter [cloud account setup](docs/SETUP.md).
2. Publish the container image with the GitHub Actions workflow.
3. Add an Azure SSH public key as an HCP Terraform variable.
4. Enable one cloud at a time and review each plan.
5. Enable DNS after at least one provider endpoint returns HTTP 200; two or more providers enable failover.
6. Enable databases only if the project demonstration truly requires them.

Follow the complete [run and verification guide](docs/RUN_AND_VERIFY.md). Also see [MongoDB setup](docs/MONGODB_SETUP.md), [architecture](docs/ARCHITECTURE.md), [failover testing](docs/FAILOVER_TEST.md), and [troubleshooting](docs/TROUBLESHOOTING.md).

## Common commands

```bash
make test
make fmt
make compose-check
make local-up
make local-down
```

`terraform apply` for real clouds is intentionally not wrapped in the Makefile. Run it through the configured HCP Terraform workspace after reviewing the speculative and confirmed plans.
