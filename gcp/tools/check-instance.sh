#!/usr/bin/env bash
# What the design promises about this instance, written as assertions.
#
# It reads the LIVE instance rather than the configuration, because a
# configuration that says the right thing and was never applied looks exactly
# like one that was. Run after every apply that touches instance.tf.
set -euo pipefail

project="${1:?usage: check-instance.sh <project> <instance>}"
instance="${2:?usage: check-instance.sh <project> <instance>}"

actual="$(gcloud sql instances describe "$instance" --project="$project" --format=json)"
failures=0

check() {
  local path="$1" want="$2"
  local got
  got="$(printf '%s' "$actual" | python3 -c "
import json,sys
o=json.load(sys.stdin)
for k in '$path'.split('.'):
    o = o.get(k) if isinstance(o, dict) else None
print(json.dumps(o))
")"
  if [ "$got" != "$want" ]; then
    printf '%-60s %s, want %s\n' "$path" "$got" "$want"
    failures=$((failures + 1))
  fi
}

check databaseVersion '"POSTGRES_16"'
check settings.edition '"ENTERPRISE"'
check settings.tier '"db-f1-micro"'
check settings.availabilityType '"ZONAL"'
check settings.dataDiskType '"PD_SSD"'
check settings.dataDiskSizeGb '"10"'
check settings.storageAutoResize 'true'
check settings.storageAutoResizeLimit '"50"'
check settings.deletionProtectionEnabled 'true'
check settings.backupConfiguration.enabled 'true'
check settings.backupConfiguration.startTime '"12:00"'
check settings.backupConfiguration.pointInTimeRecoveryEnabled 'true'
check settings.backupConfiguration.transactionLogRetentionDays '7'
check settings.backupConfiguration.backupRetentionSettings.retainedBackups '7'
check settings.backupConfiguration.backupRetentionSettings.retentionUnit '"COUNT"'
check settings.ipConfiguration.ipv4Enabled 'true'
check settings.ipConfiguration.sslMode '"ENCRYPTED_ONLY"'

# The flag is a list, not a field, so it is read on its own.
if ! printf '%s' "$actual" | python3 -c "
import json,sys
flags = json.load(sys.stdin)['settings'].get('databaseFlags', [])
sys.exit(0 if {'name':'cloudsql.iam_authentication','value':'on'} in flags else 1)
"; then
  echo 'cloudsql.iam_authentication is not on'
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures setting(s) do not match the design"
  exit 1
fi
echo "the instance matches the design"
