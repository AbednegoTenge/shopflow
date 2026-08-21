# environments/dev/outputs.tf

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