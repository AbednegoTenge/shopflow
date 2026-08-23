variable "github_org"  { type = string }
variable "github_repo" { type = string }

variable "ecr_repository_arn"      { type = string }
variable "ecs_cluster_arn"         { type = string }
variable "ecs_service_arn"         { type = string }
variable "task_execution_role_arn" { type = string }
variable "task_role_arn"           { type = string }
