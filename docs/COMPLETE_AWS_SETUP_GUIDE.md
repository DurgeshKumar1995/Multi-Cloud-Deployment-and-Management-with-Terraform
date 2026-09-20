# Complete GitHub, HCP Terraform, and AWS setup guide

This guide builds and operates the working AWS portion of the multi-cloud project. It explains what to configure, where to configure it, and why each step exists.

## 1. Result and current identifiers

The deployed path is:

```text
GitHub source and GHCR image
              |
        HCP Terraform
              |
     short-lived AWS OIDC role
              |
Route 53 -> AWS ALB -> two EC2 instances -> container port 8080
              |
       S3, CloudWatch, and SNS
```

Current non-secret identifiers:

| Item | Value |
|---|---|
| GitHub repository | `DurgeshKumar1995/Multi-Cloud-Deployment-and-Management-with-Terraform` |
| HCP organization | `Multi-Cloud-Deployment-and-Management` |
| HCP project | `Multi-Cloud Deployment-Management` |
| HCP workspace | `Multi-Cloud-Deployment_Management_Terraform` |
| AWS account | `075472845204` |
| AWS region | `ap-south-1` |
| AWS role | `hcp-terraform-multicloud` |
| Route 53 child zone | `multicloud.durgesh.space` |
| Route 53 hosted-zone ID | `Z03408713FBQPRLGXVTO6` |
| Application hostname | `app.multicloud.durgesh.space` |

Why: recording identifiers prevents configuring a similarly named role, workspace, or hosted zone by mistake.

## 2. Security prerequisite

Revoke and replace any AWS access key or HCP Terraform token that was pasted into a message, terminal history, issue, or file. Never add these to GitHub or HCP workspace variables:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
TF_TOKEN_app_terraform_io
```

This deployment uses HCP Terraform workload identity federation. HCP receives short-lived AWS credentials for each run, so no permanent AWS key is required.

Why: a leaked long-lived key continues working until it is explicitly revoked; an OIDC run credential expires automatically and is restricted to one workspace.

## 3. Install and verify local tools

Install Git, Docker Desktop, Terraform 1.16.x, and optionally the AWS CLI. Then run:

```bash
cd /Users/durgesh.kumar/Documents/terraform_2/multicloud-project
git --version
docker version
terraform version
aws --version
```

Why: Git publishes code, Docker builds/tests the application, Terraform validates configuration, and the AWS CLI is useful for read-only diagnosis.

## 4. Create or connect the GitHub repository

Create the GitHub repository, then connect and push this working tree:

```bash
cd /Users/durgesh.kumar/Documents/terraform_2/multicloud-project
git remote -v
git branch --show-current
git push origin main
```

The expected remote is:

```text
https://github.com/DurgeshKumar1995/Multi-Cloud-Deployment-and-Management-with-Terraform.git
```

Why: HCP Terraform downloads the exact committed revision from GitHub. Uncommitted local changes are not included in a VCS-triggered run.

### GitHub validation workflow

`.github/workflows/validate.yml` runs on pushes to `main` and pull requests. It:

1. Runs the Python application tests.
2. Checks Terraform formatting.
3. validates Docker Compose.
4. Builds the container image.

Why: invalid code should fail in GitHub before HCP Terraform attempts an infrastructure plan.

### Publish the container image

In GitHub, open **Actions -> Publish container image -> Run workflow**. The workflow uses the repository-provided `GITHUB_TOKEN`; no personal access token is required.

After it succeeds, open the package settings and make `multicloud-demo` public. Verify anonymous access:

```bash
docker pull ghcr.io/durgeshkumar1995/multicloud-demo:v1.0.0
```

Why: EC2 cloud-init pulls this image without a GitHub login. A private package would leave the ALB targets unhealthy.

## 5. Create the HCP Terraform workspace

In HCP Terraform:

1. Create/select organization `Multi-Cloud-Deployment-and-Management`.
2. Create/select project `Multi-Cloud Deployment-Management`.
3. Create workspace `Multi-Cloud-Deployment_Management_Terraform`.
4. Choose **Version control workflow** and connect the GitHub repository.
5. Track branch `main`.
6. Open **Settings -> General** and configure:

```text
Execution mode:       Remote
Working directory:    environments/cloud
Terraform version:    ~> 1.16.0
Auto-apply:           Off
```

Why: the working directory contains the cloud root module; remote mode protects state in HCP; manual apply makes every billable change require review.

The Terraform `cloud` block is already present in `environments/cloud/versions.tf`. Do not add a second backend block.

## 6. Create the AWS OIDC identity provider

In AWS Console, open **IAM -> Identity providers -> Add provider**:

```text
Provider type: OpenID Connect
Provider URL:  https://app.terraform.io
Audience:      aws.workload.identity
```

Allow AWS to obtain the current certificate thumbprint when the console supports automatic retrieval.

Why: this registers HCP Terraform as a trusted token issuer. The audience prevents a token intended for another service from being accepted by AWS.

## 7. Create the AWS deployment role

Open **IAM -> Roles -> Create role**:

1. Select **Web identity**.
2. Select provider `app.terraform.io`.
3. Select audience `aws.workload.identity`.
4. Name the role `hcp-terraform-multicloud`.

After creation, open **Trust relationships -> Edit trust policy** and use [`aws-trust-policy.json`](aws-trust-policy.json).

The important restriction is:

```text
organization:Multi-Cloud-Deployment-and-Management:
project:Multi-Cloud Deployment-Management:
workspace:Multi-Cloud-Deployment_Management_Terraform:
run_phase:*
```

Why: `run_phase:*` permits both plan and apply, while the organization/project/workspace fields prevent another HCP workspace from assuming the role.

## 8. Add AWS deployment permissions

Open **IAM -> Policies -> Create policy -> JSON** and paste [`aws-deployment-policy.json`](aws-deployment-policy.json). Name it:

```text
hcp-terraform-multicloud-deployment-policy
```

Attach it to role `hcp-terraform-multicloud`.

The policy covers:

| Service | Purpose |
|---|---|
| EC2/VPC | VPC, subnets, routes, security groups, and two instances |
| Elastic Load Balancing | ALB, listener, target group, and registrations |
| S3 | Private versioned backup bucket |
| CloudWatch/SNS | Health alarm and notifications |
| Route 53 | Provider/application records and HTTP health check |
| RDS/Secrets Manager | Optional database path only |
| IAM service-linked roles | Allows AWS services to create their required service roles |

The policy is intentionally broad enough for a sandbox demonstration. Production deployments should split services and scope resources/tags more narrowly.

Why: the trust policy controls who can assume the role; this separate permissions policy controls what an assumed role can create.

If using a granular EC2 policy rather than the supplied policy, include `ec2:GetSecurityGroupsForVpc`. Current AWS provider versions call it while creating an ALB.

## 9. Configure AWS dynamic credentials in HCP

Under **Workspace -> Variables -> Environment variables**, add:

| Key | Value | Sensitive |
|---|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::075472845204:role/hcp-terraform-multicloud` | No |

