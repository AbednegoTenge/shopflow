resource "aws_cloudwatch_event_rule" "order_created" {
    name = "shopflow-order-created"
    event_pattern = jsonencode({
        source = ["shopflow.app"]
        detail-type = ["OrderCreated"]
    })
}

resource "aws_cloudwatch_event_target" "to_sqs" {
    rule = aws_cloudwatch_event_rule.order_created.name
    arn = aws_sqs_queue.orders_queue.arn
}
