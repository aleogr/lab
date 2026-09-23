# Schooling moves in — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `schooling`'s laboratory database from its own Cloud SQL instance in `aleogr-schooling` onto `lab-postgres`, with `schooling` ready for a sleeping instance before a single row moves.

**Architecture:** Four stages, in order, each finished before the next starts. Stage 1 changes `schooling` on the instance it has today, one pull request at a time, each written by `schooling`'s own session from a prompt in this plan. Stage 2 makes `lab-postgres` ready to receive it. Stage 3 moves the data under a freeze, with a report compared line for line before and after. Stage 4 stops the old instance, proves the new backups by restoring one, and only then deletes the old instance.

**Tech Stack:** Terraform (1.16.3 in `aleogr/lab`), Google Cloud provider, Cloud SQL for PostgreSQL 16, Cloud Run, Cloud Scheduler, Cloud Monitoring, Secret Manager, the Cloud SQL Auth Proxy v2, `pg_dump`/`psql` 16, `schooling`'s own `tools/restore-drill/`.

**Spec:** `docs/superpowers/specs/2026-09-23-schooling-moves-in-design.md`. It argues from `docs/superpowers/specs/2026-09-20-shared-database-instance-design.md` (Phase 2, the isolation grants) and `docs/superpowers/specs/2026-09-21-sleep-schedule-design.md` (the window). Read all three.

## Status, 2026-09-23

Stages 1–3 are done; Stage 4 is in its cool-down week. What ran, and where it
departed from what is written below:

| task | outcome |
|---|---|
| 1 | Drill on `aleogr-schooling` passed, 07:40:57Z: 931 lines identical, 56 tables, 21,368 rows, 52 migrations. It ran at night: `schooling`'s own instance never sleeps, so "by day" did not apply. It waited only for the backup window, whose `07:00` is the start of a four-hour window, not the time. |
| 2 | Peak 8 connections (hour ending 2026-08-25T17:21Z); `schooling-load` 1m47s–4m28s. Measured with a Monitoring API query from Cloud Shell rather than Metrics Explorer. |
| 3 | `codeschool-ing/schooling` #418: API pool 2, jobs 1, `max_instance_count = 1`, a `concurrency` group on the deploy, and `budget_test.go`; worst case 8. Its apply also carried three merged-but-never-applied changes from 2026-09-01 and 2026-09-16, because the owner's checkout was behind: every `schooling` apply now starts with `git pull --ff-only` on `main`. Live from release v0.52.0. |
| 4 | #419: jobs at `10 8 * * *` and `40 8 * * *`; first runs at the new hours succeeded the same day. |
| 5 | #420: `var.database_instances`; the restart command in `infra/README.md` proved once (`schooling-00065` → `00066`, plan empty). |
| 6 | #421. **P4 was amended before it was handed over:** the preflight reads one literal, `DATABASE_CONNECTION`, not `var.database_instances`, which the workflow cannot read and which names two instances during the move. `roles/cloudsql.viewer` on `aleogr-schooling` for `schooling-deploy`; v0.52.0 passed through it. |
| 7 | #422: custom role `schoolingAlertToggle`, account `schooling-alert-toggle`, jobs `schooling-alert-sleep` / `-wake`; silencing from now rather than gated. No `actAs` binding: the owner applies as Owner. Both jobs run by hand by day: `False`, then `True`. |
| 8 | `aleogr/lab` #13; plan `2 to add`, the `marketplace` binding untouched; grants read back live. |
| 9 | #423. **P6 was amended:** it also switched `DATABASE_CONNECTION` to `lab-postgres`. Plan `1 to add, 5 to change`. |
| 10 | Done as written. `connect_probe` refused; `pg_trgm` created and dropped by `schooling`. |
| 11 | 2026-09-23, 09:07–09:20 local. Before and after reports differed in three lines, none of them data; see "When a stage is done" in the spec. The owner proceeded. Secret version 2 is the new address, version 1 the way back; API revision `schooling-00069`; a `load` execution wrote the catalogue on `lab-postgres` at 12:17:34Z. |
| 12 | Step 1 done: the old instance reports `NEVER` / `STOPPED` (not `RUNNABLE`). A restart with it stopped and still mounted gave `/readyz` 200. Steps 2–4 not before 2026-09-30. |
| 13, 14 | Not started. |

## Global Constraints

