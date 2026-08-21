# ShopFlow — project context

A highly available, secure AWS order-processing platform built as a portfolio project for AWS SAA-C03 prep. Full stack: VPC → ALB → ECS Fargate → RDS Multi-AZ, with an async SQS/EventBridge/Lambda path, CloudFront + WAF at the edge, provisioned entirely with Terraform, deployed via GitHub Actions.

**Region:** `us-east-1`, standardized everywhere (backend, provider, all resources) — a past mismatch between the CLI default region and the project region caused real debugging pain, so double-check region consistency on any new AWS CLI command that doesn't already have `--region` baked in.

## Repo structure

```
shopflow/
├── terraform/
│   ├── modules/
│   │   ├── networking/     # Phase 1 — done
│   │   ├── data/            # Phase 2 — done
│   │   ├── compute/         # Phase 3 — in progress
│   │   ├── async/            # Phase 4 — not started
│   │   └── edge/              # Phase 5 — not started
│   └── environments/
│       └── dev/
│           ├── backend.tf
│           ├── providers.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── main.tf      # module call site
├── app/                    # minimal Express API
├── worker/                  # Lambda worker (Phase 4)
├── .github/workflows/        # CI/CD (Phase 6)
└── docs/                       # WAF review, chaos test writeup, cost breakdown (Phase 10-11)
```

## Conventions established so far

- **Module pattern:** each module owns its own `variables.tf` and `outputs.tf`. Root `environments/dev/` declares its own root-level variables (with defaults/validation) and passes them into modules via `module.x { var = var.x }`. Root `outputs.tf` re-exposes `module.x.output_name` so `terraform output` shows anything useful.
- **Any new `module` block requires `terraform init`** before `plan`/`apply` will recognize it — easy to forget.
- **Security group chain:** `alb-sg` (public, 80/443 from 0.0.0.0/0) → `ecs-sg` (from alb-sg only, port 3000) → `rds-sg` / `cache-sg` (from ecs-sg only, 5432 / 6379). Nothing skips a tier. `ecs-sg` needs an explicit egress rule (Terraform-managed SGs don't get AWS's default allow-all outbound).
- **Subnet groups** (`aws_db_subnet_group`, `aws_elasticache_subnet_group`) live in the `networking` module, exposed as outputs — treated as a networking concern, not a data concern.
- **Secrets:** RDS uses `manage_master_user_password = true` (AWS-managed rotation via Secrets Manager) rather than a hardcoded password anywhere.
- **Tags:** `Name = "ShopFlow-<resource>"` on everything.
- **Git:** annotated tags per completed phase (`git tag -a phase-1-networking -m "..."`), `push.followTags` enabled so `git push` carries commits + tags together.

## Phase status

