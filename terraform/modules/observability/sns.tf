
resource "aws_sns_topic" "alerts" {
    name = "shopflow-alerts"
}

resource "aws_sns_topic_subscription" "email" {
    topic_arn = aws_sns_topic.name.arn
    protocol = "email"
    endpoint = var.alert_email
}