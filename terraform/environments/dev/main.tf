# terraform/environments/dev/main.tf

module "networking" {
  source   = "../../modules/networking"
  vpc_cidr = var.vpc_cidr
}