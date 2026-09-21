# The lab has a home

**Date:** 2026-09-21
**Status:** implemented; the page is public at `https://lab.aleogr.dev` (2026-09-21)

`lab.aleogr.dev` is the address every laboratory project already lives under —
`marketplace.lab.aleogr.dev`, `code.schooling.lab.aleogr.dev`,
`my.schooling.lab.aleogr.dev` and the rest. The address itself answers nothing.

This repository, meanwhile, is named for one of the things it holds rather than
for what it is. It owns the shared Cloud SQL instance because that was the first
thing several laboratory projects needed to share. It was not the last.

The two facts are the same fact: **the laboratory is a real thing and has no
home.** This design gives it one.

## What is decided

### D1 — The repository becomes `aleogr/lab`

Not `shared-infra` with a page bolted on. The name describes the place, and the
shared infrastructure becomes one of the things the place holds.

The alternative considered and rejected was keeping `shared-infra` as it is and
creating a second repository for the page. It is defensible: the page repository
would hold no cloud credential at all, which is the smallest possible blast
radius. It was rejected because the problem being solved is one of organisation,
and two repositories — one of which exists to publish a page about the other —
is a worse map of the world than one repository named after the world.

### D2 — What the repository owns, and the rule that decides the next case

**Owns**

- the shared project `aleogr-lab-shared-dacd` and the instance `lab-postgres`
  (`gcp/terraform/`, unchanged)
- the laboratory's front door: the page at `lab.aleogr.dev`, on the `site`
  branch (D4)
- the rules that hold across the whole laboratory: the sleep schedule, the
  project and database naming conventions, the rule that consolidation happens
  by environment and never across environments, and the list of which projects
  exist and where

**Does not own**

- any tenant's database, roles, grants, infrastructure or content. Unchanged,
  and the sentence that says why stays: whoever looks after the house is the
  house; whoever looks after a room is whoever lives in it.

**The rule for the next case, which is the point of writing this down:**

> What lives here is what is **true about the laboratory as a whole**. What is
> true about one project lives in that project.

Applied: the sleep schedule is the laboratory's, because stopping the instance
affects everyone. The `marketplace` database's connection ceiling is the
marketplace's, because its own pool is what sets the number. The instance is the
laboratory's. The database is the tenant's.

Without a rule, "it belongs to the lab" becomes the answer for anything nobody
knows where to put, and a home becomes a junk drawer.

### D3 — The rename widens the trust before it moves, and narrows it after

The federation is pinned to the repository's name in two places: the provider's
`attribute_condition`, and the `principalSet` in the deploy account's
`workloadIdentityUser` binding. Renaming the repository changes what GitHub
asserts, so CI stops authenticating — and cannot apply the fix, because the fix
is the authentication.

`attribute_condition` is updatable in place (verified against the provider
schema for `hashicorp/google` 8.3: the attribute carries no `ForceNew`). So the
rename needs no hand-applied exception:

1. **Still named `shared-infra`, CI working.** A pull request widens the
   condition to accept either name and adds a second `workloadIdentityUser`
   binding for `aleogr/lab`. CI applies it with the authentication it still has.
2. **The repository is renamed.** CI now presents `aleogr/lab`, which the
   condition already accepts. Nothing breaks. GitHub redirects the old URL, so
   existing clones keep working.
3. **Named `lab`.** A second pull request narrows the condition back to one
   repository and removes the old binding.

Between 1 and 3 the trust is wider than it needs to be: it would accept a
repository named `aleogr/shared-infra`, a name that becomes free after the
rename. Only the account's owner can create a repository under `aleogr`, so the
exposure is to one's own carelessness rather than to a stranger — but step 3 is
not optional. A trust nobody remembers is still a trust.

**What does not change**, which bounds the whole operation: the GCP project id,
the instance name, the state bucket, the workload identity provider's resource
name, the repository variables, the `sqlTenant` role and every tenant grant. Two
strings in IAM and one repository name. No tenant needs a pull request.

### D4 — The page is static and publishes without a workflow, which is a security requirement

Hand-written HTML, one file, inline CSS, roughly forty lines of JavaScript. No
framework, no `npm`, no build step, and **no workflow runs to publish it**.

This is not a preference. This repository's federation grants `cloudsql.admin`
and `resourcemanager.projectIamAdmin` to any workflow in it, and the official
`actions/deploy-pages` requires `id-token: write` — the same permission that
mints the GCP credential. A publishing workflow here would be exactly the
supply-chain path this rule exists to close. A dependency tree would be another.

