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
  start  07:30  Tue–Fri   30 7 * * 2-5
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
| `gcp/terraform/instance.tf` (modify) | a `lifecycle` block that has Terraform ignore `activation_policy`, since leaving the field absent let the provider fill it with `ALWAYS` and fight the schedule |
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

## Task 1: Measure what the design assumed — DONE, 2026-09-21

**This task produced a number, not a commit.** It ran in the owner's Cloud
Shell, because a session holds no `gcloud` credential, and it came first
because its answer could change Task 3. It did.

**The result: 686 seconds.** Eleven minutes and twenty-six seconds from
issuing `activation-policy=ALWAYS` to `marketplace.lab.aleogr.dev/health`
answering `database: ok`. Stopping took 55 seconds.

The 2026-09-20 design had put the start at 07:45 "because a stopped instance
takes a minute or two to accept connections". That estimate was wrong by
between six and eleven times. 07:45 would still have worked — by three and a
half minutes — which is not a margin on a sample of one, so **the start moved
to `30 7 * * 2-5`**, leaving about eighteen minutes over the measured figure.
Fifteen more awake minutes on four nights is roughly 4.3 hours a month, about
R$ 0.27.

Two things the measurement settled that were not what it was for:

- **`gcloud` gave up waiting after 600 seconds** on an operation that
  succeeded, which is how we know the Admin API's `PATCH` returns an operation
  rather than blocking. So Cloud Scheduler will record that its request was
  *accepted*, not that the instance *started*. Task 8 Step 6 depends on this.
- **`attempt_deadline = "320s"` is generous rather than tight**, for the same
  reason: the job does not wait the operation out.

The measurement also gave the index page its first real test, unplanned: with
the instance stopped, the `marketplace` card read `down · 503 · database
unreachable · 202639b-20260921` — the 503, the reason, the CORS header that
lets a browser read it, and the deployed version, all confirmed against a real
outage rather than a mock.

**Files:** none. The corrections it forced are commits of their own, on
`claude/lab-sleep`: the 2026-09-20 spec's estimate replaced by the measurement
with the estimate left visible, the 2026-09-21 spec moved from "not verified"
to "what was verified", and this plan carrying `30 7 * * 2-5` throughout.

**Interfaces:**
- Consumes: nothing.
- Produces: `30 7 * * 2-5`, used by Task 3, Task 4 and Task 5.

- [x] **Step 1: Warn the owner what this does**
- [x] **Step 2: Stop the instance and time the stop** — 55 seconds.
- [x] **Step 3: Start it and time until it accepts a connection** — 686 seconds.
- [x] **Step 4: Decide** — the 10-to-20-minute band, so the start moved earlier.
- [x] **Step 5: Amend the specs with the measurement**

**If the window is ever changed again, this is the procedure.** Measure against
`/health`, not against the API's opinion of itself; a start that reports
success is not a database that answers.

---

## Task 2: The identity that may start and stop the instance — DONE, `43dd680`

**Files:**
- Create: `gcp/terraform/sleeper.tf`
- Test: `gcp/tools/check-schedule.sh` (Task 4) proves it in the live project; here the test is `terraform validate` plus a reading of the plan output on the pull request.

**Interfaces:**
- Consumes: `var.project_id` (declared in `gcp/terraform/variables.tf`), `google_project_service.enabled` (declared in `gcp/terraform/services.tf`).
- Produces: `google_service_account.sleeper` with attribute `.email`, used by Task 3's two `oauth_token` blocks.

- [x] **Step 1: Write the file** — done, `43dd680`. The shipped file's comments
  are worded differently from the draft below (refined while writing it — see
  the commit message), but the three resources, the role id, the permissions
  and the account id match this step exactly.

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

- [x] **Step 2: Check it is well-formed** — done. `fmt -check -recursive` and
  `validate` both pass at `43dd680` (re-run against that commit directly to
  confirm, rather than trusted from the diff): `fmt` silent, `validate` prints
  `Success! The configuration is valid.`

