# Run and Verification Guide

This runbook verifies the project in three stages:

1. Local application, failover, monitoring, and Floci Terraform test.
2. HCP Terraform remote execution with every paid resource disabled.
3. One-at-a-time AWS, Azure, and GCP deployments, followed by DNS failover.

Do not skip directly to all-cloud deployment. Load balancers, public IP addresses, virtual machines, health checks, disks, logs, and managed databases can incur charges.

## 1. Local prerequisites

Required:

- Docker Desktop is running.
- Terraform 1.16.x is installed.
- Ports `3000`, `4577`, `4588`, `8080`-`8083`, `9090`, and `14566` are available.

From Terminal:

```bash
cd /Users/durgesh.kumar/Documents/terraform_2/multicloud-project
terraform version
docker info
git status
```

Expected Terraform version: `1.16.x`. `git status` should not show secrets or unexpected files.

## 2. Validate code locally

Run the application tests, Terraform formatter, and Compose parser:

```bash
make test
terraform fmt -check -recursive
make compose-check
terraform -chdir=environments/local validate
terraform -chdir=environments/cloud validate
```

Expected results:

- Three application tests pass.
- Terraform formatting produces no error.
- Docker Compose validation produces no error.
- Both Terraform validations report `Success! The configuration is valid.`

Provider validation may require `terraform init` first:

```bash
terraform -chdir=environments/local init
terraform -chdir=environments/cloud init -backend=false
```

The cloud initialization command downloads provider schemas only. Do not run a cloud `apply` from this directory when the workspace is VCS-connected.

## 3. Start the local environment

```bash
make local-up
docker compose -f local/docker-compose.yml ps
```

Wait until the three application and three Floci containers show `healthy`. The gateway, Prometheus, and Grafana should show `Up`.

Local services:

| Component | Address |
|---|---|
| Failover gateway | `http://localhost:8080` |
| AWS-labelled application | `http://localhost:8081` |
| Azure-labelled application | `http://localhost:8082` |
| GCP-labelled application | `http://localhost:8083` |
| Grafana | `http://localhost:3000` |
| Prometheus | `http://localhost:9090` |
| Floci AWS | `http://localhost:14566` |
| Floci Azure | `http://localhost:4577` |
| Floci GCP | `http://localhost:4588` |

## 4. Verify local application endpoints

```bash
curl -fsS http://localhost:8080/health
curl -fsS http://localhost:8081/health
curl -fsS http://localhost:8082/health
curl -fsS http://localhost:8083/health
curl -fsS http://localhost:8080/ready
curl -fsS http://localhost:8080/metrics
```

Expected:

- Every command succeeds with HTTP 200.
- `/health` and `/ready` contain `"status": "healthy"`.
- The three direct endpoints identify `aws`, `azure`, and `gcp` respectively.
- `/metrics` contains `multicloud_demo_requests_total`.

## 5. Verify local Terraform against Floci

This creates only an emulated S3 bucket and object inside the local Floci container:

```bash
make local-terraform
terraform -chdir=environments/local output
```

Expected outputs:

```text
bucket_name = "multicloud-local-demo"
floci_endpoint = "http://localhost:14566"
```

If the AWS CLI is installed, verify the emulated object:

```bash
AWS_ACCESS_KEY_ID=test \
AWS_SECRET_ACCESS_KEY=test \
AWS_DEFAULT_REGION=ap-south-1 \
aws --endpoint-url=http://localhost:14566 \
  s3api head-object \
  --bucket multicloud-local-demo \
  --key health/status.json
```

The `test` values are local placeholders and must never be used with real AWS endpoints.

## 6. Verify Prometheus and Grafana

Check Prometheus readiness and scrape targets:

```bash
curl -fsS http://localhost:9090/-/ready
curl -fsS 'http://localhost:9090/api/v1/query?query=up'
```

The query response should show the three application targets with a value of `1`.

Open `http://localhost:3000` and sign in with:

```text
Username: admin
Password: local-only-change-me
```

Open **Dashboards → Multi-cloud Overview** and confirm all three providers are visible. This password is deliberately local-only.

## 7. Test local failover

Stop the AWS-labelled application:

```bash
docker compose -f local/docker-compose.yml stop app-aws
curl -fsS http://localhost:8080/health
```

Expected: the response still returns HTTP 200 and identifies either `azure` or `gcp`.

Restore AWS:

```bash
docker compose -f local/docker-compose.yml start app-aws
docker compose -f local/docker-compose.yml ps
```

Do not leave the application stopped before continuing.

## 8. Prepare the remote workflow

Confirm the current code is on GitHub:

```bash
git status
git log -1 --oneline
git remote -v
git push origin main
```

Then run GitHub **Actions → Publish container image → Run workflow**. After it succeeds, make the `multicloud-demo` GHCR package public and verify it can be pulled anonymously:

```bash
docker pull ghcr.io/durgeshkumar1995/multicloud-demo:v1.0.0
```

In the HCP Terraform workspace, verify:

```text
Execution mode:              Remote
Terraform version:           ~> 1.16.0
Terraform working directory: environments/cloud
Auto-apply API, UI, VCS:     Off
VCS branch:                  main
```

Verify every OIDC environment variable listed in [SETUP.md](SETUP.md). Do not add static AWS keys, an Azure client secret, a GCP service-account JSON key, or an HCP token to the workspace.

## 9. Run the zero-resource remote test

Under **Workspace → Variables → Terraform variables**, either leave the five variables absent (their code defaults are false) or set:

```text
enable_aws       = false
enable_azure     = false
enable_gcp       = false
enable_dns       = false
enable_databases = false
```

In HCP Terraform select **New run → Plan and apply → Start run**.

Expected:

