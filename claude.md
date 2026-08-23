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
│   │   ├── compute/         # Phase 3 — done
│   │   ├── async/            # Phase 4 — done
│   │   ├── edge/              # Phase 5 — done
│   │   └── cicd/              # Phase 6 — done
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
- **Module file layout:** within `compute` and `async`, resources are split into per-concern files (`ecr.tf`, `alb.tf`, `ecs.tf`, `autoscaling.tf`, `logs.tf`, `sqs.tf`, `eventbridge.tf`, `lambda.tf`, plus `iam.tf`/`variables.tf`/`outputs.tf` in each) rather than one monolithic `<module>.tf` — Terraform merges everything in the directory regardless, this is purely for readability.
- **Cross-module IAM avoids hard dependencies where possible:** the ECS task role's `events:PutEvents` permission (needed to publish `OrderCreated`) is scoped to the default event bus ARN built from `data.aws_caller_identity.current.account_id` in `compute/iam.tf`, rather than `compute` taking an output from `async` — keeps the two modules independently applicable.
- **Security groups must pick one rule style and stick to it:** `alb-sg` and `rds-sg` use standalone `aws_vpc_security_group_ingress_rule`/`egress_rule` resources exclusively; mixing those with the legacy inline `ingress {}`/`egress {}` block on the *same* SG makes Terraform fight itself — the inline block is authoritative over "its" SG's rules and will plan to delete anything a standalone resource added alongside it. `ecs-sg` and `cache-sg` still use the inline style and currently have nothing else targeting them, but convert them the same way before adding any standalone rule against them.

## Phase status

