# The instance sleeps

**Date:** 2026-09-21
**Status:** agreed, not yet implemented

The sleep schedule has existed on paper since 2026-09-20 and nothing implements
it. `lab-postgres` has run continuously since the day it was created, and every
document that describes the window now says, correctly, that it is not in
effect.

This design decides the **mechanism**: what stops and starts the instance, what
happens to the work that runs while it is asleep, and what a deployment does
when it arrives to find the database off.

## What this does not decide

`docs/superpowers/specs/2026-09-20-shared-database-instance-design.md` already
decided the window and the reasons for it, and none of it is reopened here:

```
start  07:30  Tue–Fri   30 7 * * 2-5
stop   22:00  Mon–Thu    0 22 * * 1-4
time_zone = "America/Sao_Paulo"
```

Four nights, not five. Friday night and Sunday night stay awake. The start is
before 08:00 because a stopped instance does not answer the moment it is asked
to — it was 07:45 on an estimate, and moved to 07:30 when the estimate was
measured and found wrong by an order of magnitude. The backup window is 12:00
UTC because a stopped instance runs no automated backup. All of that stands.

`schooling` is also out of scope. It has not moved onto this instance, its
migration is a separate piece of work coordinated with its own repository, and
the two nightly jobs the 2026-09-20 spec lists as its own are not this
design's to move. What is decided here applies to the tenants that are on the
instance today, which is `marketplace` alone.

## D1 — Cloud Scheduler calls the Cloud SQL Admin API directly

Two `google_cloud_scheduler_job` resources in this project, one to stop and one
to start, each with an `http_target` pointing at
`https://sqladmin.googleapis.com/v1/projects/<project>/instances/lab-postgres`,
method `PATCH`, body `{"settings":{"activationPolicy":"NEVER"}}` and
`{"settings":{"activationPolicy":"ALWAYS"}}`, authenticated with an
`oauth_token` from a service account of their own.

No code, no container, no build, no dependency, nothing to keep up to date.

**Why not a Cloud Function.** Scheduler → Pub/Sub → Function is the shape
Google's own documentation reached for, and it buys nothing here: a runtime, a
deployment, a language version and a piece of source to maintain, all to issue
one HTTP request that Scheduler can issue itself. It is also at odds with this
repository's own rule that nothing here builds or deploys anything.

**Why not a scheduled GitHub Actions workflow.** It would put a cron in the one
repository that holds a federation able to change a GCP project, and GitHub's
scheduled workflows are delayed under load — routinely by minutes, sometimes by
more. A schedule that sleeps at 22:14 because a queue was busy is not a
schedule. `CLAUDE.md` already forbids adding workflows here for the adjacent
reason.

**A failed start matters more than a failed stop.** An instance that fails to
stop costs a few reais and nothing else; an instance that fails to start means
the day begins against a dead database. The two jobs are configured
accordingly, and the start job retries.

**Nobody is watching Cloud Scheduler.** A start that fails every morning would
be discovered by a person trying to work. The index page at `lab.aleogr.dev`
already probes each project's `/health` and shows `database: unreachable`
during the window, so a morning where the instance did not come back is visible
in the same place, in the same way — which is worth more than an alert nobody
configured.

## D2 — `activation_policy` is deliberately absent from `instance.tf`

`google_sql_database_instance.shared` does not declare
`settings.activation_policy`, and that is now a decision rather than an
accident.

CI applies this repository's Terraform on every merge to `main`. If the
configuration named `ALWAYS`, a merge at 23:00 would wake the instance and the
schedule would lose to Terraform every time somebody shipped a documentation
fix. Leaving the field out makes the running state the only authority on
whether the instance is awake, which is what a schedule needs.

The field gets a comment saying so. A future reader who "completes" the
settings block by adding it would silently disable the schedule.

## D3 — The sleeper has its own role, and it can do more than sleep

A service account of its own, `sleeper@`, holding a second custom role beside
`sqlTenant`, with its permissions named rather than inherited from
`roles/cloudsql.admin`:

```
cloudsql.instances.get
cloudsql.instances.update
```

No `delete`, no `databases.*`, no `users.*`.

**And it is not as narrow as its name.** Cloud SQL has no "may start and stop"
permission: starting an instance is `instances.patch`, which is
`cloudsql.instances.update`, which is also the permission that resizes the
disk, rewrites the backup schedule and turns deletion protection off. The role
is the smallest GCP offers and it is still larger than the job. This is stated
here for the same reason D8 of the 2026-09-20 design is stated: a boundary
described as tighter than it is will be trusted for something it does not do.

What contains it is that it lives in this project, is held by a Cloud Scheduler
job whose body is a constant, and is granted to nothing else.

## D4 — The laboratory publishes the window; each tenant arranges its own work around it

Anything that runs between 22:00 and 07:30 and touches the database is the
tenant's to move, in the tenant's own repository. This repository does not
reach into a tenant's Cloud Scheduler, for the same reason it does not declare
a tenant's database: a house that reorganises the furniture in a room it rents
out is not holding a boundary.

That means the window is written in two places — `docs/lab.md` here, and a cron
expression in each tenant — and the duplication is inherent rather than
sloppy. Whoever lives on an instance that sleeps has to know when. `docs/lab.md`
is the source; a tenant's cron is derived from it, and a change to the window
is a change every tenant has to be told about.

## D5 — `dispatch-outbox` does not run while the instance sleeps

