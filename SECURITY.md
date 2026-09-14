# Security

Do not report credentials in public issues. Revoke exposed credentials immediately in the issuing service, then review audit logs for unexpected use.

This repository must contain no AWS access keys, HCP Terraform tokens, Azure client secrets, GCP service-account keys, database passwords, or private SSH keys. Authentication for cloud runs uses short-lived HCP Terraform OIDC credentials.

Before every push, run a secret scanner and review `git diff --staged`. Git history preserves deleted secrets, so removing a credential from the latest file is not sufficient after it has been committed.
