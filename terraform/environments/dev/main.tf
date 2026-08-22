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

# environments/dev/main.tf — add this block
module "compute" {
  source              = "../../modules/compute"
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  alb_sg_id           = module.networking.alb_sg_id
  ecs_sg_id           = module.networking.ecs_sg_id
  rds_endpoint        = module.data.db_endpoint
  rds_secret_arn      = module.data.db_secret_arn
  redis_endpoint      = module.data.redis_primary_endpoint
}

# environments/dev/main.tf — add this
module "async" {
  source             = "../../modules/async"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
  rds_endpoint       = module.data.db_endpoint
  rds_secret_arn     = module.data.db_secret_arn
}