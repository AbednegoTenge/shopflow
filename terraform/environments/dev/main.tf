# terraform/environments/dev/main.tf

module "networking" {
  source   = "../../modules/networking"
  vpc_cidr = var.vpc_cidr
}

module "data" {
  source               = "../../modules/data"
  db_subnet_group_name = module.networking.db_subnet_group_name
  elasticache_subnet_group_name = module.networking.elasticache_subnet_group_name
  rds_sg_id                     = module.networking.rds_sg_id
  cache_sg_id                   = module.networking.cache_sg_id
  kms_key_arn                   = module.networking.kms_key_arn
}
