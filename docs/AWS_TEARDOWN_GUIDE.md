# AWS teardown and deletion guide

This guide removes the AWS infrastructure created by this project while protecting unrelated account resources. Follow it after saving any screenshots, outputs, database records, logs, or other demonstration evidence that must be retained.

## What this procedure deletes

When the corresponding features are enabled, the reviewed HCP Terraform run removes:

- EC2 application instances and their root volumes
- Application Load Balancer, listener, target group, and attachments
- Elastic IP addresses
- Project VPC, public subnets, route table, internet gateway, and security groups
- Application EC2 IAM role, inline secret-read policy, and instance profile
- Project S3 backup bucket and its Terraform-managed configuration
- SNS alert topic and CloudWatch alarm
- Route 53 application/provider records and Terraform-managed health checks
- Optional AWS RDS resources when `enable_databases` was enabled

The normal procedure does **not** delete:

- the HCP Terraform AWS deployment role or its OIDC provider
- a Route 53 hosted zone that was created outside this Terraform state
- Namecheap registration or delegation records
- a MongoDB Atlas cluster
- a MongoDB URI secret created manually in AWS Secrets Manager
- unrelated AWS resources
- local Docker volumes, unless `down -v` is explicitly used

## 1. Confirm the correct workspace and account

In HCP Terraform, open the workspace used by this repository and verify its organization, project, repository, branch, and working directory.

From a trusted terminal, verify the AWS identity:

```bash
aws sts get-caller-identity
```

Confirm that the returned account is the intended demonstration account. Do not continue when the account or workspace is unexpected.

Why: deletion cannot be made safe by resource names alone when the wrong credentials or workspace are selected.

## 2. Save required evidence and data

Before changing any flags:

1. Save Terraform outputs and screenshots required by the project report.
2. Export application/database data that must be retained.
3. Review the project S3 bucket. The module uses `force_destroy = false`, so Terraform intentionally refuses to delete a non-empty bucket.
4. Record any DNS values that might be needed again.
5. Confirm that no other application depends on these project resources.

## 3. Stop the local environment

From the repository root:

```bash
docker compose -f local/docker-compose.yml down
```

This removes this project's containers and network but preserves named volumes. Confirm:

```bash
docker compose -f local/docker-compose.yml ps -a
```

To delete local database and monitoring data as well, use the following only after confirming that the volumes are disposable:

```bash
docker compose -f local/docker-compose.yml down -v
```

If the local Terraform/Floci smoke test was applied, remove its emulated state separately:

```bash
terraform -chdir=environments/local destroy
```

## 4. Disable AWS-dependent features in HCP Terraform

Open:

```text
HCP Terraform -> Organization -> Project -> Workspace -> Variables
```

Set these **Terraform variables** to `false`:

```text
enable_dns          = false
enable_aws_mongodb = false
enable_aws          = false
```

Also keep these disabled unless their resources are intentionally being managed elsewhere:

```text
enable_databases = false
enable_azure     = false
enable_gcp       = false
```

Why: a normal feature-flag run is safer than a workspace-wide destroy run. It removes the AWS and DNS resources selected by these variables without automatically destroying resources from another cloud that might later share the workspace.

Do not delete `aws_mongodb_secret_arn` or other variables before the run. Terraform can still need their values while refreshing resources that are about to be deleted.

## 5. Queue a normal manual-apply run

Open the workspace **Runs** page and select **New run**. Use the normal plan type, not a speculative plan and not a workspace-wide destroy plan. Suggested message:

```text
Destroy Terraform-managed AWS and DNS project resources
```

Keep auto-apply disabled.

Why: changing the feature flags to `false` causes Terraform to plan deletions through the same dependency graph that created the resources.

## 6. Review the deletion plan

Every changed managed AWS/DNS resource should show `delete`. Typical addresses include:

```text
aws_route53_health_check.provider["aws"]
aws_route53_record.application["aws"]
aws_route53_record.provider["aws"]
module.aws[0].aws_instance.application[*]
module.aws[0].aws_eip.application[*]
module.aws[0].aws_lb.application
module.aws[0].aws_lb_listener.http
module.aws[0].aws_lb_target_group.application
module.aws[0].aws_iam_role.application[0]
module.aws[0].aws_iam_instance_profile.application[0]
module.aws[0].aws_s3_bucket.backup
module.aws[0].aws_sns_topic.alerts
module.aws[0].aws_cloudwatch_metric_alarm.unhealthy_hosts
module.aws[0].aws_vpc.main
```

The exact count varies with enabled features. Stop and investigate if the plan contains:

- any Azure or GCP deletion that was not requested
- a Route 53 hosted zone rather than only records/health checks
- the HCP deployment role
- resources without this project's expected names/tags
- replacements or creations that are not understood

Only select **Confirm & Apply** after the complete plan matches the intended scope.

## 7. Monitor the apply

