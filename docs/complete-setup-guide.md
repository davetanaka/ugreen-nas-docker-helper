# UGREEN NAS Docker 完全セットアップガイド

> 「理論と実践のギャップを乗り越える実践的ガイド」

## 📋 このガイドについて

このガイドは、UGREEN NAS（特にDXP4800Plusなど）でDockerコンテナを安全かつ確実に導入するための完全マニュアルです。実際の環境で遭遇する「理論と実践のギャップ」を踏まえた実践的なアドバイスを含んでいます。

## 🎯 対象読者

- UGREEN NASユーザー（DXP2800, DXP4800Plus, DXP6800Pro, DXP8800Plus）
- Docker初心者〜中級者
- 手動設定でのミスを減らしたい方
- コンテナ環境の再現性を高めたい方

## ⚠️ 前提条件

- UGREEN NASが正常に動作していること
- SSH接続が可能であること
- 基本的なLinuxコマンドの理解
- 外付けHDD（推奨：バックアップ用）

## 🚀 Step 1: 環境検出スクリプトの実行

### 1.1 SSH接続

```bash
# MacまたはWindowsのターミナルから
ssh nasuser@あなたのNASのIPアドレス
# 例: ssh nasuser@192.168.0.78
```

### 1.2 環境検出スクリプトのダウンロードと実行

```bash
# スクリプトをダウンロード
wget -O ugreen-env-detect.sh https://raw.githubusercontent.com/davetanaka/ugreen-nas-docker-helper/main/scripts/ugreen-env-detect.sh

# 実行権限を付与
chmod +x ugreen-env-detect.sh

# スクリプトを実行
./ugreen-env-detect.sh
```

### 1.3 結果の確認

スクリプト実行後、以下のような情報が表示されます：

```
🔍 UGREEN NAS環境情報を収集中...
==================================
📊 システム情報
ローカルIP: 192.168.0.78
PUID: 1000
PGID: 100  ← 重要！多くのガイドでは1000だが、実際は100
💾 ストレージ情報
外付けHDD: /mnt/@usb/sdd1
🔌 ポート使用状況
  ポート 8096: ✅ 利用可能
  ポート 8200: ✅ 利用可能
  ポート 9000: ✅ 利用可能
```

**重要**: この結果をメモしておいてください。後の設定で使用します。

## 🛠️ Step 2: Portainer の導入

### 2.1 Portainer コンテナの起動

```bash
sudo docker run -d \
  --name portainer \
  --restart always \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /volume1/docker/configs/portainer:/data \
  portainer/portainer-ce:latest
```

### 2.2 Portainer の初期設定

1. ブラウザで `http://あなたのNASのIP:9000` にアクセス
2. 管理者アカウント（ユーザー名・パスワード）を作成
3. 「Get Started」をクリック

## 📦 Step 3: コンテナの導入方式選択

### 🎯 推奨アプローチ：ハイブリッド方式

1. **Portainer**: SSH経由で導入済み ✅
2. **Fail2ban**: Portainerで手動導入（セキュリティ理解のため）
3. **残り3つ**: Stack方式で一括導入（効率化）

### Option A: Fail2ban 手動導入

#### A.1 Portainerでコンテナ作成

1. Portainer → 「Containers」→「+ Add container」
2. 以下の設定を入力：

```
Name: fail2ban
Image: crazymax/fail2ban:latest
Network: host
Privileged mode: ON
Restart policy: Unless stopped

Environment variables:
TZ=Asia/Tokyo
F2B_LOG_LEVEL=INFO
F2B_DB_PURGE_AGE=7d

Volumes:
/volume1/docker/configs/fail2ban:/data
/var/log:/var/log:ro
/var/run/docker.sock:/var/run/docker.sock:ro
```

#### A.2 デプロイと確認

1. 「Deploy the container」をクリック
2. コンテナが正常に起動することを確認

### Option B: Stack方式で一括導入

#### B.1 YAMLファイルの準備

