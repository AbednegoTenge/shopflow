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