- Everything versioned is written in **English**. Talk to the owner in Portuguese.
- Both repositories are **public**. No secret may ever be committed, printed, or pasted into a prompt.
- Model identifiers appear only in the attribution trailer of commit messages and pull request descriptions.
- **This session never commits, branches, pushes or opens a pull request in `codeschool-ing/schooling`.** Every change there is a prompt the owner pastes into that repository's own session. This session may read it.
- **Terraform in `aleogr/lab` is only ever applied by CI.** `schooling`'s Terraform is applied by the owner from Cloud Shell, as it is today (`infra/README.md` there).
- Claude Code opens pull requests and **never merges**. The owner merges.
- Manual steps are given to the owner **one at a time**, at the moment each is needed.
- **Never buy a green check.**
- The window, from `docs/lab.md`: asleep Monday through Thursday, 22:00 to 07:30 `America/Sao_Paulo`. A start takes 686 seconds. **Nothing in Stages 2–4 is done inside the window.**
- `lab-postgres` in `aleogr-lab-shared-dacd`, region `us-central1`, connection name `aleogr-lab-shared-dacd:us-central1:lab-postgres`.
- `schooling`'s instance today: `schooling` in `aleogr-schooling`, connection name `aleogr-schooling:us-central1:schooling`.
- On `lab-postgres`: database `schooling`, user `schooling` (a password user, the same name as today, so `verify.sql`'s report and the drill's defaults hold unchanged), `CONNECTION LIMIT 8`. `marketplace` keeps 14. 14 + 8 = 22.
- Identities in `aleogr-schooling`: `schooling-run@` (the service and all four jobs), `schooling-deploy@` (the release workflow).
- The secret `schooling-database-url` stays in `aleogr-schooling`. Its value is never set by Terraform.
- D5: `schooling-analyse-nightly` at `10 8 * * *`, `schooling-settle-nightly` at `40 8 * * *`, `America/Sao_Paulo`.
- D6: the alert policy "schooling is not answering" disabled at `0 22 * * 1-4`, re-enabled at `0 8 * * 2-5`, `America/Sao_Paulo`.
- **A restore is never tested over a live instance.** The drill clones; it only reads the live one.
- The stage is done only when `verify.sql`'s two reports are identical, line for line, less the `snapshot|` line. Identical, or stop.

## Repositories and pull requests

| repository | who writes | branch | pull request |
|---|---|---|---|
| `aleogr/lab` | this session | `claude/lab-schooling-move` (carries the spec) | **A**: spec and this plan, now |
| `aleogr/lab` | this session | `claude/lab-schooling-tenant`, from `main`, at Task 8 | **B**: the tenant registration (Task 8) |
| `aleogr/lab` | this session | `claude/lab-schooling-done`, from `main`, at Task 14 | **C**: the record (Task 14) |
| `codeschool-ing/schooling` | its own session, from prompts P1–P7 | its own | one per prompt |

Prompts are handed over **one at a time**: the next is given only after the previous pull request is merged and its verification has been reported back here.

## File Structure

**`aleogr/lab`**

| file | responsibility |
|---|---|
| `gcp/terraform/variables.tf` (modify, Task 8) | `declares` becomes optional; a tenant gains `reads` |
| `gcp/terraform/tenants.tf` (modify, Task 8) | `tenant_deployers` skips a tenant with no `declares`; a new `tenant_reads` grants `roles/cloudsql.viewer` |
| `gcp/terraform/lab/lab.tfvars` (modify, Task 8) | `schooling` registered |
| `docs/lab.md` (modify, Task 8) | the tenants and their ceilings |
| `docs/superpowers/specs/2026-09-23-schooling-moves-in-design.md` (modify, Task 14) | status, and what was measured |

**`codeschool-ing/schooling`** — written by its own session; named here so the prompts can be precise.

| file | changed by |
|---|---|
| `internal/platform/database/database.go` (`maxConns = 4`), `infra/run.tf` (`max_instance_count = 4`) | P1 |
| `infra/scheduler.tf` (`10 3 * * *`, `40 3 * * *`) | P2 |
| `infra/run.tf` (five `cloud_sql_instance { instances = [...] }`), `infra/variables.tf` | P3 |
| `.github/workflows/release.yml` | P4 |
| `infra/monitoring.tf`, a new Terraform file for the two scheduler jobs | P5 |
| `infra/database.tf` | P6, P7 |

---

# Stage 1 — ready for the night, on the instance `schooling` has today

## Task 1: The restore drill against today's schema

**Who:** the owner, in Cloud Shell. By day. No release running in `schooling`.

**Why first:** the only proof of `schooling`'s backups is from 28 migrations ago. No data moves until the backup of the data as it stands has been restored and compared.

- [ ] **Step 1: Get the drill, read-only**

```sh
cd ~ && rm -rf schooling-drill
git clone --depth 1 https://github.com/codeschool-ing/schooling.git schooling-drill
cd schooling-drill
gcloud config set project aleogr-schooling
```

`~/schooling-drill` is used again in Tasks 11 and 12, for `verify.sql` and the drill. If the clone asks for credentials, use the same authentication the owner already uses for that repository in Cloud Shell.

- [ ] **Step 2: Run it**

```sh
tools/restore-drill/restore-drill.sh
```

Expected, after about fifteen minutes: the two reports are declared identical, and the clone `schooling-drill-<timestamp>` is deleted by the script's trap.

- [ ] **Step 3: Prove nothing was left running**

```sh
gcloud sql instances list --project=aleogr-schooling --format='value(name)'
```

Expected: `schooling` and nothing else.

- [ ] **Step 4: Report back here**

The owner pastes the last lines of the run: the table count, the row count, the migration count, and the verdict. If the reports differ or the script fails, this stage stops: the output goes to `schooling`'s session as a bug report against its drill, and Stage 1 resumes only after the drill passes.

## Task 2: Measure before sizing

**Who:** the owner, in the console and Cloud Shell. The spec (D2) commits to a ceiling of 8; the split inside it is chosen from these numbers.

- [ ] **Step 1: The most connections `schooling` has actually held**

