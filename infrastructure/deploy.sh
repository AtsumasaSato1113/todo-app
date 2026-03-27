#!/bin/bash
# ============================================================
# Todo App - AWS ECS Fargate デプロイスクリプト
# ============================================================
# 前提条件:
#   - AWS CLI がインストール済み (aws configure 設定済み)
#   - Docker Desktop が起動中
#
# 使い方:
#   cd C:\aws\20260327_01
#   bash infrastructure/deploy.sh
# ============================================================
set -e

# ====== 設定 ======
REGION="${AWS_REGION:-ap-northeast-1}"
CLUSTER="todo-cluster"
SERVICE="todo-service"
TASK_FAMILY="todo-task"
ALB_NAME="todo-alb"
TG_NAME="todo-tg"

# AWS アカウントID を自動取得
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "======================================================"
echo " AWS Account : $ACCOUNT_ID"
echo " Region      : $REGION"
echo "======================================================"

# スクリプトの場所からプロジェクトルートを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ====== ネットワーク情報を取得 (デフォルトVPC使用) ======
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" --output text --region $REGION)

SUBNET_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=defaultForAz,Values=true" \
  --query "Subnets[0].SubnetId" --output text --region $REGION)

SUBNET_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=defaultForAz,Values=true" \
  --query "Subnets[1].SubnetId" --output text --region $REGION)

ALL_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=defaultForAz,Values=true" \
  --query "Subnets[*].SubnetId" --output text --region $REGION)

echo "VPC     : $VPC_ID"
echo "Subnets : $SUBNET_1, $SUBNET_2"
echo ""

# ====== [1/7] ECR リポジトリ作成 ======
echo "[1/7] ECR リポジトリを作成..."

aws ecr describe-repositories --repository-names todo-frontend --region $REGION > /dev/null 2>&1 || \
  aws ecr create-repository --repository-name todo-frontend --region $REGION > /dev/null

aws ecr describe-repositories --repository-names todo-backend --region $REGION > /dev/null 2>&1 || \
  aws ecr create-repository --repository-name todo-backend --region $REGION > /dev/null

echo "  OK"

# ====== [2/7] Docker イメージをビルド & プッシュ ======
echo "[2/7] Docker イメージをビルド & プッシュ..."

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_BASE

# Frontend: 本番用 nginx ステージをビルド
docker build -t $ECR_BASE/todo-frontend:latest "$PROJECT_DIR/frontend"
docker push $ECR_BASE/todo-frontend:latest
echo "  frontend: OK"

# Backend
docker build -t $ECR_BASE/todo-backend:latest "$PROJECT_DIR/backend"
docker push $ECR_BASE/todo-backend:latest
echo "  backend: OK"

# ====== [3/7] IAM ロール ======
echo "[3/7] IAM ロールを確認/作成..."

aws iam get-role --role-name ecsTaskExecutionRole > /dev/null 2>&1 || {
  aws iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{
        "Effect":"Allow",
        "Principal":{"Service":"ecs-tasks.amazonaws.com"},
        "Action":"sts:AssumeRole"
      }]
    }' > /dev/null
  aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
}

EXEC_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole"
echo "  OK: $EXEC_ROLE_ARN"

# ====== [4/7] セキュリティグループ ======
echo "[4/7] セキュリティグループを作成..."

# ALB SG: インターネット → ポート80 を許可
ALB_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=todo-alb-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text --region $REGION 2>/dev/null)

if [ "$ALB_SG_ID" = "None" ] || [ -z "$ALB_SG_ID" ]; then
  ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name todo-alb-sg \
    --description "Todo App ALB" \
    --vpc-id $VPC_ID \
    --query "GroupId" --output text --region $REGION)
  aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 \
    --region $REGION > /dev/null
fi
echo "  ALB SG  : $ALB_SG_ID"

# ECS SG: ALB → ポート80 を許可
ECS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=todo-ecs-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text --region $REGION 2>/dev/null)

