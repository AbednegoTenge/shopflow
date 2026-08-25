# Well-Architected review — Phase 10

One paragraph per pillar, focused on the actual trade-offs made in this project rather than a
generic AWS pillar summary. See [`cost-breakdown.md`](./cost-breakdown.md) for the numbers
referenced below and [`chaos-test.md`](./chaos-test.md) for the reliability data.

## Operational Excellence

Everything is provisioned through Terraform in per-phase modules (`networking`, `data`,
`compute`, `async`, `edge`, `cicd`, `observability`, `security`), mirroring the project's phased
delivery plan — each module was built, applied, and verified independently before the next
phase started, which is also why `environments/dev` can still be applied module-by-module today
if only one part of the stack needs touching. App deploys are automated via GitHub Actions over
OIDC — no long-lived AWS keys stored anywhere. The ECS deployment circuit breaker with
auto-rollback exists specifically because of a real incident: a bad amd64 image (a
GitHub-hosted-runner/ARM64-Fargate architecture mismatch) looped 40 failed task starts before
being caught, and that gap is now closed structurally rather than by "remembering to check."
CloudWatch alarms, dashboards, and X-Ray tracing (Phase 7) give real operational visibility
rather than relying on manual log-tailing when something goes wrong.

## Security

Defense runs in layers rather than at one chokepoint: a security-group chain where nothing skips
a tier (`alb-sg` → `ecs-sg` → `rds-sg`/`cache-sg`), WAF at the edge with both the AWS Common Rule
Set and a *dedicated* SQLi rule group (added after live testing showed the Common Rule Set alone
lets `' OR 1=1--`-style payloads straight through — it covers OWASP generics, not SQLi
specifically), Secrets Manager with AWS-managed rotation instead of any hardcoded credential, and
IAM scoped tightly enough that Access Analyzer's Phase 8 scan found only one project-related
finding — the GitHub OIDC deploy role — and that one is a correctly-scoped `sub`-claim condition
limiting it to a single repo and branch, not a gap. Phase 8 added GuardDuty, Security Hub (backed
by AWS Config, since most Security Hub controls need Config's resource snapshots to evaluate
anything), and VPC Flow Logs on top of that. The one deliberate gap: CloudFront terminates HTTPS
at the edge, but CloudFront-to-ALB traffic is still plain HTTP, since the ALB has no ACM
certificate — accepted because that hop stays inside AWS's backbone rather than the public
internet, not because it's free of trade-offs.

## Reliability

The chaos test (Phase 9) is the honest answer to this pillar, not a claim. Killing one of two
ECS tasks caused zero application-level errors across 116 logged requests, because the ALB simply
routed around it while ECS took ~78 seconds to replace it. A forced RDS Multi-AZ failover was
faster than expected (34 seconds RDS-side, against the commonly-quoted 60–120s), with real
application impact — 4 failed `POST /orders` — confined to a 17-second window. That test also
surfaced a genuine gap: the app has no retry logic on the write path, so a transient DB failure
during failover surfaces straight to the caller as a 500 instead of being retried transparently.
That's a deliberate trade-off for a project this size (client-visible failure over hidden retry
complexity), not an oversight, and it's named explicitly rather than left implicit. The other
known reliability gap is structural: the single NAT gateway lives only in `us-east-1a`'s public
subnet, so a full outage of that AZ would cut outbound internet access for `us-east-1b`'s private
subnets too — accepted for cost rather than fixed with a second NAT gateway per AZ.

## Performance Efficiency

Fargate over self-managed EC2 trades a per-vCPU cost premium for zero host patching or capacity
planning — the right trade at this scale, where operational overhead costs more than the compute
markup. Both compute surfaces run on Graviton (ARM64): the ECS task definition and, as of this
revision, the Lambda worker as well — verified against AWS's own Fargate/Lambda pricing (not
just assumed), ARM64 runs ~20% cheaper per vCPU-hour, per GB-hour, and per GB-second than the
x86_64 equivalent, with identical per-request pricing. `pg` has no native bindings and the AWS
SDK v3 client is architecture-agnostic, so the Lambda switch was a zero-risk change. Getting the
ECS side onto ARM64 in CI cost a real debugging session, since GitHub's hosted runners are
amd64-only and needed QEMU emulation via `docker buildx --platform linux/arm64` to cross-build
correctly. ElastiCache's cache-aside pattern (60s TTL, invalidated on write) keeps hot reads off
RDS, and CloudFront + WAF filter and cache traffic before it ever reaches the ALB. ECS
auto-scaling is CPU-target-tracking at 60%: reactive, not predictive, which is a fine trade for
traffic at this scale.

## Cost Optimization

`infracost` against the live Terraform config is the source of truth here (see
`cost-breakdown.md`) — not a manually-assembled spreadsheet. The three resources that actually
drive the bill are the NAT gateway, RDS, and ElastiCache; everything else in the stack (Lambda,
SQS, S3, IAM, GuardDuty, Config, Access Analyzer, CloudWatch alarms) is free or close to it at
this traffic level. Within that: a single NAT gateway instead of one per AZ is the biggest
single lever, accepted at the cost of the AZ-b single-point-of-failure noted under Reliability.
RDS and ElastiCache are both already on the smallest instance size either service offers —
neither has a "nano" tier the way EC2 does, so `.micro` is the floor, not a choice left on the
table. Architecture (not size) was the remaining lever: switching RDS to `db.t4g.micro` saves
real money (Graviton is genuinely cheaper there), but the same swap was deliberately *not* made
for ElastiCache — AWS actually prices `cache.t4g.micro` higher than `cache.t3.micro` at this tier
in `us-east-1`, so "ARM is cheaper" doesn't hold universally and was verified per-service rather
than assumed. Demand spikes — autoscaling pulling in extra ECS tasks, a burst of Lambda
invocations, a traffic surge through the ALB/WAF — aren't treated as a material cost risk here:
they're short, bounded events (hours, not days), running on top of a fixed 24/7 baseline (NAT
gateway, RDS, ElastiCache, ALB) that dominates the bill regardless of traffic. A few hours a
month of extra Fargate task-time or Lambda invocations doesn't meaningfully move a bill whose
floor is already set by always-on infrastructure, so this project doesn't over-engineer for
spike cost the way it does for spike *reliability*.

## Sustainability

The two levers that most directly reduce this project's footprint are also the ones already
covered by other pillars: Fargate's shared-tenancy model means idle capacity isn't sitting
dedicated to this workload between requests the way a fixed EC2 fleet would be, and Graviton
(ARM64) — now used for both ECS and Lambda — measurably uses less power per unit of compute than
comparable x86 instances, so the same architectural choice that helps Performance Efficiency and
Cost Optimization also cuts energy draw. The single NAT gateway and `.micro`-tier RDS/ElastiCache
sizing reduce the physical resource footprint the same way they reduce cost, at the same
reliability trade-offs already named above — right-sizing for actual demand rather than
provisioning headroom "just in case" is the sustainability story here, not any offline/idle-time
behavior.