- The configuration downloads successfully from GitHub.
- Terraform initializes the AWS, Azure, GCP, and Random providers.
- Authentication errors do not appear.
- The plan proposes zero infrastructure resources. It may add the `deployment_safety` output to the initial state.
- HCP waits for operator approval because auto-apply is off.

An empty plan does not need a meaningful apply. If HCP offers an automatic empty apply, it is safe because the plan contains no resources.

## 10. Deploy and verify AWS first

Change only this Terraform variable:

```text
enable_aws = true
```

Keep Azure, GCP, DNS, and databases false. Start a new HCP run.

Before confirming, review the plan and verify that it contains AWS resources only: VPC, two subnets, routing, security groups, two EC2 instances, an Application Load Balancer, S3, SNS, and CloudWatch. It must not contain Azure, GCP, DNS, or database resources.

Click **Confirm & Apply**. After the apply succeeds, obtain `aws_endpoint` from the run outputs or workspace state outputs and test:

```bash
curl -fsS http://AWS_ENDPOINT/health
```

Expected: HTTP 200 with `"cloud": "aws"` and region `ap-south-1`.

If the target stays unhealthy, verify that the configured AMI is Ubuntu-compatible and that the GHCR image is public.

## 11. Deploy and verify Azure

Before enabling Azure, add `azure_ssh_public_key` as a Terraform variable. A public key exists locally at `/Users/durgesh.kumar/.ssh/id_rsa.pub`; copy it with:

```bash
pbcopy < /Users/durgesh.kumar/.ssh/id_rsa.pub
```

Never copy the private file named `id_rsa`.

Set:

```text
enable_aws   = true
enable_azure = true
enable_gcp   = false
enable_dns   = false
```

Start a new run. Confirm that the additional resources are Azure VNet, subnet, network security group, two Linux VMs, Standard Load Balancer, public IP, storage, and monitoring. Review and apply.

Obtain `azure_endpoint` and test:

```bash
curl -fsS http://AZURE_ENDPOINT/health
```

Expected: HTTP 200 with `"cloud": "azure"` and region `centralindia`.

## 12. Deploy and verify GCP

Set:

```text
enable_aws   = true
enable_azure = true
enable_gcp   = true
enable_dns   = false
```

Start a new run. Confirm that the additional resources are GCP APIs, VPC/subnet/firewall, instance template, regional managed instance group, HTTP load balancer, storage bucket, and monitoring. Review and apply.

Obtain `gcp_endpoint` and test:

```bash
curl -fsS http://GCP_ENDPOINT/health
```

Expected: HTTP 200 with `"cloud": "gcp"` and region `asia-south1`.

## 13. Enable and verify public DNS

Enable DNS after at least one provider `/health` endpoint returns HTTP 200 and the Namecheap `multicloud` NS delegation points to the Route 53 name servers. One enabled provider publishes a working application hostname; two or more healthy providers enable DNS failover.

Set:

```text
enable_dns = true
```

Keep `enable_databases=false`. Review the plan for Route 53 provider records, health checks, and weighted application records, then apply.

Verify delegation and the application:

```bash
dig +short NS multicloud.durgesh.space
dig @ONE_OF_THE_ROUTE53_NAME_SERVERS multicloud.durgesh.space SOA +noall +answer
dig +short app.multicloud.durgesh.space
curl -fsS http://app.multicloud.durgesh.space/health
```

The SOA answer must be owned by `multicloud.durgesh.space.`. An SOA answer owned by `durgesh.space.` means the Namecheap child delegation points at the wrong Route 53 hosted zone.

Allow time for health-check evaluation and DNS caching. Repeated responses may identify different healthy clouds.

## 14. Test remote DNS failover

Use a demonstration environment only.

1. Record the current provider endpoints and Route 53 health statuses.
2. Stop both application instances in one provider using that provider's console. Do not delete them.
3. Wait for Route 53 to mark the provider health check unhealthy and for the 60-second record TTL plus resolver caching.
4. Repeatedly call `http://app.multicloud.durgesh.space/health`.
5. Confirm responses come only from healthy providers.
6. Restart the stopped instances and wait for their load-balancer targets and Route 53 health check to recover.

Capture timestamps, health-check screenshots, `dig` results, and application responses for the project report.

## 15. Optional database verification

Databases are not used by the current stateless demo application. Leave this disabled unless database provisioning evidence is required:

```text
enable_databases = false
```

Enabling it creates billable managed PostgreSQL services. Before doing so, add `database_admin_password` as a sensitive Terraform variable with at least 16 characters and grant the documented database permissions.

## 16. Stop or destroy resources

Stop the local environment:

```bash
terraform -chdir=environments/local destroy -auto-approve
make local-down
```

For real clouds, do not delete resources manually. In HCP Terraform use **Settings → Destruction and Deletion → Queue destroy plan**, review every proposed deletion, and confirm only when backups and evidence are safe.

After destruction, check all three cloud consoles for retained disks, public IPs, load balancers, databases, snapshots, log storage, and Route 53 health checks that may continue to incur charges.

## Success checklist

- [ ] Unit tests, formatting, Compose validation, and Terraform validation pass.
- [ ] All local containers are healthy or running.
- [ ] Local `/health`, `/ready`, and `/metrics` endpoints work.
- [ ] Local Floci Terraform creates and reports the emulated S3 bucket.
- [ ] Prometheus sees all three application targets.
- [ ] Local gateway survives stopping one application container.
- [ ] GitHub image workflow succeeds and the image is publicly pullable.
- [ ] HCP zero-resource plan proposes no cloud resources.
- [ ] AWS, Azure, and GCP are each deployed and verified separately.
- [ ] DNS is enabled only after provider health checks pass.
- [ ] Remote failover is demonstrated and the stopped provider is restored.
- [ ] Unneeded cloud resources are destroyed after the demonstration.