if [ "$ECS_SG_ID" = "None" ] || [ -z "$ECS_SG_ID" ]; then
  ECS_SG_ID=$(aws ec2 create-security-group \
    --group-name todo-ecs-sg \
    --description "Todo App ECS Tasks" \
    --vpc-id $VPC_ID \
    --query "GroupId" --output text --region $REGION)
  aws ec2 authorize-security-group-ingress \
    --group-id $ECS_SG_ID --protocol tcp --port 80 \
    --source-group $ALB_SG_ID \
    --region $REGION > /dev/null
fi
echo "  ECS SG  : $ECS_SG_ID"

# EFS SG: ECSタスク → NFS (ポート2049) を許可
EFS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=todo-efs-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text --region $REGION 2>/dev/null)

if [ "$EFS_SG_ID" = "None" ] || [ -z "$EFS_SG_ID" ]; then
  EFS_SG_ID=$(aws ec2 create-security-group \
    --group-name todo-efs-sg \
    --description "Todo App EFS" \
    --vpc-id $VPC_ID \
    --query "GroupId" --output text --region $REGION)
  aws ec2 authorize-security-group-ingress \
    --group-id $EFS_SG_ID --protocol tcp --port 2049 \
    --source-group $ECS_SG_ID \
    --region $REGION > /dev/null
fi
echo "  EFS SG  : $EFS_SG_ID"

# ====== [5/7] EFS (SQLiteデータ永続化) ======
echo "[5/7] EFS を作成..."

EFS_ID=$(aws efs describe-file-systems \
  --query "FileSystems[?Tags[?Key=='Name'&&Value=='todo-efs']].FileSystemId|[0]" \
  --output text --region $REGION)

if [ "$EFS_ID" = "None" ] || [ -z "$EFS_ID" ]; then
  EFS_ID=$(aws efs create-file-system \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=todo-efs \
    --query "FileSystemId" --output text --region $REGION)

  echo "  EFS 起動を待機中..."
  while true; do
    STATUS=$(aws efs describe-file-systems \
      --file-system-id $EFS_ID \
      --query "FileSystems[0].LifeCycleState" --output text --region $REGION)
    [ "$STATUS" = "available" ] && break
    echo "  ... $STATUS"
    sleep 5
  done

  # 各サブネットにマウントターゲットを作成
  for SUBNET_ID in $ALL_SUBNETS; do
    aws efs create-mount-target \
      --file-system-id $EFS_ID \
      --subnet-id $SUBNET_ID \
      --security-groups $EFS_SG_ID \
      --region $REGION > /dev/null 2>&1 || true
  done

  # マウントターゲットが全て available になるまで待機
  echo "  マウントターゲット起動を待機中..."
  while true; do
    MT_COUNT=$(aws efs describe-mount-targets \
      --file-system-id $EFS_ID \
      --query "length(MountTargets)" \
      --output text --region $REGION)
    AVAILABLE=$(aws efs describe-mount-targets \
      --file-system-id $EFS_ID \
      --query "length(MountTargets[?LifeCycleState=='available'])" \
      --output text --region $REGION)
    echo "  ... $AVAILABLE / $MT_COUNT が available"
    [ "$MT_COUNT" -gt 0 ] && [ "$MT_COUNT" = "$AVAILABLE" ] && break
    sleep 10
  done
fi
echo "  EFS ID  : $EFS_ID"

# ====== ECS クラスタ & CloudWatch ログ ======
aws ecs describe-clusters --clusters $CLUSTER --region $REGION \
  --query "clusters[0].status" --output text 2>/dev/null | grep -q "ACTIVE" || \
  aws ecs create-cluster --cluster-name $CLUSTER --region $REGION > /dev/null

aws logs create-log-group --log-group-name /ecs/todo-app --region $REGION 2>/dev/null || true

