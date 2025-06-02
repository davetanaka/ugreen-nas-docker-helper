#!/bin/bash

# ===================================================
# UGREEN NAS 環境検出スクリプト
# ===================================================
# 作成者: デイブデンキ
# バージョン: 1.0.0
# 最終更新: 2025年5月28日
# ===================================================
# 使用方法:
# 1. SSHでNASに接続: ssh ugreenadmin@あなたのNASのIP
# 2. このスクリプトをコピーして実行
# ===================================================

echo "🔍 UGREEN NAS環境情報を収集中..."
echo "=================================="

# システム情報
echo "📊 システム情報"
echo "ホスト名: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "アーキテクチャ: $(uname -m)"
echo

# ネットワーク情報
echo "🌐 ネットワーク情報"
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo "ローカルIP: $LOCAL_IP"
echo "ネットワークインターフェース:"
ip -o addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print "  "$2": "$4}'
echo

# Docker情報
echo "🐳 Docker情報"
if command -v docker &> /dev/null; then
    echo "Docker: インストール済み"
    echo "バージョン: $(docker --version | awk '{print $3}' | sed 's/,//')"
    docker ps &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$(docker ps 2>&1)"
        echo "稼働中コンテナ数: 0"
    else
        echo "稼働中コンテナ数: $(docker ps -q | wc -l)"
    fi
else
    echo "Docker: インストールされていません"
fi
echo

# ポート使用状況
echo "🔌 ポート使用状況チェック"
check_port() {
    nc -z -w1 localhost $1 &> /dev/null
    if [ $? -eq 0 ]; then
        echo "  ポート $1: ❌ 使用中"
    else
        echo "  ポート $1: ✅ 利用可能"
    fi
}
check_port 8096  # Jellyfin
check_port 8200  # Duplicati
check_port 9000  # Portainer
check_port 9001  # 代替ポート
check_port 8080  # 代替ポート
check_port 32400 # Plex
check_port 8443  # Nextcloud
check_port 8123  # Home Assistant
echo

# ストレージ情報
echo "💾 ストレージ情報"
echo "内蔵ストレージ:"
df -h | grep -v tmpfs | grep -v devtmpfs
echo
echo "外付けドライブ:"
ls -la /mnt/@usb/ 2>/dev/null || echo "外付けドライブが見つかりません"
echo

# ユーザー情報
echo "👤 ユーザー・グループ情報"
echo "現在のユーザー: $(whoami)"
echo "ユーザーID (PUID): $(id -u)"
echo "グループID (PGID): $(id -g)"
echo "グループ一覧:"
id | sed 's/,/\n  /g' | sed 's/(/: /g' | sed 's/)//g' | grep -v '=' | sed 's/^/  /'
echo

# 権限チェック
echo "🔐 権限チェック"
if [ -d "/volume1" ]; then
    if [ -w "/volume1" ]; then
        echo "/volume1: ✅ 書き込み権限あり"
    else
        echo "/volume1: ❌ 書き込み権限なし"
    fi
else
    echo "/volume1: ❌ ディレクトリが存在しません"
fi

if [ -e "/var/run/docker.sock" ]; then
    if [ -w "/var/run/docker.sock" ]; then
        echo "Docker Socket: ✅ アクセス権限あり"
    else
        echo "Docker Socket: ❌ アクセス権限なし (sudoが必要)"
    fi
else
    echo "Docker Socket: ❌ ファイルが存在しません"
fi
echo

# GPU情報（ハードウェアトランスコード用）
echo "🎮 GPU情報（トランスコード用）"
if [ -d "/dev/dri" ]; then
    echo "Intel QuickSync: ✅ 利用可能 (/dev/dri)"
    ls -la /dev/dri
else
    echo "Intel QuickSync: ❌ 利用不可"
fi

if [ -c "/dev/nvidia0" ]; then
    echo "NVIDIA GPU: ✅ 利用可能"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "  NVIDIA ドライバ情報を取得できません"
else
    echo "NVIDIA GPU: ❌ 利用不可"
fi
echo

# システムリソース
echo "⚡ システムリソース"
echo "メモリ: $(free -h | grep Mem | awk '{print $2}') (使用中: $(free -h | grep Mem | awk '{print $3}'))"
echo "CPU: $(grep -c processor /proc/cpuinfo)コア"
echo "CPU情報: $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')"
echo "負荷平均: $(uptime | awk -F'load average: ' '{print $2}')"
echo

# Docker コンテナ検出
echo "🔍 既存Docker コンテナ検出"
if command -v docker &> /dev/null; then
    if docker ps &> /dev/null; then
        echo "稼働中コンテナ:"
        docker ps --format "  {{.Names}}: {{.Image}} ({{.Status}})"
    fi
else
    echo "Docker コマンドが利用できません"
fi
echo

# 推奨設定値
echo "📋 推奨YAML設定値"
echo "=================================="
echo "# あなたの環境に合わせた設定値"
echo "LOCAL_IP: $LOCAL_IP"
echo "PUID: $(id -u)"
echo "PGID: $(id -g)"
echo "MEDIA_PATH: /volume1"
USB_PATH=$(ls -d /mnt/@usb/* 2>/dev/null | head -1)
if [ -n "$USB_PATH" ]; then
    echo "USB_PATH: $USB_PATH"
else
    echo "USB_PATH: /mnt/@usb/sdd1 # 外付けHDDが見つかりません。適切なパスに変更してください"
fi
echo "TZ: Asia/Tokyo"
echo

# 1000/100 vs 1000/1000 の検証
echo "🧪 PUID/PGID 検証"
echo "=================================="
echo "多くのガイドでは PUID=1000, PGID=1000 が推奨されていますが、"
echo "UGREEN NASでは PUID=1000, PGID=100 が正解の可能性が高いです。"
echo
echo "あなたの環境では:"
echo "  PUID=$(id -u), PGID=$(id -g)"
echo
echo "users グループ (GID=100) の存在確認:"
getent group 100 > /dev/null
if [ $? -eq 0 ]; then
    echo "  ✅ users グループ (GID=100) が存在します: $(getent group 100 | cut -d: -f1)"
else
    echo "  ❌ users グループ (GID=100) が存在しません"
fi
echo
echo "davetanaka ユーザーの存在確認:"
id davetanaka > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "  ✅ davetanaka ユーザーが存在します: $(id davetanaka)"
else
    echo "  ❌ davetanaka ユーザーが存在しません"
fi
echo

echo "🎉 環境情報収集完了！"
echo "上記の設定値をYAMLファイルに適用してください。"
echo
echo "💡 このスクリプトの実行方法:"
echo "1. SSH接続: ssh ユーザー名@${LOCAL_IP}"
echo "2. スクリプト実行: bash ugreen-env-detect.sh"
echo
echo "📦 GitHub リポジトリ:"
echo "https://github.com/yourusername/ugreen-nas-docker-helper"
echo "詳細なガイドとトラブルシューティングを確認できます。"
