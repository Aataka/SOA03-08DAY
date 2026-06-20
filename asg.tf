# 最新のAmazon Linux 2023 AMI（SSMパブリックパラメータ）
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- インスタンスロール：SSM（インバウンド無しで操作するため）---
resource "aws_iam_role" "app" {
  name_prefix = "${var.name_prefix}-app-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.name_prefix}-app-"
  role        = aws_iam_role.app.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2必須
  }

  # どのインスタンス/AZが応答したか分かるindexを返す。ヘルスチェックは / が200を返せばOK。
  user_data = base64encode(<<EOT
#!/bin/bash
dnf install -y httpd
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds:21600")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
echo "OK host=$IID az=$AZ" > /var/www/html/index.html
systemctl enable --now httpd
# destroy忘れの課金頭打ち（24h後にstop）
shutdown -h +1440
EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-app" })
  }

  tags = local.tags
}

resource "aws_autoscaling_group" "app" {
  name_prefix         = "${var.name_prefix}-asg-"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = local.subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]

  # EC2(既定)=ステータスチェックのみでアプリ死を検知できない／ELB=TGのヘルスを反映(本番推奨)
  health_check_type         = var.asg_health_check_type
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # GroupInServiceInstances 等をCloudWatchへ（1分粒度）
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupInServiceInstances",
    "GroupDesiredCapacity",
    "GroupTotalInstances",
    "GroupTerminatingInstances",
    "GroupPendingInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }
}