Cloud Console → Monitoring → Metrics Explorer → metric **Cloud SQL Database › PostgreSQL › Number of connections** (`cloudsql.googleapis.com/database/postgresql/num_backends`), filter `database = schooling`, aggregation **max**, window **last 30 days**. Report the peak and when it happened.

- [ ] **Step 2: How long `cmd/load` runs**

`cmd/load` rewrites the catalogue in one transaction, so a job execution's duration bounds how long that transaction is held.

```sh
gcloud run jobs executions list --job=schooling-load \
  --region=us-central1 --project=aleogr-schooling --limit=10 \
  --format='table(name,status.startTime,status.completionTime,status.succeededCount)'
```

Report the longest.

- [ ] **Step 3: This session records both numbers**

They go into the spec in Task 14. They are not guessed in the meantime.

## Task 3: P1 — the pool fits 8 (D2)

**Who:** `schooling`'s session, from the prompt below. The owner merges and applies.

- [ ] **Step 1: Hand the owner prompt P1, with Task 2's two numbers filled in**

```text
Context: this repository's laboratory database is going to move onto a shared
Cloud SQL instance, `lab-postgres` in `aleogr-lab-shared-dacd` (db-f1-micro,
max_connections 25, 3 reserved for superusers). Another laboratory already
lives there with a CONNECTION LIMIT of 14. This one will get a CONNECTION
LIMIT of 8, and 14 + 8 = 22 is the whole instance. Nothing moves yet; this
change is made on the instance this project has today.

Today's worst case, read from the code, is 24: `maxConns = 4` in
internal/platform/database/database.go, shared by every command, times
`max_instance_count = 4` for the API in infra/run.tf, plus `migrate` and `load`
at 4 each during a release.

Measured on the live instance:
- the most connections the `schooling` database has held in 30 days: <PEAK>
  at <WHEN>
- the longest `schooling-load` execution in the last ten: <DURATION>

Task: make the worst case at most 8, and prove it from the code the way
aleogr/marketplace's docs/infrastructure.md does ("Why the limit is 14"): a
table of every process that can hold a connection at the same time as another,
with the number each holds, and the sum.

Count, at least: the API's instances, INCLUDING the old and the new revision
serving side by side during a rollout; the release jobs (read release.yml to
establish whether migrate and load ever run at the same time); and the two
nightly jobs (analyse, settle), which will run at 08:10 and 08:40 local and
can overlap a release made at that hour.

The two levers are the pool size and `max_instance_count`. Choose the values
from the measurement above, not from a preference, and say why. If the pool
size needs to differ between the API and the jobs, make that explicit rather
than hiding it in a constant.

Deliver: one pull request with the change, the arithmetic table in the
documentation where this project keeps its infrastructure decisions, and the
`terraform -chdir=infra plan` output the owner will see (in-place updates
only — say so if anything else appears). Do not apply; the owner does.
```

- [ ] **Step 2: The owner merges, applies from Cloud Shell, and reports the plan summary**

Expected: `0 to add, N to change, 0 to destroy`, the changes limited to the Cloud Run resources the pull request names.

- [ ] **Step 3: Check the arithmetic here before moving on**

This session reads the merged table in `schooling` and confirms the sum is ≤ 8. If it is not, Stage 2 does not start.

## Task 4: P2 — the nightly jobs leave the window (D5)

- [ ] **Step 1: Hand the owner prompt P2**

```text
The shared instance this project will move to sleeps Monday through Thursday,
22:00 to 07:30 America/Sao_Paulo, and takes about 11.5 minutes (686 s,
measured) to accept connections after it is started at 07:30.

`schooling-analyse-nightly` runs at 03:10 and `schooling-settle-nightly` at
03:40 (infra/scheduler.tf). Both fall inside the window four nights a week,
and a run that fails there is invisible: the `job_runs` row that would record
it is written to the database that is off.

Task: move them to `10 8 * * *` and `40 8 * * *`, same time zone, keeping the
thirty minutes between them. Update every comment in that file that argues
for the old hour, so nothing left behind still says "03:10". Nothing else.

Deliver: one pull request, and the `terraform -chdir=infra plan` output the
owner will see (two in-place updates, nothing else). Do not apply.
```

- [ ] **Step 2: The owner merges, applies, and confirms**

```sh
gcloud scheduler jobs list --location=us-central1 --project=aleogr-schooling \
  --format='table(name.basename(),schedule,timeZone,state)'
```

Expected: `10 8 * * *` and `40 8 * * *`, `America/Sao_Paulo`, `ENABLED`.

## Task 5: P3 — the instance becomes a variable (D8)

- [ ] **Step 1: Hand the owner prompt P3**

```text
The Cloud SQL instance is written into five Cloud Run resources in
infra/run.tf as `cloud_sql_instance { instances = [google_sql_database_instance.main.connection_name] }`.
When the database moves to `aleogr-lab-shared-dacd:us-central1:lab-postgres`,
there will be a period where BOTH instances must be mounted (the service must
be able to reach either, so that switching between them is a new secret
version and a revision restart, not an apply across five resources).

Task:
1. Replace the five references with one list that comes from configuration,
   e.g. `var.database_instances` (list(string)). Its value today is the one
   connection name the instance has now. Nothing in the plan may change except
   what that indirection necessarily touches — ideally nothing at all.
2. `deletion_protection = true` on the instance and `deletion_policy = "ABANDON"`
   on the database must be untouched.
3. Write down, where this project documents operations, the exact command that
   makes the Cloud Run service start a new revision WITHOUT changing anything
   Terraform manages (so the next plan is empty), and prove it: run nothing
   against production, but show from the provider's `ignore_changes` in
   infra/run.tf why the command you chose does not drift. The move will use
   that command to pick up a new version of `schooling-database-url`, whose
   secret references are `version = "latest"`.

Deliver: one pull request and the `terraform -chdir=infra plan` output the
owner will see. The expected result is "No changes". Do not apply.
```

