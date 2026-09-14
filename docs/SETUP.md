# Cloud and HCP Terraform setup

## HCP Terraform workspace

Use these workspace settings:

- Organization: `Multi-Cloud-Deployment-and-Management`
- Project: `Multi-Cloud Deployment-Management`
- Workspace: `Multi-Cloud-Deployment_Management_Terraform`
- Execution mode: Remote
- Terraform working directory: `environments/cloud`
- Auto apply: Off

Connect the GitHub repository and choose the default branch after this project is pushed.

### Environment variables

Add these as **Environment variables** in the workspace. None contains a long-lived secret.

| Key | Value |
|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true` |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::075472845204:role/hcp-terraform-multicloud` |
| `TFC_GCP_PROVIDER_AUTH` | `true` |
| `TFC_GCP_PRINCIPAL_TYPE` | `service_account` |
| `TFC_GCP_PROJECT_NUMBER` | `234367924778` |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | `multicloud-services@multicloudproject-508411.iam.gserviceaccount.com` |
| `TFC_GCP_WORKLOAD_POOL_ID` | `hcp-terraform-pool` |
| `TFC_GCP_WORKLOAD_PROVIDER_ID` | `hcp-terraform-provider` |
| `TFC_AZURE_PROVIDER_AUTH` | `true` |
| `TFC_AZURE_RUN_CLIENT_ID` | `6d53e690-9d31-48e2-be4d-c9353f381da1` |
| `ARM_TENANT_ID` | `e5019544-2300-441d-87d0-2f4661a91823` |
| `ARM_SUBSCRIPTION_ID` | `0a56e4ba-0653-440c-8fe2-e293baa54c27` |

HashiCorp supports either the three separate GCP values shown above or one `TFC_GCP_WORKLOAD_PROVIDER_NAME` containing the full canonical provider name. Do not configure both forms; the unified full-name variable takes precedence. This project documents the separate-value form.

### Terraform variables

Start with these **Terraform variables**:

| Key | Initial value | Sensitive |
|---|---|---|
| `enable_aws` | `false` | No |
| `enable_azure` | `false` | No |
| `enable_gcp` | `false` | No |
| `enable_dns` | `false` | No |
| `enable_databases` | `false` | No |
| `azure_ssh_public_key` | contents of `~/.ssh/id_rsa.pub` | No |
| `alert_email` | your monitored email, or empty | No |

Only if databases are enabled, add `database_admin_password` as a **sensitive Terraform variable**, at least 16 characters. Do not put it in a `.tfvars` file.

## OIDC trust checks

### AWS

The role trust must allow both plan and apply runs for the exact organization, project, and workspace. If the AWS quick-setup UI created only a `plan` subject, add an equivalent `apply` condition or use a narrowly scoped `StringLike` ending in `run_phase:*`.

The accepted subject prefix is:

```text
organization:Multi-Cloud-Deployment-and-Management:project:Multi-Cloud Deployment-Management:workspace:Multi-Cloud-Deployment_Management_Terraform:run_phase:
```

Attach [the deployment permissions policy](aws-deployment-policy.json) to the role. It is service-scoped but still broad enough for this demonstration; use a separate sandbox account and tighten resource ARNs after the first successful deployment.

### GCP

The workload identity provider condition should restrict tokens to the workspace, for example:

```text
assertion.sub.startsWith("organization:Multi-Cloud-Deployment-and-Management:project:Multi-Cloud Deployment-Management:workspace:Multi-Cloud-Deployment_Management_Terraform:")
```

Grant `roles/iam.workloadIdentityUser` on the deployment service account to the restricted workload-pool principal set. Grant the deployment service account these project roles:

- Compute Admin
- Storage Admin
- Monitoring Editor
- Service Usage Admin
- Cloud SQL Admin only when `enable_databases=true`

Do not download a service-account JSON key.

### Azure

Azure federated identity credentials match an exact subject. Create **two** credentials on the app registration: one ending in `run_phase:plan` and a second ending in `run_phase:apply`. Audience is `api://AzureADTokenExchange`; issuer is `https://app.terraform.io`.

The enterprise application already needs Contributor on `rg-multicloud-terraform`. Register these resource providers in Subscription 1 before the first run because automatic provider registration is disabled in the Terraform provider:

- `Microsoft.Compute`
- `Microsoft.Network`
- `Microsoft.Storage`
- `Microsoft.Insights`
- `Microsoft.DBforPostgreSQL` only for the database option

## Safe deployment sequence

1. Set `enable_aws=true`; queue and review a plan, then apply.
2. Verify the AWS output and `/health`; then repeat for Azure.
3. Repeat for GCP.
4. Confirm `aws.`, `azure.`, and `gcp.` provider hostnames are healthy.
5. Set `enable_dns=true` and apply.
6. Validate `http://app.multicloud.durgesh.space/health`.

The supplied Route 53 zone is `Z03424422VGD13RVLRX4` for `multicloud.durgesh.space`. In Namecheap, the `multicloud` delegation must point to the four Route 53 name servers. Do not replace the parent `durgesh.space` nameservers unless the whole domain is intentionally moving to Route 53.