**Phase 1 — Networking: complete, verified.**
VPC (`10.0.0.0/16`), 2 public + 2 private subnets across `us-east-1a`/`us-east-1b`, single NAT Gateway (in `publicsubnet1` only — deliberate cost-vs-resilience trade-off, both private subnets route through it, documented as a known single point of failure for AZ-b's outbound traffic). KMS key for shared encryption. All 4 SGs described above.

**Phase 2 — Data: complete, verified via SSM.**
RDS Postgres, Multi-AZ, `db.t3.micro`, 20GB gp3, encrypted with the shared KMS key, `skip_final_snapshot = true` for easy destroy/rebuild between sessions. ElastiCache Redis via `aws_elasticache_replication_group` (not the plain `aws_elasticache_cluster` — needed for automatic failover), 2 nodes, Multi-AZ.
Verified live: connected via a temporary EC2 instance in the private subnet, reached over SSM Session Manager (IAM role `ssm-test-role` / instance profile `ssm-test-profile`, reused `ecs-sg` as its security group so the test exercises the same path real ECS tasks will use). Confirmed `psql` connects over TLS and `redis-cli PING` returns `PONG`.
**`orders` table created manually** via `psql -f schema.sql` (columns: id, customer_id, item, quantity, status, created_at). Not yet migrated to a real migration tool (`node-pg-migrate`) — flagged as a Phase 11 polish item, not urgent.

**Phase 3 — Compute: in progress.**
Terraform designed but not yet fully applied: ECR repo, execution role + task role (task role scoped to `secretsmanager:GetSecretValue` on the specific RDS secret ARN, not `*`), CloudWatch log group, ALB in public subnets with `/health` target group check, ECS Fargate service (`desired_count = 2`, private subnets, no public IP), target-tracking auto scaling on CPU at 60%.

App code (`app/`) has a known-good structure as of last review:
- `src/db.js` — owns the `pg` Pool as a module-level singleton, exports `initDb()` and `getPool()`. Pulls DB password from Secrets Manager at startup (`SECRET_ARN` env var), SSL with the RDS CA bundle (`global-bundle.pem`, must be downloaded into the Docker image — not committed to git).
- `index.js` — registers `/health` and the routes from `src/routes/orderRoutes.js`, only calls `app.listen()` after `initDb()` resolves (so the ALB never routes to a task before its DB pool is ready), exits the process on startup failure so ECS's self-healing can replace the task, handles `SIGTERM` to drain the pool cleanly before ECS kills the container.
- `src/routes/orderRoutes.js` — `POST /orders`, uses `getPool()` from `db.js`.

**Not yet done for Phase 3:**
- Dockerfile doesn't exist yet (a minimal `node:20-slim` version was sketched, not committed)
- No image has been pushed to ECR yet — apply order matters here: create the ECR repo first (`-target`), push an image, *then* apply the rest of the compute module, or the ECS service will spin up tasks that can never pull an image and just retry forever
- Haven't yet run `terraform apply` on the full compute module or curl-tested the ALB end to end

**Phases 4–11:** not started. Rough plan (see full implementation guide if present in `/docs`): SQS + DLQ + EventBridge + Lambda worker (Phase 4) → CloudFront + WAF + S3 (Phase 5) → GitHub Actions with OIDC, no long-lived AWS keys (Phase 6) → CloudWatch dashboards + alarms + X-Ray (Phase 7) → GuardDuty/Security Hub/Config/VPC Flow Logs hardening pass (Phase 8) → deliberate chaos test with a written postmortem (Phase 9) → cost + Well-Architected review (Phase 10) → README, docs, demo recording (Phase 11).

## Known issues worth remembering

- Region mismatches bit this project twice already (S3 backend bucket, then the DynamoDB lock table) — both from running AWS CLI commands without an explicit `--region` flag while the local CLI default region didn't match the project. CLI default has since been set to `us-east-1`, but stay alert on any command that omits the flag.
- `aws_vpc_security_group_egress_rule` with `ip_protocol = "-1"` must NOT include `from_port`/`to_port` at all (even `0`/`0`) — the newer standalone SG rule resources reject that combination on `Modify` calls, even though the older inline `ingress {}`/`egress {}` block style tolerates it.
- RDS engine version wasn't pinned explicitly — currently running Postgres 18 (AWS's current default), which surprised us since the plan had assumed something like 15. Worth deciding whether to pin `engine_version` explicitly rather than floating on AWS's default.

## What to do next

Pick up Phase 3: write the Dockerfile, get an image into ECR, run the full `terraform apply` on the compute module, then verify the whole synchronous path (`curl` the ALB `/health`, then `POST /orders`, then confirm the row lands in RDS via the same SSM-based `psql` check used in Phase 2).

## Phase 3 — Minimal application + compute tier

**Build the app (keep it small — see note below):**
- 3 endpoints: `POST /orders`, `GET /orders/{id}`, `GET /orders`
- Writes to RDS, reads through ElastiCache where sensible
- Dockerfile, multi-stage build, non-root user in the final image

**Build the infra:**
- ECR repository
- ECS cluster (Fargate), task definition referencing your image, task execution role (pulls image, writes logs) and a *separate* task role (app runtime permissions — SQS send, Secrets Manager read)
- ECS service behind the ALB, target group with a `/health` check
- Auto Scaling target tracking on ALB request count per task or CPU utilization

```bash
# first image push, before CI/CD exists
aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
docker build -t shopflow-app ./app
docker tag shopflow-app:latest <account>.dkr.ecr.<region>.amazonaws.com/shopflow-app:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/shopflow-app:latest
```

**Test:** `curl http://<alb-dns-name>/orders -X POST -d '{...}'` and confirm the row lands in RDS. This is your first fully working synchronous path — worth pausing here before adding complexity.

> Note on the app itself: keep it to a few hundred lines. This project is evaluated on the infrastructure around it, not the API's sophistication. Spend roughly 20% of your time here, 80% on everything else.

---

## Phase 4 — Async layer