Do not add static AWS keys.

Why: these variables tell the HCP dynamic credentials integration to exchange each run's OIDC token for the AWS role.

## 10. Create and delegate the Route 53 child zone

In **Route 53 -> Hosted zones -> Create hosted zone**:

```text
Domain name: multicloud.durgesh.space
Type:        Public hosted zone
```

Use the child zone ID `Z03408713FBQPRLGXVTO6` in Terraform. The four current child-zone nameservers are:

```text
ns-54.awsdns-06.com.
ns-1985.awsdns-56.co.uk.
ns-1027.awsdns-00.org.
ns-949.awsdns-54.net.
```

In **Namecheap -> Domain List -> durgesh.space -> Manage -> Advanced DNS**, add exactly four records:

| Type | Host | Value | TTL |
|---|---|---|---|
| NS Record | `multicloud` | `ns-54.awsdns-06.com` | Automatic |
| NS Record | `multicloud` | `ns-1985.awsdns-56.co.uk` | Automatic |
| NS Record | `multicloud` | `ns-1027.awsdns-00.org` | Automatic |
| NS Record | `multicloud` | `ns-949.awsdns-54.net` | Automatic |

Remove every old `multicloud` NS record. Do not change the registrar nameservers for the parent `durgesh.space` domain.

Why: Namecheap remains authoritative for the parent domain and delegates only the `multicloud` subtree to the matching Route 53 child zone.

Verify:

```bash
dig @dns1.registrar-servers.com multicloud.durgesh.space NS +noall +authority
dig @ns-54.awsdns-06.com multicloud.durgesh.space SOA +noall +answer
dig @8.8.8.8 +short NS multicloud.durgesh.space
```

The SOA owner must be `multicloud.durgesh.space.`, not `durgesh.space.`.

## 11. Configure HCP Terraform input variables

Under **Workspace -> Variables -> Terraform variables**, add these as non-sensitive, non-HCL values:

```text
enable_aws       = true
enable_dns       = true
enable_azure     = false
enable_gcp       = false
enable_databases = false

aws_region           = ap-south-1
domain_name          = multicloud.durgesh.space
application_hostname = app.multicloud.durgesh.space
hosted_zone_id       = Z03408713FBQPRLGXVTO6
```

Why: feature toggles prevent accidental all-cloud/database deployment. `hosted_zone_id` ensures records are written into the delegated child zone.