1. Portainer → 「Stacks」→「+ Add stack」
2. Name: `essential-stack`
3. 以下のYAMLをコピー&ペースト：

```yaml
# 神3スタック（Duplicati, Tailscale, Jellyfin）
version: '3'

# 共通環境変数（環境検出スクリプトの結果に合わせて変更してください）
x-environment: &common-env
  PUID: 1000
  PGID: 100  # ← 重要！多くのガイドでは1000だが、UGREEN NASでは100が正解
  TZ: Asia/Tokyo

# ボリューム定義（環境検出スクリプトの結果に合わせて変更してください）
x-volumes: &common-volumes
  MEDIA_PATH: /volume1
  USB_PATH: /mnt/@usb/sdd1
  DOCUMENTS_PATH: /volume1
  CONFIG_PATH: /volume1/docker/configs

services:
  # Duplicati - バックアップツール
  duplicati:
    image: linuxserver/duplicati:latest
    container_name: duplicati
    restart: unless-stopped
    ports:
      - 8200:8200
    environment:
      <<: *common-env
    volumes:
      - ${CONFIG_PATH:-/volume1/docker/configs}/duplicati:/config
      - ${DOCUMENTS_PATH:-/volume1}:/source/volume1:ro
      - ${USB_PATH:-/mnt/@usb/sdd1}/duplicati-backups:/backups
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'

  # Tailscale - VPNサービス
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    restart: unless-stopped
    network_mode: "host"
    privileged: true
    environment:
      <<: *common-env
      TS_STATE_DIR: /var/lib/tailscale
      TS_EXTRA_ARGS: --advertise-routes=192.168.0.0/24 --accept-dns=true
    volumes:
      - ${CONFIG_PATH:-/volume1/docker/configs}/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'

  # Jellyfin - メディアサーバー
  jellyfin:
    image: linuxserver/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - 8096:8096
      - 8920:8920
      - 7359:7359/udp
      - 1900:1900/udp
    environment:
      <<: *common-env
      JELLYFIN_PublishedServerUrl: 192.168.0.78  # あなたの実際のIPアドレスに変更
    volumes:
      - ${CONFIG_PATH:-/volume1/docker/configs}/jellyfin:/config
      - ${MEDIA_PATH:-/volume1}:/media
      - /tmp/jellyfin:/transcode
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '4.0'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

#### B.2 環境設定の調整

YAMLファイル内の以下の箇所を、Step 1で確認した値に変更：

```yaml
# 環境検出スクリプトの結果に合わせて変更
PUID: 1000
PGID: 100  # ← 重要！実際の値を確認
USB_PATH: /mnt/@usb/sdd1  # ← 実際のパスを確認
JELLYFIN_PublishedServerUrl: 192.168.0.78  # ← 実際のIPアドレス
TS_EXTRA_ARGS: --advertise-routes=192.168.0.0/24 --accept-dns=true  # ← ネットワーク範囲
```

#### B.3 デプロイ

1. 「Deploy the stack」をクリック
2. 3つのコンテナが正常に起動することを確認

## ⚙️ Step 4: 各コンテナの初期設定

### 4.1 Duplicati の設定

1. `http://あなたのNASのIP:8200` にアクセス
2. 初期設定ウィザードを実行：
   - **言語**: 日本語
   - **バックアップ先**: Local folder or drive
   - **パス**: `/backups/duplicati-backups/`（重要：コンテナ内パス）
   - **ソース**: `/source/volume1/`（バックアップしたいフォルダ）
   - **暗号化**: AES-256（推奨）
   - **スケジュール**: 毎日深夜など

### 4.2 Tailscale の設定

```bash
# コンテナ内で認証を実行
sudo docker exec -it tailscale tailscale up

# 表示されたURLでブラウザ認証を完了
# Tailscale管理画面でMagicDNSなどを設定
```

### 4.3 Jellyfin の設定

