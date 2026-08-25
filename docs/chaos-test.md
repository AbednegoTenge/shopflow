# Chaos test — Phase 9

Date: 2026-08-25. Two experiments run back to back against the live stack, with a background
process hitting `GET /health` and `POST /orders` through the ALB once per second throughout
(`shopflow-alb-1629690266.us-east-1.elb.amazonaws.com`), logging HTTP status and latency for
every request. 512 requests logged across both experiments; raw data in
[`chaos-test-log.csv`](./chaos-test-log.csv) (`timestamp,endpoint,http_status,latency_s`).

## Experiment 1 — kill a running ECS task

**Setup:** service steady at 2/2 tasks, 2/2 healthy targets.

**Expected:** the ALB should route around the dead task using the surviving one, so
application-level impact should be at or near zero, even though it will take ECS some time
(new task placement → image pull → health checks → target registration) to get back to 2/2.

**What I did:** `aws ecs stop-task` on one of the two running tasks, then polled ECS/target
group state every 5s until back to 2 running + 2 healthy.

**Timeline (from ECS service events):**

| Time (UTC) | Event |
|---|---|
| 16:32:09 | `stop-task` issued |
| 16:32:39 | old target deregistered, connection draining begins |
| 16:32:40 | replacement task started |
| 16:33:18 | replacement task's target registered (passed ALB health check) |
| 16:33:27 | service reports steady state |

Total ECS-level recovery: **~78 seconds** from stop command to steady state.

**Application-level impact:** 116 requests logged during the window (16:32:00–16:34:00),
covering the full kill-and-replace cycle. **Zero non-2xx responses.** Every request that hit
the ALB during those 78 seconds landed on the surviving task.

**Verdict:** matched expectations exactly. This is the whole point of running `desired_count = 2`
behind an ALB target group — no surprises here.

## Experiment 2 — forced RDS Multi-AZ failover

**Setup:** RDS `available`, primary in `us-east-1b`, standby in `us-east-1a`.

**Expected:** RDS Multi-AZ failover is normally quoted at 60–120 seconds. I expected a clear
window where every DB-touching request (`POST /orders`) fails — either as a connection
timeout or a 500 — followed by a clean recovery once the standby is promoted and DNS for the
endpoint repoints. I expected `GET /health` to be unaffected, since I didn't think it touched
the DB — I hadn't actually checked.

**What I did:** `aws rds reboot-db-instance --db-instance-identifier shopflow-db --force-failover`,
then pulled the authoritative timeline from `aws rds describe-events` (my own polling loop had
a shell bug — `status` is a read-only variable in zsh — that cost a few minutes of coarse
5-second polling before I caught it and switched to reading RDS's own event log instead, which
turned out to be the better source of truth anyway).

**Timeline (from RDS events):**

| Time (UTC) | Event |
|---|---|
| 16:35:17 | `reboot --force-failover` issued |
| 16:35:27 | Multi-AZ failover started |
| 16:35:40 | DB instance restarted |
| 16:36:11 | Multi-AZ failover completed |

Total RDS-side failover: **34 seconds** (16:35:27 → 16:36:11), roughly a third of the
commonly-quoted upper bound. AZ confirmed flipped afterward: primary now `us-east-1a`,
standby `us-east-1b`.

**Application-level impact**, from the request log:

| Time (UTC) | Endpoint | Result |
|---|---|---|
| 16:35:23 | `POST /orders` | timeout (curl `000`, 3.0s — hit the client's own timeout cap) |
| 16:35:27 | `POST /orders` | timeout (`000`, 3.0s) |
| 16:35:32 | `POST /orders` | timeout (`000`, 3.0s) |
| 16:35:37 | `POST /orders` | `500` — pool rejected the query, app returned its own error |
| 16:35:40 | `POST /orders` | `201` — recovered |
| all of the above | `GET /health` | `200` — never once failed |

**4 failed `POST /orders` out of 512 total requests logged (0.78% overall error rate)**,
concentrated entirely in a **17-second window** (16:35:23 → 16:35:40) — tighter than RDS's own
34-second failover window, since the primary appears to start rejecting new connections before
the failover is officially logged as "started." Zero data corruption: each failed request was a
single `INSERT ... RETURNING id`, so failures just didn't insert a row — no partial writes to
clean up.

## The real surprise

**`GET /health` returned 200 through the entire RDS outage.** Looking at why: it's implemented
as a pure liveness check —

```js
app.get('/health', (req, res) => res.status(200).send('OK'));
```

— it doesn't touch the DB, Redis, or anything else. I expected this endpoint to reflect actual
service health and was wrong; it only proves the Node process is alive and listening.

This matters because it's the same endpoint the ALB target group uses to decide whether a task
is healthy. During the failover, ECS had zero reason to believe anything was wrong — which,
looking at it after the fact, is actually the *correct* behavior, not a bug: the app process was
never unhealthy, only one of its downstream dependencies (RDS) was briefly unavailable. If
`/health` did check DB connectivity, a routine RDS failover would have caused ECS to conclude
**both** tasks were unhealthy simultaneously (they share the same RDS instance) and cycle them
— replacing perfectly good containers, adding ECS-level churn on top of an outage that was
already going to self-resolve in under 40 seconds, and potentially masking the real signal
(“RDS is down”) behind a misleading one (“the app is down”).

## What I changed afterward

Nothing in the code. I considered adding a deep `/ready`-style check that pings the DB, but
concluded it should never back the ALB target group's health check for the reason above — a
shared downstream dependency failing shouldn't cause every task to be torn down and replaced.
If I revisit this, the right shape is a **separate** diagnostic endpoint (not wired into the
target group) for manually checking DB/cache connectivity, not a change to `/health` itself.

The one real gap this test exposed: **the app has no retry logic on the write path.** A single
transient `pool.query` failure during failover is an immediate 500 to the caller, with no
backoff/retry. For a 17-second window this is a defensible trade-off for a project this size —
the client (or a real caller) can just retry the POST — but it's worth naming explicitly rather
than leaving it implicit: this system tolerates RDS failover by exposing it to the client, not
by hiding it.

## Numbers, for reference

- Total requests logged across both experiments: 512
- Total non-2xx responses: 4 (all `POST /orders`, all during the RDS failover)
- `GET /health` error rate: 0% (0/256)
- ECS task-kill recovery time (stop command → steady state): ~78s
- RDS forced-failover time (RDS-reported): 34s
- RDS forced-failover application-level impact window: 17s
