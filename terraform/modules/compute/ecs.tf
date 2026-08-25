resource "aws_ecs_cluster" "main" {
    name = "shopflow-cluster"
    tags = { Name = "ShopFlow-ecs-cluster" }
}

resource "aws_ecs_task_definition" "app" {
    family = "shopflow-app"
    requires_compatibilities = ["FARGATE"]
    network_mode = "awsvpc"
    cpu = "256"
    memory = "512"
    execution_role_arn = aws_iam_role.execution.arn
    task_role_arn = aws_iam_role.task.arn
    runtime_platform {
        cpu_architecture        = "ARM64"
        operating_system_family = "LINUX"
    }
    tags = { Name = "ShopFlow-task-def" }
    container_definitions = jsonencode([
        {
            name = "app"
            image = "${aws_ecr_repository.app.repository_url}:latest"
            portMappings = [
                {
                    containerPort = var.container_port, protocol = "tcp"
                }
            ]
            environment = [
                { name = "DB_HOST", value = var.rds_endpoint },
                { name = "DB_NAME", value = "shopflow" },
                { name = "SECRET_ARN", value = var.rds_secret_arn },
                { name = "REDIS_HOST", value = var.redis_endpoint }
            ]
            logConfiguration = {
                logDriver = "awslogs"
                options = {
                    "awslogs-group" = aws_cloudwatch_log_group.app.name,
                    "awslogs-region" = "us-east-1",
                    "awslogs-stream-prefix" = "app"
                }
            }
        },
        {
            name = "xray-daemon"
            image = "amazon/aws-xray-daemon:latest"
            cpu = 32
            memory = 256
            portMappings = [{ containerPort = 2000, protocol = "udp" }]
            logConfiguration = {
                logDriver = "awslogs"
                options = {
                    "awslogs-group" = aws_cloudwatch_log_group.app.name,
                    "awslogs-region" = "us-east-1",
                    "awslogs-stream-prefix" = "xray"
                }
            }
        }
    ])

    # CI (Phase 6) registers new revisions directly and points the service at them;
    # this field ignored here so terraform apply doesn't revert deploys back to :latest.
    lifecycle {
        ignore_changes = [container_definitions]
    }
}

resource "aws_ecs_service" "app" {
    name = "shopflow-app-service"
    cluster = aws_ecs_cluster.main.id
    task_definition = aws_ecs_task_definition.app.arn
    desired_count = 2
    launch_type = "FARGATE"
    enable_execute_command = true

    network_configuration {
      subnets = var.private_subnet_ids
      security_groups = [var.ecs_sg_id]
      assign_public_ip = false
    }

    load_balancer {
      target_group_arn = aws_lb_target_group.app.arn
      container_name = "app"
      container_port = var.container_port
    }

    # a deploy whose tasks keep failing (e.g. wrong image architecture) rolls
    # back automatically instead of retrying forever — see CLAUDE.md Phase 6
    # notes for the incident that motivated this
    deployment_circuit_breaker {
      enable   = true
      rollback = true
    }

    tags = { Name = "ShopFlow-ecs-service" }

    depends_on = [aws_lb_listener.http]

    # CI (Phase 6) points this at whatever revision it just registered;
    # ignored here so terraform apply doesn't revert the running revision.
    lifecycle {
        ignore_changes = [task_definition]
    }
}
