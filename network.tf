# デフォルトVPCとAZごとの既定サブネットを使う（NAT GW不要・コスト最小）。
# ALB/ASG/RDSサブネットグループはいずれも2AZ以上が必要なので、先頭2サブネット(=2AZ)を採用。
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  subnet_ids = slice(tolist(data.aws_subnets.default.ids), 0, 2)
}

# --- ALB セキュリティグループ：インターネットから HTTP のみ ---
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "ALB SG: HTTP from internet"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.tags, { Name = "${local.name}-alb-sg" })
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- アプリ(ASG)セキュリティグループ：ALB からの HTTP のみ受ける ---
resource "aws_security_group" "app" {
  name_prefix = "${var.name_prefix}-app-"
  description = "App SG: HTTP only from ALB"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.tags, { Name = "${local.name}-app-sg" })
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# egress 全許可（SSM/yum/RDS への接続用）。インバウンドは公開しない。
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- RDS セキュリティグループ：アプリ SG からの 3306 のみ ---
resource "aws_security_group" "rds" {
  count       = var.enable_rds ? 1 : 0
  name_prefix = "${var.name_prefix}-rds-"
  description = "RDS SG: MySQL from app SG only"
  vpc_id      = data.aws_vpc.default.id
  tags        = merge(local.tags, { Name = "${local.name}-rds-sg" })
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  count                        = var.enable_rds ? 1 : 0
  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}
