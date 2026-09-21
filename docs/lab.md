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

**Not yet — the instance runs continuously today.** Plan 2 puts it to sleep on
four weeknights only, Monday through Thursday, from 22:00 to 07:45 local
(UTC−3); 07:45 rather than 08:00 because a stopped instance takes a minute or
two to accept connections. Friday night and the whole weekend stay awake: two
hours until Saturday is not worth a stop and a start, and the same risk holds
for Sunday night, which would leave the database dying at midnight while
somebody is working.

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