- [ ] **Step 2: The owner merges and applies**

Expected: `No changes. Your infrastructure matches the configuration.` Anything else is reported back before applying.

- [ ] **Step 3: The owner runs the restart command once, by day, and reports**

The command P3 documented, then:

```sh
gcloud run services describe schooling --region=us-central1 --project=aleogr-schooling \
  --format='value(status.latestReadyRevisionName)'
```

and `terraform -chdir=infra plan` from the checkout the owner applies `schooling`'s Terraform from.

Expected: a revision name newer than before the command, and the plan still `No changes`. This is the rollback of Stage 3, tried before it is needed.

## Task 6: P4 — a release refuses a sleeping instance (D7)

- [ ] **Step 1: Hand the owner prompt P4**

```text
A release run inside the sleep window fails at the `migrate` gate with a raw
pgx or Cloud SQL error, after the images are already pushed.
aleogr/marketplace removed exactly that failure mode on 2026-09-21: read it in
that repository's .github/workflows/terraform.yml (the step that reads
`activationPolicy`), including the `if ! shared=$(...)` form that keeps a
failed read from passing as "awake".

Task: add the same preflight to .github/workflows/release.yml, as the FIRST
thing the deploy job does, before any image is pushed:
- read the connection name from the same configuration P3 introduced (the
  instance the release is about to migrate), split it into project and
  instance, and run
  `gcloud sql instances describe <instance> --project=<project> --format='value(settings.activationPolicy)'`;
- if the read fails, stop and say the instance could not be read;
- if the value is not ALWAYS, stop with one sentence naming the window:
  "The shared database sleeps Monday–Thursday 22:00–07:30 (America/Sao_Paulo)
  and takes about 12 minutes to wake; release after 07:45 or on another day."

The release runs as schooling-deploy@aleogr-schooling.iam.gserviceaccount.com.
Today the instance is in this project: check whether that identity can already
read it (`cloudsql.instances.get`) and, if not, grant the narrowest role in
infra/iam.tf. When the instance moves, the shared project grants it
`roles/cloudsql.viewer` there — nothing for this repository to do about that.

Deliver: one pull request. The first release after merge is its test: the
preflight must print the policy it read (ALWAYS) and continue.
```

- [ ] **Step 2: The owner merges, applies if `iam.tf` changed, and the next release shows the preflight reading `ALWAYS`**

The owner pastes that step's log lines here.

## Task 7: P5 — the readiness alert sleeps with the instance (D6)

- [ ] **Step 1: Hand the owner prompt P5**

```text
The alert policy "schooling is not answering" (infra/monitoring.tf) fires on
600 s of failed /readyz probes. Once the database is on the shared instance,
/readyz fails every night the instance sleeps, and the file's own argument is
that a daily false alarm is worse than none.

Task: two Cloud Scheduler jobs in this project that disable the policy at
`0 22 * * 1-4` and re-enable it at `0 8 * * 2-5`, time zone America/Sao_Paulo.
08:00 and not 07:30: the instance takes 686 s to answer after its 07:30 start,
so an alert re-armed at 07:30 would fire on probes that are expected to fail.

Mechanism, the same one aleogr/lab uses to stop and start the instance
(read gcp/terraform/sleep.tf and sleeper.tf there): an `http_target` PATCH to
`https://monitoring.googleapis.com/v3/<policy name>?updateMask=enabled` with
body `{"enabled": false}` / `{"enabled": true}`, authenticated by an
`oauth_token` for a service account of its own that holds only what updating
an alert policy needs. Grant the identity that applies this Terraform
`iam.serviceAccountUser` on that account if the scheduler needs to act as it,
and say so — aleogr/lab lost an afternoon to a missing actAs grant.

The policy has `count = local.monitoring`; the jobs follow the same count.

Until the database moves, disabling the alert at night silences a check on an
instance that does not sleep. Accept that for the weeks in between, or gate
the jobs behind a variable that turns on at the move — choose, and say which.

Deliver: one pull request, and the `terraform -chdir=infra plan` output the
owner will see. Do not apply.
```

- [ ] **Step 2: The owner merges and applies; the first night proves it**

The next morning, after 08:00:

```sh
gcloud scheduler jobs list --location=us-central1 --project=aleogr-schooling \
  --format='table(name.basename(),schedule,state,status.code,lastAttemptTime)'
gcloud alpha monitoring policies list --project=aleogr-schooling \
  --filter='displayName="schooling is not answering"' --format='value(enabled)'
