#!/usr/bin/env bash
# Whether the live sleep schedule for this instance is the one the design
# declares, asserted against Cloud Scheduler rather than against sleep.tf.
#
# THE EXPECTATION ARRIVES AS ARGUMENTS, from the workflow, not from the
# Terraform this verifies. A check that reads its expectation out of the
# thing it is checking passes whatever that thing says. `sleep.tf` declares
# its own cron expressions; the workflow declares these; and the two
# disagreeing is the failure this exists to catch.
#
# The region is an argument for the same reason it is one in
# `gcloud scheduler jobs list`: Cloud Scheduler is a regional service, and
# guessing the region would be the check reading its own expectation again,
# one layer down.
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
failures=0

report() {
  printf '%-34s %s, want %s\n' "$1" "$2" "$3"
  failures=$((failures + 1))
}

# ONE READ OF THE LIVE WORLD, reused by every assertion below. A `describe`
# per job would ask a moving target twice and could answer differently each
# time.
jobs="$(gcloud scheduler jobs list --project="$project" --location="$region" --format=json)"

check_job() {
  local name=$1 want_cron=$2 want_policy=$3
  local job cron tz state uri body policy

  job="$(jq -r --arg n "$name" \
    '.[] | select(.name | endswith("/jobs/" + $n))' <<<"$jobs")"

  if [ -z "$job" ]; then
    report "$name" "does not exist" "to exist"
    return
  fi

  # `// ""` on every field below, not just the ones the draft guarded. A
  # missing key indexes to `null` in jq, and `jq -r` on `null` prints the
  # four-character string "null", which is not equal to any expectation
  # here by accident — but relying on that is exactly the kind of thing
  # that stops being true the next time this function grows a field. `// ""`
  # makes a missing key read as empty on purpose, which every comparison
  # below (schedule, timeZone, state, uri, activationPolicy) is guaranteed
  # to reject, because none of the six arguments this script takes is ever
  # empty.
  cron="$(jq -r '.schedule // ""' <<<"$job")"
  tz="$(jq -r '.timeZone // ""' <<<"$job")"
  state="$(jq -r '.state // ""' <<<"$job")"
  uri="$(jq -r '.httpTarget.uri // ""' <<<"$job")"

  # A body that is absent must decode to an explicit empty string, not to
  # whatever `base64 -d` had half-written to stdout before it errored out.
  # `body=$(... || echo "")` looks like it clears that on failure, but the
  # partial output the left side of `||` already wrote survives inside the
  # same command substitution — `echo ""` only appends a newline the
  # substitution then strips. The `if` form below only assigns on success,
  # so failure leaves `body` genuinely empty.
  if ! body="$(jq -r '.httpTarget.body // ""' <<<"$job" | base64 -d 2>/dev/null)"; then
    body=""
  fi
  if ! policy="$(jq -r '.settings.activationPolicy // ""' <<<"$body" 2>/dev/null)"; then
    policy=""
  fi

  [ "$cron" = "$want_cron" ] || report "$name schedule" "$cron" "$want_cron"
  [ "$tz" = "$zone" ] || report "$name timeZone" "$tz" "$zone"
  [ "$state" = "ENABLED" ] || report "$name state" "$state" "ENABLED"
  [ "$policy" = "$want_policy" ] || report "$name activationPolicy" "$policy" "$want_policy"

  # THE SAME BOUNDARY THE EXTRA-JOB SCAN USES, BELOW, not an exact-suffix
  # glob. This function used to require the uri to END with
  # "/instances/$instance", which is a stricter reading of "targets this
  # instance" than the scan's `test(...)`: a declared job whose uri carried a
  # query string (`?updateMask=settings.activationPolicy`) or a sub-path
  # would fail this check as a target mismatch while the scan below correctly
  # counted it as targeting the instance. Two matchers in one file
  # disagreeing about what "targets this instance" means is its own bug, so
  # this one now accepts the same boundary set the scan does — see the
  # comment there for what each character is and why.
  case "$uri" in
  *"/projects/$project/instances/$instance" | *"/projects/$project/instances/$instance"[/?#:\;]*) : ;;
  *) report "$name target" "$uri" "$instance in $project" ;;
  esac
}

