data "archive_file" "worker_zip" {
    type = "zip"
    source_dir = "${path.module}/../../../worker"
    output_path = "${path.module}/worker.zip"
}

resource "aws_security_group" "lambda_sg" {
    name_prefix = "shopflow-lambda-sg"
    vpc_id = var.vpc_id
    description = "Security group for lambda function"
}

resource "aws_vpc_security_group_egress_rule" "lambda_egress" {
    security_group_id = aws_security_group.lambda_sg.id
    ip_protocol        = "-1"
    cidr_ipv4          = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda" {
    security_group_id = var.rds_sg_id
    referenced_security_group_id = aws_security_group.lambda_sg.id
    ip_protocol = "tcp"
    from_port = 5432
    to_port = 5432
}

resource "aws_lambda_function" "worker" {
    function_name = "shopflow-order-worker"
    role = aws_iam_role.lambda_worker.arn
    handler = "index.handler"
    runtime = "nodejs20.x"
    filename = data.archive_file.worker_zip.output_path
    source_code_hash = data.archive_file.worker_zip.output_base64sha256
    timeout = 10
    memory_size = 256

    vpc_config {
      subnet_ids = var.private_subnet_ids
      security_group_ids = [aws_security_group.lambda_sg.id]
    }
    environment {
        variables = {
            DB_HOST = var.rds_endpoint
            DB_NAME = "shopflow"
            SECRET_ARN = var.rds_secret_arn
        }
    }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
    event_source_arn = aws_sqs_queue.orders_queue.arn
    function_name = aws_lambda_function.worker.arn
    batch_size = 5
}