**Build:**
- SQS queue + a dead-letter queue (DLQ) for messages that fail repeatedly
- EventBridge rule (or have the app publish directly to SQS — simpler, and still a legitimate design choice you can defend)
- Modify the app: after a successful order write, publish an event
- Lambda worker subscribed to the queue, its own least-privilege IAM role, logs to CloudWatch

**Test:** place an order, then check CloudWatch Logs for the Lambda invocation. Deliberately break the worker (throw an exception) and confirm the message lands in the DLQ instead of disappearing.

---

## Phase 5 — Edge layer

**Build:**
- S3 bucket for static assets and DB backups, versioned, lifecycle rule to transition old backups to Glacier
- CloudFront distribution in front of the ALB
- WAF Web ACL (AWS managed rule groups — Core Rule Set, rate-based rule) attached to the CloudFront distribution
- Optional: Route 53 hosted zone + ACM certificate for a real domain — makes the demo look more finished

**Test:** hit the CloudFront URL instead of the ALB directly; confirm WAF blocks an obvious bad request (e.g. a SQLi-pattern query string) with a 403.

---

## Phase 6 — CI/CD pipeline

**Build:**
- GitHub OIDC identity provider in IAM + a role GitHub Actions can assume (no long-lived AWS access keys stored as GitHub secrets — this is a real security upgrade over most tutorials)
- Workflow: on push to `main` → run tests → build image → push to ECR → register new task definition revision → update ECS service → run a smoke test against the new deployment

```yaml
# .github/workflows/deploy.yml (excerpt)
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account>:role/github-actions-deploy
          aws-region: us-east-1
      - run: |
          docker build -t $ECR_REPO:${{ github.sha }} ./app
          docker push $ECR_REPO:${{ github.sha }}
      - run: aws ecs update-service --cluster shopflow --service app --force-new-deployment
```

- Keep `terraform apply` for infrastructure as a separate, manually-triggered workflow (or gated behind an approval) — don't auto-apply infra changes on every push.

**Test:** push a trivial change, watch the pipeline run end to end, confirm zero-downtime rolling deploy (curl the endpoint in a loop during deploy — no failed requests).

---

## Phase 7 — Observability

**Build:**
- CloudWatch dashboard: ALB latency + 5xx rate, ECS CPU/memory, RDS connections, SQS queue depth
- Alarms on the above → SNS topic → your email
- X-Ray tracing enabled on the ALB and ECS task, so you can pull up an actual trace of a request through the system
- Log group retention set explicitly (don't leave it at "never expire")

**Test:** generate some load (see Phase 9) and confirm the dashboard moves and an alarm fires correctly at least once.

---

## Phase 8 — Security hardening pass

Go back through what you built with a security lens:

- Enable GuardDuty and Security Hub
- Turn on VPC Flow Logs
- Run IAM Access Analyzer, fix any overly broad policy it flags
- Re-check every security group for anything wider than it needs to be
- Confirm nothing sensitive is in Terraform state without encryption (state bucket should be encrypted + versioned, which you set up in Phase 0)

---

## Phase 9 — Chaos test (do this deliberately, and document it)

Pick at least one:
- Stop a running ECS task manually (`aws ecs stop-task`) and time how long until it's replaced and healthy
- Force an RDS failover (`aws rds reboot-db-instance --force-failover`) and measure the application-level impact
- Run a load test (k6 or Artillery) at the same time to see real numbers, not just "it seemed fine"

Write up: what you expected, what actually happened, any surprises, and what you changed afterward. This write-up is worth more in interviews than any other single artifact in the repo.

---

## Phase 10 — Cost and Well-Architected review

- Pull a Cost Explorer report or run `infracost` against your Terraform plan
- Write one paragraph per Well-Architected pillar (Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization, Sustainability) on the trade-offs you made — e.g. why Fargate over EC2, why Multi-AZ RDS despite the cost, where you chose cheaper over more resilient and why

---

## Phase 11 — Package it

- `README.md`: architecture diagram, one-paragraph business framing, setup instructions
- `/docs`: Well-Architected review, chaos-test write-up, cost breakdown
- A 60–90 second screen recording or GIF of the app working plus the CloudWatch dashboard under load
- Push everything, tag a `v1.0` release

---

## Rough time budget (4 weeks alongside exam study)

| Week | Focus |
|---|---|
| 1 | Phases 0–3 (network, security, data, first working sync path) |
| 2 | Phases 4–6 (async, edge, CI/CD) |
| 3 | Phases 7–9 (observability, hardening, chaos test) |
| 4 | Phase 10–11 (cost review, write-ups, polish, record demo) |
