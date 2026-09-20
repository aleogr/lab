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
  description = "The deployer service accounts allowed to declare a database inside this instance. One entry per tenant repository."
  type        = map(string)
}
