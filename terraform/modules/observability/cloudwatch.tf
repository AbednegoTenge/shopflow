

resource "aws_cloudwatch_dashboard" "main" {
    dashboard_name = "shopflow-dashboard"
    dashboard_body = jsonencode({
        widgets = [
            {
                type = "metric"
                x = 0
                y = 0
                width = 12
                height = 6 
                properties = {
                    title = "ALB requests and errors"
                    region = "us-east-1"
                    metrics = [
                        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
                        [".", "HTTPCode_Target_5XX_Count", ".", "."]
                    ]
                }
            },
            {
                type = "metric"
                x = 0
                y = 0
                width = 12
                height = 6
                properties = {
                    title = "ECS CPU and memory"
                    region = "us-east-1"
                    metrics = [
                        ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
                        [".", "MemoryUtilization", ".", ".", ".", "."]
                    ]
                }
            },
            {
                type = "metric", x = 0, y = 0, width = 12, height = 6
                properties = {
                    title = "RDS Connections"
                    region = "us-east-1"
                    metrics = [["AWS/RDS", "DatabaseConnections", "D   DBInstanceIdentifier", var.rds_instance_id]]
                }
            },
            {
                type = "metric", x = 0, y = 0, width = 12, height = 6
                properties = {
                    title = "SQS Queue depth"
                    region = "us-east-1"
                    metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name]]
                }
            }

        ]
    })
}