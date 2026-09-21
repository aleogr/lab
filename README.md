# lab

The home of `lab.aleogr.dev`: the Cloud SQL instance the laboratory's projects
share, the index page the address answers with, and the rules that hold across
every project in it.

## What lives here

What is **true about the laboratory as a whole**. What is true about one project
lives in that project. The sleep schedule is the laboratory's, because stopping
the instance affects everyone; the `marketplace` database's connection ceiling
is the marketplace's, because its own pool is what sets the number.

Without that rule, "it belongs to the lab" becomes the answer for anything
nobody knows where to put.

The index page lives on its own orphan branch, `site` — `index.html`, `CNAME`
and `.nojekyll`, nothing else. GitHub Pages serves it directly from that
branch; it never merges into `main`, and `main` never merges into it.

## What this does not own

**Any tenant's database, roles or grants.** Those are declared by the tenant,
in the tenant's own repository, against this project — `google_sql_database`
and `google_sql_user` both take `project` and `instance`. The boundary is
deliberate: whoever looks after the house is the house; whoever looks after a
room is whoever lives in it. A tenant cannot change the instance, and this
repository cannot change a tenant's data.

## The rules of the laboratory

`docs/lab.md` — what may be shared, how things are named, when the instance is
awake, and what a project may do inside it.

## What was done by hand, and why it is not in the configuration

Four things exist because somebody typed a command. Each is here with the
reason it is not code — "somebody did it in the console once" is not among
them.

**The project and the state bucket.** Terraform cannot create the place it
stores its state, so `aleogr-lab-shared-dacd` and
`gs://aleogr-lab-shared-dacd-tfstate` were created first. The bucket is
versioned: a truncated state write has to be recoverable.

**The deploy identity's first apply.** A federation cannot apply itself — the
identity that applies it has to exist already — so `deployer.tf` was applied
once from the commit that held it alone, by the project's owner.

**Five grants to the deploy identity.** Terraform manages the pool, the service
account, the tenant role, Cloud Scheduler and the state, and needs permission
on all of them before it can read or write them:

```sh
PROJECT=aleogr-lab-shared-dacd
SA="serviceAccount:deployer@$PROJECT.iam.gserviceaccount.com"

gcloud storage buckets add-iam-policy-binding "gs://$PROJECT-tfstate" \
  --member="$SA" --role=roles/storage.objectAdmin

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$SA" --role=roles/iam.workloadIdentityPoolAdmin --condition=None

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$SA" --role=roles/iam.serviceAccountAdmin --condition=None

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$SA" --role=roles/iam.roleAdmin --condition=None

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$SA" --role=roles/cloudscheduler.admin --condition=None
```

`workloadIdentityPoolAdmin`, `serviceAccountAdmin`, `roleAdmin` and
`cloudscheduler.admin` are also declared in `deployer.tf`, and
`storage.objectAdmin` deliberately is not: a `google_storage_bucket_iam_member`
would have Terraform managing the access it needs in order to run, so a
`terraform destroy` would revoke its own reach to the state halfway through
its own execution.

### The blind spot these grants came from

Every one of them was discovered by a red check, one at a time, and the reason
is worth writing down. **The bootstrap plan runs as the project's owner, who can
read everything.** Any permission the deploy identity needs and the owner
already has is invisible there. The first plan run *as* the deploy identity is
the first honest one.

If a resource is added to this configuration whose API the deployer cannot
already reach, expect the same failure, and grant for the resource rather than
waiting to be told which permission is missing.

**It happened again — twice in the same apply.** `sleep.tf`'s two
`google_cloud_scheduler_job` resources shipped after this section was
written, and the apply on `main` failed with `cloudscheduler.jobs.create`
denied: the deploy identity held five roles, and none was Cloud Scheduler's.
`deployer_scheduler` in `deployer.tf` fixed that, and the next apply failed
again, on `iam.serviceAccounts.actAs` for `sleeper@` — each job's
`oauth_token` makes it act as that account, which is a permission
`serviceAccountAdmin` administers rather than grants. `sleeper.tf`'s
`deployer_acts_as_sleeper` binding is that fix. This section had already
named the shape of the first failure and did not stop either from happening;
fixing the two one red apply at a time cost a cycle each. The question worth
asking before a resource is added is not "can the deployer create this?" but
**"what does the deployer need in order to create this, including the right
to act as anything the resource runs as?"** — a new resource *type* can need
more than one permission the deployer lacks, and the second one hides behind
the first until the first is fixed.

**IAM changes take a few minutes to propagate.** A run started immediately
after a grant can still be refused; that is not a second missing permission.
