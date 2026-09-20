# MongoDB test setup

MongoDB support is optional. The application continues serving `/health` when MongoDB is disabled or unavailable, while `/db/health` reports database-specific status.

Important: `enable_databases` in the Terraform configuration controls the existing optional PostgreSQL resources. It does **not** enable MongoDB. Keep it `false` when testing MongoDB.

## What was added

- Official PyMongo driver, pinned in `requirements.txt`.
- Authenticated MongoDB 8.0 container for local testing (when the Docker VM kernel is supported).
- Persistent Docker volume `mongodb-data`.
- `MONGODB_URI`, `MONGODB_DATABASE`, and `MONGODB_COLLECTION` configuration.
- `GET /db/health` for a MongoDB ping.
- `POST /db/items` to insert test data.
- `GET /db/items` to read the latest 20 test records.

The application never includes the connection URI, username, or password in an HTTP response.

## Option A: run a local MongoDB test

This is the recommended first test because it requires no Atlas network allowlist and creates no cloud database charge.

Start the stack:

```bash
cd /path/to/multicloud-project
make local-up
docker compose -f local/docker-compose.yml ps
```

Wait for `mongodb`, `app-aws`, `app-azure`, and `app-gcp` to become healthy. Check MongoDB through the application:

```bash
curl -fsS http://localhost:8081/db/health
```

Expected:

```json
{"database":"mongodb","database_name":"multicloud_demo","status":"healthy"}
```

Insert a test item:

```bash
curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"message":"MongoDB test from the AWS-labelled local app"}' \
  http://localhost:8081/db/items
```

Read it through another application instance:

```bash
curl -fsS http://localhost:8082/db/items
```

Why: all three local application containers use the same MongoDB database, demonstrating shared persistence across cloud-labelled instances.

Stop containers while preserving MongoDB data:

```bash
make local-down
```

To deliberately delete local MongoDB and all other Compose volumes:

```bash
docker compose -f local/docker-compose.yml down -v
```

## Option B: connect the local application to MongoDB Atlas

### 1. Create/select an Atlas deployment

In MongoDB Atlas, create a project and a test cluster. A free or low-cost test tier is suitable when its limits meet the demonstration needs.

Why: Atlas manages the MongoDB servers, TLS, replication, and backups; the application only needs a connection string.

### 2. Create a database user

Open **Security -> Database Access** and create a dedicated database user. Grant only read/write access to database `multicloud_demo`; do not use an Atlas organization owner's login as an application credential.

Why: Atlas users manage the control plane, while database users authenticate application connections. They are separate identities.

### 3. Configure the Atlas IP access list

Open **Security -> Network Access** and add the public IP of the machine running Docker. Use a `/32` entry for a single test address.

Do not use `0.0.0.0/0` except for a short, explicitly accepted test risk, and remove it immediately afterward.

Why: Atlas rejects client connections unless their source address is in the project IP access list.

### 4. Obtain the driver connection string

Open the cluster, select **Connect -> Drivers -> Python**, and copy the `mongodb+srv://` connection string. URL-encode reserved characters in the password.

The credential file must contain at least:

```text
MONGODB_URI=mongodb+srv://DATABASE_USER:URL_ENCODED_PASSWORD@CLUSTER.mongodb.net/multicloud_demo?retryWrites=true&w=majority
MONGODB_DATABASE=multicloud_demo
```

Do not commit this file. The repository ignores every file ending in `.env` while retaining `*.env.example` templates.

### 5. Start Compose with the Atlas environment file

Use an absolute path to the downloaded credential file:

```bash
docker compose \
  --env-file /absolute/path/to/atlas-credentials.env \
  -f local/docker-compose.yml \
  up --build -d --no-deps app-aws app-azure app-gcp gateway
```

Docker Compose substitutes `MONGODB_URI` into the application containers. `--no-deps` deliberately skips the local MongoDB container because the applications use Atlas. This also avoids a known MongoDB startup incompatibility on Docker VMs using Linux kernel 6.19 through 7.0.13.

