variable "region" {
  description = "リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "name_prefix" {
  description = "リソース名プレフィックス"
  type        = string
  default     = "soa03-08"
}

variable "notification_email" {
  description = "SNS通知先メール（空ならサブスクリプションを作成しない）"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "ASGインスタンスタイプ"
  type        = string
  default     = "t3.micro"
}

variable "asg_health_check_type" {
  description = "ASGヘルスチェック種別。EC2=ステータスチェックのみ(アプリ層の死を検知できない)／ELB=ターゲットグループのヘルスを反映(本番推奨)"
  type        = string
  default     = "ELB"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "enable_rds" {
  description = "Multi-AZ RDSを作成するか。falseでコスト削減(HA=ALB/ASG/Route53のみ検証)"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}