```

Expected: both jobs attempted with no error code, and the policy `True`.

---

# Stage 2 — the laboratory takes a second tenant

**Starts only when Tasks 1–7 are all done.**

## Task 8: Register `schooling` in `aleogr/lab`

**Who:** this session. Pull request **B**.

**Files:**
- Modify: `gcp/terraform/variables.tf` (the `tenants` object type)
- Modify: `gcp/terraform/tenants.tf`
- Modify: `gcp/terraform/lab/lab.tfvars`
- Modify: `docs/lab.md`

- [ ] **Step 1: Branch from `main`**

```sh
git fetch origin main && git checkout -b claude/lab-schooling-tenant origin/main
```

- [ ] **Step 2: Make `declares` optional and add `reads`**

In `gcp/terraform/variables.tf`, the `tenants` type becomes:

```hcl
  type = map(object({
    declares = optional(string)
    connects = list(string)
    logs_in  = list(string)
    reads    = optional(list(string), [])
  }))
```

and the description gains, after the sentence about `logs_in`: "`reads` may read the instance's settings and nothing else, for a deploy that checks whether the instance is awake. A tenant whose Terraform is applied by a person rather than a service account has no `declares`."

- [ ] **Step 3: Skip a tenant with no `declares`; grant `reads`**

In `gcp/terraform/tenants.tf`, `tenant_deployers`' `for_each` becomes:

```hcl
  for_each = { for name, tenant in var.tenants : name => tenant if tenant.declares != null }
```

The key is still the tenant's name, so `marketplace`'s existing binding keeps its address and the plan does not touch it. Append:

```hcl
# `cloudsql.viewer` reads the instance and nothing else: no connection, no
# write. A tenant's deploy reads `activationPolicy` before it starts, so a
# release inside the sleep window stops with a sentence instead of a pgx error.
resource "google_project_iam_member" "tenant_reads" {
  for_each = toset(flatten([for tenant in var.tenants : tenant.reads]))

  project = var.project_id
  role    = "roles/cloudsql.viewer"
  member  = "serviceAccount:${each.value}"
}
```

- [ ] **Step 4: Register the tenant**

In `gcp/terraform/lab/lab.tfvars`, after `marketplace`'s entry, inside `tenants`:

```hcl
  schooling = {
    # No `declares`: schooling's Terraform is applied by the owner from Cloud
    # Shell, not by a service account, and the owner already holds more than
    # `sqlTenant` here.
    connects = [
      "schooling-run@aleogr-schooling.iam.gserviceaccount.com",
    ]
    # The release reads `activationPolicy` before it pushes anything.
    reads = [
      "schooling-deploy@aleogr-schooling.iam.gserviceaccount.com",
    ]
    # A password user, not an IAM one.
    logs_in = []
  }
```

- [ ] **Step 5: Format and validate**

```sh
terraform -chdir=gcp/terraform fmt -check -recursive
terraform -chdir=gcp/terraform init -backend=false -input=false >/dev/null
terraform -chdir=gcp/terraform validate
```

Expected: no `fmt` output, `Success! The configuration is valid.` (This exact change was validated in a scratch copy on 2026-09-23.)

- [ ] **Step 6: Name the tenants in `docs/lab.md`**

A new section after "What a project may do inside the shared instance":

```markdown
## Who lives here

| tenant | database | connection ceiling | how its Terraform is applied |
|---|---|---|---|
| `aleogr/marketplace` | `marketplace` | 14 | CI, as `terraform@` |
| `codeschool-ing/schooling` | `schooling` | 8 | the owner, from Cloud Shell |

The ceilings sum to 22, which is the whole instance: `max_connections` is 25
and PostgreSQL reserves three for superusers. Each ceiling is that tenant's
worst case read from its own code, and a third tenant is a new design, not a
new row.
```

- [ ] **Step 7: Commit, push, open pull request B, subscribe to it**

```sh
git add gcp/terraform/variables.tf gcp/terraform/tenants.tf gcp/terraform/lab/lab.tfvars docs/lab.md
git commit -m "Register schooling as the laboratory's second tenant"
git push -u origin claude/lab-schooling-tenant
```

- [ ] **Step 8: Read the plan in CI before asking for the merge**

Expected in the pull request's plan: exactly `2 to add, 0 to change, 0 to destroy` — `tenant_connects["schooling-run@…"]` and `tenant_reads["schooling-deploy@…"]`. Any change to a `marketplace` binding is a defect in Step 3.

- [ ] **Step 9: After the owner merges, prove the grants from the live project**

```sh
gcloud projects get-iam-policy aleogr-lab-shared-dacd \
  --flatten='bindings[].members' \
  --filter='bindings.members:aleogr-schooling.iam.gserviceaccount.com' \
  --format='table(bindings.role,bindings.members)'
```

Expected: `roles/cloudsql.client` for `schooling-run@`, `roles/cloudsql.viewer` for `schooling-deploy@`, nothing else.

## Task 9: P6 — `schooling` declares its database on `lab-postgres` and mounts both instances

- [ ] **Step 1: Hand the owner prompt P6**

```text
The shared project now lets this project in: `schooling-run@` holds
roles/cloudsql.client and `schooling-deploy@` holds roles/cloudsql.viewer on
`aleogr-lab-shared-dacd`.

Task, in one pull request:
1. Declare the database on the shared instance, the way this project declares
   its own today:
     resource "google_sql_database" "shared" {
       project  = "aleogr-lab-shared-dacd"
       instance = "lab-postgres"
       name     = "schooling"
       deletion_policy = "ABANDON"
     }
   (names and layout are yours; ABANDON is not optional — say why in the
   comment, as database.tf already does for the current one).
   The owner applies this Terraform as their own user, who already has the
   rights on the shared project; no new identity is needed.
