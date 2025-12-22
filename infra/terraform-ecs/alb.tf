resource "aws_lb" "ecs_alb" {
  name               = "${var.project_name}-alb-main"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [local.alb_sg]
  subnets            = local.public_subnets
  
  # Increase idle timeout to 120 seconds (default is 60)
  # This prevents 504 errors when backend takes time to connect to Couchbase
  idle_timeout = 120
}

# frontend target group
resource "aws_lb_target_group" "webapp_tg" {
  name        = "${var.project_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/"
    matcher             = "200,301,302"
    protocol            = "HTTP"
  }
}

# backend target group
resource "aws_lb_target_group" "backend_tg" {
  name        = "${var.project_name}-api-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/healthz"
    matcher             = "200"
    protocol            = "HTTP"
  }
}

# listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp_tg.arn
  }
}

# route /api to backend
resource "aws_lb_listener_rule" "api_routing" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/healthz", "/docs", "/openapi.json"]
    }
  }
}