```sh
terraform -chdir=gcp/terraform fmt -check -recursive
terraform -chdir=gcp/terraform init -backend=false
terraform -chdir=gcp/terraform validate
```

Expected: `fmt` silent, `validate` prints `Success! The configuration is valid.`

- [x] **Step 3: Commit** — `43dd680`, "Give the schedule an identity of its own".

```bash
git add gcp/terraform/sleeper.tf
git commit -m "Give the schedule an identity of its own"
```

**Not a step of its own, and not scope creep: `f5fe14a`.** Creating
`google_service_account.sleeper` above needs `iam.serviceAccounts.create`,
which none of the deploy identity's three declared roles carry. `deployer@`
already held `roles/iam.serviceAccountAdmin` on the live project — granted by
hand at bootstrap, the same way `workloadIdentityPoolAdmin` and `roleAdmin`
were — but `deployer.tf` and `README.md` had never caught up to that grant,
because an undeclared permission that is already held stays silent: nothing
fails, so nothing asks. `sleeper.tf` is the first resource in this repository
to actually need it, which surfaced the gap by luck rather than by process.
`f5fe14a` declares the grant this task's own Step 1 depends on; it belongs on
this branch because Task 2 is what needed it, not because Task 2 asked for it.

---

## Task 3: The schedule — DONE, `82c64fa`, Step 3 corrected in `ebb2017`

**Files:**
- Create: `gcp/terraform/sleep.tf`
- Modify: `gcp/terraform/instance.tf` — a `lifecycle { ignore_changes = [...] }` block on `google_sql_database_instance.shared`, telling Terraform not to manage `activation_policy` (corrected in `ebb2017` from the comment-only approach this line first described)
- Test: `terraform validate`; the live proof is Task 4's check and the apply on `main`.

**Interfaces:**
- Consumes: `google_service_account.sleeper.email` (Task 2), `google_sql_database_instance.shared.name` (declared in `gcp/terraform/instance.tf`), `var.project_id`, `var.region`.
- Produces: two `google_cloud_scheduler_job` resources named `lab-postgres-stop` and `lab-postgres-start`, which Task 4's check reads by those names.

**Task 1 moved the start from 07:45 to 07:30. `30 7 * * 2-5` below is that decision; it is not the figure the 2026-09-20 design was written with.**

- [x] **Step 1: Write the schedule** — done, `82c64fa`, matching the block below.

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

  schedule  = "30 7 * * 2-5"
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

- [x] **Step 2: Correct the hour the backup comment names** — done, `82c64fa`.

`gcp/terraform/instance.tf` line 40 says the instance is stopped "from 22:00 to
07:45 local on Monday, Tuesday, Wednesday and Thursday nights". Task 1 moved
the start. Change 07:45 to 07:30 and leave the rest of that comment alone — its
argument, that a backup window in the small hours would silently stop producing
backups, does not depend on the minute.

- [x] **Step 3: Make Terraform ignore `activation_policy`, and say why** — done,
  corrected in `ebb2017` after the comment-only approach shipped in `82c64fa`
  turned out not to work. The paragraph below already narrates that
  correction; nothing further to reconcile.

**This step was revised after it first shipped.** The original instruction
here was to leave `activation_policy` out of the `settings` block and add a
comment saying the omission was deliberate. That shipped, and it does not do
what it was written to do: `activation_policy` is Optional but not Computed in
provider 8.3.0's own schema (`terraform providers schema -json`), unlike
`edition` and `disk_type` beside it, and a plan run against a state carrying
`NEVER` — the instance stopped for the night — proposed `NEVER -> ALWAYS` as
an in-place update, with the field still absent from config. Omitting the
field is not the same as telling Terraform to ignore it. D2 in the design
records this in full; this step now matches what D2 actually specifies.