2. Add `aleogr-lab-shared-dacd:us-central1:lab-postgres` to the list P3
   introduced, so both instances are mounted. The secret still points at the
   old one; nothing switches yet.
3. On the CURRENT instance, add
     lifecycle { ignore_changes = [settings[0].activation_policy] }
   After the move the owner stops it by hand for a week before deleting it.
   Without this, the provider's default of ALWAYS would restart it on the next
   apply — aleogr/lab hit exactly this (read the comment in
   gcp/terraform/instance.tf there).

Deliver: the pull request and the `terraform -chdir=infra plan` output the
owner will see: 1 to add (the database), in-place updates to the five Cloud
Run resources, nothing destroyed. Do not apply.
```

- [ ] **Step 2: The owner merges and applies; confirm**

```sh
gcloud sql databases list --instance=lab-postgres --project=aleogr-lab-shared-dacd --format='value(name)'
```

Expected: `marketplace`, `postgres`, `schooling`.

## Task 10: The user and the isolation

**Who:** the owner, in Cloud Shell, by day. **The password is the one `schooling` uses today**, read from the secret and never printed, so the secret's cutover in Task 11 changes the host and nothing else.

- [ ] **Step 1: Read today's password, without printing it**

```sh
URL="$(gcloud secrets versions access latest --secret=schooling-database-url --project=aleogr-schooling)"
case "$URL" in
  postgres://schooling:*@*) PW="${URL#postgres://schooling:}"; PW="${PW%%@*}"; echo "password read" ;;
  *) echo "the secret is not postgres://schooling:…@… — stop here" ;;
esac
unset URL
```

Expected: `password read`. The same shape check the drill makes: without it, an unexpected secret would silently become a "password" that is the whole connection string.

- [ ] **Step 2: Create the user**

```sh
gcloud sql users create schooling --instance=lab-postgres \
  --project=aleogr-lab-shared-dacd --password="$PW"
grep -rlF -- "$PW" ~/.config/gcloud/logs 2>/dev/null
```

Expected: `Created user [schooling].`, and the `grep` prints nothing. If it names a file, gcloud logged the argument: delete that file.

- [ ] **Step 3: Grant before revoking, and set the ceiling**

Through the proxy the drill fetched in Task 1 (any v2 works):

```sh
~/cloud-sql-proxy "aleogr-lab-shared-dacd:us-central1:lab-postgres?port=6544" >/tmp/proxy.log 2>&1 &
export PGPASSWORD="$PW"
DST="host=127.0.0.1 port=6544 user=schooling dbname=schooling sslmode=disable"
psql "$DST" -v ON_ERROR_STOP=1 <<'SQL'
GRANT  CONNECT ON DATABASE schooling TO schooling;
REVOKE CONNECT ON DATABASE schooling FROM PUBLIC;
ALTER  DATABASE schooling CONNECTION LIMIT 8;
SELECT datname, datconnlimit FROM pg_database WHERE datname IN ('marketplace', 'schooling') ORDER BY 1;
SQL
```

Expected: `marketplace|14` and `schooling|8`. The grant comes first for the reason `aleogr/marketplace`'s `docs/infrastructure.md` gives: revoking first can lock out the role that was reaching the database through `PUBLIC`. `sslmode=disable` is to the loopback only; the proxy encrypts to Cloud SQL.

- [ ] **Step 4: Prove the revoke bites**

The probe is dropped in the same command, whatever the outcome, so an unexpected result cannot leave a login role on a shared instance:

```sh
PROBE_PW="$(openssl rand -hex 16)"
psql "$DST" -c "CREATE ROLE connect_probe LOGIN PASSWORD '$PROBE_PW'"
PGPASSWORD="$PROBE_PW" psql "host=127.0.0.1 port=6544 user=connect_probe dbname=schooling sslmode=disable" -c 'SELECT 1'; \
  psql "$DST" -c 'DROP ROLE connect_probe'
