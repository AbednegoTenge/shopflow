
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
    alarm_name = "shopflow-alb-5xx"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name = "HTTPCode_Target_5XX_Count"
    namespace = "AWS/ApplicationELB"
    period = 60
    statistic = "Sum"
    threshold = 10
    alarm_actions = [aws_sns_topic.alerts.arn]
    ok_actions = [aws_sns_topic.alerts.arn]
    dimensions = { LoadBalancer = var.alb_arn_suffix}
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
    alarm_name = "shopflow-alb-latency"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 3
    metric_name = "TargetResponseTime"
    namespace = "AWS/ApplicationELB"
    period = 60
    statistic = "Average"
    threshold = 1
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = { LoadBalancer = var.alb_arn_suffix}
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
    alarm_name = "shopflow-unhealthy-targets"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name = "UnHealthyHostCount"
    namespace = "AWS/ApplicationELB"
    period = 60
    statistic = "Average"
    threshold = 0
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = {
        TargetGroup = var.target_group_arn_suffix
        LoadBalancer = var.alb_arn_suffix
    }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
    alarm_name = "shopflow-ecs-cpu-high" 
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name = "CPUUtilization"
    namespace = "AWS/ECS"
    period = 60
    statistic = "Average"
    threshold = 85
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
    }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
    alarm_name = "shopflow-ecs-memory-high"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name = "MemoryUtilization"
    namespace = "AWS/ECS"
    period = 60
    statistic = "Average"
    threshold = 75
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
    }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
    alarm_name = "shopflow-rds-connections"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name = "DatabaseConnections"
    namespace = "AWS/RDS"
    period = 60
    statistic = "Average"
    threshold = 40
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = { DBInstanceIdentifier = var.rds_instance_id }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
    alarm_name = "shopflow-rds-cpu"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 2
    metric_name = "CPUUtilization"
    namespace = "AWS/RDS"
    period = 60
    statistic = "Average"
    threshold = 75
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = { DBInstanceIdentifier = var.rds_instance_id }
}

resource "aws_cloudwatch_metric_alarm" "dlq_has_messages" {
    alarm_name = "shopflow-dlq-has-messages"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods = 1
    metric_name = "ApproximateNumberOfMessagesVisible"
    namespace = "AWS/SQS"
    period = 300
    statistic = "Maximum"
    threshold = 0
    alarm_actions = [aws_sns_topic.alerts.arn]
    dimensions = { QueueName = var.dlq_name }
}