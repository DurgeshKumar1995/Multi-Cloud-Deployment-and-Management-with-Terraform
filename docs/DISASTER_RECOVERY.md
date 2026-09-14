# Disaster recovery plan

The recovery objective for this demonstration is to restore the stateless application in another enabled cloud through DNS health-based routing. Object storage versioning protects artifacts from accidental overwrite. Database disaster recovery is intentionally a separate exercise because the application does not replicate database writes.

Recommended procedure:

1. Confirm the incident using provider endpoint and Route 53 health status.
2. Freeze infrastructure changes and preserve logs.
3. Verify traffic is served by a healthy provider.
4. Restore artifacts from the relevant versioned bucket/container.
5. If databases are enabled, restore the latest provider backup into a new instance and validate data before changing application configuration.
6. Recreate the failed provider with Terraform, validate `/health`, then allow Route 53 to return it to service.
7. Document recovery time, recovery point, root cause, and follow-up controls.

Cross-cloud database replication is not implemented. Claiming zero data loss would therefore be incorrect.
