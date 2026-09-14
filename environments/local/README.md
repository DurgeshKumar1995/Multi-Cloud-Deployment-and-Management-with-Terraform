# Local Terraform and Floci

This root deliberately has no HCP Terraform `cloud` block. It uses local state and
points the standard AWS provider at Floci on `localhost:14566` (container port `4566`).

From the repository root:

```bash
docker compose -f local/docker-compose.yml up -d --build
terraform -chdir=environments/local init
terraform -chdir=environments/local apply
curl http://localhost:8080/health
```

Local endpoints:

| Service | URL |
| --- | --- |
| Demo gateway | http://localhost:8080 |
| AWS app | http://localhost:8081 |
| Azure app | http://localhost:8082 |
| GCP app | http://localhost:8083 |
| Floci AWS | http://localhost:14566 |
| Floci Azure | http://localhost:4577 |
| Floci GCP | http://localhost:4588 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 |

Grafana's local-only login is `admin` / `local-only-change-me`. Do not reuse this
password outside the local Docker environment.

Destroy the Terraform resources before stopping Floci:

```bash
terraform -chdir=environments/local destroy
docker compose -f local/docker-compose.yml down
```
