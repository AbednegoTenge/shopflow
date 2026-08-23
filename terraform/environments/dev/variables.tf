
variable "vpc_cidr" {
  type = string
  description = "The Classless Inter-Domain Routing (CIDR) for the VPC"
  default = "10.0.0.0/16"
}

variable "github_org" {
  type        = string
  description = "GitHub org/user that owns the repo allowed to assume the CI deploy role"
  default     = "AbednegoTenge"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo name allowed to assume the CI deploy role"
  default     = "shopflow"
}