**The page therefore lives at the root of a `site` branch**, published by Pages
deploying from a branch. GitHub offers only two sources for that mode: a
branch's root, or its `/docs` folder — a `site/` folder on `main` is not among
them. `/docs` was rejected because it is where this repository's documentation
belongs, in the same shape as the marketplace's. `main`'s root was rejected
because Pages would then serve the whole repository, answering for
`lab.aleogr.dev/gcp/terraform/instance.tf`: nothing secret in a public
repository, but the laboratory's front door should not hand out Terraform.

The cost, stated plainly: the page is edited on a branch that never merges into
`main`. That is unusual to look at, and it is what the classic `gh-pages`
pattern exists for.

If the page ever needs a generator, that is the moment to reconsider D1 and give
the page its own repository — not the moment to add a build here.

### D5 — Live state comes from each project's `/health`, read by the browser

The marketplace's health endpoint is public and already answers, in one line,
almost everything the page wants to show:

```json
{"database":"ok","status":"ok","version":"3da1f81-20260920"}
```

The service is up; the shared instance is awake and reachable, because that `ok`
comes from a real `Ping`; and this is the deployed version. The page fetches it
from the reader's browser. No job, no scheduled export, no credential, no server.

What this does not give is the instance's raw state in GCP (`RUNNABLE` versus
`STOPPED`). It is inferable — if any tenant reports `database: ok` the instance
is awake — and inference is honest enough for a personal index. Reading GCP
directly would mean a credential and a job, which D4 exists to avoid.

**This requires something of each tenant.** A page on `lab.aleogr.dev` cannot
read a response from `marketplace.lab.aleogr.dev` without that origin's
permission. The marketplace sends no CORS header today — the repository contains
none at all. Each tenant adds, on `/health` and on no other path:

```
Access-Control-Allow-Origin: https://lab.aleogr.dev
```

One line, on an endpoint already public, returning nothing sensitive. It is a
change in the tenant's repository, so it travels as its own pull request there
(D7), and until a tenant makes it that tenant reads as "unknown" (D6).

`mode: 'no-cors'` was considered and rejected. It returns an opaque response:
the browser fetches but the page may read nothing, so a 503 becomes
indistinguishable from a 200. A panel that cannot tell "up" from "down" is worse
than no panel.

### D6 — Three states, never two

Every project reads as **up**, **failing**, or **unknown**. "Unknown" is what
the page shows when it could not check — CORS absent, network, anything.

This is not an interface detail. A panel that calls "I could not check" a
failure cries wolf; one that calls it success hides a fire. The third state is
what prevents both lies, and it is what makes the panel worth looking at in six
months.

The case that will occur Monday through Thursday nights, once Plan 2's
schedule is in effect: from 22:00 to 07:30 the instance sleeps, Cloud Run
keeps serving, and `/health` answers **503 with
`"database":"unreachable"`**. The page shows what `/health` said, and shows the
working window beside it so the reading takes one glance. It does **not** assert
that the instance is asleep. It does not know that; it knows what the service
answered.

### D7 — The CORS change is each tenant's own pull request

Small, with its own test, in the tenant's repository. It is a change to a
service's behaviour and should not travel inside the creation of a website. It
can land before or after this work; the page degrades to "unknown" until it does.

Schooling's is a request to that project's session, not work in this one.

### D8 — English only

The page is written in English, consistent with everything else versioned here.
The marketplace's two-language rule exists for a product with users; this index
has one reader, and a second translation of it would be recurring work with no
audience.

### D9 — DNS uses a CNAME; the rule that ruled it out was wrong

`lab.aleogr.dev` already carries a TXT record (`brevo-code=…`), and
`brevo1._domainkey.lab`, `brevo2._domainkey.lab` and `_dmarc.lab` sit beneath
it. That TXT is what proves domain ownership to the mail provider, so it stays.

**This decision originally reached for A records, on the general rule that a
CNAME cannot coexist with other records at the same name. That rule does not
describe Cloudflare's behaviour, and the design assumed it instead of checking
it.** Applying it found the opposite: Cloudflare accepts a `CNAME` at
`lab.aleogr.dev`, pointing to `aleogr.github.io`, unproxied, sitting beside the
Brevo TXT at the same name, unchanged. The name resolves to GitHub's Pages
addresses and the site serves. A CNAME is also what GitHub documents for a
**subdomain** — A records are what it documents for an **apex** — so the
earlier reasoning had reached for the record GitHub recommends for the wrong
shape of name.

