# Cost breakdown — Phase 10

Source of truth: `infracost inspect`, run against the live Terraform config in
`terraform/environments/dev` (`us-east-1`). This reflects the architecture as coded, not a
manually-assembled estimate — it prices every resource against AWS's published on-demand rates.

## Total

**$136/month**, 107 resources scanned (39 priced, 68 free).

| Resource | Monthly cost |
|---|---:|
| `aws_nat_gateway.nat-gw` | $33 |
| `aws_db_instance.shopflow` (RDS, Multi-AZ) | $31 |
| `aws_elasticache_replication_group.cache` (2-node, automatic failover) | $25 |
| `aws_ecs_service.app` (2 Fargate tasks, ARM64) | $18 |
| `aws_lb.app` (ALB) | $16 |
| `aws_wafv2_web_acl.main` | $8 |
| `aws_cloudwatch_dashboard.main` | $3 |
| `aws_kms_key.main` | $1 |
| Everything else (Lambda, SQS, S3, IAM, Secrets Manager, GuardDuty, Config, Access Analyzer, CloudFront, alarms, ...) | $0–low cents each |

Three resources — the NAT gateway, RDS, and ElastiCache — account for **$89 of the $136**, or
about two-thirds of the bill. Everything downstream of those (compute, edge, security tooling,
observability) is comparatively cheap at this scale.

## Known limitation: local pricing cache

This `infracost` install has a stale local pricing cache for RDS instance-class changes — verified
by swapping `aws_db_instance.shopflow`'s `instance_class` all the way up to `db.m5.large` (a far
pricier class) and seeing the identical $136 total both before and after. So the $31 RDS figure
above does **not** reflect the `db.t4g.micro` (Graviton) instance class this project currently
uses. Cross-checked directly against `aws pricing get-products` instead: `db.t4g.micro` runs
**$0.016/hr** vs. `db.t3.micro`'s **$0.018/hr** (Postgres, Single-AZ) — real Graviton savings of
about **$2.92/month** on the Multi-AZ instance, not reflected in the table above. Net effect: the
true current total is closer to **$133/month**, not $136.

The same direct-pricing check was run for ElastiCache before switching architecture there:
`cache.t4g.micro` is actually **more expensive** than `cache.t3.micro` in `us-east-1`
($0.016/hr vs. $0.014/hr) — so ElastiCache was deliberately left on `t3.micro` rather than
following the same Graviton swap made for RDS and the compute layer. "ARM is cheaper" doesn't
hold universally; it was checked per-service against real pricing rather than assumed.

## Demand-driven cost variance

Autoscaling events, Lambda invocation bursts, and ALB/WAF traffic spikes are not treated as a
material cost risk in this breakdown. They're short, bounded windows — hours, not days — layered
on top of a fixed 24/7 baseline (NAT gateway, RDS, ElastiCache, ALB) that already accounts for
$89 of the $136 total regardless of traffic. A few extra hours a month of Fargate task-time or
Lambda GB-seconds during a genuine high-demand period doesn't meaningfully move a bill whose
floor is set by always-on infrastructure, not by request volume.