In `gcp/terraform/instance.tf`, on `google_sql_database_instance.shared`, add
a `lifecycle { ignore_changes = [settings[0].activation_policy] }` block, with
a comment above it carrying: that `sleep.tf` owns this field and nothing else
does; that omission was tried first and does not work, with the schema finding
and the reproduced plan that proves it; what an unpatched apply would have
cost (CI applies on every merge to `main`, and `check-instance.sh` does not
read this field, so a merge inside the window would have woken the instance
in silence); and the trade `ignore_changes` accepts — Terraform manages this
field in neither direction now, so an instance stopped by hand and forgotten
stays stopped, which is deliberate because `check-schedule.sh` (Task 4) is
what verifies the schedule, not this file.

- [x] **Step 4: Check it is well-formed** — done. `fmt -check -recursive` and
  `validate` both pass at `82c64fa` and again at `ebb2017` (checked out and
  re-run against each directly): `fmt` silent, `validate` prints `Success! The
  configuration is valid.`

```sh
terraform -chdir=gcp/terraform fmt -check -recursive
terraform -chdir=gcp/terraform init -backend=false
terraform -chdir=gcp/terraform validate
```

Expected: `fmt` silent, `validate` prints `Success! The configuration is valid.`

- [x] **Step 5: Commit** — `82c64fa`, "Declare when the instance sleeps". The
  `activation_policy` fix that followed is its own commit, `ebb2017`, "Ignore
  activation_policy instead of omitting it" — not this step's commit, since it
  corrects what this step first shipped.

```bash
git add gcp/terraform/sleep.tf gcp/terraform/instance.tf
git commit -m "Declare when the instance sleeps"
```

---

## Task 4: A check that asks the live project — DONE, `65b632a`

**Files:**
- Create: `gcp/tools/check-schedule.sh`
- Modify: `.github/workflows/ci.yml` — a step after "The federation matches the design"
- Test: run it against the live project before the apply and watch it fail; after the apply, watch it pass.

**Interfaces:**
- Consumes: the two job names from Task 3 — `lab-postgres-stop` and `lab-postgres-start`.
- Produces: `gcp/tools/check-schedule.sh <project> <region> <instance> <stop-cron> <start-cron> <time-zone>`, exit 0 when the live schedule matches the arguments, exit 1 with a readable diagnosis when it does not.

The region is an argument rather than a default because Cloud Scheduler is a regional service and `jobs list` needs to be told where to look. Guessing it would be the check reading its own expectation again, one layer down.

**Read `gcp/tools/check-federation.sh` before writing this.** It is the pattern: the expectation arrives as arguments so that the check and the thing checked cannot agree by construction, and a `remainder` clause fails when the live world carries something the check does not know about.

- [x] **Step 1: Write the check** — done, `65b632a`, `chmod +x` set. The
  shipped script is not byte-for-byte the draft below: exercising it against
  fixtures found two bugs in the draft and fixed them before shipping — a
  `// ""` default missing from the plain `schedule`/`timeZone`/`state`/`uri`
  reads (so a job with those fields absent read as the literal string `"null"`
  instead of empty), and the extra-job scan matching `endswith` rather than
  `contains` on the instance URI (so `lab-postgres-replica` cannot be
  misreported as targeting `lab-postgres`). Same checks, same argument
  contract, same two job names.

  **A third difference, larger than the first two and not previously
  recorded here:** the whole reporting mechanism changed. The draft below has
  `fail()` write `NOT AS DESIGNED: <message>` to stderr and set a flag; the
  shipped script has `report()` write aligned columns
  (`printf '%-34s %s, want %s\n'`) to stdout and count `failures`, ending in
  a `"$failures mismatch(es)..."` summary the draft never printed. This is
  the same fixture exercise that found the first two differences, and it is
  why Step 4 below originally quoted an "Expected" line that never shipped —
  corrected there.

  **A fourth difference, later than the other three and later than this
  record was last written:** `cb0248f` replaced the extra-job scan's
  `endswith` match — the one lines 392-393 above still describe as what
  shipped in `65b632a` — with the boundary `test(...)` the live file now
  carries. `endswith`, anchored on the project too, still rejected
  `-replica`, but it also rejected every legitimate suffix: a query string, a
  trailing slash, a sub-path — so a rogue job reached through any of those
  forms passed uncaught. The boundary regex accepts anything that starts a
  new path segment, a query string, a fragment, or (added in the re-review
  that found this paragraph itself stale) GCP's own custom-verb separator or
  a statement separator, while `-replica` still cannot match any of them.
  Lines 392-393 are left describing `endswith`, deliberately, because that is
  what `65b632a` shipped and this is a draft-to-shipped record of that
  commit; `cb0248f` is a later commit correcting the shipped script further,
  not a correction of what this paragraph says `65b632a` did.

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

