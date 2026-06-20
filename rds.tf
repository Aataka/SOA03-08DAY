# Multi-AZ RDS（MariaDB）。アプリ層は本検証ではDBに依存させず（テスト分離）、
# 構成の忠実性と「Multi-AZ標準の意味論（ReplicaLag不在/スタンバイは読めない）」の実証に使う。
resource "aws_db_subnet_group" "rds" {
  count      = var.enable_rds ? 1 : 0
  name       = "${var.name_prefix}-rds-${random_id.suffix.hex}"
  subnet_ids = local.subnet_ids
  tags       = local.tags
}

resource "aws_db_instance" "rds" {
  count                  = var.enable_rds ? 1 : 0
  identifier             = "${var.name_prefix}-db-${random_id.suffix.hex}"
  engine                 = "mariadb"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = "WaRdsDb"
  username               = "mainuser"
  password               = "WaStr0ngP4ssw0rd" # 検証用の使い捨て。非公開DB。本番はSecrets Manager。
  multi_az               = true
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  db_subnet_group_name   = aws_db_subnet_group.rds[0].name

  # ラボは backup_retention_period=0（自動バックアップ無効＝PITR不可の本番アンチパターン）。
  # ここでは1日に。可用性(Multi-AZ)≠耐久性/復旧(バックアップ)。
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = local.tags
}
