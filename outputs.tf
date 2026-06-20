output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "alb_url" {
  value = "http://${aws_lb.app.dns_name}/"
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "alb_arn_suffix" {
  value = aws_lb.app.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "health_check_id" {
  value = aws_route53_health_check.app.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "rds_endpoint" {
  value = try(aws_db_instance.rds[0].endpoint, "disabled")
}

output "instance_name_tag" {
  value = "${local.name}-app"
}

output "region" {
  value = var.region
}
