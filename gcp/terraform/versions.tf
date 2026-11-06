terraform {
  # The same floors as the tenants that address this instance. Two
  # configurations on different provider majors for one instance is a
  # difference nobody chose and nobody tests.
  required_version = "~> 1.16.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3"
    }
  }
}
