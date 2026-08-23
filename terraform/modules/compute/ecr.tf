resource "aws_ecr_repository" "app" {
    name = "shopflow-app"
    image_tag_mutability = "MUTABLE"
    image_scanning_configuration { scan_on_push = true }
    # this project destroys/rebuilds often; without this, terraform destroy
    # fails on a non-empty repo (RepositoryNotEmptyException)
    force_delete = true
    tags = { Name = "ShopFlow-ecr" }
}
