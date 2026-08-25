# ShopFlow

A highly available, secure order-processing platform on AWS, built as a hands-on portfolio
project for AWS SAA-C03 prep. The premise: a small e-commerce backend that needs to accept and
process orders reliably, survive an AZ-level failure without dropping requests, and stay
observable and secure enough to defend in a real design review — not a toy that just "works on
one instance." Every layer here is one a real order-processing system would need: a synchronous
API for placing/reading orders, an asynchronous path for post-order processing that shouldn't
block the customer-facing response, a CDN + WAF edge so the origin isn't hit directly, and a CI/CD
pipeline that deploys without ever touching a long-lived AWS credential.

## Architecture

```
                                   Internet
                                      │
                                      ▼
                         ┌─────────────────────────┐
                         │   CloudFront + WAFv2     │  Common Rule Set, SQLi rule set,
                         │  (edge cache + filtering)│  2000 req/5min rate limit
                         └────────────┬─────────────┘
                                      │
                     ┌────────────────┼────────────────┐
                     ▼                                  ▼
          ┌─────────────────────┐          ┌─────────────────────────┐
          │  S3 (static assets) │          │   ALB (public subnets)  │
          │  OAC + SSE-KMS      │          │   /health target check  │
          └─────────────────────┘          └────────────┬─────────────┘
                                                          │
                                            VPC 10.0.0.0/16, 2 AZs
                                                          ▼
                                             ┌─────────────────────────┐
                                             │   ECS Fargate service   │
                                             │   (private subnets,     │
                                             │    ARM64, X-Ray traced) │
                                             └────────────┬─────────────┘
                                                          │
                                   ┌──────────────────────┼──────────────────────┐
                                   ▼                      ▼                      ▼
                        ┌───────────────────┐  ┌───────────────────┐  ┌──────────────────┐
                        │  RDS Postgres      │  │  ElastiCache Redis │  │  EventBridge      │
                        │  Multi-AZ, t4g.micro│  │  2-node, failover  │  │  → SQS → DLQ      │
                        └───────────────────┘  └───────────────────┘  └─────────┬──────────┘
                                                                                  ▼
                                                                        ┌──────────────────┐
                                                                        │ Lambda worker     │
                                                                        │ (ARM64, VPC-attached)│
                                                                        │ → RDS status flip │
                                                                        └──────────────────┘

  GitHub Actions ──(OIDC, no stored keys)──▶ ECR push ──▶ ECS deploy ──▶ smoke test
  GuardDuty · Security Hub · AWS Config · Access Analyzer · VPC Flow Logs (account-wide hardening)
  CloudWatch dashboards + alarms → SNS → email, X-Ray tracing on ALB + ECS task
```

**Synchronous path:** client → CloudFront → WAF → ALB → ECS Fargate (Express API) → RDS (write)
and ElastiCache (cache-aside read, 60s TTL). **Asynchronous path:** after a successful order
write, the app publishes an `OrderCreated` event to EventBridge, which routes it to SQS; a
VPC-attached Lambda worker processes the message and flips the order's status, with a DLQ
catching anything that fails three times.

## Why these choices

- **Fargate over EC2** — no host patching or capacity planning to manage for a project this size;
  the per-vCPU premium is worth it at this scale.
- **RDS Multi-AZ + ElastiCache with automatic failover** — verified, not assumed: Phase 9's chaos
  test forced a real RDS failover and measured a 34-second RDS-side interruption with app-level
  impact confined to a 17-second window.
