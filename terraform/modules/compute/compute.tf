

resource "aws_ecr_repository" "app" {
    name = "shopflow-app"
    image_tag_mutability = "MUTABLE"
    image_scanning_configuration { scan_on_push = true }
    tags = { Name = "ShopFlow-ecr" }
}


resource "aws_cloudwatch_log_group" "app" {
    name = "/ecs/shopflow-app"
    retention_in_days = 14
    tags = { Name = "ShopFlow-log-group" }
}

resource "aws_lb" "app" {
    name = "shopflow-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [var.alb_sg_id]
    subnets = var.public_subnet_ids
    tags = { Name = "ShopFlow-alb" }
}

resource "aws_lb_target_group" "app" {
    name = "shopflow-tg"
    port = var.container_port
    protocol = "HTTP"
    vpc_id = var.vpc_id
    target_type = "ip"
    health_check {
        path = "/health"
        healthy_threshold = 2
        unhealthy_threshold = 3
        interval = 30
        timeout = 5
    }
    tags = { Name = "ShopFlow-tg" }
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.app.arn
    port = 80
    protocol = "HTTP"
    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.app.arn
    }
}

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
        }
    ])
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

    tags = { Name = "ShopFlow-ecs-service" }

    depends_on = [aws_lb_listener.http]
}

resource "aws_appautoscaling_target" "ecs" {
  max_capacity = 4
  min_capacity = 2
  resource_id = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name = "ecs-cpuscaling-policy"
  policy_type = "TargetTrackingScaling"
  resource_id = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 60
    scale_in_cooldown = 300
    scale_out_cooldown = 300
  }
}
