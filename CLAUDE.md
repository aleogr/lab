# Working agreements

- Talk to the owner in **Portuguese**. Everything versioned is in **English**.
- This repository is **public**. No secret may ever be committed.
- **Terraform is only ever applied by CI.** A session never runs `apply`.
- Claude Code opens the pull request and **never merges**. The owner merges.
- This repository owns the instance. It never declares a tenant's database,
  role or grant — see README.md.
- The index page at `lab.aleogr.dev` is served by GitHub Pages from the
  orphan `site` branch (`index.html`, `CNAME`, `.nojekyll`, nothing else). No
  workflow builds or deploys it, and none may be added: this repository's CI
  holds a credential that can change a GCP project, and a publishing job
  would be a second path to it.
- Before pushing: `terraform fmt -check`, `terraform init -backend=false`,
  `terraform validate`.
