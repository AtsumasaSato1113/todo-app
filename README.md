# Todo App — ローカル開発 & AWS デプロイ ガイド

FastAPI + React + Docker で作った Todo アプリを、ローカルで動かして AWS にデプロイするまでの手順です。

---

## 構成

```
[ブラウザ]
    ↓
[React (Vite / nginx)]  ← ポート 5173 (開発) / 80 (本番)
    ↓ /todos/ をプロキシ
[FastAPI]               ← ポート 8000
    ↓
[SQLite]                ← todos.db
```

AWS 本番環境では：

```
[ブラウザ]
    ↓
[ALB] → [ECS Fargate タスク]
              ├ frontend コンテナ (nginx:80)
              └ backend  コンテナ (FastAPI:8000)
                              ↓
                         [EFS] ← todos.db を永続保存
```

---

## Part 1 — ローカル開発

### 1-1. Docker Desktop をインストール

**WSL2 を有効化**（PowerShell を管理者で起動して実行）

```powershell
wsl --install
```

PC を**再起動**する。

**Docker Desktop をインストール**
- [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/) からダウンロード
- CPU の種類で選択：
  - Intel / AMD → **AMD64**
  - ARM (Snapdragon など) → **ARM64**
  - ※ タスクマネージャー → CPU タブで確認できる
- インストール時「Use WSL 2 instead of Hyper-V」にチェック ✓
- インストール後 Docker Desktop を起動し、タスクバーのアイコンが**緑色**になるまで待つ

**動作確認**

```cmd
docker --version
docker compose version
```

---

### 1-2. アプリを起動する

```cmd
cd C:\aws\20260327_01
docker compose up --build
```

ブラウザで [http://localhost:5173](http://localhost:5173) を開く。

**停止するには**

```cmd
Ctrl + C
docker compose down
```

---

### トラブルシューティング（ローカル）

#### ❌ `'docker' は内部コマンドまたは外部コマンドとして認識されていません`
→ Docker Desktop がインストールされていない。Part 1-1 へ。

#### ❌ `container todo-backend is unhealthy`
→ ヘルスチェックに使う `curl` が Python イメージに含まれていない。

`backend/Dockerfile` に以下を追加（追加済みであれば不要）：

```dockerfile
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

#### ❌ `NetworkError when attempting to fetch resource`
→ フロントエンドが `/todos` を呼ぶと FastAPI が `/todos/` にリダイレクトし、
　 ブラウザが Docker 内部ホスト名 `backend` を解決しようとして失敗する。

`frontend/src/api.js` の BASE_URL を以下にする（末尾スラッシュあり）：

```js
const BASE_URL = '/todos/'
```

---

## Part 2 — AWS デプロイ

### 2-1. AWS CLI を WSL にインストール

Windows の `bash` は WSL (Linux 環境) を使うため、
Windows にインストールした AWS CLI は WSL からは使えない。

WSL (Ubuntu) を開く：

```cmd
wsl
```

AWS CLI をインストール：

```bash
apt-get install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version   # インストール確認
```

---

### 2-2. AWS 認証情報を設定

AWS コンソール → IAM → セキュリティ認証情報 でアクセスキーを発行してから：

```bash
aws configure
```

```
AWS Access Key ID     : （発行したキー）
AWS Secret Access Key : （発行したシークレット）
Default region name   : ap-northeast-1
Default output format : json
```

---

### 2-3. デプロイを実行

```bash
cd /mnt/c/aws/20260327_01
bash infrastructure/deploy.sh
```

スクリプトが自動で以下を作成します：

| ステップ | 内容 |
|---|---|
| 1/7 | ECR リポジトリ（Docker イメージの保存場所） |
| 2/7 | Docker イメージをビルドして ECR にプッシュ |
| 3/7 | IAM ロール（ECS が ECR からイメージを取得するための権限） |
| 4/7 | セキュリティグループ（ALB / ECS / EFS それぞれのファイアウォール） |
| 5/7 | EFS（SQLite ファイルの永続化ストレージ） |
| 6/7 | ALB（インターネットからのアクセスを受け付けるロードバランサー） |
| 7/7 | ECS サービス（コンテナの起動・管理） |

完了後に URL が表示されます：

```
URL: http://todo-alb-xxxxxxxxxx.ap-northeast-1.elb.amazonaws.com
```

> ALB とコンテナの起動まで **3〜5 分**かかります。

---

### 2-4. 起動確認

```bash
aws ecs describe-services \
  --cluster todo-cluster \
  --services todo-service \
  --query "services[0].{Running:runningCount,Pending:pendingCount,Desired:desiredCount}" \
  --output table \
  --region ap-northeast-1
```

`Running: 1` になれば起動完了です。

---

### トラブルシューティング（AWS デプロイ）

#### ❌ `aws: command not found`
→ WSL 内に AWS CLI がインストールされていない。Part 2-1 へ。

#### ❌ `Found invalid choice 'wait'`
→ `aws efs wait` コマンドがこのバージョンで未サポート。
　 `infrastructure/deploy.sh` のポーリングループ方式に修正済み。

#### ❌ `ResourceInitializationError: failed to resolve EFS DNS`
→ EFS のマウントターゲットが作成されていない、または起動前にECSが起動した。
　 以下の手順でマウントターゲットを作成してから再デプロイ：

```bash
EFS_ID=$(aws efs describe-file-systems \
  --query "FileSystems[?Tags[?Key=='Name'&&Value=='todo-efs']].FileSystemId|[0]" \
  --output text --region ap-northeast-1)

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" --output text --region ap-northeast-1)

EFS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=todo-efs-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text --region ap-northeast-1)

for SUBNET_ID in $(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=defaultForAz,Values=true" \
  --query "Subnets[*].SubnetId" --output text --region ap-northeast-1); do
  aws efs create-mount-target \
    --file-system-id $EFS_ID --subnet-id $SUBNET_ID \
    --security-groups $EFS_SG_ID --region ap-northeast-1 > /dev/null 2>&1 && echo "OK: $SUBNET_ID" || echo "SKIP: $SUBNET_ID"
done

# マウントターゲットが available になるまで待機
while true; do
  STATES=$(aws efs describe-mount-targets \
    --file-system-id $EFS_ID \
    --query "MountTargets[*].LifeCycleState" --output text --region ap-northeast-1)
  echo "状態: $STATES"
  echo "$STATES" | grep -qv available && sleep 10 || break
done

# 再デプロイ
aws ecs update-service --cluster todo-cluster --service todo-service \
  --force-new-deployment --region ap-northeast-1 > /dev/null && echo "再デプロイ開始"
```

---

### 2-4-2. デプロイ中のログ確認（任意）

`deploy.sh` を実行中、別のターミナルで ECS タスクの状態を監視できます：

```bash
watch -n 5 'aws ecs describe-services \
  --cluster todo-cluster --services todo-service \
  --query "services[0].{Running:runningCount,Pending:pendingCount}" \
  --output table --region ap-northeast-1'
```

---

### 2-5. 再デプロイ（コード変更後）

コードを変更してAWSに反映させるには：

```bash
cd /mnt/c/aws/20260327_01
bash infrastructure/deploy.sh
```

スクリプトは既存リソースを再利用し、イメージだけ新しくビルドして更新します。

---

## ログの確認

AWS コンソール → CloudWatch → ロググループ → `/ecs/todo-app`

または CLI で：

```bash
aws logs tail /ecs/todo-app --follow --region ap-northeast-1
```
