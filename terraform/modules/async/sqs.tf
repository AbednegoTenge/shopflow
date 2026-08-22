resource "aws_sqs_queue" "orders_dlq" {
    name = "shopflow-orders-dlq"
    message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "orders_queue" {
    name = "shopflow-orders-queue"
    visibility_timeout_seconds = 60
    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
        maxReceiveCount = 3
    })
}

data "aws_iam_policy_document" "sqs" {
    statement {
      effect = "Allow"
      actions = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.orders_queue.arn]
      principals {
        type = "Service"
        identifiers = ["events.amazonaws.com"]
      }
      condition {
        test = "ArnEquals"
        variable = "aws:SourceArn"
        values = [aws_cloudwatch_event_rule.order_created.arn]
      }
    }
}

resource "aws_sqs_queue_policy" "orders_queue" {
    queue_url = aws_sqs_queue.orders_queue.id
    policy = data.aws_iam_policy_document.sqs.json
}