- [x] **Step 2: Check the shell is well-formed** — done, only partly:
  `bash -n gcp/tools/check-schedule.sh` passes (exit 0). `shellcheck` did not
  run — it is installed in none of this session's sandboxes, exactly as this
  step warns below, so this stays an unrun check rather than a passed one.

```sh
bash -n gcp/tools/check-schedule.sh
shellcheck gcp/tools/check-schedule.sh   # if shellcheck exists in this sandbox
```

`shellcheck` is installed in none of this session's sandboxes. If it is missing, say so in the pull request as an unrun check — never as a passed one.

- [x] **Step 3: Add the step to CI** — done, `65b632a`, matching the block
  below exactly.

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
            lab-postgres "0 22 * * 1-4" "30 7 * * 2-5" America/Sao_Paulo
```

- [x] **Step 4: Collect the red, before the merge** — done, 2026-09-21.

**This is a blocking step and it slipped last time.** The 2026-09-21 lab-home plan collected its red after the pull request had already merged, and the ledger records that the pre-apply moment was then gone for good. Do not repeat it. **This time the order is right: the owner ran the check below against the live project while `claude/lab-sleep` was still unmerged and the schedule did not yet exist**, before this pull request opens — not after.

Given to the owner, to run in Cloud Shell while the pull request is open and the schedule does not yet exist:

```sh
git clone https://github.com/aleogr/lab.git /tmp/lab-check
cd /tmp/lab-check && git checkout claude/lab-sleep
./gcp/tools/check-schedule.sh aleogr-lab-shared-dacd us-central1 \
  lab-postgres "0 22 * * 1-4" "30 7 * * 2-5" America/Sao_Paulo
echo "exit: $?"
```

Expected (shipped format — `report()`'s aligned columns, not the draft's
`fail()`; see Step 1's note on the third draft-to-shipped difference):
`lab-postgres-stop                  does not exist, want to exist`, the same
for `lab-postgres-start`, a `"2 mismatch(es)..."` summary line, and `exit: 1`.

**Collected, 2026-09-21, against the live project, schedule not yet applied:**

```
lab-postgres-stop                  does not exist, want to exist
lab-postgres-start                 does not exist, want to exist
2 mismatch(es) between the live schedule and the design
exit: 1
```

Two jobs missing, `exit: 1` — the schedule does not yet exist, exactly as expected before this merges. Paste that output into the pull request. A check first seen passing proves nothing.

- [x] **Step 5: Commit** — `65b632a`, "Ask the live project whether the
  schedule is the designed one". That commit also carried the File Structure
  table correction noted above (this plan file, not just the two files
  below). Step 4's own red is recorded in that step above and was committed
  separately, later, in `fa54ff8`.

```bash
git add gcp/tools/check-schedule.sh .github/workflows/ci.yml
git commit -m "Ask the live project whether the schedule is the designed one"
```

---

## Task 5: Say it in the laboratory's own words — DONE, `fa54ff8`

**Files:**
- Modify: `docs/lab.md` — the section "When the instance is awake"

**Interfaces:**
- Consumes: the file `gcp/terraform/sleep.tf` created in Task 3, which it names.
- Produces: nothing other tasks read.

`docs/lab.md` currently opens that section with "**Not yet — the instance runs continuously today.**" That stops being true when this merges and applies.

- [x] **Step 1: Rewrite the section** — done, `fa54ff8`. **Corrected since:**
  the shipped paragraph claimed the two cron expressions "appear nowhere else
  in this repository", which was false the day it shipped —
  `.github/workflows/ci.yml` passes the same two expressions to
  `check-schedule.sh` as its expectation, deliberately, per the Global
  Constraint that a check must not read its expectation from the thing it
  checks. A later commit on this branch rewrites both this section and the
  2026-09-21 spec's D4 and Risks section to say the expressions live in
  exactly two places on purpose, name both, and say that changing the window
  means changing both.

The division the spec settles: this file carries the **policy**, `sleep.tf` carries the **expressions**. **This is the note that found the contradiction fixed above, and this sentence is what it was contradicting:** the paragraph two steps above already says a later commit rewrote this section to say the expressions live in two operative places on purpose, naming both; the instruction below has to match that, not the disproven "appears nowhere else" claim it replaced. Keep the two consequences that follow the section — the backup window and the missing transaction log — untouched; both are still true and neither depends on this change.

Replace the opening paragraph — the one beginning "**Not yet — the instance runs continuously today.**" — with this:

```markdown
Asleep four weeknights: Monday through Thursday, from 22:00 to 07:30 local
(UTC−3). Awake at every other hour, which means Friday night and the whole
weekend run unbroken — two hours until Saturday is not worth a stop and a
start, and a stop on Sunday night would risk the database going down at
midnight while somebody is still working.

