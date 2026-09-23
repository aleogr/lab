# Schooling moves in

**Date:** 2026-09-23
**Status:** Stages 1–3 implemented on 2026-09-23; Stage 4 in cool-down until at
least 2026-09-30. What happened is recorded under "What was measured" below
and in the plan's status block.

`marketplace` has lived on `lab-postgres` since 2026-09-21, and the instance
has slept four weeknights since the same day. `schooling` still lives on an
instance of its own, in `aleogr-schooling`. This design moves it.

## What this does not decide

`docs/superpowers/specs/2026-09-20-shared-database-instance-design.md` decided
that both laboratories consolidate onto one instance (its D1), and its Phase 2
decided how the data moves: freeze, photograph the source with
`tools/restore-drill/verify.sql`, `pg_dump --no-owner`, `psql` into the target,
photograph the target, diff the two reports, cut over, unfreeze. None of that
is reopened.

`docs/superpowers/specs/2026-09-21-sleep-schedule-design.md` decided the
sleep mechanism and the window, Monday through Thursday, 22:00 to 07:30 local.
That stands too.

## What changed since the plan was written

Four things the 2026-09-20 design did not know, each found by reading the
world rather than the plan. The last three came from a read-only inventory of
`codeschool-ing/schooling` made by that repository's own session on
2026-09-22.

**The order inverted.** The 2026-09-20 plan put the sleep schedule last, as
Phase 4, after `schooling` had moved. The schedule went live first. So
`schooling` has to be ready for a sleeping instance *before* it moves, not
after — its nightly jobs, its alert and its deployment all assume a database
that never goes away.

**The rollback in the 2026-09-20 plan is wrong for `schooling`.** It says
reverting is "one variable goes back" and "a new version of the
`schooling-database-url` secret". It is neither: the instance is written into
five Cloud Run resources as `cloud_sql_instance { instances = [...] }`, and the
host inside the secret is `/cloudsql/<connection name>`. Reverting today is an
apply touching five resources plus a new secret version.

**The connections do not fit.** `lab-postgres` is a `db-f1-micro` with
`max_connections = 25`, read from the live instance on 2026-09-21. Three are
reserved for the actual superuser, which a tenant's user is not, leaving 22.
`marketplace` holds a `CONNECTION LIMIT` of 14, which leaves **8**.
`schooling`'s declared peak, read from its code, is **24**: the API at
`MaxConns = 4` across `max_instance_count = 4`, plus `migrate` and `load` at 4
each during a deployment. `schooling` alone does not fit on the instance, even
with `marketplace` idle.

