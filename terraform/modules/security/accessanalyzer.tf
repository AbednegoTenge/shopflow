resource "aws_accessanalyzer_analyzer" "main" {
    analyzer_name = "shopflow-access-analyzer"
    type          = "ACCOUNT"
    tags          = { Name = "ShopFlow-access-analyzer" }
}
