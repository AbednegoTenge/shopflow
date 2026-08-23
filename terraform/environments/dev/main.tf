
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

module "async" {
  source             = "../../modules/async"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
  rds_endpoint       = module.data.db_endpoint
  rds_secret_arn     = module.data.db_secret_arn
}

module "edge" {
  source       = "../../modules/edge"
  alb_dns_name = module.compute.alb_dns_name
  kms_key_arn = module.networking.kms_key_arn
}

module "cicd" {
  source                   = "../../modules/cicd"
  github_org               = var.github_org
  github_repo              = var.github_repo
  ecr_repository_arn       = module.compute.ecr_repository_arn
  ecs_cluster_arn          = module.compute.ecs_cluster_arn
  ecs_service_arn          = module.compute.ecs_service_arn
  task_execution_role_arn  = module.compute.task_execution_role_arn
  task_role_arn            = module.compute.task_role_arn
}