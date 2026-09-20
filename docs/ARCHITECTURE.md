# Architecture and design decisions

## Application tier

The same immutable OCI image is run on two instances in each enabled provider. Each cloud exposes the instances through its native HTTP load balancer. The application is stateless; `/health` returns provider metadata and `/metrics` exposes basic Prometheus metrics.

## Network tier

- AWS: one VPC, two public subnets in separate availability zones, security groups, and an Application Load Balancer.
- Azure: one VNet and application subnet, network security group, two zonal NIC/VM pairs, and a Standard public Load Balancer.
- GCP: custom VPC/subnet, regional managed instance group spanning two zones, and a global external managed HTTP load balancer.

This demonstration places compute in public subnets to avoid NAT gateway cost. In production, use private instances, managed egress, TLS, a web application firewall, and restrictive administrator access.

## Data and backup tier

Every provider creates a versioned private object store for backups or artifacts. Managed PostgreSQL is optional and disabled. The demo application does not yet use a database, so enabling one proves provisioning and recovery procedures rather than application persistence.

## DNS failover

Route 53 creates one provider hostname per enabled cloud and a weighted record set for `app.multicloud.example.com`. Each record is associated with an HTTP `/health` check. A single enabled cloud provides a stable public application hostname; with two or more, equal weights spread DNS responses and unhealthy endpoints are removed. DNS failover is not instantaneous because recursive resolvers cache results.

## Observability

The local stack includes Prometheus and Grafana. Cloud modules create basic CPU alarms and optional email notification channels. A production implementation should centralize logs and metrics, define service-level objectives, and alert on end-to-end availability rather than CPU alone.

## Terraform state

Real-cloud state is held in HCP Terraform. Local Floci state remains local under `environments/local` and is ignored by Git. The two roots must never share state.
