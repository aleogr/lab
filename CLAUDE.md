# Working agreements

- Talk to the owner in **Portuguese**. Everything versioned is in **English**.
- This repository is **public**. No secret may ever be committed.
- **Terraform is only ever applied by CI.** A session never runs `apply`.
- Claude Code opens the pull request and **never merges**. The owner merges.
- This repository owns the instance. It never declares a tenant's database,
  role or grant — see README.md.
- Before pushing: `terraform fmt -check`, `terraform init -backend=false`,
  `terraform validate`.