1. `http://あなたのNASのIP:8096` にアクセス
2. 初期設定ウィザードを実行：
   - **言語**: 日本語
   - **ユーザーアカウント**: 管理者作成
   - **メディアライブラリ**: `/media` 配下のフォルダを追加
   - **リモートアクセス**: 必要に応じて設定

## 🔍 Step 5: 動作確認と検証

### 5.1 コンテナ状態の確認

```bash
# 全コンテナの状態確認
sudo docker ps

# 特定コンテナのログ確認
sudo docker logs duplicati
sudo docker logs tailscale
sudo docker logs jellyfin
sudo docker logs fail2ban
```

### 5.2 マウント状況の確認

```bash
# Duplicatiのマウント確認
sudo docker exec -it duplicati ls -la /backups/
sudo docker exec -it duplicati ls -la /source/

# 実際のファイル確認
ls -la /mnt/@usb/sdd1/duplicati-backups/
```

### 5.3 権限の確認

```bash
# 実際のファイル所有者確認
ls -la /volume1/docker/configs/
ls -la /mnt/@usb/sdd1/
```

## 🛠️ Step 6: トラブルシューティング

### 6.1 よくある問題

#### 問題1: コンテナが起動しない

**確認項目**:
- ポート競合の確認: `netstat -tlnp | grep :8096`
- ログの確認: `sudo docker logs コンテナ名`
- 権限の確認: `ls -la /volume1/docker/configs/`

**解決策**:
```bash
# ポート変更（YAMLファイル内）
ports:
  - 8097:8096  # 8096→8097に変更

# 権限修正
sudo chown -R 1000:100 /volume1/docker/configs/
```

#### 問題2: 外付けHDDにアクセスできない

**確認項目**:
- マウント状況: `mount | grep usb`
- パスの確認: `ls -la /mnt/@usb/`
- 権限の確認: `ls -la /mnt/@usb/sdd1/`

**解決策**:
```bash
# 外付けHDDの再マウント
sudo umount /mnt/@usb/sdd1
sudo mount -t ntfs-3g /dev/sdd1 /mnt/@usb/sdd1

# 権限の修正
sudo chmod 777 /mnt/@usb/sdd1/
```

#### 問題3: 権限エラー（PUID/PGID問題）

**症状**: ファイルが異なるユーザー（unknown、911など）で作成される

**理解すべきこと**: 
- これは「理論と実践のギャップ」の典型例
- 設定値と実際の動作が異なることがある
- 多くの場合、実際には問題なく動作する

**対処法**:
1. **様子見**: エラーが発生するまで何もしない（推奨）
2. **権限変更**: 問題が発生した場合のみ
```bash
sudo chown -R 1000:100 /volume1/docker/configs/コンテナ名/
```

#### 問題4: Docker Socket 権限エラー

**エラー**: `permission denied while trying to connect to the Docker daemon socket`

**解決策**:
```bash
# sudoを使用
sudo docker exec -it コンテナ名 コマンド

# または、ユーザーをdockerグループに追加
sudo usermod -aG docker $USER
# ログアウト/ログインが必要
```

### 6.2 ログの活用

#### 重要なログファイル

```bash
# Dockerデーモンログ
sudo journalctl -u docker

# 個別コンテナログ
sudo docker logs --tail 50 duplicati
sudo docker logs --tail 50 tailscale
sudo docker logs --tail 50 jellyfin
sudo docker logs --tail 50 fail2ban

# リアルタイムログ監視
sudo docker logs -f コンテナ名
```

#### AI活用によるトラブル解決

**現代的なアプローチ**: エラーログをChatGPTやClaudeに相談

1. ログをコピー: `sudo docker logs duplicati 2>&1 | tail -20`
2. AIツールに貼り付けて相談
3. 提案された解決策を試行

**例**:
```
「以下のDuplicatiのエラーログについて、原因と解決策を教えてください：

[エラーログをここに貼り付け]
```

## 📊 Step 7: 定期メンテナンス

