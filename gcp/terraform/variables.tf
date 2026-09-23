variable "project_id" {
  description = "The shared project. Permanent, and never reused once created."
  type        = string
}

variable "region" {
  description = "Where the instance runs. The same region as every tenant that uses it, because a cross-region socket is latency nobody asked for."
  type        = string
  default     = "us-central1"
}

variable "database_tier" {
  description = "Cloud SQL machine type. Shared-core tiers require edition ENTERPRISE, which is stated out loud in instance.tf."
  type        = string
  default     = "db-f1-micro"
}

variable "database_disk_size" {
  description = "Size in GB of the disk, which is also its floor: Cloud SQL grows a disk and never shrinks one."
  type        = number
  default     = 10
}

variable "database_disk_limit" {
  description = "Ceiling for automatic growth. Growth is one-way, so an unbounded limit turns one runaway write into a permanent bill."
  type        = number
  default     = 50
}

variable "tenants" {
  description = "Each project that keeps a database in this instance, and the identities it reaches it with. `declares` is the identity that APPLIES the tenant's Terraform, which is not the one that deploys its application — naming the wrong one costs a 403 at apply time and nothing earlier. `connects` may open a connection through the connector; `logs_in` may authenticate as an IAM database user; `reads` may read the instance's settings and nothing else, for a deploy that checks whether the instance is awake. A tenant whose Terraform is applied by a person rather than a service account has no `declares`. Nothing here lets a tenant change the instance."
  type = map(object({
    declares = optional(string)
    connects = list(string)
    logs_in  = list(string)
    reads    = optional(list(string), [])
  }))
}