Variables such as `enable_aws` must be **Terraform variables**, not ordinary environment variables. Environment variables with that bare name are ignored by Terraform.

## 12. Validate before deploying

From the repository:

```bash
terraform fmt -check -recursive
terraform -chdir=environments/cloud init
terraform -chdir=environments/cloud validate
terraform -chdir=environments/cloud plan
```

Why: formatting and validation catch local syntax/schema errors; the remote plan confirms OIDC, live permissions, state, and exact infrastructure changes.

For a new deployment, enable AWS first with DNS false. Review and apply AWS, verify the ALB, then enable DNS and apply the three Route 53 resources. This staged approach separates compute problems from DNS problems.

## 13. Review and apply in HCP Terraform

There are two supported ways to start a run:

1. Commit and push to `main`; the VCS connection creates a run automatically.
2. Open **Runs -> New run -> Plan and apply -> Start run**.

Review the plan summary before approval. A fresh AWS deployment should contain AWS resources only. It must show zero deletions unless deletion is intentional.

Select **Confirm & Apply** only after reviewing the plan.

Why: a Terraform plan is the final safety boundary before billable or destructive cloud changes.

## 14. Verify the deployment

Check HCP outputs:

```text
aws_endpoint    = http://multicloud-demo-alb-118255151.ap-south-1.elb.amazonaws.com
global_endpoint = http://app.multicloud.durgesh.space
```

Verify the application:

```bash
curl -fsS http://multicloud-demo-alb-118255151.ap-south-1.elb.amazonaws.com/health
curl -fsS http://aws.multicloud.durgesh.space/health
curl -fsS http://app.multicloud.durgesh.space/health
```

Expected response fields:

```json
{
  "cloud": "aws",
  "region": "ap-south-1",
  "service": "multicloud-demo",
  "status": "healthy"
}
```

Verify DNS:

```bash
dig +short aws.multicloud.durgesh.space
dig +short app.multicloud.durgesh.space
```

Run a final drift check:

```bash
terraform -chdir=environments/cloud plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

Why: HTTP verifies the application path; DNS verifies delegation/records; the final plan verifies that Terraform state matches AWS.

## 15. Make future changes safely

```bash
git status
terraform fmt -recursive
terraform -chdir=environments/cloud validate
git add <only-the-intended-files>
git commit -m "Describe the change"
git push origin main
```

Open the new HCP run, review it, and manually apply it.

Why: small reviewed commits make infrastructure changes traceable and reversible.

## 16. Run the local demonstration

Local Docker/Floci does not use real cloud credentials:

```bash
make local-up
docker compose -f local/docker-compose.yml ps
curl -fsS http://localhost:8080/health
make local-terraform
```

Open:

```text
Grafana:    http://localhost:3000  (admin / local-only-change-me)
Prometheus: http://localhost:9090
```

Stop local services:

```bash
make local-down
```

Why: the local environment demonstrates the application, monitoring, failover proxy, and Terraform workflow without cloud charges.

## 17. Disable or destroy AWS safely

Because DNS depends on AWS, disable and apply in two stages:

1. Set `enable_dns=false`, review the plan, and apply. This removes Route 53 application records and health checks.
2. Set `enable_aws=false`, review the plan, and apply. This removes AWS resources managed by this state.

Keep `enable_databases=false` unless a managed database is intentionally required.

Why: removing dependent DNS first avoids validation failures and dangling records. Review S3 contents before destruction because non-empty/versioned buckets can require deliberate cleanup.

## 18. Common failures

| Symptom | Cause | Fix |
|---|---|---|
| HCP plan has zero changes unexpectedly | Toggle was created as an Environment variable | Recreate it as a Terraform variable |
| `AssumeRoleWithWebIdentity` fails | Trust subject/audience does not match | Compare the role with `aws-trust-policy.json` |
| ALB creation denies `ec2:GetSecurityGroupsForVpc` | Granular role policy is missing a newer EC2 read action | Add that action or use the supplied deployment policy |
| ALB returns 503 | Container did not start or target is unhealthy | Check target health, image visibility, port 8080, and `/health` |
| `aws.multicloud...` does not resolve | Route 53 records not applied or delegation is wrong | Check `enable_dns`, zone ID, NS records, and SOA owner |
| DNS works on one resolver only | Cached prior NXDOMAIN/delegation | Wait for TTL and compare `1.1.1.1` with `8.8.8.8` |
| `https://` fails | This demo currently has an HTTP-only ALB listener | Use `http://` or add ACM plus an HTTPS listener |

For additional operational checks, use [`RUN_AND_VERIFY.md`](RUN_AND_VERIFY.md) and [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).
