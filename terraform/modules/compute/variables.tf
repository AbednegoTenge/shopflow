# modules/compute/variables.tf
variable "vpc_id"             { type = string }
variable "public_subnet_ids"  { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "alb_sg_id"          { type = string }
variable "ecs_sg_id"          { type = string }
variable "rds_endpoint"       { type = string }
variable "rds_secret_arn"     { type = string }
variable "redis_endpoint"     { type = string }
variable "container_port" {
  type    = number
  default = 3000
}