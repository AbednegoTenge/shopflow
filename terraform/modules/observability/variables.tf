variable "alb_arn_suffix"          { type = string }
variable "target_group_arn_suffix" { type = string }
variable "ecs_cluster_name"        { type = string }
variable "ecs_service_name"        { type = string }
variable "rds_instance_id"         { type = string }
variable "dlq_name"                { type = string }
variable "alert_email"             { type = string } 