unset PROBE_PW
```

Expected: `FATAL:  permission denied for database "schooling"`, then `DROP ROLE`. If the probe connects, the revoke did not take and Stage 3 does not start.

- [ ] **Step 5: `pg_trgm` by the tenant's own user**

The spec lists this as unverified. Prove it on the empty database before the copy needs it:

```sh
psql "$DST" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION pg_trgm' -c 'DROP EXTENSION pg_trgm'
```

Expected: `CREATE EXTENSION`, `DROP EXTENSION`. If refused, stop: the copy would fail at migration 0048's objects.

- [ ] **Step 6: Leave nothing behind**

```sh
unset PW PGPASSWORD DST; kill %1
```

---

# Stage 3 — the move

## Task 11: Freeze, copy, compare, cut over

**Who:** the owner, in Cloud Shell, **by day, outside the window, not between 08:00 and 09:00 (the nightly jobs), and with no release running**. Budget an hour. This session guides it one step at a time.

- [ ] **Step 1: Preflight — everything cheap that can fail, fails here**

```sh
pg_dump --version      # must be 16 or newer; Cloud Shell's may be older
gcloud sql instances describe lab-postgres --project=aleogr-lab-shared-dacd --format='value(settings.activationPolicy,state)'
gcloud sql instances describe schooling --project=aleogr-schooling --format='value(settings.activationPolicy,state)'
```

Expected: `ALWAYS RUNNABLE` twice, and `pg_dump (PostgreSQL) 16.x` or newer. If older: `sudo apt-get install -y postgresql-client-16` after adding the PGDG repository, or run the dump from `docker run --rm --network host postgres:16`. Resolve it here, not halfway through.

- [ ] **Step 2: Both proxies, one password**

```sh
SRC_CONN=aleogr-schooling:us-central1:schooling
DST_CONN=aleogr-lab-shared-dacd:us-central1:lab-postgres
~/cloud-sql-proxy "$SRC_CONN?port=6543" "$DST_CONN?port=6544" >/tmp/proxy.log 2>&1 &
OLD_URL="$(gcloud secrets versions access latest --secret=schooling-database-url --project=aleogr-schooling)"
PW="${OLD_URL#postgres://schooling:}"; PW="${PW%%@*}"; export PGPASSWORD="$PW"; unset PW
SRC="host=127.0.0.1 port=6543 user=schooling dbname=schooling sslmode=disable"
DST="host=127.0.0.1 port=6544 user=schooling dbname=schooling sslmode=disable"
psql "$SRC" -qtAc 'SELECT 1' && psql "$DST" -qtAc 'SELECT 1'
```

Expected: `1` twice. `OLD_URL` stays in the shell until Step 10: it is the rollback.

- [ ] **Step 3: Freeze**

```sh
gcloud scheduler jobs pause schooling-analyse-nightly --location=us-central1 --project=aleogr-schooling
gcloud scheduler jobs pause schooling-settle-nightly  --location=us-central1 --project=aleogr-schooling
psql "$SRC" -v ON_ERROR_STOP=1 \
  -c 'ALTER DATABASE schooling SET default_transaction_read_only = on' \
  -c "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE datname = 'schooling' AND pid <> pg_backend_pid()"
```

The terminate makes the service's pools reconnect, and every new connection is read-only. From here the site reads but does not write. `pg_dump` does not carry a database-level setting without `--create`, so the target does not inherit the read-only flag.

- [ ] **Step 4: Photograph the source**

```sh
psql "$SRC" -qtAX -v ON_ERROR_STOP=1 -f ~/schooling-drill/tools/restore-drill/verify.sql > ~/before.txt
wc -l ~/before.txt
```

- [ ] **Step 5: Copy**

```sh
pg_dump --no-owner "$SRC" > ~/schooling.sql
psql "$DST" -v ON_ERROR_STOP=1 --single-transaction -f ~/schooling.sql
```

Expected: the load ends without `ERROR`. `--single-transaction` makes a failure leave the target empty, not half-filled. A failure here stops the move; the source is frozen but intact, and Step 11's rollback applies.

- [ ] **Step 6: Photograph the target, and compare**

```sh
psql "$DST" -qtAX -v ON_ERROR_STOP=1 -f ~/schooling-drill/tools/restore-drill/verify.sql > ~/after.txt
diff <(grep -v '^snapshot|' ~/before.txt) <(grep -v '^snapshot|' ~/after.txt) && echo IDENTICAL
```

Expected: `IDENTICAL`. Anything else: stop, rollback (Step 11), and bring the diff here.

- [ ] **Step 7: Cut over — a new secret version**

```sh
case "$OLD_URL" in *"$SRC_CONN"*) ;; *) echo "the secret does not name $SRC_CONN — stop"; false ;; esac && \
printf '%s' "${OLD_URL//$SRC_CONN/$DST_CONN}" | \
  gcloud secrets versions add schooling-database-url --project=aleogr-schooling --data-file=-