The start is at 07:30 rather than 08:00 because a stopped instance does not
answer the moment it is asked to: measured on 2026-09-21, it took 686 seconds
— eleven and a half minutes — from the start command to `/health` reporting
`database: ok`.

The two cron expressions live in two operative places that must be kept in
step, on purpose, outside the design documents that quote them for
reference: `gcp/terraform/sleep.tf`, the schedule itself, and the
`check-schedule.sh` invocation in `.github/workflows/ci.yml`, which is what
that script is told to expect. The second copy is not drift — it exists
because a check must not read its expectation from the thing it is checking.
**Changing the window means changing both operative places**, `sleep.tf` and
the arguments in `ci.yml`.

**A tenant whose own work runs at night moves it, in its own repository.**
This project does not reach into a tenant's Cloud Scheduler for the same
reason it does not declare a tenant's database. `aleogr/marketplace` moved two
jobs for exactly this reason: an audit walk that ran at 01:17, and an outbox
dispatch that ran every minute of every day.
```

- [x] **Step 2: Reconcile the three documents Task 1's measurement invalidated** — done, `fa54ff8`.

Moving the start from 07:45 to 07:30 left `07:45` standing in three places that
are not historical records, and one of them is a promise this repository made
three commits ago.

1. **`docs/superpowers/specs/2026-09-21-lab-home-design.md`, D6's `/health`
   illustration** — "from 22:00 to 07:45 the instance sleeps". It is an
   illustration of what the page will show, so the hour has to be the real one.
   Change it to 07:30.

2. **`docs/superpowers/plans/2026-09-21-lab-home.md`, Task 5's quoted
   `docs/lab.md` block** — it quotes the paragraph this task is rewriting, so it
   diverges the moment this task lands.

3. **That same plan's status block**, which says quoted content "agrees with
   the file it produced". Once `docs/lab.md` moves on for a reason that has
   nothing to do with that plan, the sentence stops being true, and chasing it
   forever is not the answer. Narrow it: the quotes record what each task
   produced **on the day it shipped**, and a later change to the file is a
   later decision rather than a divergence to fix. Then update the Task 5 block
   once, to what this task writes, and say in the block that it was refreshed
   on 2026-09-21 when the start time moved.

The third is the interesting one. That sentence was added to stop a reader
treating a stale quote as a competing decision — and it was written as though
quoted content could stay current forever, which nothing can.

- [x] **Step 3: Check nothing else still says it is not in effect** — done,
  `fa54ff8`, but **the sweep as shipped could not and did not reach
  everything, and both misses were found later, not by this step:**

  - **The `site` branch's public page (C2).** The command below only ever
    grepped `--include='*.md' --include='*.tf'` in the working tree. The
    page this task's own prose points at — "the live page on the `site`
    branch also says 'that is not in effect yet'" — is `index.html` on an
    **orphan branch**, which is neither an `.md`/`.tf` file nor in this
    branch's working tree. That combination is structurally invisible to
    the command as shipped; it could not have found the page's stale hour
    (07:45, moved to 07:30 the same day, in commit `ac48128`) no matter how
    carefully it was read. Fixed below by adding `--include='*.html'` and an
    explicit `git show site:index.html` pass, which is the only way to reach
    a file that lives on a branch this one never checks out.
  - **The 2026-09-20 spec's status line (C3).** The acceptance rule below
    exempted "a dated historical record in `docs/superpowers/`", and the
    2026-09-20 spec's status line matched that exemption's location without
    meeting its purpose: that document itself says its status line "says
    what the world has since done, not why" — a live tracker, not a record
    of what was true on the date in the filename. The rule as written let a
    line that will go stale the moment `aleogr/lab` merges pass as though it
    were dated history. Narrowed below.
  - **This design's own status line and opening paragraph (found in
    re-review, after this step shipped).** `grep` matches line by line, and
    this document's own opening wrapped the phrase across a line break — "...
    now says, correctly, that it is not in\neffect." — with "not in" ending
    one line and "effect." starting the next. The pattern
    `"not in effect"` cannot match text no single line contains, so this
    sweep walked past the exact sentence its own prose most needed to catch,
    in the file it was written in. Line-wrapped prose is invisible to a
    line-by-line grep on principle, not by bad luck here, and nothing about
    C2 or C3's fixes touches that. Fixed below by joining each file's lines
    before matching, so a phrase wrapped by hand cannot hide from a pattern
    written on one line.

```sh
grep -rn -iE "not in effect|runs continuously|four weeknight|22:00|07:30" \
  --include='*.md' --include='*.tf' --include='*.html' . \
  | grep -v '^./.superpowers'