`aleogr/marketplace` declares `dispatch-outbox` as `* * * * *` in `Etc/UTC`:
every minute of every day, and its handler reads the outbox from the database.
Against a sleeping instance that is roughly 585 failed executions a night, each
with one retry, four nights a week.

It becomes `* 8-21 * * *` in `America/Sao_Paulo`: every minute from 08:00 to
21:59 local, which is inside the awake period on every day of the week.

**The job does not run because the thing it needs is deliberately off.** That
is the honest shape. The alternatives were considered and rejected: letting it
fail turns a job dashboard into something nobody reads, and then a real failure
hides among the expected ones; making the handler return success when the
database is unreachable hides a genuine outage exactly as well as it hides a
planned one.

**What it costs.** An event written at 23:00 waits until 08:00. The outbox
carries mail, in a laboratory, at night. The expression also stops dispatching
on Friday, Saturday and Sunday nights, when the instance is in fact awake —
accepted, because one cron expression that is always safe is worth more than
four that are exactly right.

## D6 — A deployment inside the window fails, and says why

The 2026-09-20 design said the deployment workflow would start the instance and
wait for it. That is no longer possible without breaking something newer and
more considered: starting an instance needs `cloudsql.instances.update`, and
`sqlTenant` excludes that permission on purpose — the comment in
`tenant_role.tf` says a tenant "cannot remove the instance, resize its disk,
change its backup schedule or stop it". The marketplace's deploy identity holds
nothing at all on this project today.

**The role wins.** Granting a tenant the power to start the shared instance is
granting it the power to stop it, and this repository exists to hold that line.

So a merge inside the window fails, and the two workflows that would fail —
`terraform.yml`, which declares the tenant's database and users against a
stopped instance, and `deploy.yml`, which runs the migration job — are made to
fail legibly rather than cryptically: a check that reads the instance's state
and stops with a message naming the window and the next start time, in place of
a connection timeout or a 400 from the Cloud SQL API. The previous revision
keeps serving, and re-running in the morning is the whole remedy.

The cost is bounded by the same fact that chose the window: the owner works
between 08:00 and 22:00, so merging at 23:00 on a Tuesday is rare by
construction.

**If this ever becomes a real obstacle**, the upgrade is a narrow "wake" in this
project — an endpoint or a job whose only power is to set `ALWAYS`, callable by
tenants — and not a wider grant. It is not built now because nothing yet
justifies a subsystem.

## What must move

| what | today | becomes | whose |
|---|---|---|---|
| `verify-audit-chain` | `17 4 * * *` `Etc/UTC` — 01:17 local, inside the window | `17 12 * * *` `Etc/UTC` — 09:17 local | `aleogr/marketplace` |
| `dispatch-outbox` | `* * * * *` `Etc/UTC` | `* 8-21 * * *` `America/Sao_Paulo` | `aleogr/marketplace` |
| automated backup | already `12:00` UTC | unchanged | `aleogr/lab` |

The backup window was moved to noon when the instance was created, ahead of the
schedule that makes it necessary. Nothing to do.

## What is not verified, and must be before this is called done

**That Cloud Scheduler's `oauth_token` authenticates against
`sqladmin.googleapis.com`.** It is what the documentation describes for calls
to Google APIs, and it is not something a session without `gcloud` can prove.
The first night is the proof, not the first apply: a job can exist, be enabled,
carry the right cron and the right body, and still be refused the first time it
fires.

**And the job's own result will not tell the whole truth.** The Admin API's
`PATCH` returns an operation immediately rather than blocking until the
instance has changed state — which the measurement below makes concrete, since
`gcloud` gave up waiting after 600 seconds on an operation that succeeded. So
Cloud Scheduler records that the request was **accepted**, not that the
instance **started**. Its `status.code` proves the authentication and nothing
beyond it. What proves the instance woke is `/health` and the index page, which
is where the check belongs anyway.

It also settles `attempt_deadline`: the job does not wait out the operation, so
320 seconds is generous rather than tight.

## What was verified

**How long a stopped instance takes to accept connections: 686 seconds.**
Measured on 2026-09-21, from issuing `activation-policy=ALWAYS` to
`marketplace.lab.aleogr.dev/health` answering `database: ok` — against the
service rather than against the API's opinion of itself, which is the only
reading that means anything here. Stopping took 55 seconds.

The 2026-09-20 design had estimated "a minute or two". It was wrong by between
six and eleven times, and 07:45 survived only by three and a half minutes. The
start moved to 07:30 for a margin that does not depend on a sample of one.

## Risks

**A silent failure to start.** Mitigated by the index page rather than by an
alert: a morning with `database: unreachable` on `marketplace.lab.aleogr.dev`
is the signal, and it is already built.

**A tenant added later that nobody tells about the window.** The window lives
in `docs/lab.md` and a new tenant's own jobs are its own to arrange. The
mitigation is that `docs/lab.md` is where a tenant is told what the laboratory
does to it, and it says this.

**The cron and the documentation drifting apart.** Two places, by D4. The
Terraform is executable and the document is prose, so the Terraform will be
right and the prose will be stale — which is the failure this repository spent
2026-09-21 correcting six times over. The division is therefore explicit:
`docs/lab.md` states the **policy** — four weeknights, 22:00 to 07:30 local,
and what that means for a tenant — and names the Terraform file as the place
the **expressions** live, without repeating them. A cron expression appears
exactly once in this repository.
