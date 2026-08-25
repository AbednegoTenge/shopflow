
output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "alb_sg_id" {
  value = module.networking.alb_sg_id
}

output "ecs_sg_id" {
  value = module.networking.ecs_sg_id
}

output "rds_sg_id" {
  value = module.networking.rds_sg_id
}

output "cache_sg_id" {
  value = module.networking.cache_sg_id
}

output "kms_key_arn" {
  value = module.networking.kms_key_arn
}

output "db_endpoint" {
  value = module.data.db_endpoint
}

output "db_port" {
  value = module.data.db_port
}

output "db_name" {
  value = module.data.db_name
}

output "db_secret_arn" {
  value = module.data.db_secret_arn
}

output "redis_primary_endpoint" {
  value = module.data.redis_primary_endpoint
}

output "redis_reader_endpoint" {
  value = module.data.redis_reader_endpoint
}

output "redis_port" {
  value = module.data.redis_port
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "ecr_repository_url" {
  value = module.compute.ecr_repository_url
}

output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.compute.ecs_service_name
}

output "task_execution_role_arn" {
  value = module.compute.task_execution_role_arn
}

output "task_role_arn" {
  value = module.compute.task_role_arn
}

output "cloudfront_domain_name" {
  value = module.edge.cloudfront_domain_name
}

output "static_assets_bucket" {
  value = module.edge.static_assets_bucket
}

output "backups_bucket" {
  value = module.edge.backups_bucket
}

output "github_deploy_role_arn" {
  value = module.cicd.deploy_role_arn
}

output "guardduty_detector_id" {
  value = module.security.guardduty_detector_id
}

output "access_analyzer_arn" {
  value = module.security.access_analyzer_arn
}

output "flow_log_group_name" {
  value = module.security.flow_log_group_name
}

output "config_bucket" {
  value = module.security.config_bucket
}