# THE PASS ABOVE IS LINE-BY-LINE AND MISSES A PHRASE WRAPPED ACROSS A LINE
# BREAK, which is exactly how this design's own opening paragraph hid from
# it once. Join each file's lines into one before matching, so wrapping
# cannot hide a phrase from a pattern that names it whole.
grep -rlZ --include='*.md' --include='*.tf' --include='*.html' -e . . \
  | grep -vz '^./.superpowers' \
  | xargs -0 -I{} sh -c 'tr "\n" " " < "{}" | grep -inE -o ".{0,40}(not in effect|runs continuously|four weeknight).{0,40}" && echo "  in: {}"'

git show site:index.html | grep -n -iE "not in effect|runs continuously|four weeknight|22:00|07:4|07:3"
git show site:index.html | tr '\n' ' ' | grep -inE -o ".{0,40}(not in effect|runs continuously|four weeknight).{0,40}"
```

Every working-tree hit must either be the new prose, the expressions in
`sleep.tf`, or a genuinely dated historical record — a passage that describes
what was true **on the date in its own filename or heading**, not a status
line that is written to track the present and will go stale on somebody
else's merge; `docs/superpowers/` alone does not make a line historical. The
`git show site:index.html` pass must show either the corrected hour with "not
in effect yet" still standing, or nothing — never a hit that this sweep
silently skipped because the file lives outside the working tree. The live
page on the `site` branch keeps saying "that is not in effect yet": that
sentence is **not** in this task and **not** in this pull request, and stays
true until the first night the schedule actually runs. Only its hour, a
separate and already-stale fact, is this session's to correct, on the `site`
branch, unpushed.

- [x] **Step 4: Commit** — done, `fa54ff8`.

```bash
git add docs/lab.md docs/superpowers/specs/2026-09-21-lab-home-design.md \
  docs/superpowers/plans/2026-09-21-lab-home.md
