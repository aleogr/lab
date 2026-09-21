#!/usr/bin/env bash
# Which repositories may authenticate as the deploy identity, asserted against
# the LIVE federation.
#
# THE EXPECTED NAMES ARE ARGUMENTS AND NOT READ FROM THE CONFIGURATION. A check
# that takes its expectation from the thing it is checking proves nothing. These
# come from the workflow; `deployer.tf` declares its own list; and the two
# disagreeing is the failure this exists to catch.
#
# It exists because a rename widens this trust and something has to narrow it
# again (docs/superpowers/specs/2026-09-21-lab-home-design.md, D3 and D10). A
# widening nobody removed looks exactly like a widening nobody made.
set -euo pipefail

project="${1:?usage: check-federation.sh <project> <repository>...}"
shift
if [ "$#" -eq 0 ]; then
  echo "usage: check-federation.sh <project> <repository>..." >&2
  exit 2
fi

expected="$(printf '%s\n' "$@" | sort)"
failures=0

number="$(gcloud projects describe "$project" --format='value(projectNumber)')"

condition="$(gcloud iam workload-identity-pools providers describe github \
  --project="$project" --location=global --workload-identity-pool=github \
  --format='value(attributeCondition)')"

# Every repository the condition names, and then whatever is left once the
# names and the separators are removed — because a clause nobody planned is
# exactly what this must not let through.
named="$(printf '%s' "$condition" \
  | grep -oE "assertion\.repository == '[^']+'" \
  | sed -E "s/.*'([^']+)'.*/\1/" | sort || true)"
remainder="$(printf '%s' "$condition" \
  | sed -E "s/assertion\.repository == '[^']+'//g" \
  | sed -E 's/\|\|//g' | tr -d '[:space:]')"

if [ "$named" != "$expected" ]; then
  echo "the provider's condition names:"
  printf '%s\n' "$named" | sed 's/^/  /'
  echo "expected:"
  printf '%s\n' "$expected" | sed 's/^/  /'
  failures=$((failures + 1))
fi

if [ -n "$remainder" ]; then
  echo "the condition carries something beyond the repository names: $remainder"
  failures=$((failures + 1))
fi

members="$(gcloud iam service-accounts get-iam-policy \
  "deployer@$project.iam.gserviceaccount.com" --project="$project" --format=json \
  | python3 -c "
import json, sys

policy = json.load(sys.stdin)
for binding in policy.get('bindings', []):
    if binding.get('role') == 'roles/iam.workloadIdentityUser':
        for member in binding.get('members', []):
            print(member)
" | sort)"

wanted="$(for repository in "$@"; do
  echo "principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/github/attribute.repository/$repository"
done | sort)"

if [ "$members" != "$wanted" ]; then
  echo "the deploy account trusts:"
  printf '%s\n' "$members" | sed 's/^/  /'
  echo "expected:"
  printf '%s\n' "$wanted" | sed 's/^/  /'
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "the federation does not match the design"
  exit 1
fi

echo "the federation matches the design"