check_job "lab-postgres-stop" "$stop_cron" "NEVER"
check_job "lab-postgres-start" "$start_cron" "ALWAYS"

# ANYTHING ELSE THAT CAN TOUCH THE INSTANCE IS A FINDING — the same kind of
# remainder clause `check-federation.sh` runs on its condition string. A
# third job nobody declared is exactly what this exists to notice.
#
# Matched on a BOUNDARY, not a bare `endswith` and not `contains`. `contains`
# was rejected first, and the reasoning still holds: a `uri` ending in
# ".../instances/lab-postgres-replica" contains the substring
# ".../instances/lab-postgres" as a prefix, so `contains` would misreport a
# job that targets a different, similarly-named instance as one that targets
# this one. `endswith`, anchored on the project too, fixed that — and paid
# for it by rejecting every suffixed form: a query string
# (`?updateMask=settings.activationPolicy`), a trailing slash, a sub-path
# (`/restart`, or the same instance reached through `/sql/v1beta4/`) all fail
# `endswith`, so a job using any of them passes uncaught. `test(...)` below
# keeps `endswith`'s anchor — nothing may precede "/instances/$i" but the
# project path, so `-replica` still cannot match — while accepting anything
# that FOLLOWS only if it starts a new path segment, a query string, a
# fragment, GCP's own custom-verb separator, or a statement separator
# (`[/?#:;]` — the Admin API itself uses `:` for verbs like
# `instances/NAME:failover`, and `;` is a valid path-parameter delimiter in
# a URI) or the string simply ends there (`$`), which a `-replica` suffix
# does not do either. `check_job`'s own uri match, above, accepts the same
# set for the same reason — two matchers in one file must agree on what
# "targets this instance" means.
#
# WHAT THIS STILL DOES NOT CATCH: a uri built with the project NUMBER
# (`.../projects/123456789012/instances/lab-postgres`) instead of the project
# id this script is given as `$project`. The Cloud SQL Admin API accepts
# both forms, so a rogue job addressed by number would target the instance
# and pass this scan unremarked — a real gap, left open rather than widened,
# for two reasons. First, every job this repository's own Terraform declares
# addresses the instance by project id (`sleep.tf` interpolates
# `var.project_id`, never a number), so the gap only admits a job created
# out of band, by hand, which is already a bypass of this repository's
# review — the same class of problem as a console change to any other
# resource here, and not one a schedule-matching script can close on its
# own. Second, closing it would mean this script also taking the project
# NUMBER as an argument, which nothing else here needs to know and which
# would have to come from `data.google_project.current.number` in Terraform
# — a second expectation this check would then be trusting from the thing
# it verifies, in spirit if not in the letter of the Global Constraint above.
# A manually created scheduler job is also the kind of change Cloud Audit
# Logs records regardless of what this script catches.
extra_raw="$(jq -r --arg p "$project" --arg i "$instance" \
  '.[] | select((.httpTarget.uri // "") | test("/projects/" + $p + "/instances/" + $i + "($|[/?#:;])"))
       | .name | split("/") | last' <<<"$jobs")"

# `|| true` covers only `grep -vx`'s own legitimate exit 1 here — the common
# case where every job touching the instance is one of the two declared ones,
# so nothing is left after filtering them out. It does not also cover `jq`
# above: that call now runs on its own line, under `set -e`, so a `jq`
# failure still stops the script instead of being swallowed by the same `||`.
extra="$(grep -vx -e "lab-postgres-stop" -e "lab-postgres-start" <<<"$extra_raw" || true)"

if [ -n "$extra" ]; then
  while IFS= read -r job_name; do
    report "extra job $job_name" "targets $instance" "no such job (the design names none)"
  done <<<"$extra"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures mismatch(es) between the live schedule and the design"
  exit 1
fi

echo "the schedule matches the design"
