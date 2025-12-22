output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "alb_dns_name" {
  value = aws_lb.ecs_alb.dns_name
}

output "alb_arn" {
  value = aws_lb.ecs_alb.arn
}

output "webapp_url" {
  value = "http://${aws_lb.ecs_alb.dns_name}"
}
