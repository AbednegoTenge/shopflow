output "guardduty_detector_id" {
    value = aws_guardduty_detector.main.id
}

output "access_analyzer_arn" {
    value = aws_accessanalyzer_analyzer.main.arn
}

output "flow_log_group_name" {
    value = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "config_bucket" {
    value = aws_s3_bucket.config.id
}
