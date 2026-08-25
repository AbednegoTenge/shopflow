

resource "aws_db_instance" "shopflow" {
  identifier = "shopflow-db"
  username = "shopflow_admin"
  engine = "postgres"
  instance_class = "db.t4g.micro"
  manage_master_user_password = true
  multi_az = true
  storage_encrypted = true
  kms_key_id = var.kms_key_arn
  db_subnet_group_name = var.db_subnet_group_name
  db_name = "shopflow"
  vpc_security_group_ids = [var.rds_sg_id]
  skip_final_snapshot = true
  allocated_storage = 20
}


resource "aws_elasticache_replication_group" "cache" {
    replication_group_id = "shopflow-cache"
    description = "ShopFlow Redis with automatic failover"
    node_type = "cache.t3.micro"
    engine = "redis"
    num_cache_clusters = 2
    automatic_failover_enabled = true
    multi_az_enabled = true
    subnet_group_name = var.elasticache_subnet_group_name
    security_group_ids = [var.cache_sg_id]
}