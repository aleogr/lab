# shared-infra

The Cloud SQL instance the lab databases of `aleogr/marketplace` and
`codeschool-ing/schooling` share, and nothing else.

## What this owns

The project `aleogr-lab-shared-dacd`, the instance `lab-postgres`, and the IAM
that lets each tenant declare its own database inside it.

## What this does not own

**Any tenant's database, roles or grants.** Those are declared by the tenant,
in the tenant's own repository, against this project — `google_sql_database`
and `google_sql_user` both take `project` and `instance`. The boundary is
deliberate: whoever looks after the house is the house; whoever looks after a
room is whoever lives in it. A tenant cannot change the instance, and this
repository cannot change a tenant's data.

## The rule that decides what may live here

**Consolidate by environment, never across environments.** Every database in
this instance holds a lab. The day one of them becomes production it leaves.

See `docs/superpowers/specs/2026-09-20-shared-database-instance-design.md` in
`aleogr/marketplace` for why, including what this arrangement does *not*
protect against.