git commit -m "Say that the instance now really does sleep"
```

---

## Task 6: Move the marketplace's nightly work out of the window — DONE, `faed8f4`, documentation fallout corrected in `043ae57` and `cf6a25e`

**Repository: `aleogr/marketplace`. Branch: `claude/funny-wright-379asb-labwindow`, from `main`.**

**Files:**
- Modify: `infra/terraform/audit.tf:57`
- Modify: `infra/terraform/tasks.tf:113-114`
- Modify: `docs/infrastructure.md`
- Test: `make check`, `make test`, and reading the Terraform plan the pull request comments.

**Interfaces:**
- Consumes: the window, as policy, from `docs/lab.md` in `aleogr/lab`.
- Produces: nothing other tasks read.

- [x] **Step 1: Move `verify-audit-chain`** — done, `faed8f4`.

`infra/terraform/audit.tf` line 57 reads `schedule = "17 4 * * *"` with `time_zone = "Etc/UTC"` — 04:17 UTC, which is 01:17 local, inside the window. Change the schedule to `"17 12 * * *"`, leaving the time zone as `Etc/UTC`: 12:17 UTC is 09:17 local, comfortably inside the working day.

Extend the comment above the resource with a sentence saying the hour is not free to move: it sits inside the laboratory's awake window, which `aleogr/lab` publishes in `docs/lab.md`.

- [x] **Step 2: Move `dispatch-outbox`** — done, `faed8f4`.

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

- [x] **Step 3: Run the checks** — done, `faed8f4`.

```sh
make check
make test
```

Expected: both clean. Neither touches Terraform, but a comment edit that broke a Go build would be found here, and `make check` runs `terraform fmt` through its own path — if it does not, run `terraform -chdir=infra/terraform fmt -check -recursive` as well.

- [x] **Step 4: Record it where the marketplace explains itself** — done,
  `faed8f4`. **Corrected twice since it shipped, neither correction a
  revision of this step's own work:** `043ae57` fixed a stale `07:45` and
  removed a "not in effect yet" status claim this paragraph did not itself
  add but sat beside, in favour of naming `docs/lab.md` as the authority for
  whether the window is currently in effect. `cf6a25e` reframed a nearby
  runbook sentence ("the dispatcher runs every minute") that this step's own
  `dispatch-outbox` change had made false, around the job's own hours rather
  than the instance's sleep status. Both are corrections this step's
  neighbours needed once the window it documents actually shipped.

- [x] **Step 5: Commit** — done, `faed8f4`, "Keep the nightly jobs out of the
  window the instance sleeps in".

```bash
git add infra/terraform/audit.tf infra/terraform/tasks.tf docs/infrastructure.md
git commit -m "Keep the nightly jobs out of the window the instance sleeps in"
```

---

## Task 7: Refuse to deploy into a sleeping instance, legibly — DONE, `d4776ca`

**Repository: `aleogr/marketplace`, same branch as Task 6.**

**Files:**
- Modify: `.github/workflows/terraform.yml` — the `apply` job, a step between "Initialise" and "Apply"
- Test: the step's own logic, exercised locally against both states; the live proof is a run.

**Interfaces:**
- Consumes: `vars.GCP_TERRAFORM_SA`, already used by the job; `shared_project_id` and the instance name, read from the repository rather than retyped.
- Produces: nothing other tasks read.

**One check is enough, and this is why.** `deploy.yml` runs on `workflow_run` from Terraform with `if: github.event.workflow_run.conclusion == 'success'`. A Terraform run that fails therefore stops the deployment too. And the apply job authenticates as `terraform@`, which holds `sqlTenant`, which includes `cloudsql.instances.get` — so it can read the instance's state without any new grant. The spec described two workflows failing legibly; one check placed here does both.

- [x] **Step 1: Add the step** — done, `d4776ca`. The shipped comment is
  worded more fully than the draft below — it adds why the check lives here
  rather than in `deploy.yml` and closes with "this step reads and refuses;
  it does not wake anything" — but the step's logic, its two-word invariant
  (read, then refuse) and its message match this step exactly.

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
              "It sleeps Monday to Thursday, 22:00 to 07:30 local" \
              "(aleogr/lab, docs/lab.md). Nothing is wrong with this commit;" \
              "re-run this workflow after the instance starts."
            exit 1
          fi
```

- [x] **Step 2: Exercise both branches of the condition locally** — done,
  `d4776ca`.

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

