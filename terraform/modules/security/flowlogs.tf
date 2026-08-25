resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
    name              = "/vpc/shopflow-flow-logs"
    retention_in_days = 14
    tags              = { Name = "ShopFlow-vpc-flow-logs" }
}

resource "aws_iam_role" "flow_logs" {
    name = "shopflow-vpc-flow-logs-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect    = "Allow"
            Principal = { Service = "vpc-flow-logs.amazonaws.com" }
            Action    = "sts:AssumeRole"
        }]
    })
}

resource "aws_iam_role_policy" "flow_logs" {
    name = "publish-to-log-group"
    role = aws_iam_role.flow_logs.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Action = [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ]
            Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
        }]
    })
}

resource "aws_flow_log" "vpc" {
    vpc_id               = var.vpc_id
    traffic_type          = "ALL"
    log_destination_type  = "cloud-watch-logs"
    log_destination        = aws_cloudwatch_log_group.vpc_flow_logs.arn
    iam_role_arn           = aws_iam_role.flow_logs.arn
    tags                    = { Name = "ShopFlow-vpc-flow-log" }
}
