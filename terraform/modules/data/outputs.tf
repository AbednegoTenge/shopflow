output "db_endpoint" {
  value = aws_db_instance.shopflow.address
}

output "db_port" {
  value = aws_db_instance.shopflow.port
}

output "db_name" {
  value = aws_db_instance.shopflow.db_name
}

output "db_secret_arn" {
  value = aws_db_instance.shopflow.master_user_secret[0].secret_arn
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.cache.primary_endpoint_address
}

output "redis_reader_endpoint" {
  value = aws_elasticache_replication_group.cache.reader_endpoint_address
}

output "redis_port" {
  value = 6379
}

output "rds_instance_id" { 
  value = aws_db_instance.shopflow.id 
}