*Correction, 2026-09-23:* the real worst case was **44**, not 24. The sum
above left out the old and the new revision serving side by side during a
rollout (2 × 4 × 4 = 32) and the two nightly jobs; two tags pushed close
together could reach 48. `codeschool-ing/schooling`'s session found it while
fitting the pool (its PR #418).

The 2026-09-20 design reserved 10 for `schooling`. When `marketplace`'s ceiling
was measured and raised from 10 to 14, nobody redid the sum.

**A restore cannot be isolated to one tenant.** Cloud SQL backups and
point-in-time recovery belong to the instance, not to a database. There is no
"restore only the `schooling` database". And `schooling`'s restore drill —
`tools/restore-drill/restore-drill.sh`, the one piece of that repository that
has turned a belief about backups into a fact — clones the instance, which
`sqlTenant` does not permit.

## D1 — Ready for the night first, then move

Every change `schooling` needs is made on the instance it has today, one at a
time, each verified while the old database still serves. Only then does the
data move, and the day it moves, moving the data is the only thing that
happens.

This is the 2026-09-20 design's own D6 applied again: doing several things at
once means a failure could be any of them, with no way to tell which.

The alternative of not moving `schooling` at all — letting its own instance
sleep alone — was considered. It keeps the isolated restore intact and costs
roughly R$ 30 a month more than consolidating. It was set aside because it
reopens D1 of the 2026-09-20 design, which the owner did not want to reopen.

## D2 — `schooling`'s pool shrinks to fit 8

The ceilings are designed to sum to the instance's capacity, 14 + 8 = 22, so
that neither tenant can starve the other. `CONNECTION LIMIT` is a cap and not a
reservation; the point of the sum is that the worst case — both deploying at
once — still fits.

`schooling`'s own configuration changes to reach a peak of at most 8 — the
number of connections per process and the number of API instances, both
configuration in its repository. A laboratory without students does not need
four API instances holding four connections each.

The exact values are set after measuring, not before. `schooling` has never
measured its real usage, because until now it never mattered. The spec commits
to the ceiling, not to the split inside it.

A larger tier or a raised `max_connections` flag were rejected: the first costs
most of what consolidating saves, and the second trades an explicit limit for
the risk of a `db-f1-micro` with 0.6 GB of memory running out of it and taking
both tenants down together.

## D3 — Restore is of the whole instance, and it is the owner's to run

A restore of `lab-postgres` overwrites every database on it. Restoring
`schooling` to yesterday at 15:00 also returns `marketplace` to yesterday at
15:00, and whatever `marketplace` wrote since is lost.

**The owner accepted this on 2026-09-23**, for laboratories. It is D1 of the
2026-09-20 design doing its job: this arrangement is only allowed because
both tenants are laboratories, and the day either becomes production it
leaves, and this cost leaves with it.

The one per-tenant path that exists is indirect — clone the instance to a
point in time, which creates a new instance and does not touch the original;
`pg_dump` only the one database from the clone; `pg_restore` it into
`lab-postgres`; delete the clone. It works, it needs tooling neither
repository has, and cloning needs a permission a tenant does not hold. It is
recorded here as the route if one is ever needed, not built.

`schooling`'s restore drill is already the owner's to run: the script says it
runs from Cloud Shell, with credentials that administer Cloud SQL, and never
from CI. After the move it has to stay that way, because cloning `lab-postgres`
is what `sqlTenant` denies. `verify.sql` discovers its tables from the database
it connects to, so pointed at the `schooling` database inside a clone of
`lab-postgres` it reports on `schooling` and nothing else. The one thing that
changes is where it looks: the instance is in `aleogr-lab-shared-dacd` and the
secret stays in `aleogr-schooling`, so the secret is named by its full resource
name.

**A restore is never tested over the live instance.** Taking a backup, making a
small change and restoring over it was considered on 2026-09-23 and set aside:
it takes the database down for the length of the restore, discards every write
since the backup, and if the restore fails, what it broke is the database in
use. The drill restores into a new instance and only ever reads the live one,
which proves the same backup without any of that.

**What a restore of `schooling` loses, read from its code on 2026-09-23.** Not
the course content. The nineteen `catalog_*` tables are written by `cmd/load`
alone, from `content/` in the repository, and their keys are text identifiers
taken from the files, so a reload after a restore rebuilds the same catalogue
under the same keys and nothing that points at it is orphaned. What is lost is
every write since the restored moment that exists only in the database:
accounts and sessions, study progress, practice, exams, notes, ratings,
certificates, subscriptions and the ledger, the append-only event stream, the
audit log and the record of job runs. The nightly analysis recomputes its own
output from the answers that remain.

## D4 — The backup window does not need to move

`schooling`'s inventory listed moving its 04:00 backup out of the window as a
blocker. (04:00 local, `start_time = "07:00"` UTC, is the start of a four-hour
window, not the time: the backups on 2026-09-20 to 2026-09-22 began between
08:11 and 09:33 UTC.) It is not one. A backup belongs to an instance: after the move, the
`schooling` data is backed up by `lab-postgres`, at 12:00 UTC, the window
chosen on 2026-09-20 precisely because a stopped instance runs no backup — and
observed producing backups on 2026-09-21 and 2026-09-22. The 04:00 setting
describes an instance that is about to be stopped.

## D5 — The two nightly jobs move to 08:10 and 08:40

`schooling-analyse-nightly` at 03:10 and `schooling-settle-nightly` at 03:40
fall inside the window four nights a week. They move to 08:10 and 08:40 local,
the hours already in the 2026-09-20 design's table, keeping the thirty minutes
between them and the `America/Sao_Paulo` zone both comments argue for.

What their failure costs was established by `schooling`'s own session and is
worth keeping: `settle` failing delays reports; `analyse` failing delays the
withdrawal of a broken question from circulation, which is the one thing that
platform does without a person. And a failed run is invisible — the `job_runs`
row that would record it is written to the database that is off.

## D6 — The readiness alert is silenced inside the window

`schooling`'s `/readyz` is probed every 300 seconds and answers 200 only when
the pool pings; its alert policy fires on two failed probes sustained for 600
seconds. Inside a nine-and-a-half-hour window it would fire every night, and
`infra/monitoring.tf` itself argues that a daily false alarm is worse than
none.

The alert is disabled at 22:00 and re-enabled at 08:00 on the nights the
instance sleeps, by two Cloud Scheduler jobs in `schooling`'s own project — the
same mechanism `aleogr/lab` uses for the instance, applied by the tenant to the
tenant's own alert. By D4 of the sleep design, the laboratory publishes the
window and each tenant arranges its own work around it; this repository does
not reach into `schooling`'s monitoring.

08:00 and not 07:30, the minute the instance is started: it was measured
taking 686 seconds to answer after a start, so re-enabling the alert at 07:30
would arm it against ten minutes of probes that are expected to fail, and a
policy that fires on 600 seconds of failure would fire. The same measurement is
why D5's jobs start at 08:10.

## D7 — The deployment refuses a sleeping instance, legibly

`schooling`'s release workflow runs `migrate` and `load` as gates after pushing
images. A release inside the window fails at the `migrate` gate with a raw
`pgx` or Cloud SQL error, after the images are already pushed — the failure
mode `aleogr/marketplace` removed on 2026-09-21. The same preflight is copied:
read the instance's `activationPolicy` before anything else, and stop with a
sentence naming the window if it is not `ALWAYS`.

The release runs as `schooling-deploy@aleogr-schooling`, which holds nothing on
the shared project. Reading the instance needs `cloudsql.instances.get` there,
so `aleogr/lab` grants that identity `roles/cloudsql.viewer` — read, and
nothing that connects or writes.

The instance the preflight reads is one literal in `release.yml`,
`DATABASE_CONNECTION`, not `var.database_instances`: the workflow does not
read Terraform, and during the move that list names two instances while the
data lives in one. It was switched to `lab-postgres` in the change that
mounted both (Stage 2), so the cutover edited nothing in the repository.

## D8 — The instance becomes a variable, and both are mounted during the move

The five Cloud Run resources take the connection name from a variable instead
of from `google_sql_database_instance.main.connection_name`. During
coexistence both instances are mounted in the `instances` list, which is a
list. Rollback then becomes what the 2026-09-20 design said it was: a new
secret version and a revision restart, not an apply across five resources on a
bad afternoon.

`deletion_protection = true` on the instance and `deletion_policy = ABANDON`
on the database are already right and must survive the change; the second was
written for exactly the case of a rename Terraform reads as a replacement.

## Who does what

| who | what |
|---|---|
| **this session**, in `aleogr/lab` | this spec and its plan; `schooling` registered as a tenant; `docs/lab.md` naming its second tenant; the prompts that carry every change below to `schooling`'s session |
| **`schooling`'s session**, in `codeschool-ing/schooling` | D2, D5, D6, D7 and D8 — every change in that repository, from prompts, merged by the owner |
| **the owner**, in Cloud Shell | the restore drill, before the move and after it; applying `schooling`'s Terraform, as today; creating the database user on `lab-postgres`; the isolation grants; the copy |

This session never commits to `codeschool-ing/schooling`.

## The stages

**Stage 1 — ready for the night, on the instance `schooling` has today.**
First, the owner runs the restore drill from Cloud Shell against today's
schema: the only proof that exists is from 28 migrations ago, and the data is not touched until the backup of the
data as it stands has been restored and compared. Then D2 — measure, then set
the pool — then D5, D6, D7 and D8, each its own pull request in `schooling`,
each verified while the old instance serves.

**Stage 2 — the laboratory takes a second tenant.** `schooling` is added to
`gcp/terraform/lab/lab.tfvars` — its runtime service account under `connects`,
its deploy identity under a new `reads` for D7, and nothing under `logs_in`,
because `schooling` authenticates with a password rather than as an IAM user.
Nothing under `declares` either: `schooling`'s Terraform is applied by the
owner from Cloud Shell, not by a service account, and the owner already holds
more than `sqlTenant` on the shared project. `declares` becomes optional to say
so, rather than naming a service account that applies nothing. `schooling`
declares its own database on `lab-postgres`, as `marketplace` did. The owner creates the user and applies the same isolation
`marketplace` has: `REVOKE CONNECT ON DATABASE schooling FROM PUBLIC`, a grant
by name, `CONNECTION LIMIT 8`, and a throwaway role proving the revoke refuses
it.

**Stage 3 — the move.** The 2026-09-20 design's Phase 2, with two corrections:
the two nightly jobs are paused for the freeze, and the rollback is D8's, not
the one that plan describes.

**Stage 4 — cool down.** The old instance is stopped, not deleted, for at
least a week (D7 of the 2026-09-20 design). Before it is deleted, the owner
runs the restore drill against `lab-postgres`. That is the only proof that D3
works rather than being believed to.

## When a stage is done

The same rule as `marketplace`'s move: `verify.sql` run before and after
produces reports that are identical, line for line, less the one `snapshot|`
line allowed to differ. Identical, or stop. There is no third outcome and no
"close".

**Corrected on 2026-09-23, during Stage 3.** A logical copy cannot meet that
rule, and the rule was written without knowing it. `verify.sql` reports a
column's `ordinal_position`, which is PostgreSQL's `attnum` and keeps the gap
a dropped column leaves; `pg_dump` recreates the table without the gap. It
also prints `CHECK` expressions as stored, and a nested `AND` written by an
old migration is flattened when the dump is read back. The copy of
`schooling` differed in exactly three lines, each of those two kinds:

| line | source | target | cause |
|---|---|---|---|
| `catalog_courses.slug` position | 12 | 11 | one dropped column in the source table |
| `tenants.catalog_published_at` position | 9 | 7 | two dropped columns in the source table |
| `catalog_images_are_pictures` | `((a AND b) AND c)` | `(a AND b AND c)` | nested `AND` flattened on re-parse |

The dropped columns were counted in the source (`pg_attribute.attisdropped`:
1 and 2) before going on, every `rows|` line was identical, and the owner
chose to proceed. The rule for a logical copy is therefore: identical less
`snapshot|`, less column positions that the source's dropped columns account
for, less `CHECK` text that differs only in parentheses — each named, never
waved through as a class. A clone (the restore drill) is still held to
identical.

## What was measured

Each of these was listed here as not verified when this design was written.

**`CREATE EXTENSION pg_trgm` by the tenant's user: it can.** Created and
dropped by `schooling` on the empty database on `lab-postgres`, 2026-09-23,
before the copy needed it.

**`schooling`'s real connection usage.** The most the database held in 30
days was 8, in the hour ending 2026-08-25T17:21Z (hourly maximum of
one-minute samples); no release ran in that hour. The split chosen from it:
the API 2 per instance × 1 instance × 2 revisions during a rollout, one per
job, one for a person — 8 exactly, held to the code by a test in
`codeschool-ing/schooling` (`internal/platform/database/budget_test.go`).

**How long `cmd/load` holds its single transaction.** The last ten
executions took 1m47s to 4m28s end to end, container start and validation
included; `schooling`'s session measured the transaction itself at about four
seconds against a local database.

**The restore drill against today's schema: it works.** Run on 2026-09-23 at
07:40:57Z against `aleogr-schooling`: 931 report lines identical, 56 tables,
21,368 rows, 52 migrations, clone deleted by the script. The drill against
`lab-postgres` is Stage 4's and has not run yet.

**A stopped instance that is still mounted does not stop Cloud Run starting
the service.** Proved by day on 2026-09-23: with the old instance stopped and
both mounted, a new revision started and `/readyz` answered 200.

## Risks

**The copy loses writes.** Only if the freeze is skipped. Phase 2's freeze is
what closes it, and D5's schedules are paused as part of it.

**The ceilings sum to the capacity exactly.** 14 + 8 = 22 leaves nothing for a
third tenant or for a manual `psql` session through the Auth Proxy. The restore
drill costs one connection on the live instance, for the snapshot it reads
first, and it comes out of `schooling`'s own 8; everything else it does is on
the clone, which has connections of its own. The third tenant is a future design's problem; the manual
session is the owner's to take outside a deployment.

**`schooling` goes dark at night, and so does the index page's card for it.**
Its service pings the database before it listens, exactly as `marketplace`
does, so inside the window no container comes up and Google Frontend answers
instead. For `marketplace` this was examined on 2026-09-23 and kept on
purpose — refusing to start is what keeps a revision with a broken database
setting from ever taking traffic — and the same trade applies here.
