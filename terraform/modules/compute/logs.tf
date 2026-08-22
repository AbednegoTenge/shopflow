resource "aws_cloudwatch_log_group" "app" {
    name = "/ecs/shopflow-app"
    retention_in_days = 14
    tags = { Name = "ShopFlow-log-group" }
}
