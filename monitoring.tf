resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-ha-alarms-${random_id.suffix.hex}"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- ALB: 異常ホスト >= 1（ターゲットがローテーションから外れた）---
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.app.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --- ALB: 健全ホスト < 2（冗長喪失＝AZ単位で見ないと見逃す点を検証）---
resource "aws_cloudwatch_metric_alarm" "healthy_hosts_low" {
  alarm_name          = "${local.name}-alb-healthy-hosts-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 2
  treat_missing_data  = "breaching"
  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.app.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# --- ALB: ELB生成の5xx（健全ターゲット無し=503等）---
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${local.name}-alb-elb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# --- Route 53 ヘルスチェック（メトリクスは us-east-1）---
resource "aws_cloudwatch_metric_alarm" "route53_unhealthy" {
  provider            = aws.use1
  alarm_name          = "${local.name}-route53-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  dimensions = {
    HealthCheckId = aws_route53_health_check.app.id
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# --- ASG: 稼働インスタンス < 2 ---
resource "aws_cloudwatch_metric_alarm" "asg_inservice_low" {
  alarm_name          = "${local.name}-asg-inservice-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Minimum"
  threshold           = 2
  treat_missing_data  = "breaching"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  alarm_actions = [aws_sns_topic.alarms.arn]
}