Wait until HCP reports `Applied`. Load balancers, network interfaces, security groups, and VPC components can take several minutes to delete because AWS removes them in dependency order.

If deletion fails:

- **S3 bucket not empty:** empty only the named project bucket, including object versions and delete markers, then queue another run.
- **Security group/VPC dependency:** wait for ALB and network-interface deletion, then retry.
- **IAM instance-profile conflict:** confirm the EC2 instances are gone and the role has been removed from the profile.
- **AccessDenied:** add only the missing action to the HCP deployment policy and retry the same feature-flag plan.

Do not manually delete a random dependency merely to make Terraform continue. Resolve it against the exact resource address from the failed run.

## 8. Delete a manually created MongoDB secret

Terraform intentionally does not manage the MongoDB URI value, so deleting the AWS module does not delete this secret.

The operator needs these permissions on only the project secret:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeleteProjectMongoDbSecret",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:DescribeSecret",
        "secretsmanager:DeleteSecret"
      ],
      "Resource": "arn:aws:secretsmanager:<AWS_REGION>:<AWS_ACCOUNT_ID>:secret:multicloud/demo/mongodb-uri-*"
    }
  ]
}
```

Schedule recoverable deletion using AWS's minimum seven-day recovery window:

```bash
aws secretsmanager delete-secret \
  --region <AWS_REGION> \
  --secret-id multicloud/demo/mongodb-uri \
  --recovery-window-in-days 7
```

Do not use `--force-delete-without-recovery` for the normal project cleanup. During the recovery window, the secret is inaccessible but can be restored if the deletion was accidental:

```bash
aws secretsmanager restore-secret \
  --region <AWS_REGION> \
  --secret-id multicloud/demo/mongodb-uri
```

After scheduling deletion, remove any temporary bootstrap policy that was added to the operator IAM user.

## 9. Verify that project resources are gone

Terraform state should contain no resources when AWS was the only enabled provider:

```bash
terraform -chdir=environments/cloud state list
```

The command should print nothing. Then check the account using the same region and project tags used during deployment:

```bash
aws ec2 describe-instances \
  --region <AWS_REGION> \
  --filters \
    Name=tag:Project,Values=multicloud-terraform \
    Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text

aws ec2 describe-vpcs \
  --region <AWS_REGION> \
  --filters Name=tag:Project,Values=multicloud-terraform \
  --query 'Vpcs[].VpcId' \
  --output text

aws ec2 describe-addresses \
  --region <AWS_REGION> \
  --filters Name=tag:Project,Values=multicloud-terraform \
  --query 'Addresses[].AllocationId' \
  --output text

aws s3api list-buckets \
  --query 'Buckets[?starts_with(Name, `multicloud-demo-backup-`)].Name' \
  --output text
```

Each command should return no project resource. Verify application records are gone:

```bash
dig +short aws.multicloud.example.com
dig +short app.multicloud.example.com
```

Verify the secret is marked for deletion. Attempting to read it should return an error stating that it is marked for deletion:

```bash
aws secretsmanager get-secret-value \
  --region <AWS_REGION> \
  --secret-id multicloud/demo/mongodb-uri
```

## 10. Optional: delete the pre-existing Route 53 hosted zone

The Terraform root receives `hosted_zone_id` as an input and therefore does not own or delete that hosted zone. A public hosted zone can continue incurring a Route 53 charge.

Delete it only when the delegated subdomain will no longer be used:

1. In Namecheap, remove the child-zone NS records for `multicloud` that point to AWS nameservers.
2. In Route 53, open the hosted zone and verify only the default NS and SOA records remain.
3. Select **Delete hosted zone** and confirm the exact zone name.
4. Verify that the child-zone delegation no longer resolves.

Do not delete a parent/root domain zone or a zone used by another application.

## 11. Optional: remove bootstrap IAM resources

The HCP deployment role and Terraform OIDC provider are deliberately retained so the project can be deployed again. IAM roles do not incur hourly charges.

Delete them only when no workspace uses them:

1. Confirm no HCP workspace references the role ARN.
2. Detach/delete the deployment role policies.
3. Delete the deployment role.
4. Delete the Terraform OIDC provider only when no other role trusts it.

Keep the GitHub repository, HCP workspace, and variables with all `enable_*` flags set to `false` if a future redeployment is expected.

## Final checklist

- [ ] Required evidence and data were saved.
- [ ] Local containers are stopped.
- [ ] `enable_dns`, `enable_aws_mongodb`, and `enable_aws` are false.
- [ ] The deletion plan contained only intended resources.
- [ ] HCP reports the run as applied.
- [ ] Terraform state and AWS verification commands show no project resources.
- [ ] Application DNS records no longer resolve.
- [ ] The MongoDB secret is marked for deletion.
- [ ] Temporary operator permissions were removed.
- [ ] The hosted zone and HCP role were deliberately retained or separately reviewed and deleted.