The zone is on Cloudflare, and the `lab` CNAME is unproxied — which is what
lets GitHub issue its certificate. Nothing in the zone's posture had to
change to add it.

**A records to GitHub's published addresses remain the fallback** if the CNAME
ever has to go — read from GitHub's documentation at the moment of applying,
never from memory, since they are exactly the class of fact that changes and
that this session has already been bitten by, and since GitHub documents them
for an apex rather than for a subdomain like this one.

Alongside: a `CNAME` file in the repository (how Pages learns the domain),
"Enforce HTTPS" on, and the Pages domain verification record, which is what stops
somebody else claiming the subdomain.

### D10 — A check that reads the live federation

A `gcp/tools/check-federation.sh`, sibling to `check-instance.sh`, reads the
provider's condition and the account's live bindings from GCP and fails when they
are not exactly what is expected.

Its value is not the day of the rename. It is the months afterwards: it is what
stops step 3 of D3 being left half-done without anyone noticing, and what makes a
future widening show up as a red check instead of as nothing at all.

### D11 — The earlier spec moves here too

`docs/superpowers/specs/2026-09-20-shared-database-instance-design.md` currently
lives in `aleogr/marketplace`, and by D2's rule it is in the wrong place: it
describes an instance shared by several projects. It moves into this repository,
and the README's link to it is corrected.

The rule is worth more if the first thing it corrects is one of our own
inconsistencies.

## The order of the work

| # | deliverable | where | run by |
|---|---|---|---|
| 1 | widen the federation to accept both names | pull request in `shared-infra` | CI |
| 2 | rename the repository | GitHub | the owner |
| 3 | narrow the federation, remove the old binding, rewrite README and comments | pull request in `lab` | CI |
| 4 | the page: the `site` branch, the `CNAME` file, Pages, the DNS `CNAME` record, domain verification | pull request in `lab` + Cloudflare | CI and the owner |
| 5 | the laboratory's rules move in; the earlier spec moves in (D11) | pull requests in `lab` and `marketplace` | CI |
| — | CORS on `/health` | a pull request per tenant | CI |

1 → 2 → 3 is a chain: each link is safe only after the one before it. 4 and 5
may come in either order after 3. The CORS change is independent of all of it.

## What proves each step

The discipline is the one this repository already keeps: **the proof is a
reading of the live world, never the file that states the intent.**

- **Step 1** — a green apply is not the proof. The proof is the *next* CI run
  authenticating, because that run is the one that exercises the new condition.
- **Step 2** — the proof is the first CI run under `aleogr/lab` passing. If it
  fails, step 1 was incomplete, and the way back is to rename back.
- **Step 3** — the proof is the live policy: the condition names one repository,
  and the old binding is gone. `check-federation.sh` (D10) is that reading.
- **Step 4** — the proof is `https://lab.aleogr.dev` answering with a valid
  certificate, and, once a tenant has shipped its CORS header, that tenant's
  health actually arriving in the page.

## Out of scope, deliberately

- history, uptime graphs, alerting — the budget alert already exists, and a
  personal index should not become monitoring
- automatic discovery of projects; the inventory is edited by hand, and there
  are three
- any build, framework or dependency (D4)
- authentication on the page; it is public and shows nothing that cannot be
- reading GCP directly — no job, no credential, no published status file. If
  `/health` ever stops being enough, that is a conversation, not an assumption
- schooling's CORS change, which is a request to that project

## Risks

**A CNAME sharing its name with another record.** GitHub's documented path for
a subdomain is a CNAME, and that is what serves `lab.aleogr.dev` now (D9). The
general DNS rule says a CNAME must be the only record at its name; Cloudflare
does not enforce that here, so the Brevo TXT and the CNAME coexist at the same
name. That is this provider's behaviour, not a documented standard, so a
different provider might refuse it — A records to GitHub's published
addresses are the reserved fallback if it ever does.

**Certificate issuance** depends on DNS having propagated and on the record
staying unproxied, which it is. Usually minutes; it can be hours.

**The page is public.** It is written for one reader, but a GitHub Pages site on
a public repository is readable by anyone who types the address. The inventory
may contain only what the owner would publish.
