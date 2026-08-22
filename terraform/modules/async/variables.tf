

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "rds_sg_id" { type = string }
variable "rds_endpoint" { type = string }
variable "rds_secret_arn" { type = string }
