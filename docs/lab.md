# The laboratory

What is true across every project under `lab.aleogr.dev`. What is true about one
project lives in that project.

## The rule that decides what may be shared

**Consolidate by environment, never across environments.** Every database in
`lab-postgres` holds a laboratory. The day one of them becomes production, it
leaves.

See `docs/superpowers/specs/2026-09-20-shared-database-instance-design.md` for
why, including what this arrangement does *not* protect against.

## Names

| | |
|---|---|
| Project | `aleogr-lab-<product>-<4 random>`, `aleogr-prd-<product>-<4 random>` — environment first, so every laboratory and every production project sorts together in the console and in `gcloud projects list`, putting the thing you must not confuse at the front of the name. Ids are immutable and a deleted one never returns, so everything that cannot be fixed later is in the name from the start |
| Shared project | `aleogr-lab-shared-<4 random>` |
| Shared instance | `lab-postgres` — named for what it is, never for the first project that used it |
| Database | the project's own name |
| Database role | the project's name as a prefix: `marketplace_migrator`, not `migrator`. Roles are cluster-wide objects, so a generic name on a shared instance is a collision waiting for the second tenant |

## When the instance is awake

Asleep four weeknights: Monday through Thursday, from 22:00 to 07:30 local
(UTC−3). Awake at every other hour, which means Friday night and the whole
weekend run unbroken — two hours until Saturday is not worth a stop and a
start, and a stop on Sunday night would risk the database going down at
midnight while somebody is still working.

The start is at 07:30 rather than 08:00 because a stopped instance does not
answer the moment it is asked to: measured on 2026-09-21, it took 686 seconds
— eleven and a half minutes — from the start command to `/health` reporting
`database: ok`.

`gcp/terraform/sleep.tf` holds the two cron expressions, and they appear
nowhere else in this repository — this section is the policy, that file is the
schedule.

**A tenant whose own work runs at night moves it, in its own repository.**
This project does not reach into a tenant's Cloud Scheduler for the same
reason it does not declare a tenant's database. `aleogr/marketplace` moved two
jobs for exactly this reason: an audit walk that ran at 01:17, and an outbox
dispatch that ran every minute of every day.

Two consequences, and both have bitten somebody:

- **A stopped instance runs no automated backup.** The backup window is
  12:00 UTC (09:00 local) for that reason, and not the small hours where a
  backup window normally goes. In the old windows the backups would simply stop
  happening, silently, with no error for anyone to notice.
- **There is no transaction log for the hours an instance was stopped**, so a
  restore to a point in time has to target a moment it was awake.

## What a project may do inside the shared instance

The custom role `sqlTenant`, granted to the identity that applies the project's
Terraform — which is not the identity that deploys its application. It may
create and alter its own database and its own users, and nothing else: no
`cloudsql.instances.delete`, no `cloudsql.instances.update`.

**That role is not a wall between projects.** Cloud SQL grants IAM per project
and not per database. What keeps one laboratory's data away from another's is
the database grant: `CONNECT` revoked from `PUBLIC` and given by name, with a
connection ceiling computed from that project's own pools.

That protection has a limit worth stating rather than implying away: a user
created by `gcloud sql users create` belongs to `cloudsqlsuperuser`, and a
member of that role can grant itself back the `CONNECT` this revokes. The
grant and the ceiling guard against **accident** — a runaway CI job, a
mistyped connection string — not against deliberate action from inside.
Between laboratories that share one owner, that is the accepted trade.
