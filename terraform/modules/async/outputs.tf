# modules/async/outputs.tf
output "queue_url"      { value = aws_sqs_queue.orders_queue.url }
output "dlq_url"        { value = aws_sqs_queue.orders_dlq.url }
output "lambda_function_name" { value = aws_lambda_function.worker.function_name }
output "dlq_name" { value = aws_sqs_queue.orders_dlq.name }