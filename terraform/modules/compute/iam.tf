data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "shopflow-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "ShopFlow-ecs-execution-role" }
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "shopflow-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "ShopFlow-ecs-task-role" }
}

resource "aws_iam_role_policy" "task_secrets" {
  name = "read-db-secret"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.rds_secret_arn      # scoped to this one secret, not "*"
    }]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "task_events" {
  name = "publish-order-events"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = "arn:aws:events:us-east-1:${data.aws_caller_identity.current.account_id}:event-bus/default"
    }]
  })
}

resource "aws_iam_role_policy" "task_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}