# ====== タスク定義を登録 ======
# ECSサイドカーパターン:
#   - frontend (nginx) と backend (FastAPI) が同じタスク内に共存
#   - 同じ localhost を共有するため nginx から localhost:8000 で FastAPI に接続可能
#   - EFS を /data にマウント → SQLite ファイルを永続化
cat > /tmp/todo-task-definition.json << EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "${EXEC_ROLE_ARN}",
  "volumes": [{
    "name": "efs-todo-data",
    "efsVolumeConfiguration": {
      "fileSystemId": "${EFS_ID}",
      "transitEncryption": "ENABLED"
    }
  }],
  "containerDefinitions": [
    {
      "name": "frontend",
      "image": "${ECR_BASE}/todo-frontend:latest",
      "essential": true,
      "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/todo-app",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "frontend"
        }
      }
    },
    {
      "name": "backend",
      "image": "${ECR_BASE}/todo-backend:latest",
      "essential": true,
      "environment": [
        {"name": "DATABASE_URL", "value": "sqlite:////data/todos.db"}
      ],
      "mountPoints": [{
        "sourceVolume": "efs-todo-data",
        "containerPath": "/data",
        "readOnly": false
      }],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
        "interval": 10,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 30
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/todo-app",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "backend"
        }
      }
    }
  ]
}
EOF

aws ecs register-task-definition \
  --cli-input-json file:///tmp/todo-task-definition.json \
  --region $REGION > /dev/null
echo "  タスク定義: OK"

# ====== [6/7] ALB ======
echo "[6/7] ALB を作成..."

ALB_ARN=$(aws elbv2 describe-load-balancers --names $ALB_NAME \
  --query "LoadBalancers[0].LoadBalancerArn" --output text --region $REGION 2>/dev/null || echo "")

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name $ALB_NAME \
    --subnets $SUBNET_1 $SUBNET_2 \
    --security-groups $ALB_SG_ID \
    --scheme internet-facing \
    --type application \
    --query "LoadBalancers[0].LoadBalancerArn" --output text \
    --region $REGION)
fi

TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME \
  --query "TargetGroups[0].TargetGroupArn" --output text --region $REGION 2>/dev/null || echo "")

if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  TG_ARN=$(aws elbv2 create-target-group \
    --name $TG_NAME \
    --protocol HTTP --port 80 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path / \
    --health-check-interval-seconds 30 \
    --query "TargetGroups[0].TargetGroupArn" --output text \
    --region $REGION)

  aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region $REGION > /dev/null
fi

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query "LoadBalancers[0].DNSName" --output text --region $REGION)
echo "  ALB DNS : $ALB_DNS"

# ====== [7/7] ECS サービス ======
echo "[7/7] ECS サービスを作成/更新..."

SERVICE_STATUS=$(aws ecs describe-services \
  --cluster $CLUSTER --services $SERVICE \
  --query "services[0].status" --output text --region $REGION 2>/dev/null || echo "")

if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
  # 既存サービスを強制再デプロイ (新しいイメージを反映)
  aws ecs update-service \
    --cluster $CLUSTER \
    --service $SERVICE \
    --task-definition $TASK_FAMILY \
    --force-new-deployment \
    --region $REGION > /dev/null
  echo "  既存サービスを更新しました"
else
  aws ecs create-service \
    --cluster $CLUSTER \
    --service-name $SERVICE \
    --task-definition $TASK_FAMILY \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=frontend,containerPort=80" \
    --region $REGION > /dev/null
  echo "  新規サービスを作成しました"
fi

# ====== 完了 ======
echo ""
echo "======================================================"
echo " デプロイ完了！"
echo ""
echo " URL: http://$ALB_DNS"
echo ""
echo " ※ ALB とコンテナの起動まで 3〜5分かかります"
echo " ※ ログ確認: AWS Console > CloudWatch > /ecs/todo-app"
echo "======================================================"
