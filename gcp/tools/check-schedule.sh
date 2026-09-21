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

  case "$uri" in
  *"/projects/$project/instances/$instance") : ;;
  *) report "$name target" "$uri" "$instance in $project" ;;
  esac
}

check_job "lab-postgres-stop" "$stop_cron" "NEVER"
check_job "lab-postgres-start" "$start_cron" "ALWAYS"

# ANYTHING ELSE THAT CAN TOUCH THE INSTANCE IS A FINDING — the same kind of
# remainder clause `check-federation.sh` runs on its condition string. A
# third job nobody declared is exactly what this exists to notice.
#
# Matched with `endswith`, not `contains`: a `uri` ending in
# ".../instances/lab-postgres-replica" contains the substring
# ".../instances/lab-postgres" as a prefix, so `contains` would misreport a
# job that targets a different, similarly-named instance as one that
# targets this one. `endswith`, anchored on the project too, does not.
extra="$(jq -r --arg p "$project" --arg i "$instance" \
  '.[] | select((.httpTarget.uri // "") | endswith("/projects/" + $p + "/instances/" + $i))
       | .name | split("/") | last' <<<"$jobs" \
  | grep -vx -e "lab-postgres-stop" -e "lab-postgres-start" || true)"

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
