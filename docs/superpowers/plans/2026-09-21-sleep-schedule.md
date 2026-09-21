# The instance sleeps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put `lab-postgres` to sleep on four weeknights, and arrange everything that runs at night around the window instead of into it.

**Architecture:** Two Cloud Scheduler jobs in `aleogr/lab` call the Cloud SQL Admin API directly to set `activationPolicy` to `NEVER` and back to `ALWAYS`, authenticated by a service account of their own holding a named custom role. No function, no code, no build. The tenant arranges its own scheduled work around the published window, and a merge that lands inside the window is stopped by one check in the Terraform workflow, whose failure also stops the deployment that follows it.

**Tech Stack:** Terraform (version pinned in each repository's `.terraform-version`), Google Cloud provider, Cloud Scheduler, Cloud SQL Admin API v1, GitHub Actions with Workload Identity Federation, `bash` + `gcloud` + `jq` for the live checks.

**Spec:** `docs/superpowers/specs/2026-09-21-sleep-schedule-design.md`

## Global Constraints

- Everything versioned is written in **English**. Talk to the owner in Portuguese.
- Both repositories are **public**. No secret may ever be committed.
- Model identifiers appear only in the attribution trailer of commit messages and pull request descriptions — never in code, documentation, titles or comments.
- **Terraform is only ever applied by CI.** A session never runs `apply`.
- Claude Code opens the pull requests and **never merges**. The owner merges.
- **Never buy a green check.** No test skipped, no job made non-blocking, no threshold lowered.
- The window, copied verbatim from `docs/superpowers/specs/2026-09-20-shared-database-instance-design.md`:
  ```
  start  07:45  Tue–Fri   45 7 * * 2-5
  stop   22:00  Mon–Thu    0 22 * * 1-4
  time_zone = "America/Sao_Paulo"
  ```
- The shared project is `aleogr-lab-shared-dacd`; the instance is `lab-postgres`; the region is `us-central1`.
- A check never reads its expectation from the thing it is checking. `gcp/tools/check-federation.sh` is the pattern: expectations arrive as arguments, from a different file than the one being verified.

## Repositories and branches

| repository | branch | pull request |
|---|---|---|
| `aleogr/lab` | `claude/lab-sleep` (already carries the spec, commit `1a88b53`) | one, with the spec, this plan and Tasks 2–5 |
| `aleogr/marketplace` | `claude/funny-wright-379asb-labwindow` (to create from `main`) | one, Tasks 6–7 |

**Order between them matters.** The marketplace's pull request moves its nightly jobs out of the window and teaches its Terraform workflow to refuse a sleeping instance. It must be **merged first**. If the schedule lands first, the very next night produces ~585 failed `dispatch-outbox` runs before anybody moves it.

## File Structure

**`aleogr/lab`**

| file | responsibility |
|---|---|
| `gcp/terraform/sleeper.tf` (create) | the identity that may start and stop the instance, and the custom role that says what that means |
| `gcp/terraform/sleep.tf` (create) | the two Cloud Scheduler jobs — the schedule itself |
| `gcp/terraform/instance.tf` (modify) | one comment recording that `activation_policy` is absent on purpose |
| `gcp/tools/check-schedule.sh` (create) | asks the live project whether the schedule matches the design |
| `.github/workflows/ci.yml` (modify) | runs that check after the apply, like the two checks already there |
| `docs/lab.md` (modify) | states the policy and names the file the expressions live in |

The identity and the jobs are separate files for the same reason `tenant_role.tf` is separate from `tenants.tf`: one is a statement about power, the other a statement about behaviour, and they are reviewed by different questions.

**`aleogr/marketplace`**

| file | responsibility |
|---|---|
| `infra/terraform/audit.tf` (modify) | `verify-audit-chain` moves out of the window |
| `infra/terraform/tasks.tf` (modify) | `dispatch-outbox` stops running at night |
| `.github/workflows/terraform.yml` (modify) | refuses to apply against a sleeping instance, legibly |
| `docs/infrastructure.md` (modify) | records that these schedules are derived from the laboratory's window |

---

## Task 1: Measure what the design assumed

**This task produces a number, not a commit.** It runs in the owner's Cloud Shell, because a session holds no `gcloud` credential. It comes first because its answer can change Task 3.

The whole window rests on one unmeasured claim: the 2026-09-20 design put the start at 07:45 rather than 08:00 "because a stopped instance takes a minute or two to accept connections". Nobody timed it. If the real figure is six minutes, 07:45 is wrong and the start moves.

**Files:** none.

**Interfaces:**
- Consumes: nothing.
- Produces: a duration in seconds, used by Task 3 to confirm or change `45 7 * * 2-5`.

- [ ] **Step 1: Warn the owner what this does**

Give this to the owner one command at a time, and say plainly first: this stops the shared laboratory database and starts it again. `marketplace.lab.aleogr.dev` will answer `database: unreachable` for the duration. Nothing is lost — a stopped instance keeps its disk — but it is an outage of the laboratory, so it happens at a moment the owner picks.

- [ ] **Step 2: Stop the instance and time the stop**

```sh
PROJECT=aleogr-lab-shared-dacd
time gcloud sql instances patch lab-postgres \
  --project="$PROJECT" --activation-policy=NEVER --quiet
```

- [ ] **Step 3: Start it and time until it accepts a connection**

```sh
PROJECT=aleogr-lab-shared-dacd
date -u +%H:%M:%S
gcloud sql instances patch lab-postgres \
  --project="$PROJECT" --activation-policy=ALWAYS --quiet
date -u +%H:%M:%S

# Then poll until the service says the database is back, which is the
# thing that actually matters — not what the API reports about the instance.
until curl -sf https://marketplace.lab.aleogr.dev/health \
  | grep -q '"database":"ok"'; do sleep 5; done
date -u +%H:%M:%S
```

- [ ] **Step 4: Decide, and record the decision**

Three outcomes, and the plan says what each means rather than leaving it to judgement:

| measured | what to do |
|---|---|
| under 10 minutes | `45 7 * * 2-5` stands. Record the measured figure in the 2026-09-21 spec, replacing "a minute or two" with what was seen. |
| 10 to 20 minutes | the start moves earlier so the instance is up by 08:00 — `30 7 * * 2-5` or `15 7 * * 2-5`. Every document stating 07:45 changes with it, and this plan's Task 3, Task 5 and the CI step in Task 4 all carry the new expression. |
| over 20 minutes | stop and take it to the owner. A start that slow changes the case for sleeping at all, and that is a design decision, not an implementation one. |

- [ ] **Step 5: Amend the spec with the measurement**

The spec's section "What is not verified, and must be before this is called done" says nobody has timed it. Replace that paragraph with the figure and the date. Commit on `claude/lab-sleep`.

```bash
git add docs/superpowers/specs/2026-09-21-sleep-schedule-design.md
git commit -m "Record how long the instance really takes to come back"
```

---

## Task 2: The identity that may start and stop the instance

**Files:**
- Create: `gcp/terraform/sleeper.tf`
- Test: `gcp/tools/check-schedule.sh` (Task 4) proves it in the live project; here the test is `terraform validate` plus a reading of the plan output on the pull request.

**Interfaces:**
- Consumes: `var.project_id` (declared in `gcp/terraform/variables.tf`), `google_project_service.enabled` (declared in `gcp/terraform/services.tf`).
- Produces: `google_service_account.sleeper` with attribute `.email`, used by Task 3's two `oauth_token` blocks.

- [ ] **Step 1: Write the file**

Create `gcp/terraform/sleeper.tf`:

```hcl
/* THE IDENTITY THAT PUTS THE INSTANCE TO SLEEP, and the role that says what
   that is allowed to mean.

   It is held by two Cloud Scheduler jobs and by nothing else. Both send a
   constant body to one instance's URL, so what this account can be made to do
   is what those two jobs already do.

   IT IS WIDER THAN ITS NAME, and that is said here rather than implied away.
   Cloud SQL has no "may start and stop" permission: starting an instance is
   `instances.patch`, which is `cloudsql.instances.update`, which is also the
   permission that resizes the disk, rewrites the backup schedule and turns
   deletion protection off. This is the smallest role GCP allows for the job
   and it is still larger than the job. The same caveat the shared-instance
   design records about database grants applies here: a boundary described as
   tighter than it is will be trusted for something it does not do. */
resource "google_project_iam_custom_role" "sleeper" {
  project     = var.project_id
  role_id     = "sqlSleeper"
  title       = "Cloud SQL sleeper"
  description = "Starts and stops the shared instance on a schedule. It cannot delete it and owns no data."

  permissions = [
    "cloudsql.instances.get",
    "cloudsql.instances.update",
  ]
}

resource "google_service_account" "sleeper" {
  project      = var.project_id
  account_id   = "sleeper"
  display_name = "The schedule that stops and starts lab-postgres"
  description  = "Held by two Cloud Scheduler jobs and by nothing else. It may start and stop the shared instance; it reaches no database and no tenant."
}

resource "google_project_iam_member" "sleeper" {
  project = var.project_id
  role    = google_project_iam_custom_role.sleeper.name
  member  = "serviceAccount:${google_service_account.sleeper.email}"
}
```

- [ ] **Step 2: Check it is well-formed**

```sh
terraform -chdir=gcp/terraform fmt -check -recursive
terraform -chdir=gcp/terraform init -backend=false
terraform -chdir=gcp/terraform validate
```

Expected: `fmt` silent, `validate` prints `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add gcp/terraform/sleeper.tf
git commit -m "Give the schedule an identity of its own"
```

---

## Task 3: The schedule

**Files:**
- Create: `gcp/terraform/sleep.tf`
- Modify: `gcp/terraform/instance.tf` — the `settings` block, adding a comment where `activation_policy` is not
- Test: `terraform validate`; the live proof is Task 4's check and the apply on `main`.

**Interfaces:**
- Consumes: `google_service_account.sleeper.email` (Task 2), `google_sql_database_instance.shared.name` (declared in `gcp/terraform/instance.tf`), `var.project_id`, `var.region`.
- Produces: two `google_cloud_scheduler_job` resources named `lab-postgres-stop` and `lab-postgres-start`, which Task 4's check reads by those names.

**If Task 1 changed the start time, use the new expression everywhere below rather than `45 7 * * 2-5`.**

- [ ] **Step 1: Write the schedule**

Create `gcp/terraform/sleep.tf`:

```hcl
/* WHEN THE INSTANCE IS AWAKE, and the only place the expressions live.

   Cloud Scheduler calls the Cloud SQL Admin API itself. The alternative
   everybody reaches for — Scheduler to Pub/Sub to a Cloud Function — buys a
   runtime, a deployment and a piece of source to maintain, all to issue one
   HTTP request that Scheduler can issue on its own.

   NOT A SCHEDULED GITHUB ACTIONS WORKFLOW, for two reasons that are each
   enough. It would put a cron in the repository that holds a federation able
   to change a GCP project, and GitHub delays scheduled runs under load — an
   instance that sleeps at 22:14 because a queue was busy is not a schedule.

   The window is four weeknights: Friday night and Sunday night are left awake
   deliberately. The reasoning is in the 2026-09-20 design, and `docs/lab.md`
   states the policy for a reader who is not reading Terraform. */

resource "google_cloud_scheduler_job" "stop" {
  project     = var.project_id
  region      = var.region
  name        = "lab-postgres-stop"
  description = "Stops the shared instance for the night."

  schedule  = "0 22 * * 1-4"
  time_zone = "America/Sao_Paulo"

  attempt_deadline = "320s"

  # A stop that fails costs a few reais of instance-hours and nothing else.
  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.shared.name}"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ settings = { activationPolicy = "NEVER" } }))

    oauth_token {
      service_account_email = google_service_account.sleeper.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_cloud_scheduler_job" "start" {
  project     = var.project_id
  region      = var.region
  name        = "lab-postgres-start"
  description = "Starts the shared instance before the working day."

  schedule  = "45 7 * * 2-5"
  time_zone = "America/Sao_Paulo"

  attempt_deadline = "320s"

  # A START THAT FAILS IS NOT LIKE A STOP THAT FAILS. A day that begins against
  # a dead database is the failure this schedule can actually cause, so this
  # one retries and the stop does not.
  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "PATCH"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${google_sql_database_instance.shared.name}"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ settings = { activationPolicy = "ALWAYS" } }))

    oauth_token {
      service_account_email = google_service_account.sleeper.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_service.enabled]
}
```

- [ ] **Step 2: Record why `activation_policy` is not in `instance.tf`**

In `gcp/terraform/instance.tf`, inside the `settings` block, immediately after the `deletion_protection_enabled` line, add:

```hcl
    # `activation_policy` IS ABSENT ON PURPOSE. It is the one setting this
    # file does not own: `sleep.tf` changes it four times a week, and CI
    # applies this configuration on every merge to main. A line here naming
    # ALWAYS would wake the instance whenever somebody shipped a
    # documentation fix, and the schedule would lose to Terraform every time.
    # Completing this block by adding it would silently disable the schedule.
```

- [ ] **Step 3: Check it is well-formed**

```sh
terraform -chdir=gcp/terraform fmt -check -recursive
terraform -chdir=gcp/terraform init -backend=false
terraform -chdir=gcp/terraform validate
```

Expected: `fmt` silent, `validate` prints `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add gcp/terraform/sleep.tf gcp/terraform/instance.tf
git commit -m "Declare when the instance sleeps"
```

---

## Task 4: A check that asks the live project

**Files:**
- Create: `gcp/tools/check-schedule.sh`
- Modify: `.github/workflows/ci.yml` — a step after "The federation matches the design"
- Test: run it against the live project before the apply and watch it fail; after the apply, watch it pass.

**Interfaces:**
- Consumes: the two job names from Task 3 — `lab-postgres-stop` and `lab-postgres-start`.
- Produces: `gcp/tools/check-schedule.sh <project> <region> <instance> <stop-cron> <start-cron> <time-zone>`, exit 0 when the live schedule matches the arguments, exit 1 with a readable diagnosis when it does not.

The region is an argument rather than a default because Cloud Scheduler is a regional service and `jobs list` needs to be told where to look. Guessing it would be the check reading its own expectation again, one layer down.

**Read `gcp/tools/check-federation.sh` before writing this.** It is the pattern: the expectation arrives as arguments so that the check and the thing checked cannot agree by construction, and a `remainder` clause fails when the live world carries something the check does not know about.

- [ ] **Step 1: Write the check**

Create `gcp/tools/check-schedule.sh`, `chmod +x`:

```sh
#!/usr/bin/env bash
# Asks the live project whether the sleep schedule is what the design says.
#
# THE EXPECTATION ARRIVES AS ARGUMENTS, from the workflow rather than from the
# Terraform this verifies. A check that reads its expectation out of the thing
# it is checking passes whatever that thing says.
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: $0 <project> <region> <instance> <stop-cron> <start-cron> <time-zone>" >&2
  exit 2
fi

project=$1
region=$2
instance=$3
stop_cron=$4
start_cron=$5
zone=$6
failed=0

note() { echo "  $*"; }
fail() { echo "NOT AS DESIGNED: $*" >&2; failed=1; }

# ONE READ OF THE LIVE WORLD, reused by every assertion below. A `describe`
# per job would ask a moving target twice and could answer differently each
# time.
jobs=$(gcloud scheduler jobs list \
  --project="$project" --location="$region" --format=json)

check_job() {
  local name=$1 want_cron=$2 want_policy=$3
  local job cron tz state uri body policy

  job=$(jq -r --arg n "$name" \
    '.[] | select(.name | endswith("/jobs/" + $n))' <<<"$jobs")

  if [ -z "$job" ] || [ "$job" = "null" ]; then
    fail "the job '$name' does not exist"
    return
  fi

  cron=$(jq -r '.schedule' <<<"$job")
  tz=$(jq -r '.timeZone' <<<"$job")
  state=$(jq -r '.state' <<<"$job")
  uri=$(jq -r '.httpTarget.uri' <<<"$job")
  body=$(jq -r '.httpTarget.body // ""' <<<"$job" | base64 -d 2>/dev/null || echo "")
  policy=$(jq -r '.settings.activationPolicy // ""' <<<"$body" 2>/dev/null || echo "")

  [ "$cron" = "$want_cron" ] || fail "$name runs '$cron', the design says '$want_cron'"
  [ "$tz" = "$zone" ] || fail "$name is in '$tz', the design says '$zone'"
  [ "$state" = "ENABLED" ] || fail "$name is '$state' rather than ENABLED"
  [ "$policy" = "$want_policy" ] || fail "$name sets activationPolicy '$policy', the design says '$want_policy'"

  case "$uri" in
    *"/projects/$project/instances/$instance") : ;;
    *) fail "$name targets '$uri', which is not $instance in $project" ;;
  esac

  note "$name: $cron $tz, $state, sets $policy"
}

check_job "lab-postgres-stop"  "$stop_cron"  "NEVER"
check_job "lab-postgres-start" "$start_cron" "ALWAYS"

# ANYTHING ELSE THAT CAN TOUCH THE INSTANCE IS A FINDING. A third job nobody
# declared is exactly the thing this check exists to notice.
extra=$(jq -r --arg i "$instance" \
  '.[] | select((.httpTarget.uri // "") | contains("/instances/" + $i))
       | .name | split("/") | last' <<<"$jobs" \
  | grep -vx -e "lab-postgres-stop" -e "lab-postgres-start" || true)

if [ -n "$extra" ]; then
  fail "these jobs also target $instance and the design names none of them: $(echo "$extra" | tr '\n' ' ')"
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "the schedule matches the design"
```

- [ ] **Step 2: Check the shell is well-formed**

```sh
bash -n gcp/tools/check-schedule.sh
shellcheck gcp/tools/check-schedule.sh   # if shellcheck exists in this sandbox
```

`shellcheck` is installed in none of this session's sandboxes. If it is missing, say so in the pull request as an unrun check — never as a passed one.

- [ ] **Step 3: Add the step to CI**

In `.github/workflows/ci.yml`, after the "The federation matches the design" step, add:

```yaml
      # The third of the three: the instance's shape, who may authenticate,
      # and now when it is awake. Same reason as the two above — the schedule
      # that matters is the one Cloud Scheduler holds, not the one the files
      # describe.
      - name: The schedule matches the design
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: |
          ./gcp/tools/check-schedule.sh "${{ vars.GCP_PROJECT_ID }}" us-central1 \
            lab-postgres "0 22 * * 1-4" "45 7 * * 2-5" America/Sao_Paulo
```

- [ ] **Step 4: Collect the red, before the merge**

**This is a blocking step and it slipped last time.** The 2026-09-21 lab-home plan collected its red after the pull request had already merged, and the ledger records that the pre-apply moment was then gone for good. Do not repeat it.

Give the owner this, to run in Cloud Shell while the pull request is open and the schedule does not yet exist:

```sh
git clone https://github.com/aleogr/lab.git /tmp/lab-check
cd /tmp/lab-check && git checkout claude/lab-sleep
./gcp/tools/check-schedule.sh aleogr-lab-shared-dacd us-central1 \
  lab-postgres "0 22 * * 1-4" "45 7 * * 2-5" America/Sao_Paulo
echo "exit: $?"
```

Expected: `NOT AS DESIGNED: the job 'lab-postgres-stop' does not exist`, the same for `lab-postgres-start`, and `exit: 1`.

Paste that output into the pull request. A check first seen passing proves nothing.

- [ ] **Step 5: Commit**

```bash
git add gcp/tools/check-schedule.sh .github/workflows/ci.yml
git commit -m "Ask the live project whether the schedule is the designed one"
```

---

## Task 5: Say it in the laboratory's own words

**Files:**
- Modify: `docs/lab.md` — the section "When the instance is awake"

**Interfaces:**
- Consumes: the file `gcp/terraform/sleep.tf` created in Task 3, which it names.
- Produces: nothing other tasks read.

`docs/lab.md` currently opens that section with "**Not yet — the instance runs continuously today.**" That stops being true when this merges and applies.

- [ ] **Step 1: Rewrite the section**

The division the spec settles: this file carries the **policy**, `sleep.tf` carries the **expressions**, and a cron appears exactly once in the repository. Keep the two consequences that follow the section — the backup window and the missing transaction log — untouched; both are still true and neither depends on this change.

Replace the opening paragraph — the one beginning "**Not yet — the instance runs continuously today.**" — with this. `<measured>` is the one value Task 1 supplies, and it is the only thing left to fill in:

```markdown
Asleep four weeknights: Monday through Thursday, from 22:00 to 07:45 local
(UTC−3). Awake at every other hour, which means Friday night and the whole
weekend run unbroken — two hours until Saturday is not worth a stop and a
start, and a stop on Sunday night would risk the database going down at
midnight while somebody is still working.

The start is at 07:45 rather than 08:00 because a stopped instance does not
answer the moment it is asked to: measured on 2026-09-21, it took `<measured>`
from the start command to `/health` reporting `database: ok`.

`gcp/terraform/sleep.tf` holds the two cron expressions, and they appear
nowhere else in this repository — this section is the policy, that file is the
schedule.

**A tenant whose own work runs at night moves it, in its own repository.**
This project does not reach into a tenant's Cloud Scheduler for the same
reason it does not declare a tenant's database. `aleogr/marketplace` moved two
jobs for exactly this reason: an audit walk that ran at 01:17, and an outbox
dispatch that ran every minute of every day.
```

- [ ] **Step 2: Check nothing else still says it is not in effect**

```sh
grep -rn -iE "not in effect|runs continuously|four weeknight|22:00|07:45" \
  --include='*.md' --include='*.tf' . | grep -v '^./.superpowers'
```

Every hit must either be the new prose, the expressions in `sleep.tf`, or a dated historical record in `docs/superpowers/`. The live page on the `site` branch also says "that is not in effect yet" — it is **not** in this task and **not** in this pull request. Publishing it is the owner's act, and it happens after the first night the schedule actually runs, not before.

- [ ] **Step 3: Commit**

```bash
git add docs/lab.md
git commit -m "Say that the instance now really does sleep"
```

---

## Task 6: Move the marketplace's nightly work out of the window

**Repository: `aleogr/marketplace`. Branch: `claude/funny-wright-379asb-labwindow`, from `main`.**

**Files:**
- Modify: `infra/terraform/audit.tf:57`
- Modify: `infra/terraform/tasks.tf:113-114`
- Modify: `docs/infrastructure.md`
- Test: `make check`, `make test`, and reading the Terraform plan the pull request comments.

**Interfaces:**
- Consumes: the window, as policy, from `docs/lab.md` in `aleogr/lab`.
- Produces: nothing other tasks read.

- [ ] **Step 1: Move `verify-audit-chain`**

`infra/terraform/audit.tf` line 57 reads `schedule = "17 4 * * *"` with `time_zone = "Etc/UTC"` — 04:17 UTC, which is 01:17 local, inside the window. Change the schedule to `"17 12 * * *"`, leaving the time zone as `Etc/UTC`: 12:17 UTC is 09:17 local, comfortably inside the working day.

Extend the comment above the resource with a sentence saying the hour is not free to move: it sits inside the laboratory's awake window, which `aleogr/lab` publishes in `docs/lab.md`.

- [ ] **Step 2: Move `dispatch-outbox`**

`infra/terraform/tasks.tf` lines 113–114 read `schedule = "* * * * *"` and `time_zone = "Etc/UTC"`. Change to:

```hcl
  schedule  = "* 8-21 * * *"
  time_zone = "America/Sao_Paulo"
```

Extend the comment above the resource:

```
  # IT DOES NOT RUN AT NIGHT, because the database it reads is deliberately
  # off: the shared instance sleeps four weeknights (aleogr/lab, docs/lab.md).
  # Every minute from 08:00 to 21:59 local is inside the awake period on every
  # day of the week, which is one expression that is always safe rather than
  # four that are exactly right. The cost is that an event written at 23:00
  # waits until 08:00, including on the nights the instance is in fact awake.
  #
  # The alternatives were worse. Letting it fail every minute turns a job
  # dashboard into something nobody reads, and then a real failure hides among
  # the expected ones. Making the handler return success when the database is
  # unreachable hides a genuine outage exactly as well as a planned one.
```

- [ ] **Step 3: Run the checks**

```sh
make check
make test
```

Expected: both clean. Neither touches Terraform, but a comment edit that broke a Go build would be found here, and `make check` runs `terraform fmt` through its own path — if it does not, run `terraform -chdir=infra/terraform fmt -check -recursive` as well.

- [ ] **Step 4: Record it where the marketplace explains itself**

In `docs/infrastructure.md`, in the section that already explains the noon backup window and the sleep window, add a short paragraph naming both jobs, their new hours, and the rule: the laboratory publishes the window, and this project arranges its own scheduled work around it. Say that the window's authority is `docs/lab.md` in `aleogr/lab` and that these two expressions are derived from it, so a change to the window is a change here.

- [ ] **Step 5: Commit**

```bash
git add infra/terraform/audit.tf infra/terraform/tasks.tf docs/infrastructure.md
git commit -m "Keep the nightly jobs out of the window the instance sleeps in"
```

---

## Task 7: Refuse to deploy into a sleeping instance, legibly

**Repository: `aleogr/marketplace`, same branch as Task 6.**

**Files:**
- Modify: `.github/workflows/terraform.yml` — the `apply` job, a step between "Initialise" and "Apply"
- Test: the step's own logic, exercised locally against both states; the live proof is a run.

**Interfaces:**
- Consumes: `vars.GCP_TERRAFORM_SA`, already used by the job; `shared_project_id` and the instance name, read from the repository rather than retyped.
- Produces: nothing other tasks read.

**One check is enough, and this is why.** `deploy.yml` runs on `workflow_run` from Terraform with `if: github.event.workflow_run.conclusion == 'success'`. A Terraform run that fails therefore stops the deployment too. And the apply job authenticates as `terraform@`, which holds `sqlTenant`, which includes `cloudsql.instances.get` — so it can read the instance's state without any new grant. The spec described two workflows failing legibly; one check placed here does both.

- [ ] **Step 1: Add the step**

In `.github/workflows/terraform.yml`, in the `apply` job, between "Initialise" and "Apply":

```yaml
      # THE INSTANCE SLEEPS FOUR WEEKNIGHTS (aleogr/lab, docs/lab.md), and
      # every resource this applies against it — the database, the users —
      # fails when it is stopped. Without this step that arrives as a 400 from
      # the Cloud SQL API in the middle of an apply; with it, it arrives as a
      # sentence. `deploy.yml` runs only when this workflow succeeds, so this
      # one check also stops the deployment that would follow.
      #
      # `cloudsql.instances.get` is part of the sqlTenant role this job already
      # holds. Starting the instance is NOT: that is cloudsql.instances.update,
      # which the role withholds on purpose, and which is the same permission
      # that would let this repository stop the instance other projects share.
      - name: Refuse to apply against a sleeping instance
        run: |
          shared=$(grep -E '^\s*shared_project_id\s*=' lab/lab.tfvars \
            | sed -E 's/.*"([^"]+)".*/\1/')
          state=$(gcloud sql instances describe lab-postgres \
            --project="$shared" --format='value(settings.activationPolicy)')
          echo "activationPolicy=$state"
          if [ "$state" != "ALWAYS" ]; then
            echo "::error::The shared instance lab-postgres is stopped." \
              "It sleeps Monday to Thursday, 22:00 to 07:45 local" \
              "(aleogr/lab, docs/lab.md). Nothing is wrong with this commit;" \
              "re-run this workflow after the instance starts."
            exit 1
          fi
```

- [ ] **Step 2: Exercise both branches of the condition locally**

The step is shell, so test it as shell, with the `gcloud` call replaced by each answer it can give:

```sh
for state in ALWAYS NEVER; do
  ( set -e
    echo "activationPolicy=$state"
    if [ "$state" != "ALWAYS" ]; then echo "would fail"; exit 1; fi
    echo "would apply" )
  echo "exit: $?"
done
```

Expected: `ALWAYS` → `would apply`, `exit: 0`. `NEVER` → `would fail`, `exit: 1`.

- [ ] **Step 3: Check the tfvars parsing against the real file**

```sh
grep -E '^\s*shared_project_id\s*=' infra/terraform/lab/lab.tfvars \
  | sed -E 's/.*"([^"]+)".*/\1/'
```

Expected: exactly `aleogr-lab-shared-dacd`, one line, no quotes.

- [ ] **Step 4: Confirm the workflow still parses**

```sh
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/terraform.yml')); print('valid')"
actionlint .github/workflows/terraform.yml   # if actionlint exists in this sandbox
```

`actionlint` is installed in none of this session's sandboxes. If it is missing, say so in the pull request as an unrun check.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/terraform.yml
git commit -m "Say why an apply failed when the instance is asleep"
```

---

## Task 8: Open the two pull requests, in order

**Files:** none.

- [ ] **Step 1: Push both branches**

```bash
git -C <marketplace> push -u origin claude/funny-wright-379asb-labwindow
git -C <lab> push -u origin claude/lab-sleep
```

- [ ] **Step 2: Open the marketplace's pull request first**

Its body says what moved and why, names `aleogr/lab`'s window as the authority, and states plainly that it must merge **before** the laboratory's, because a schedule that lands first produces a night of failures before anybody moves these jobs.

- [ ] **Step 3: Open the laboratory's pull request**

Its body carries the spec's reasoning, the red collected in Task 4 Step 4, the measured wake-up figure from Task 1, and the unrun checks named as unrun.

- [ ] **Step 4: Subscribe to both and watch them to green**

- [ ] **Step 5: After the laboratory's merge, read the apply's own log**

The pull request run stops at `plan`; `apply` and the three checks run only on the push to `main`. Confirm from that log that "The schedule matches the design" printed and passed — that, and not the plan, is the first evidence the two jobs exist.

- [ ] **Step 6: Watch the first night — this is the proof, not the apply**

The spec names one thing it could not verify: **that Cloud Scheduler's `oauth_token` authenticates against `sqladmin.googleapis.com`.** No apply proves that. A job can exist, be enabled, carry the right cron and the right body, and still be refused by the API the first time it fires. Until a night has run, D1 is a claim.

So the morning after the first stop, read the live world rather than the dashboard:

```sh
curl -s https://marketplace.lab.aleogr.dev/health
```

Before 07:45 it should answer `"database":"unreachable"`; after the start, `"database":"ok"`. The index page at `lab.aleogr.dev` shows the same thing without a terminal.

Then read both jobs' last result, which is where an authentication refusal would actually appear:

```sh
gcloud scheduler jobs describe lab-postgres-stop \
  --project=aleogr-lab-shared-dacd --location=us-central1 \
  --format='value(status.code, status.message, lastAttemptTime)'
```

Expected: an empty status and a recent `lastAttemptTime`. A `status.code` of 7 or 16 is the `oauth_token` being refused, and it means D1 is wrong rather than merely unproven — bring it back to the owner instead of patching around it.

Once that has happened, amend the 2026-09-21 spec: the `oauth_token` line moves out of "what is not verified" and becomes a dated fact.

Only once a night has actually run is the `site` branch's sentence — "that is not in effect yet" — false, and only then is it the owner's to publish.