- **CloudFront + WAF in front of the ALB** — the origin is never hit directly; a dedicated SQLi
  rule group was added after live testing showed AWS's Common Rule Set alone lets `' OR 1=1--`
  through unblocked.
- **GitHub OIDC instead of stored AWS keys** — the deploy role's trust policy is scoped to one
  repo and one branch via the `sub` claim; no long-lived credential exists anywhere in GitHub.
- **Graviton (ARM64) where it's actually cheaper** — checked per-service against AWS's real
  pricing rather than assumed uniformly: ECS and Lambda both run ARM64, RDS runs `db.t4g.micro`;
  ElastiCache was deliberately left on `t3.micro` because Graviton is *pricier* there at this tier.

See [`docs/well-architected-review.md`](./docs/well-architected-review.md) for the full pillar-by-
pillar trade-off writeup and [`docs/cost-breakdown.md`](./docs/cost-breakdown.md) for the actual
`infracost`-sourced numbers (~$136/month).

## Repo structure

```
shopflow/
├── terraform/
│   ├── modules/
│   │   ├── networking/      # VPC, subnets, SGs, KMS key
│   │   ├── data/             # RDS Postgres Multi-AZ, ElastiCache Redis
│   │   ├── compute/           # ECR, ALB, ECS Fargate, autoscaling
│   │   ├── async/               # SQS, DLQ, EventBridge, Lambda worker
│   │   ├── edge/                  # S3, CloudFront, WAFv2
│   │   ├── cicd/                    # GitHub OIDC provider + deploy role
│   │   ├── observability/            # CloudWatch dashboard, alarms, SNS, X-Ray
│   │   └── security/                   # GuardDuty, Security Hub, Config, Access Analyzer, Flow Logs
│   └── environments/dev/       # root module — wires the above together
├── app/                    # Express API (orders CRUD, cache-aside, event publish)
├── worker/                  # Lambda worker (SQS-triggered order processor)
├── .github/workflows/        # OIDC-based CI/CD to ECS
└── docs/                       # chaos test, cost breakdown, Well-Architected review
```

## Setup

Requires Terraform ≥ 1.15, the AWS CLI configured for an account with sufficient permissions, and
Docker (for the first manual image push before CI/CD exists). Everything is pinned to
`us-east-1`.

```bash
# 1. Bootstrap the Terraform backend (S3 state bucket + DynamoDB lock table) once, by hand,
#    before the first `terraform init` — see terraform/environments/dev/backend.tf for the names.

# 2. Apply the network and data layers first
cd terraform/environments/dev
terraform init
terraform apply -target=module.networking
terraform apply -target=module.data

# 3. Build and push the first image (subsequent pushes are handled by CI)
aws ecr create-repository --repository-name shopflow-app --region us-east-1   # or apply -target=module.compute for just the ECR resource first
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
docker buildx build --platform linux/arm64 -t <account>.dkr.ecr.us-east-1.amazonaws.com/shopflow-app:latest ./app --push

# 4. Apply everything else
terraform apply -target=module.compute
terraform apply -target=module.async
terraform apply -target=module.edge
terraform apply -target=module.cicd
terraform apply -target=module.observability
terraform apply -target=module.security

# 5. Apply the DB schema
aws ecs execute-command --cluster shopflow-cluster --task <task-arn> --container app \
  --interactive --command "node migrate.js"
```

```bash
# Smoke test through CloudFront
curl https://<cloudfront-domain>/health
curl https://<cloudfront-domain>/orders -X POST -d '{"customer_id":1,"item":"widget","quantity":2}' -H 'Content-Type: application/json'
curl https://<cloudfront-domain>/orders/<id>
```

After the first apply, `.github/workflows/deploy.yml` handles every subsequent deploy: push to
`main` touching `app/**` → OIDC-authenticated build/push/register/deploy/smoke-test, no manual
steps.

## Docs

- [`docs/chaos-test.md`](./docs/chaos-test.md) — ECS task kill and forced RDS Multi-AZ failover,
  with exact timelines and the app-level gaps they surfaced.
- [`docs/cost-breakdown.md`](./docs/cost-breakdown.md) — `infracost`-sourced monthly cost, top
  drivers, and the architecture decisions that trade cost against resilience.
- [`docs/well-architected-review.md`](./docs/well-architected-review.md) — one paragraph per
  Well-Architected pillar on the actual trade-offs made in this project.
