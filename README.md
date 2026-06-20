# SOA03-08DAY ― Multi-AZ 高可用性アーキテクチャ (ALB + Auto Scaling + Multi-AZ RDS + Route 53 ヘルスチェック)

ALB / Amazon EC2 Auto Scaling / Multi-AZ RDS / Route 53 ヘルスチェックで構成した高可用性
Web アプリを Terraform で再現し、**障害挿入（インスタンス終了）で耐障害性を実測検証**するための IaC 一式です。

- デフォルト VPC の 2 AZ（NAT GW 不要 = コスト最小）
- ALB（インターネット公開）→ ターゲットグループ → ASG（2 AZ・min2/max4）
- ASG ヘルスチェックは `ELB` 型（EC2 型はアプリ層の死を検知できないため）
- Multi-AZ MariaDB（非公開・アプリ層とは分離してテスト）
- Route 53 ヘルスチェック（エンドポイント単位）＋ CloudWatch アラーム（ALB / Route 53 / ASG）

## アーキテクチャ

```
                          Internet
                              │  HTTP :80
                              ▼
                    ┌───────────────────┐
                    │  Application LB    │  (public subnet ×2 / 2AZ)
                    └─────────┬─────────┘
              ┌───────────────┴───────────────┐
              ▼                               ▼
      ┌──────────────┐                ┌──────────────┐
      │  AZ-a  EC2   │                │  AZ-d  EC2   │   Auto Scaling Group
      │  (httpd)     │                │  (httpd)     │   min2 / max4 / desired2
      └──────┬───────┘                └──────┬───────┘   health_check_type = ELB
             │ :3306                         │ :3306
             ▼                               ▼
      ┌──────────────────────────────────────────────┐
      │   Multi-AZ RDS (MariaDB)  primary ⇄ standby   │
      └──────────────────────────────────────────────┘

   監視: Route 53 Health Check ─▶ ALB（エンドポイント全体）
        ALB Target Group HC ─▶ 各 EC2（インスタンス単位）
        CloudWatch Alarms ─▶ SNS
```

## 前提

- Terraform >= 1.5 / AWS Provider >= 5.40
- 認証は環境側（`~/.aws/`）、リージョンは `ap-northeast-1`
- インスタンス操作は SSH 鍵なし・Session Manager(SSM) 経由

## 使い方

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
# ... 検証 ...
terraform destroy
```

主な変数（`variables.tf`）:

| 変数 | 既定 | 説明 |
|---|---|---|
| `region` | `ap-northeast-1` | リージョン |
| `name_prefix` | `soa03-08` | リソース名プレフィックス |
| `instance_type` | `t3.micro` | ASG インスタンスタイプ |
| `asg_health_check_type` | `ELB` | `EC2`=ステータスチェックのみ／`ELB`=TG ヘルス反映(推奨) |
| `asg_min_size` / `asg_max_size` / `asg_desired_capacity` | `2` / `4` / `2` | ASG 容量 |
| `enable_rds` | `true` | `false` で Multi-AZ RDS を省きコスト削減 |
| `db_instance_class` | `db.t3.micro` | RDS インスタンスクラス |
| `notification_email` | `""` | SNS 通知先（空ならサブスクリプション作らない） |

主な出力: `alb_url` / `asg_name` / `target_group_arn_suffix` / `health_check_id` / `sns_topic_arn` / `rds_endpoint`

## 検証 Runbook（障害挿入 / カオステスト）

```bash
ALB=$(terraform output -raw alb_url)
ASG=$(terraform output -raw asg_name)
TAG=$(terraform output -raw instance_name_tag)

# 1) 連続アクセスで応答インスタンスを観測しながら…
while true; do curl -s -o /dev/null -w "%{http_code} " "$ALB"; sleep 0.3; done

# 2) ASG の1台を終了（障害シミュレート）
IID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$TAG" \
  "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ec2 terminate-instances --instance-ids "$IID"

# 3) ASG の自己修復タイムラインを確認
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" \
  --query 'Activities[].{Time:StartTime,Desc:Description,Status:StatusCode}' --output table

# 4) Route 53 ヘルスチェックは緑のまま（ALB が単一障害を隠蔽）
aws cloudwatch get-metric-statistics --region us-east-1 \
  --namespace AWS/Route53 --metric-name HealthCheckStatus \
  --dimensions Name=HealthCheckId,Value=$(terraform output -raw health_check_id) \
  --start-time "$(date -u -d '-15 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 60 --statistics Minimum --output table
```

## ハマりどころ

- ASG ヘルスチェックの既定は `EC2`（ステータスチェックのみ）。プロセスは死んでも EC2 が正常なら
  ASG は置換しない＝ALB から外れたゾンビが残る。本番は `ELB` 型にする（本構成の既定）。
- Route 53 ヘルスチェックの CloudWatch メトリクス(`HealthCheckStatus`)は **us-east-1** にのみ出る。
- ALB ターゲットグループの `deregistration_delay` 既定は 300s。検証では長すぎるので 30s に短縮。
- Multi-AZ RDS の standby は読み取りに使えない（read replica とは別物）。`ReplicaLag` メトリクスも出ない。
- RDS の `backup_retention_period=0` は自動バックアップ無効＝PITR 不可の本番アンチパターン。
  可用性(Multi-AZ) ≠ 耐久性/復旧(バックアップ)。本構成は 1 日に設定。
