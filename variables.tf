# Automatic Variables
variable "region" {
}

variable "tenancy_ocid" {
}

variable "compartment_ocid" {
}

variable "current_user_ocid" {
}

# Defaulted Variables
variable "stack_compartment_description" {
  default = "Cludd"
}

variable "github_url" {
  default = "https://github.com/ethanbergstrom/munn.git"
}

variable "github_branch" {
  default = "main"
}

# Required Variables
variable "github_token" {
}