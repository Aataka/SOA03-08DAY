# Route 53 ヘルスチェック：ALBエンドポイント全体を監視（エンドポイント単位）。
# ALBのターゲットグループ・ヘルスチェック(インスタンス単位)とは監視レイヤが異なる。
resource "aws_route53_health_check" "app" {
  fqdn              = aws_lb.app.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 10 # 高速
  failure_threshold = 1

  tags = merge(local.tags, { Name = "${local.name}-health" })
}