The local MongoDB host port defaults to `27018` to avoid collisions with another MongoDB installation. Override it when required with `MONGODB_HOST_PORT`.

### 6. Verify Atlas through the application

```bash
curl -fsS http://localhost:8081/db/health
curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"message":"MongoDB Atlas test"}' \
  http://localhost:8081/db/items
curl -fsS http://localhost:8082/db/items
```

If `/db/health` returns `503`, inspect logs without printing the URI:

```bash
docker compose -f local/docker-compose.yml logs --tail=100 app-aws
```

Common causes are a missing IP access-list entry, incorrect database-user password, an unescaped password character, or a paused cluster.

## Recommended AWS deployment design

Do not place `MONGODB_URI` directly in Terraform variables, EC2 user data, GitHub Actions variables, or the container image. Those locations can expose it through Terraform state, plans, instance metadata, logs, or image history.

The AWS module implements this design:

1. Store `MONGODB_URI` as a secret in AWS Secrets Manager.
2. Attach an EC2 instance role granting only `secretsmanager:GetSecretValue` for that one secret ARN.
3. Fetch the value during instance startup and pass it directly to the container environment.
4. Terraform assigns two stable Elastic IPs; add both `/32` addresses to the Atlas IP access list.
5. Rotate the Atlas database-user password and secret regularly.

### Deploy MongoDB Atlas integration to AWS

The secret must contain the MongoDB URI as its complete plain `SecretString`, not JSON. Create or update it outside Terraform so its value never enters Terraform state:

```bash
aws secretsmanager create-secret \
  --region AWS_REGION \
  --name multicloud/demo/mongodb-uri \
  --secret-string file:///secure/path/containing-only-the-uri
```

If it already exists, use `aws secretsmanager put-secret-value` with the same `file://` input. Never place the URI directly on a shared command line.

Add these non-sensitive Terraform variables to the HCP Terraform workspace:

```text
enable_aws_mongodb      = true
aws_mongodb_secret_arn = arn:aws:secretsmanager:AWS_REGION:AWS_ACCOUNT_ID:secret:multicloud/demo/mongodb-uri-SUFFIX
mongodb_database        = multicloud_demo
container_image         = ghcr.io/GITHUB_OWNER/multicloud-demo:v1.1.0
```

Keep `enable_databases = false`; it controls PostgreSQL rather than MongoDB.

Before applying, add the IAM statements in `docs/aws-deployment-policy.json` to the HCP Terraform AWS deployment role. They allow Terraform to manage only project-prefixed EC2 roles and instance profiles.

Apply the HCP Terraform plan. The AWS instances are replaced because their startup configuration and instance profile change. After apply, obtain the stable egress addresses:

```bash
terraform -chdir=environments/cloud output -json aws_application_public_ips
```

In Atlas, open **Security -> Network Access -> Add IP Address** and add each address as `/32`. Then verify:

```bash
curl -fsS http://aws.example.com/health
curl -fsS http://aws.example.com/db/health
curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"message":"MongoDB Atlas test from AWS"}' \
  http://aws.example.com/db/items
curl -fsS http://aws.example.com/db/items
```

`/health` remains independent of MongoDB so the load balancer does not remove an otherwise healthy application instance while Atlas network access is being configured.

## Credential handling

- Keep downloaded Atlas `.env` files outside the repository.
- Do not paste connection strings into issues, commits, screenshots, or chat.
- Rotate the database-user password if the file has been shared.
- Use a dedicated read/write user for `multicloud_demo`, not an administrative database user.
- Remove temporary Atlas IP access-list entries after testing.

Official references:

- [Connect Atlas with a driver](https://www.mongodb.com/docs/atlas/driver-connection/)
- [PyMongo connection targets](https://www.mongodb.com/docs/languages/python/pymongo-driver/current/connect/connection-targets/)
- [Atlas IP access lists](https://www.mongodb.com/docs/atlas/security/add-ip-address-to-list/)
- [Atlas database users](https://www.mongodb.com/docs/atlas/tutorial/create-mongodb-user-for-cluster/)
