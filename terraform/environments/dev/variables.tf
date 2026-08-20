


variable "vpc_cidr" {
  type = string
  description = "The Classless Inter-Domain Routing (CIDR) for the VPC"
  default = "10.0.0.0/16"
  
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block format (e.g., 10.0.0.0/16)."
  }
}