### 7.1 イメージ更新

```bash
# 月1回程度実行
# Portainerで該当スタックを選択
# 「Editor」→「Update the stack」をクリック
# または以下のコマンドで個別更新
sudo docker pull linuxserver/duplicati:latest
sudo docker pull linuxserver/jellyfin:latest
sudo docker pull tailscale/tailscale:latest
sudo docker pull crazymax/fail2ban:latest
```

### 7.2 ログクリーンアップ

```bash
# 月1回程度実行
sudo docker system prune -f
sudo docker image prune -f
```

### 7.3 バックアップ検証

```bash
# Duplicatiバックアップの検証（月1回）
# WebUIから「Verify」機能を実行
# または復元テストを実施
```

## 🔒 Step 8: セキュリティ強化

### 8.1 Fail2ban設定（手動導入の場合）

```bash
# カスタムjail設定
sudo docker exec -it fail2ban vi /data/jail.d/custom.conf
```

```ini
[DEFAULT]
# デフォルト設定
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
```

### 8.2 ファイアウォール設定

```bash
# 必要なポートのみ開放
sudo ufw allow 22    # SSH
sudo ufw allow 9000  # Portainer
sudo ufw allow 8096  # Jellyfin
sudo ufw allow 8200  # Duplicati
sudo ufw enable
```

### 8.3 定期的なセキュリティチェック

```bash
# 月1回実行
sudo docker exec -it fail2ban fail2ban-client status
sudo ufw status
sudo netstat -tlnp  # 開放ポート確認
```

## 📈 Step 9: 監視とアラート

### 9.1 Uptime Kuma導入（オプション）

監視ツールを追加することで、各サービスの死活監視が可能になります。

### 9.2 基本的な監視スクリプト

```bash
#!/bin/bash
# container-health-check.sh

echo "=== Docker コンテナ状態チェック ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "=== ディスク使用量 ==="
df -h | grep -E "(volume1|usb)"

echo "=== メモリ使用量 ==="
free -h
```

## 🎯 システム評価

### Before（素のUGREEN NAS）
- **コスパ**: 18点 - ハード性能は素晴らしい
- **健康プラス度**: 11点 - ただの保存装置
- **使いやすさ**: 12点 - 初心者には厳しい
- **耐久性・サポート**: 10点 - サポート体制が課題
- **環境・社会影響**: 8点 - 特筆すべき配慮なし
- **総合**: 59点

### After（神5アプリ導入後）
- **コスパ**: 19点 - 投資効果抜群！
- **健康プラス度**: 17点 - セキュリティ安心、学習機会、エンタメ向上
- **使いやすさ**: 16点 - Portainerで直感操作可能
- **耐久性・サポート**: 12点 - コミュニティサポート充実
- **環境・社会影響**: 10点 - 知識共有で社会貢献
- **総合**: 74点（+15点アップ！）

## 🎉 おめでとうございます！

このガイドに従って、あなたのUGREEN NASは「宝の持ち腐れ」から「真の宝物」へと進化しました！

### 達成したこと

✅ **セキュリティ強化**: Fail2banで24時間監視  
✅ **プロ級バックアップ**: Duplicatiで自動バックアップ  
✅ **どこでもアクセス**: Tailscaleで安全なリモートアクセス  
✅ **あなた専用Netflix**: Jellyfinでメディアストリーミング  
✅ **直感的管理**: Portainerで簡単コンテナ管理  

### 次のステップ

1. **追加アプリの検討**: Nextcloud、Home Assistantなど
2. **コミュニティ参加**: GitHubで体験を共有
3. **定期メンテナンス**: 月1回のメンテナンス実施
4. **UGREENへの要望**: より良い初心者サポートの要望

---

**重要**: 何か問題が発生した場合は、遠慮なくGitHubのIssuesで質問してください。コミュニティ全体で助け合いましょう！

> 「理論と実践のギャップを乗り越え、あなたのNASライフを豊かに！」
