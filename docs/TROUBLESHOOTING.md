# Troubleshooting

## HCP run cannot assume a cloud identity

- Confirm the organization, project, and workspace names match exactly, including spaces, hyphens, underscores, and letter case.
- Confirm both `plan` and `apply` subjects are trusted. Azure requires two exact federated identity credentials.
- Confirm all HCP values were created as Environment variables, except documented Terraform input variables.
- Never solve OIDC errors by adding static access keys.

## Azure reports a resource provider is not registered

Register the provider listed in the error under Subscription 1 > Resource providers. The AzureRM configuration intentionally does not register providers because the deployment identity is scoped to one resource group.

## Cloud VM is unhealthy

Check cloud-init/startup-script logs, then confirm the image is public and the tag exists. The default is `ghcr.io/durgeshkumar1995/multicloud-demo:v1.0.0`. Confirm port `8080` and `/health` match the variables.

## Namecheap hostname does not resolve

At Namecheap, delegate the `multicloud` subdomain with four NS records whose host is `multicloud` and whose values are the Route 53 name servers. Remove trailing dots if Namecheap rejects them. DNS propagation can take hours depending on cached TTLs.

## Docker command cannot connect to daemon

Start Docker Desktop, wait until the engine is ready, then run `make compose-check` followed by `make local-up`.

## Local Terraform cannot reach Floci

Confirm `http://localhost:14566` is listening and the `floci-aws` container is healthy. This project maps Floci's container port `4566` to host port `14566` to avoid common LocalStack/Floci conflicts. The local provider uses placeholder credentials and must never be pointed at real AWS with those values.