```

Expected: `Created version [N]`. Nothing is printed but the version number.

- [ ] **Step 8: Restart the service onto it**

The command P3 documented (Task 5). Then:

```sh
URL_RUN="$(gcloud run services describe schooling --region=us-central1 --project=aleogr-schooling --format='value(status.url)')"
curl -fsS "$URL_RUN/readyz" && echo
psql "$DST" -qtAc "SELECT count(*) FROM pg_stat_activity WHERE datname = 'schooling' AND pid <> pg_backend_pid()"
psql "$SRC" -qtAc "SELECT count(*) FROM pg_stat_activity WHERE datname = 'schooling' AND pid <> pg_backend_pid()"
```

Expected: `/readyz` answers 200; the target shows at least one connection that is not this shell's; the source shows `0` a few minutes after the restart (the old revision drains).

- [ ] **Step 9: Prove the jobs reach it too**

```sh
gcloud run jobs execute schooling-load --region=us-central1 --project=aleogr-schooling --wait
```

Expected: success. `load` rewrites the catalogue from the image's `content/` — the same one it already holds — so this proves a job connects and writes, not that anything changed.

- [ ] **Step 10: Unfreeze**

```sh
gcloud scheduler jobs resume schooling-analyse-nightly --location=us-central1 --project=aleogr-schooling
gcloud scheduler jobs resume schooling-settle-nightly  --location=us-central1 --project=aleogr-schooling
unset OLD_URL PGPASSWORD; kill %1; shred -u ~/schooling.sql
```

The source stays read-only on purpose: it is the frozen copy the rollback returns to, and a write there would make it a second truth. `before.txt` and `after.txt` hold only counts and names; keep them until Task 14.

- [ ] **Step 11: Rollback, only if Step 5, 6, 8 or 9 failed**

```sh
printf '%s' "$OLD_URL" | gcloud secrets versions add schooling-database-url --project=aleogr-schooling --data-file=-
psql "$SRC" -c 'ALTER DATABASE schooling SET default_transaction_read_only = off'
# the restart command from P3, then Step 10's resume lines
```

A rollback after writes have landed on `lab-postgres` loses those writes. That is why every check above comes before Step 10.

---

# Stage 4 — cool down

## Task 12: Stop the old instance, wait a week, drill the new one

**Who:** the owner, in Cloud Shell.

- [ ] **Step 1: Stop — do not delete**

```sh
gcloud sql instances patch schooling --project=aleogr-schooling --activation-policy=NEVER
```

Expected: `STOPPED`. It keeps its disk and data (about R$ 10 a month) and survives `schooling`'s applies because of P6's `ignore_changes`.

- [ ] **Step 2: Wait at least seven days** (D7 of the 2026-09-20 design).

- [ ] **Step 3: Check the drill can read the secret across projects**

The instance is in the shared project and the secret is not, so the drill names the secret in full:

```sh
gcloud config set project aleogr-lab-shared-dacd
gcloud secrets versions access latest \
  --secret=projects/aleogr-schooling/secrets/schooling-database-url >/dev/null && echo readable
```

Expected: `readable`. If refused, stop: `schooling`'s session teaches the drill a separate secret project before this task continues.

- [ ] **Step 4: The drill against `lab-postgres`, by day**

```sh
cd ~/schooling-drill && git pull -q
SOURCE=lab-postgres SECRET=projects/aleogr-schooling/secrets/schooling-database-url \
  tools/restore-drill/restore-drill.sh
gcloud sql instances list --project=aleogr-lab-shared-dacd --format='value(name)'
```

Expected: the two reports identical; the instance list back to `lab-postgres` alone. The drill reads the live instance once, for its snapshot, with one of `schooling`'s eight connections, and never writes to it; the clone holds `marketplace`'s data too for its fifteen minutes, and is deleted by the script's trap.

This is the only proof that D3 works. The old instance is not deleted until it passes.

## Task 13: P7 — decommission the old instance

- [ ] **Step 1: Hand the owner prompt P7**

```text
The database has lived on lab-postgres since <DATE>, the old instance has
been stopped for over a week, and a restore drill against lab-postgres passed
on <DATE>.

Task: remove the old instance from this project.
1. Take the old connection name out of the list P3 introduced, so only
   lab-postgres is mounted.
2. Remove `google_sql_database_instance.main` and the database resource on it.
   `deletion_protection = true` blocks the destroy in the same apply that
   turns it off (infra/README.md explains why), so plan it as two applies:
   first flip the protection off, then remove the resources. Say which
   commits the owner applies in which order.
3. Remove what only described the old instance: its backup window, its
   outputs, P6's ignore_changes, the comments that argue for them. Anything
   that still names the old connection name, anywhere in the repository, is
   either updated or explained.
4. Deleting an instance deletes its automated backups. State that in the pull
   request description, and that the data's backups are now lab-postgres's.

Deliver: the pull request and each apply's expected plan. Do not apply.
```

- [ ] **Step 2: The owner merges and applies, in the order P7 gave**

```sh
gcloud sql instances list --project=aleogr-schooling --format='value(name)'
```

Expected: nothing.

## Task 14: Record what happened in `aleogr/lab`

**Who:** this session. Pull request **C**.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-23-schooling-moves-in-design.md`
- Modify: `docs/superpowers/specs/2026-09-20-shared-database-instance-design.md`
- Modify: this plan

- [ ] **Step 1: Branch from `main`**

```sh
git fetch origin main && git checkout -b claude/lab-schooling-done origin/main
```

- [ ] **Step 2: The spec's "What is not verified" becomes what was measured**

Each item gets the date and the number: the connection peak and the split P1 chose (Task 2, Task 3); `pg_trgm` by the tenant's user (Task 10 Step 3); `cmd/load`'s longest run (Task 2); the drill before the move (Task 1) and after it (Task 12), with their table and row counts. The status line becomes `implemented, <date>`.

- [ ] **Step 3: The 2026-09-20 design's Phase 2 and Phase 3 point here**

One line under each: done on `<date>`, by this plan.

- [ ] **Step 4: Tick this plan's tasks against what shipped**

Each task's heading gets `— DONE, <date or commit>` as the earlier plans do, and any step that ran differently from what is written here is corrected to what ran, with the reason.

- [ ] **Step 5: Commit, push, open pull request C, subscribe to it**

```sh
git add docs/
git commit -m "Record schooling's move onto the shared instance"
git push -u origin claude/lab-schooling-done
```

---

## Now: pull request A

- [ ] **Step 1: Push the spec and this plan on `claude/lab-schooling-move`, open pull request A, subscribe to it**

Docs only; CI's plan must show `No changes`.

- [ ] **Step 2: When A is merged, hand the owner Task 1** — the first step of Stage 1.