- [x] **Step 3: Check the tfvars parsing against the real file** — done,
  `d4776ca`.

```sh
grep -E '^\s*shared_project_id\s*=' infra/terraform/lab/lab.tfvars \
  | sed -E 's/.*"([^"]+)".*/\1/'
```

Expected: exactly `aleogr-lab-shared-dacd`, one line, no quotes.

- [x] **Step 4: Confirm the workflow still parses** — done, `d4776ca`.
  `actionlint` was installed in none of this session's sandboxes; recorded as
  an unrun check rather than a passed one.

```sh
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/terraform.yml')); print('valid')"
actionlint .github/workflows/terraform.yml   # if actionlint exists in this sandbox
```

`actionlint` is installed in none of this session's sandboxes. If it is missing, say so in the pull request as an unrun check.

- [x] **Step 5: Commit** — done, `d4776ca`, "Say why an apply failed when the
  instance is asleep".

```bash
git add .github/workflows/terraform.yml
git commit -m "Say why an apply failed when the instance is asleep"
```

---

## Task 8: Open the two pull requests, in order

**Files:** none.

- [x] **Step 1: Push both branches** — done, and **this record was stale**:
  it said both branches sat at their pre-fix-wave SHAs, that this wave's own
  commits were not pushed, and that no pull request existed for either. All
  three were false by the time of the re-review that corrects this
  paragraph, checked directly against GitHub rather than assumed:
  `claude/funny-wright-379asb-labwindow` is on `origin` at `7b05592`;
  `claude/lab-sleep` is on `origin` at `8c61cba` — both include this fix
  wave's own commits, already pushed.

  **A pull request exists for each, and their histories diverged.**
  `aleogr/marketplace#67` carries all six of that repository's commits —
  Tasks 6 and 7's four (`faed8f4`, `043ae57`, `cf6a25e`, `d4776ca`) plus this
  wave's two (`e59383f`, `7b05592`) — and is **merged**, its head at exactly
  `7b05592`, every check green. `aleogr/lab#10` **merged earlier**, at
  `36e2989`, which is *before* this wave's four commits on `claude/lab-sleep`
  (`149ee99`, `c5cd7ba`, `cb0248f`, `8c61cba`) existed — so those four are
  pushed to `origin` and sit on the branch, but are not part of `#10` or of
  any other pull request, open or closed. A pull request built on this
  session's own further changes to `claude/lab-sleep` would need to be a new
  one; `#10` cannot receive them by re-opening. Neither the `site` branch nor
  its own pull request status changed; publishing `site` is still the
  owner's act (C2).

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

**And the job's own result answers only half of it.** Task 1 measured an operation that `gcloud` waited 600 seconds for and still did not see finish, which means the Admin API returns an operation immediately instead of blocking. Cloud Scheduler therefore records that its request was *accepted* — that is what a green `status.code` proves, and it is exactly the authentication question. It proves nothing about whether the instance actually started eleven minutes later. Read both, and read them for different things.

So the morning after the first stop, read the live world rather than the dashboard:

```sh
curl -s https://marketplace.lab.aleogr.dev/health
```

Before 07:30 it should answer `"database":"unreachable"`; after the start, `"database":"ok"`. The index page at `lab.aleogr.dev` shows the same thing without a terminal.

Then read both jobs' last result, which is where an authentication refusal would actually appear:

```sh
gcloud scheduler jobs describe lab-postgres-stop \
  --project=aleogr-lab-shared-dacd --location=us-central1 \
  --format='value(status.code, status.message, lastAttemptTime)'
```

Expected: an empty status and a recent `lastAttemptTime`. A `status.code` of 7 or 16 is the `oauth_token` being refused, and it means D1 is wrong rather than merely unproven — bring it back to the owner instead of patching around it.

Once that has happened, amend the 2026-09-21 spec: the `oauth_token` line moves out of "what is not verified" and becomes a dated fact.

Only once a night has actually run is the `site` branch's sentence — "that is not in effect yet" — false, and only then is it the owner's to publish.
