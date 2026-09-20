terraform {
  # The same floors as aleogr/marketplace. Two configurations that address one
  # instance on different provider majors is a difference nobody chose and
  # nobody tests.
  required_version = "~> 1.16.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3"
    }
  }
}