**Phase 1 — Networking: complete, verified.**
VPC (`10.0.0.0/16`), 2 public + 2 private subnets across `us-east-1a`/`us-east-1b`, single NAT Gateway (in `publicsubnet1` only — deliberate cost-vs-resilience trade-off, both private subnets route through it, documented as a known single point of failure for AZ-b's outbound traffic). KMS key for shared encryption. All 4 SGs described above.

**Phase 2 — Data: complete, verified via SSM.**
RDS Postgres, Multi-AZ, `db.t3.micro`, 20GB gp3, encrypted with the shared KMS key, `skip_final_snapshot = true` for easy destroy/rebuild between sessions. ElastiCache Redis via `aws_elasticache_replication_group` (not the plain `aws_elasticache_cluster` — needed for automatic failover), 2 nodes, Multi-AZ.
Verified live: connected via a temporary EC2 instance in the private subnet, reached over SSM Session Manager (IAM role `ssm-test-role` / instance profile `ssm-test-profile`, reused `ecs-sg` as its security group so the test exercises the same path real ECS tasks will use). Confirmed `psql` connects over TLS and `redis-cli PING` returns `PONG`.
**`orders` table created manually** via `psql -f schema.sql` (columns: id, customer_id, item, quantity, status, created_at). Not yet migrated to a real migration tool (`node-pg-migrate`) — flagged as a Phase 11 polish item, not urgent.

**Phase 3 — Compute: complete, verified end to end.**
ECR repo, execution role + task role (task role scoped to `secretsmanager:GetSecretValue` on the specific RDS secret ARN, plus `events:PutEvents` on the default event bus and the `ssmmessages:*` actions ECS Exec needs), CloudWatch log group, ALB in public subnets with `/health` target group check, ECS Fargate service (`desired_count = 2`, private subnets, no public IP, `enable_execute_command = true`), target-tracking auto scaling on CPU at 60%. Task definition runs `runtime_platform { cpu_architecture = "ARM64" }` — Fargate defaults to amd64 and this Mac builds arm64 natively, so ARM64 Fargate was the fix rather than cross-compiling the image.

App code (`app/`) real structure:
- `src/db.js` — `pg` Pool singleton (`initDb()`/`getPool()`), pulls the DB password from Secrets Manager via AWS SDK v3 (`SECRET_ARN` env var), SSL via the RDS CA bundle (`global-bundle.pem`, resolved with `path.join(__dirname, ...)`, fetched at Docker build time, not committed to git).
- `src/cache.js` — Redis client singleton (`initCache()`/`getCache()`) mirroring `db.js`, connects via `REDIS_HOST`/`REDIS_PORT`, no auth/TLS (matches the replication group's config).
- `src/events.js` — `EventBridgeClient` singleton, `publishOrderCreated(orderId)` puts a `Source: "shopflow.app"` / `DetailType: "OrderCreated"` event.
- `server.js` — registers `/health` + the order routes, only calls `app.listen()` after `Promise.all([initDb(), initCache()])` resolves, exits on startup failure, drains both the DB pool and cache client on `SIGTERM`.
- `src/routes/orderRoutes.js` / `src/controllers/orderController.js` — `POST /orders`, `GET /orders/:id`, `GET /orders`, `DELETE /orders/:id`. Cache-aside on reads (60s TTL), invalidated on write/delete; cache failures are logged and swallowed, never fail the request. `addOrder` publishes an `OrderCreated` event after a successful insert (also swallowed on failure — an order should still succeed even if the async leg can't be reached).
- `Dockerfile` — 3-stage build (`deps` installs prod deps, `certs` fetches the CA bundle, final stage runs as non-root `appuser` uid/gid 1001).
- `migrate.js` — reruns `src/schema.sql` (idempotent, `CREATE TABLE IF NOT EXISTS`) against the live DB; the durable, EC2-free way to (re)apply schema — run it via ECS Exec: `aws ecs execute-command --cluster shopflow-cluster --task <arn> --container app --interactive --command "node migrate.js"` (needs a pseudo-TTY if run from a non-interactive shell, e.g. `script -q /dev/null aws ecs execute-command ...`).

Verified live: `curl` through the ALB — `/health` → 200, `POST /orders` → row lands in RDS, `GET /orders/:id` round-trips through the cache correctly.

**Phase 4 — Async: complete, verified end to end.**
SQS `orders_queue` (60s visibility timeout, redrive to DLQ after 3 receives) + `orders_dlq` (14-day retention), EventBridge rule `shopflow-order-created` (pattern: `source: shopflow.app`, `detail-type: OrderCreated`) targeting the queue, Lambda worker (`shopflow-order-worker`, Node 20, VPC-attached, own security group with an ingress rule into `rds-sg` on 5432) subscribed via `aws_lambda_event_source_mapping`. Worker (`worker/index.js`) uses AWS SDK v3 for Secrets Manager (matching `app/`), reads its own `global-bundle.pem`/`package.json`/`node_modules` (separate deployable from `app/` — different runtime, different packaging, kept intentionally decoupled). IAM: Lambda's role gets `sqs:ReceiveMessage`/`DeleteMessage`/`GetQueueAttributes` scoped to the queue and `secretsmanager:GetSecretValue` scoped to the RDS secret; nothing broader.
Verified live: placed a real order, confirmed the Lambda invocation and its log lines in CloudWatch, confirmed `orders.status` flips `pending` → `confirmed`. Then ran the actual DLQ test: temporarily made the worker throw, redeployed, placed an order, watched it fail exactly 3 times at 60s intervals in CloudWatch Logs, confirmed the message (payload intact) landed in `shopflow-orders-dlq` with `ApproximateReceiveCount: 4`, then reverted and confirmed a follow-up order processed normally again.

**Phase 5 — Edge: complete, verified end to end.**
S3 `static_assets` bucket (versioned, SSE-KMS with the shared key, public access blocked, read access scoped to CloudFront only via a bucket policy conditioned on `AWS:SourceArn`) and `backups` bucket (same hardening, plus a lifecycle rule transitioning objects to Glacier after 30 days). CloudFront distribution with two origins: S3 via Origin Access Control (`assets/*` path, cached) and the ALB as the default behavior (dynamic API, all HTTP verbs forwarded, TTL=0, viewer protocol redirected to HTTPS — origin to the ALB itself is still HTTP-only since the ALB has no ACM cert yet, consistent with Phase 5's "optional" Route 53/ACM piece not being done). WAFv2 Web ACL (`scope = "CLOUDFRONT"`) with three rules in priority order: `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesSQLiRuleSet`, and a 2000 req/5-min rate-based rule — both managed groups use `override_action { none {} }` so they actually block rather than just count.
Verified live: `curl` through the CloudFront domain — `/health` → 200, `POST /orders` → 201 and row lands in RDS, `GET /orders/:id` → 200. WAF test: a SQLi-pattern query string (`?id=1' UNION SELECT...` and `?id=1 OR 1=1--`) → 403, normal traffic unaffected.

**Phase 6 — CI/CD: complete, not yet exercised by a real push.**
`cicd` module: `aws_iam_openid_connect_provider` for `token.actions.githubusercontent.com` (imported, not created — the account already had one from before this module existed; its live thumbprint (`ab9d0263244dd0326eb67015705a667e79cfe998`) was pulled via `aws iam get-open-id-connect-provider` and used instead of the commonly-cited-but-stale thumbprint value), and `shopflow-github-deploy-role` — trust policy scoped to `repo:AbednegoTenge/shopflow:ref:refs/heads/main` via the `token.actions.githubusercontent.com:sub` condition (PRs and other branches can't assume it), permissions scoped to: `ecr:GetAuthorizationToken` (`*`, required), ECR push actions scoped to the `shopflow-app` repo ARN, `ecs:RegisterTaskDefinition`/`DescribeTaskDefinition` (`*` — these two actions don't support resource-level permissions, that's not a scoping miss), `ecs:UpdateService`/`DescribeServices` scoped to the one service ARN, and `iam:PassRole` scoped to exactly the two ECS roles (execution + task) — nothing broader.
`.github/workflows/deploy.yml`: triggers on push to `main` touching `app/**`; assumes the deploy role via OIDC (no stored AWS keys); builds and pushes the image tagged with `github.sha` (never `:latest` — that's the whole point); fetches the *current live* task definition via `describe-task-definition`, patches just the image with `amazon-ecs-render-task-definition`, and registers+deploys the new revision with `amazon-ecs-deploy-task-definition` (`wait-for-service-stability: true`); smoke-tests `/health` through the ALB in a retry loop before considering the deploy successful.
**Ownership split (the actual point of Phase 6):** Terraform still creates the *first* task definition revision and owns cluster/service/IAM/networking shape; every revision after that is registered by CI directly against the AWS API, bypassing Terraform entirely. Two `lifecycle { ignore_changes = [...] }` blocks make this possible without Terraform fighting CI on the next unrelated `apply`: `aws_ecs_task_definition.app` ignores `container_definitions` (in `compute/ecs.tf`), and `aws_ecs_service.app` ignores `task_definition` — both needed, since the service's `task_definition` argument (which revision is actually running) is a *separate* drift surface from the task definition resource's own `container_definitions` JSON. Real cost of this: since `container_definitions` is a single opaque JSON string, not a keyed object, `ignore_changes` on it means Terraform stops tracking *everything* inside that JSON, not just the image — so future changes to env vars, secrets, or log config made in `ecs.tf` will silently not apply until `ignore_changes` is temporarily removed for one `apply`.
`terraform apply` for infrastructure stays manual/local, deliberately — no Terraform-apply workflow was added; only the app deploy path is automated.
**First real run failed** with `Not authorized to perform sts:AssumeRoleWithWebIdentity` at the `configure-aws-credentials` step — trust policy looked correct on paper (`repo:AbednegoTenge/shopflow:ref:refs/heads/main`), but CloudTrail's `AssumeRoleWithWebIdentity` denial event showed the actual `sub` claim GitHub sent was `repo:AbednegoTenge@175815482/shopflow@1340803657:ref:refs/heads/main` — GitHub appends an immutable numeric ID to both the org and repo name in the `sub` claim (a newer behavior, not reflected in most AWS/GitHub OIDC tutorials, which show the plain `org/repo` form). Fixed by widening the `StringLike` condition to `repo:${var.github_org}*/${var.github_repo}*:ref:refs/heads/main` (wildcards absorb the optional `@<id>` suffix without hardcoding the actual IDs) in `cicd/iam.tf`. **Diagnostic path worth remembering:** GitHub Actions' own log for an OIDC assume-role failure doesn't show the actual claims sent; `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity` does — the denied event's `userIdentity.principalId`/`userName` field contains the exact `sub` string AWS evaluated against the trust policy, which is the fastest way to see what GitHub is actually sending versus what's expected.
**Second run** (after the OIDC fix) got past auth and all the way through a real deploy — CI built, pushed, registered revision 5, and the service tried to roll onto it — but every task on revision 5 immediately exited (`exitCode: 255`, `stoppedReason: "Essential container in task exited"`), 40 failed tasks in a loop with no recovery since `aws_ecs_service.app` has no `deployment_circuit_breaker` configured (nothing auto-rolls-back a bad deploy — it just retries forever). Root cause: **architecture mismatch.** The task definition requires ARM64 (`compute/ecs.tf`'s `runtime_platform`, chosen originally because local Mac builds arm64 natively — see the Phase 3 note above), but GitHub's `ubuntu-latest` runners are amd64, and the workflow's `docker build` had no `--platform` flag, so CI silently built and pushed an amd64 image. Fargate's exec-format mismatch on an amd64 image shows up as an immediate container exit, not a pull error — easy to mistake for an app crash. Fixed by adding `docker/setup-qemu-action` + `docker/setup-buildx-action` and switching the build step to `docker buildx build --platform linux/arm64 --push` in `deploy.yml`. Manually rolled the live service back to revision 4 (last known-good) via `aws ecs update-service --task-definition ...:4` to stop the failure loop before pushing the fix, rather than leaving it retrying indefinitely.
**Worth doing before Phase 7:** add `deployment_circuit_breaker { enable = true, rollback = true }` to `aws_ecs_service.app` so a bad CI deploy auto-rolls-back instead of looping forever burning failed-task cycles — this incident is exactly the scenario that guards against. Not done yet — flagged, not fixed.
**Confirmed working end to end after the Buildx fix:** pushed a trivial `app/package.json` version bump, CI built the ARM64 image via `docker buildx build --platform linux/arm64 --push`, registered task-definition revision 6, ECS rolled it out (0 failed tasks this time — the fixed rollout, not the earlier crash loop), old revision 4 drained cleanly, deployment settled to `COMPLETED`. Verified live: the running task's image tag matches the fix commit SHA, `/health` returns 200 through both the ALB directly and CloudFront. Phase 6 is genuinely done now, not just "applied."

**Phases 7–11:** not started. Rough plan (see full implementation guide if present in `/docs`): CloudWatch dashboards + alarms + X-Ray (Phase 7) → GuardDuty/Security Hub/Config/VPC Flow Logs hardening pass (Phase 8) → deliberate chaos test with a written postmortem (Phase 9) → cost + Well-Architected review (Phase 10) → README, docs, demo recording (Phase 11).

**Full destroy/rebuild (2026-08-21/22, then again 2026-08-23):** all infra was destroyed mid-Phase-3 to stop idle resources from running up cost, then rebuilt from scratch via staged `-target` applies once Phase 3/4 code was ready. Destroyed and rebuilt a second time on 2026-08-23 once Phase 5 code existed, this time via a full 6-stage sequence: `networking` → `data` → ECR alone → image build/push → rest of `compute` → `async` → `edge`. A `terraform destroy` can leave orphaned state for resources with dependent-object protection (e.g. ECR repos aren't force-deleted by default) — if a resource shows in `terraform state list` but `aws <service> describe-*` 404s, it's orphaned state, not a real resource; `terraform state rm` it before re-applying rather than trying to import or recreate. If any resource ID, ARN, or endpoint referenced in older notes/screenshots doesn't match live AWS, trust live AWS — current IDs are the ones above (`db_endpoint`, `redis_primary_endpoint`, `alb_dns_name`, `cloudfront_domain_name` etc. are all in `terraform output`).

## Known issues worth remembering

- Region mismatches bit this project twice already (S3 backend bucket, then the DynamoDB lock table) — both from running AWS CLI commands without an explicit `--region` flag while the local CLI default region didn't match the project. CLI default has since been set to `us-east-1`, but stay alert on any command that omits the flag.
- `aws_vpc_security_group_egress_rule` with `ip_protocol = "-1"` must NOT include `from_port`/`to_port` at all (even `0`/`0`) — the newer standalone SG rule resources reject that combination on `Modify` calls, even though the older inline `ingress {}`/`egress {}` block style tolerates it.
- RDS engine version wasn't pinned explicitly — currently running Postgres 18 (AWS's current default), which surprised us since the plan had assumed something like 15. Worth deciding whether to pin `engine_version` explicitly rather than floating on AWS's default.
- Mixing an inline `ingress {}`/`egress {}` block on an `aws_security_group` with a standalone `aws_vpc_security_group_ingress_rule`/`egress_rule` targeting the *same* SG causes a real plan-time landmine: the inline block is authoritative over that SG's rules from Terraform's point of view, so adding a standalone rule alongside it makes the next plan try to delete the standalone-created rule to "reconcile" back to just the inline one — this actually happened to `rds-sg` when `async`'s Lambda ingress rule was added next to the old inline block, and would have silently cut the worker's DB access on the next `apply`. Fixed by converting `rds-sg` to the standalone style and `terraform import`-ing the pre-existing live rule (recreating it via `apply` would have 400'd as a duplicate — AWS already had it from the old inline block).
- Docker Desktop doesn't restart itself — if `docker build`/`push` fails with `failed to connect to the docker API at unix:///.../docker.sock`, it's just that the daemon isn't running; `open -a Docker` and wait ~10-30s for it to come up.
- `AWSManagedRulesCommonRuleSet` does **not** include real SQL-injection detection — it covers generic OWASP patterns (XSS, LFI/RFI, oversized bodies, SSRF-via-metadata-URL) but nothing dedicated to SQLi. A `' OR 1=1--` / `UNION SELECT` style test request will sail through with a 200 if that's the only managed rule group attached. Dedicated SQLi coverage needs `AWSManagedRulesSQLiRuleSet` added as its own rule (own priority, own `override_action { none {} }`) — this bit the Phase 5 WAF test until it was added.
- `terraform_wafv2_web_acl`'s CommonRuleSet `forwarded_values.headers` on a CloudFront cache behavior wants a **list** of strings (`["*"]`), not a bare string (`"*"`) — `terraform validate` catches this but it's an easy typo coming from tutorials that show the bare-string form for older provider versions.
- **CloudFront OAC + SSE-KMS bucket encryption needs a KMS key policy grant, not just an S3 bucket policy.** The `static_assets` bucket's default encryption uses the shared KMS key, so every object (even ones uploaded via plain `aws s3 cp` with no `--sse` flag) lands SSE-KMS encrypted. OAC alone (`origin_access_control` + the `AWS:SourceArn`-scoped S3 bucket policy) is not sufficient for CloudFront to read those objects — S3 also needs `kms:Decrypt` on the underlying key, and the shared key's policy (as created by `networking`, which never sets an explicit `policy` argument) only grants the account root, nothing to `cloudfront.amazonaws.com`. Symptom: CloudFront returns a bare `AccessDenied` XML body for objects that exist in the bucket and have a correct bucket policy. Fixed in `edge/kms.tf` via a standalone `aws_kms_key_policy` resource (keyed on `var.kms_key_arn`, not touched by `aws_kms_key.main` in `networking` since that resource never sets its own `policy` argument) that replaces the default policy with one keeping the root-account admin statement and adding `kms:Decrypt` for `cloudfront.amazonaws.com`, scoped via an `AWS:SourceArn` condition to this distribution's ARN specifically.

## What to do next

Phases 3 through 6 are done. Phase 6 hasn't been exercised by a real push yet — worth pushing a trivial `app/` change and watching `deploy.yml` run end to end before moving on, per its own test criteria (zero-downtime rolling deploy, no failed requests while curling `/health` in a loop). After that, pick up Phase 7 (observability): CloudWatch dashboard for ALB latency/5xx, ECS CPU/memory, RDS connections, SQS depth; alarms → SNS → email; X-Ray on the ALB and ECS task; explicit log retention on the CloudWatch log group (currently unset — "never expire").

## Phase 3 — Minimal application + compute tier (done)

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

## Phase 4 — Async layer (done)

**Build:**
- SQS queue + a dead-letter queue (DLQ) for messages that fail repeatedly
- EventBridge rule (or have the app publish directly to SQS — simpler, and still a legitimate design choice you can defend)
- Modify the app: after a successful order write, publish an event
- Lambda worker subscribed to the queue, its own least-privilege IAM role, logs to CloudWatch

**Test:** place an order, then check CloudWatch Logs for the Lambda invocation. Deliberately break the worker (throw an exception) and confirm the message lands in the DLQ instead of disappearing.

---

## Phase 5 — Edge layer (done)

**Build:**
- S3 bucket for static assets and DB backups, versioned, lifecycle rule to transition old backups to Glacier
- CloudFront distribution in front of the ALB
- WAF Web ACL (AWS managed rule groups — Core Rule Set, rate-based rule) attached to the CloudFront distribution
- Optional: Route 53 hosted zone + ACM certificate for a real domain — makes the demo look more finished

**Test:** hit the CloudFront URL instead of the ALB directly; confirm WAF blocks an obvious bad request (e.g. a SQLi-pattern query string) with a 403.

---

## Phase 6 — CI/CD pipeline (done)

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
