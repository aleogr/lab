# The instance sleeps

**Date:** 2026-09-21
**Status:** Whether the schedule below is in effect is not this line's to
assert: it flips on this repository's own merge and apply, and can drift from
this document the moment that happens without this line being touched.
`docs/lab.md` is the authority for the window and for whether it is currently
in effect.

The sleep schedule has existed on paper since 2026-09-20.

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

## D2 — `activation_policy` is ignored, not merely absent, in `instance.tf`

`google_sql_database_instance.shared` never names `settings.activation_policy`.
`sleep.tf` is the only thing that changes it, and Terraform is told to leave it
alone with a `lifecycle { ignore_changes = [settings[0].activation_policy] }`
block on the resource — not, as this design first assumed, by simply leaving
the line out.

CI applies this repository's Terraform on every merge to `main`, and if the
running state and Terraform's idea of the state disagree, the apply is what
wins. That much was always the reasoning; it did not change. What changed is
the mechanism, because the first one was wrong.

**The estimate this design first made: that omitting the field would be
enough.** It is recorded here rather than quietly replaced, the same way the
2026-09-20 design's wake-up estimate is recorded next to the measurement that
corrected it — a design that shows only its corrected conclusions teaches
nobody.

Task 3 shipped `instance.tf` with `activation_policy` left out of the
`settings` block and a comment asserting that an absent field is an unmanaged
one. It is not. Checked directly against provider 8.3.0's own schema
(`terraform providers schema -json`): unlike `edition` and `disk_type` in the
same block, which are `optional: true, computed: true`, `activation_policy` is
`optional: true` with no `computed` key at all — Optional but not Computed.
Reproduced directly, not merely inferred from the schema: a `terraform plan`
run against a hand-built state whose `settings.activation_policy` was `NEVER`
— an instance stopped for the night — with the field still absent from
config, proposed

```
~ activation_policy = "NEVER" -> "ALWAYS"
```

as an in-place update, every time, regardless of the prior state. The provider
fills an absent value in with `ALWAYS` rather than leaving it alone. Had this
shipped unchanged, the first CI apply landing inside the window — a
documentation fix merged at 23:00 on a Tuesday is exactly the case D1
worried about — would have woken the instance back up, and `check-instance.sh`
would have shown green immediately afterwards, because it does not read this
field. The schedule would have lost to Terraform in silence, four nights a
week, and nothing in this repository would have said so.

**The fix, verified the same way.** With the `lifecycle` block in place, the
same reproduction — a plan against a state carrying `NEVER`, config unchanged
— no longer proposes anything for `activation_policy`: the attribute drops out
of the plan entirely, into the count of attributes Terraform reports as
unchanged. This is the behaviour D2 always wanted; omission did not produce
it, and `ignore_changes` does.

**What this trades away.** With `ignore_changes`, Terraform does not manage
this field in either direction, not only the direction that mattered here. An
instance stopped by hand outside the schedule and then forgotten stays
stopped; no apply corrects it. That is accepted rather than overlooked: the
schedule in `sleep.tf` is what decides whether the instance is awake, and
`gcp/tools/check-schedule.sh` (Task 4) is what verifies the schedule matches
the design. Nothing in `instance.tf` verifies the instance's current state,
and nothing there was ever meant to.

`ignore_changes` only governs updates to a resource Terraform already manages,
not its creation — irrelevant here, since `google_sql_database_instance.shared`
already exists and is already in state. Nothing else in this repository's
Terraform reads or depends on Terraform's own idea of the instance's current
`activation_policy`: `sleep.tf`'s two jobs send a constant body to the Cloud
SQL Admin API and never read state, and `check-instance.sh` does not assert on
this field either.

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

**Within this repository, the expression itself lives in two operative places
too, and that is also deliberate — a different duplication from the one
above.** `gcp/terraform/sleep.tf` declares the schedule; `.github/workflows/ci.yml`
passes the same two cron strings to `gcp/tools/check-schedule.sh` as its
expectation. Collapsing these into one copy would mean `check-schedule.sh`
reads its expectation out of `sleep.tf`, which is exactly the thing the
Global Constraint that a check must not read its expectation from the thing
it checks (see the plan; `check-federation.sh` is the pattern) rules out —
that check would then always agree with `sleep.tf`, whatever `sleep.tf` said.
**Changing the window means changing both `sleep.tf` and the arguments in
`ci.yml`**, and `docs/lab.md` names both rather than claiming either is the
only place. "Two" counts what is operative — this document and the plan also
quote the expressions for reference, which is not a third place to keep in
step, only a citation of the two that are.

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

This project has the same exposure and no guard for it: `ci.yml` here applies
on every merge to `main` with no equivalent of the marketplace's refusal step,
so a merge landing at 23:00 also applies against a stopped instance. It is
harmless today because `check-instance.sh` asserts neither the instance's
running state nor its `activation_policy` — D2 relies on that omission on
purpose — so there is nothing in this repository's own apply that a stopped
instance could presently break. It stops being harmless the day an apply here
has a genuine settings change to make against the instance inside the window;
that is the day a guard is due, not before, and not one built now on
spec alone.

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

**That this project's Cloud Scheduler needs no App Engine application.**
Current documentation says it does not: an HTTP target, as both jobs in
`sleep.tf` use, is independent of App Engine — only the separate
`app_engine_http_target` type carries that requirement, and `us-central1` is a
supported Cloud Scheduler region for HTTP targets. `services.tf` enables
`cloudscheduler.googleapis.com` and nothing enables App Engine, which is
consistent with that reading. It is documentation, not a live project, so the
first apply is what actually settles it.

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
and what that means for a tenant — and names, rather than repeats, the places
the **expressions** live. That is two operative places, not one:
`gcp/terraform/sleep.tf`, the schedule itself, and `.github/workflows/ci.yml`,
which passes the same crons to `check-schedule.sh` as the expectation it
checks the schedule against — a second copy that D4 requires rather than
tolerates, since a check may not read its expectation from the thing it is
checking. Changing the window means changing both. Neither count includes
this document or the plan, which quote the expressions for reference rather
than acting on them.
