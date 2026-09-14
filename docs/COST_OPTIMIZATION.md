# Cost controls

- Keep every `enable_*` switch false until its plan is reviewed.
- Deploy one cloud at a time and destroy demonstration resources after evidence is captured.
- Keep `enable_databases=false` unless managed-database evidence is required.
- AWS uses small EC2 instances and no NAT gateway; Azure uses B-series VMs; GCP uses E2 micro VMs.
- Object lifecycle rules move older GCP objects to Nearline; review retention before adding real data.
- Configure native budgets manually at the account/subscription/project level. Budget alerts report spending but do not automatically stop it.
- Route 53 health checks, load balancers, public IPv4 addresses, disks, logs, and stopped VMs can all continue to incur charges.

Before destroying infrastructure, back up any evidence or data you need. Use the HCP Terraform workspace destroy plan and inspect it carefully.
