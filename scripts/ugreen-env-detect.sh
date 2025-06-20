#!/bin/bash

# =============================================================================
# UGREEN NAS 環境検出スクリプト v1.2.1 (UX改善版)
# =============================================================================
# 目的: UGREEN NAS環境の設定値を自動検出し、Docker設定を最適化
# 対応: Linux (UGREEN NAS), macOS, その他Unix系OS
# 作成: UGREEN NAS Docker Helper プロジェクト
# ライセンス: MIT
# =============================================================================

if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    declare -A COMMAND_CACHE
else
    COMMAND_CACHE=""
fi

has_command() {
    local cmd="$1"
    
    if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
        if [[ -n "${COMMAND_CACHE[$cmd]:-}" ]]; then
            return "${COMMAND_CACHE[$cmd]}"
        fi
        
        if command -v "$cmd" >/dev/null 2>&1; then
            COMMAND_CACHE[$cmd]=0
            return 0
        else
            COMMAND_CACHE[$cmd]=1
            return 1
        fi
    else
        command -v "$cmd" >/dev/null 2>&1
    fi
}

# 色付き出力の設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# アイコン定義
ICON_INFO="🔍"
ICON_SUCCESS="✅"
ICON_WARNING="⚠️ "
ICON_ERROR="❌"
ICON_SYSTEM="📊"
ICON_STORAGE="💾"
ICON_NETWORK="🔌"
ICON_DOCKER="🐳"
ICON_SECURITY="🛡️"

# OS検出
detect_os() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            ;;
        Linux)
            OS="Linux"
            ;;
        *)
            OS="Unknown"
            ;;
    esac
}

# ヘッダー表示
print_header() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${WHITE}${ICON_INFO} UGREEN NAS環境情報収集スクリプト v1.2.1${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${YELLOW}理論と実践のギャップを埋める、あなた専用の設定値を検出します${NC}"
    echo -e "${BLUE}対応OS: Linux (UGREEN NAS), macOS${NC}"
    echo ""
}

# セクションヘッダー表示
print_section() {
    echo -e "${PURPLE}${1}${NC}"
    echo -e "${PURPLE}==================================${NC}"
}

# 成功メッセージ
print_success() {
    echo -e "${GREEN}${ICON_SUCCESS} ${1}${NC}"
}

# 警告メッセージ
print_warning() {
    echo -e "${YELLOW}${ICON_WARNING} ${1}${NC}"
}

# エラーメッセージ
print_error() {
    echo -e "${RED}${ICON_ERROR} ${1}${NC}"
}

# 情報メッセージ
print_info() {
    echo -e "${BLUE}${1}${NC}"
}

# IPアドレス取得（OS別対応）
get_local_ip() {
    local ip=""
    
    if [[ "$OS" == "macOS" ]]; then
        # macOS用のIPアドレス取得
        ip=$(ifconfig | grep -E 'inet.*broadcast' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
        if [ -z "$ip" ]; then
            # Wi-Fi接続の場合
            ip=$(ifconfig en0 | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
        fi
        if [ -z "$ip" ]; then
            # Ethernet接続の場合
            ip=$(ifconfig en1 | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
        fi
    elif [[ "$OS" == "Linux" ]]; then
        # Linux用のIPアドレス取得
        if has_command ip; then
            ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)
        fi
        if [ -z "$ip" ] && has_command hostname; then
            ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        fi
    fi
    
    echo "$ip"
}

# ホスト名取得（OS別対応）
get_hostname() {
    if [[ "$OS" == "macOS" ]]; then
        hostname
    else
        hostname
    fi
}

# Docker権限チェック
check_docker_permission() {
    if docker ps >/dev/null 2>&1; then
        return 0
    elif [[ "$OS" == "macOS" ]]; then
        return 2
    elif sudo docker ps >/dev/null 2>&1; then
        return 1
    else
        return 2
    fi
}

# システム情報収集
collect_system_info() {
    print_section "${ICON_SYSTEM} システム情報"
    
    # OS情報
    print_info "OS: ${OS} ($(uname -r))"
    
    # ホスト名
    hostname=$(get_hostname)
    print_info "ホスト名: ${hostname}"
    
    # ローカルIPアドレス
    local_ip=$(get_local_ip)
    if [ -n "$local_ip" ]; then
        print_info "ローカルIP: ${local_ip}"
    else
        print_warning "ローカルIPの取得に失敗しました"
    fi
    
    # アーキテクチャ
    arch=$(uname -m)
    print_info "アーキテクチャ: ${arch}"
    
    # 現在のユーザー
    current_user=$(whoami)
    print_info "現在のユーザー: ${current_user}"
    
    # PUID/PGID取得
    puid=$(id -u)
    pgid=$(id -g)
    print_info "PUID: ${puid}"
    print_info "PGID: ${pgid}"
    
    # OS別の注意事項
    if [[ "$OS" == "macOS" ]]; then
        print_info "macOS環境: 通常PUID=501, PGID=20です"
        print_warning "UGREEN NAS環境では通常PUID=1000, PGID=100になります"
    elif [[ "$OS" == "Linux" ]]; then
        # 特別な注意事項
        if [ "$pgid" = "100" ]; then
            print_success "PGID=100 を検出！UGREEN NASの典型的な設定です"
            print_warning "多くのガイドではPGID=1000と書かれていますが、実際は100が正解です"
        elif [ "$pgid" = "1000" ]; then
            print_warning "PGID=1000 を検出。一般的なLinux設定ですが、UGREEN NASでは100の可能性があります"
        else
            print_warning "特殊なPGID (${pgid}) を検出。この値をYAMLファイルで使用してください"
        fi
    else
        print_warning "特殊なPGID (${pgid}) を検出。この値をYAMLファイルで使用してください"
    fi
    
    echo ""
}

# ストレージ情報収集
collect_storage_info() {
    print_section "${ICON_STORAGE} ストレージ情報"
    
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}📱 macOS開発・テスト環境での検出結果${NC}"
        echo -e "${BLUE}※ 実際のUGREEN NAS環境とは異なります${NC}"
        echo ""
        
        print_info "macOS環境のストレージ情報:"
        df -h / | tail -1 | awk '{print "  ルートディスク: " $2 " (使用: " $3 ", 空き: " $4 ")"}'
        
        # 外付けドライブ検索
        volumes=$(ls /Volumes 2>/dev/null | grep -v "Macintosh HD" || true)
        if [ -n "$volumes" ]; then
            print_success "外付けボリューム検出 (開発用):"
            echo "$volumes" | while read volume; do
                if [ -d "/Volumes/$volume" ]; then
                    size=$(df -h "/Volumes/$volume" 2>/dev/null | tail -1 | awk '{print $2}' || echo "不明")
                    print_info "  /Volumes/$volume (容量: $size)"
                fi
            done
        else
            print_warning "外付けボリュームが見つかりません"
        fi
        
        echo ""
        echo -e "${WHITE}💡 実際のUGREEN NAS環境では以下のようになります:${NC}"
        echo -e "${BLUE}  • 内蔵ドライブ: /volume1, /volume2, /volume3, /volume4${NC}"
        echo -e "${BLUE}  • 外付けUSB: /mnt/@usb/sdb1, /mnt/@usb/sdc1, /mnt/@usb/sdd1, /mnt/@usb/sde1${NC}"
        echo -e "${BLUE}  • 最大4ポートのUSB接続が可能${NC}"
        
    else
        # UGREEN NAS本番環境の情報
        echo -e "${GREEN}🏠 UGREEN NAS本番環境での検出結果${NC}"
        echo -e "${BLUE}※ Docker設定で使用する実際のパス情報${NC}"
        echo ""
        
        # Linux (UGREEN NAS) 用のストレージ情報
        internal_volumes=()
        for vol_num in {1..8}; do
            vol_path="/volume${vol_num}"
            if [ -d "$vol_path" ]; then
                vol_size=$(df -h "$vol_path" | tail -1 | awk '{print $2}')
                vol_used=$(df -h "$vol_path" | tail -1 | awk '{print $3}')
                vol_avail=$(df -h "$vol_path" | tail -1 | awk '{print $4}')
                internal_volumes+=("$vol_path")
                print_success "内蔵ドライブ (${vol_path}): ${vol_size} (使用: ${vol_used}, 空き: ${vol_avail})"
            fi
        done
        
        if [ ${#internal_volumes[@]} -eq 0 ]; then
            print_warning "標準的な内蔵ドライブパス (/volume1-8) が見つかりません"
            # 代替パスをチェック
            for path in "/home" "/mnt/data" "/data"; do
                if [ -d "$path" ]; then
                    print_info "代替パス候補: ${path}"
                fi
            done
        fi
        
        # 外付けHDD検索 - 4ポート対応強化
        print_info "外付けHDD検索中（NASync DXP6800 Pro 4ポート対応）..."
        usb_devices=()
        
        # UGREEN NAS特有のUSBマウントポイントを優先チェック
        for device in sdb1 sdc1 sdd1 sde1 sda1; do
            usb_path="/mnt/@usb/${device}"
            if [ -d "$usb_path" ] 2>/dev/null; then
                usb_size=$(df -h "$usb_path" 2>/dev/null | tail -1 | awk '{print $2}' 2>/dev/null)
                if [ ! -z "$usb_size" ] && [ "$usb_size" != "0" ]; then
                    usb_devices+=("$usb_path")
                    print_success "外付けHDD: ${usb_path} (容量: ${usb_size})"
                fi
            fi
        done
        
        # 一般的なUSBマウントポイントもチェック（フォールバック）
        if [ ${#usb_devices[@]} -eq 0 ]; then
            for usb_path in /mnt/usb/* /media/* /run/media/*/*; do
                if [ -d "$usb_path" ] 2>/dev/null; then
                    usb_size=$(df -h "$usb_path" 2>/dev/null | tail -1 | awk '{print $2}' 2>/dev/null)
                    if [ ! -z "$usb_size" ] && [ "$usb_size" != "0" ]; then
                        usb_devices+=("$usb_path")
                        print_success "外付けHDD: ${usb_path} (容量: ${usb_size})"
                    fi
                fi
            done
        fi
        
        if [ ${#usb_devices[@]} -eq 0 ]; then
            print_warning "外付けHDDが見つかりません"
            print_info "手動でマウントが必要な場合があります"
            
            # 未マウントのUSBデバイスをチェック
            print_info "未マウントのUSBデバイス確認中..."
            if has_command lsblk; then
                lsblk -f | grep -E "(sd[b-z]|nvme)" | while read line; do
                    if echo "$line" | grep -v "/" >/dev/null; then
                        print_info "未マウント: ${line}"
                    fi
                done
            fi
        else
            echo -e "${GREEN}✅ 検出された外付けHDD: ${#usb_devices[@]}台 (Duplicatiバックアップ用)${NC}"
            for i in "${!usb_devices[@]}"; do
                device_path="${usb_devices[$i]}"
                device_size=$(df -h "$device_path" 2>/dev/null | tail -1 | awk '{print $2}' 2>/dev/null)
                print_info "  📱 USB$((i+1)): ${device_path} (容量: ${device_size})"
            done
            
            largest_usb=""
            largest_size=0
            for device_path in "${usb_devices[@]}"; do
                size_bytes=$(df "$device_path" 2>/dev/null | tail -1 | awk '{print $4}' 2>/dev/null || echo "0")
                if [ "$size_bytes" -gt "$largest_size" ]; then
                    largest_size="$size_bytes"
                    largest_usb="$device_path"
                fi
            done
            
            if [ ! -z "$largest_usb" ]; then
                recommended_usb="$largest_usb"
                echo -e "${GREEN}🎯 Duplicati推奨バックアップパス: ${recommended_usb}${NC}"
                print_info "  💡 最大容量のデバイスを自動選択しました"
            else
                recommended_usb="${usb_devices[0]}"
                echo -e "${GREEN}🎯 Duplicati推奨バックアップパス: ${recommended_usb}${NC}"
            fi
        fi
    fi
    
    echo ""
}

# ネットワーク情報収集
collect_network_info() {
    print_section "${ICON_NETWORK} ネットワーク情報"
    
    # ネットワーク範囲推定
    if [ ! -z "$local_ip" ]; then
        if [[ "$OS" == "macOS" ]]; then
            # macOSでのネットワーク範囲推定
            network_range=$(echo $local_ip | cut -d'.' -f1-3).0/24
            print_info "推定ネットワーク範囲: ${network_range}"
            print_info "macOS環境: UGREEN NAS使用時はNASのIPレンジを使用してください"
        else
            network_range=$(echo $local_ip | cut -d'.' -f1-3).0/24
            print_info "推定ネットワーク範囲: ${network_range}"
        fi
        print_info "Tailscale設定例: --advertise-routes=${network_range}"
    fi
    
    # ポート使用状況チェック
    important_ports=(22 80 443 8096 8200 9000)
    print_info "重要ポートの使用状況:"
    
    for port in "${important_ports[@]}"; do
        if has_command netstat; then
            if netstat -an 2>/dev/null | grep -E ":${port}[[:space:]]" >/dev/null; then
                print_warning "  ポート ${port}: 使用中"
            else
                print_success "  ポート ${port}: 利用可能"
            fi
        elif has_command ss; then
            if ss -tlnp 2>/dev/null | grep ":${port} " >/dev/null; then
                print_warning "  ポート ${port}: 使用中"
            else
                print_success "  ポート ${port}: 利用可能"
            fi
        else
            print_info "  ポート ${port}: 確認ツールなし"
        fi
    done
    
    echo ""
}

# Docker情報収集
collect_docker_info() {
    print_section "${ICON_DOCKER} Docker情報"
    
    if [[ "$OS" == "macOS" ]]; then
        print_info "macOS環境: Docker Desktop の確認中..."
        
        # Docker Desktop の起動確認
        if pgrep -f "Docker Desktop" >/dev/null 2>&1; then
            print_success "Docker Desktop: 実行中"
        else
            print_warning "Docker Desktop: 停止中または未インストール"
        fi
    fi
    
    # Docker権限チェック
    check_docker_permission
    docker_perm_result=$?
    
    case $docker_perm_result in
        0)
            print_success "Docker: 通常権限でアクセス可能"
            docker_cmd="docker"
            ;;
        1)
            print_warning "Docker: sudo権限が必要"
            docker_cmd="sudo docker"
            
            if [[ "$OS" == "macOS" ]]; then
                print_info "macOS環境: Docker Desktop使用時は通常sudo不要です"
                print_info "Docker Desktop が起動していることを確認してください"
            fi
            ;;
        2)
            print_error "Docker: アクセスできません（未インストールまたは権限なし）"
            
            if [[ "$OS" == "macOS" ]]; then
                print_info "macOS環境: Docker Desktop のインストールが必要です"
                print_info "https://www.docker.com/products/docker-desktop/ からダウンロード"
            fi
            echo ""
            return
            ;;
    esac
    
    # Dockerバージョン（sudo不要の場合のみ）
    if [ $docker_perm_result -eq 0 ]; then
        docker_version=$($docker_cmd --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1)
        if [ ! -z "$docker_version" ]; then
            print_info "Dockerバージョン: ${docker_version}"
        fi
        
        # Docker Compose
        if has_command docker-compose; then
            compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1)
            print_info "Docker Composeバージョン: ${compose_version}"
        elif $docker_cmd compose version >/dev/null 2>&1; then
            compose_version=$($docker_cmd compose version --short 2>/dev/null)
            print_info "Docker Compose Plugin: ${compose_version}"
        else
            print_warning "Docker Composeが見つかりません"
        fi
        
        # 実行中のコンテナ
        running_containers=$($docker_cmd ps --format "table {{.Names}}" 2>/dev/null | tail -n +2 | wc -l)
        if [ "$running_containers" -gt 0 ]; then
            print_info "実行中のコンテナ: ${running_containers}個"
            print_info "コンテナ一覧:"
            $docker_cmd ps --format "  - {{.Names}} ({{.Image}})" 2>/dev/null | head -5
            if [ "$running_containers" -gt 5 ]; then
                print_info "  ... 他 $((running_containers - 5))個"
            fi
        else
            print_info "実行中のコンテナ: なし"
        fi
    else
        print_info "Docker情報の詳細取得をスキップしました（sudo権限が必要）"
    fi
    
    echo ""
}

# セキュリティ情報収集
collect_security_info() {
    print_section "${ICON_SECURITY} セキュリティ情報"
    
    if [[ "$OS" == "macOS" ]]; then
        print_info "macOS環境のセキュリティ:"
        
        # Firewall状態
        if has_command /usr/libexec/ApplicationFirewall/socketfilterfw; then
            fw_state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -o "enabled\|disabled")
            if [ "$fw_state" = "enabled" ]; then
                print_success "macOSファイアウォール: 有効"
            else
                print_warning "macOSファイアウォール: 無効"
            fi
        fi
        
        print_info "UGREEN NAS使用時は、NAS側のセキュリティ設定が重要です"
        
    else
        # Linux (UGREEN NAS) のセキュリティ情報
        # SSH設定
        if [ -f "/etc/ssh/sshd_config" ]; then
            ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            if [ ! -z "$ssh_port" ] && [ "$ssh_port" != "22" ]; then
                print_success "SSHポート: ${ssh_port} (デフォルトから変更済み)"
            else
                print_warning "SSHポート: 22 (デフォルト - セキュリティ上変更推奨)"
            fi
            
            root_login=$(grep "^PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            if [ "$root_login" = "no" ]; then
                print_success "rootログイン: 無効 (セキュア)"
            else
                print_warning "rootログイン: 有効 (セキュリティリスク)"
            fi
        fi
        
        # ファイアウォール
        if has_command ufw; then
            ufw_status=$(ufw status 2>/dev/null | head -1)
            if echo "$ufw_status" | grep -q "active"; then
                print_success "ファイアウォール (UFW): 有効"
            else
                print_warning "ファイアウォール (UFW): 無効"
            fi
        elif has_command iptables; then
            iptables_rules=$(iptables -L 2>/dev/null | wc -l)
            if [ "$iptables_rules" -gt 8 ]; then
                print_info "ファイアウォール (iptables): カスタムルール有り"
            else
                print_warning "ファイアウォール (iptables): 基本設定のみ"
            fi
        else
            print_warning "ファイアウォールツールが見つかりません"
        fi
    fi
    
    echo ""
}

# 設定推奨値の生成
generate_recommendations() {
    print_section "🎯 推奨設定値"
    
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}📱 macOS開発環境での参考設定値:${NC}"
        echo -e "${BLUE}  ⚠️  注意: これは開発・テスト用の値です${NC}"
        echo -e "${BLUE}  🏠 実際のUGREEN NAS環境では下記の「本番用設定値」を使用してください${NC}"
        echo ""
    else
        echo -e "${GREEN}🏠 UGREEN NAS本番用設定値:${NC}"
        echo -e "${BLUE}  ✅ Docker設定ファイルで使用する実際の値${NC}"
        echo ""
    fi
    
    echo -e "${WHITE}YAMLファイルで使用する推奨値:${NC}"
    echo -e "${GREEN}  PUID: ${puid}${NC}"
    echo -e "${GREEN}  PGID: ${pgid}${NC}"
    
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}  ※ UGREEN NAS環境では通常 PUID: 1000, PGID: 100 です${NC}"
    fi
    
    if [ ! -z "$local_ip" ]; then
        echo -e "${GREEN}  JELLYFIN_PublishedServerUrl: ${local_ip}${NC}"
        if [[ "$OS" == "macOS" ]]; then
            echo -e "${YELLOW}  ※ UGREEN NAS環境では NAS の実際のIPアドレスを使用${NC}"
        fi
    fi
    
    if [ ! -z "$network_range" ]; then
        echo -e "${GREEN}  TS_EXTRA_ARGS: --advertise-routes=${network_range} --accept-dns=true${NC}"
    fi
    
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}  USB_PATH: /Volumes/YourExternalDrive  # 📱 macOS開発用例${NC}"
        echo -e "${BLUE}  💡 NAS本番環境では: /mnt/@usb/sdd1 形式になります${NC}"
        echo -e "${YELLOW}  MEDIA_PATH: /Users/$(whoami)/Movies  # 📱 macOS開発用例${NC}"
        echo -e "${BLUE}  💡 NAS本番環境では: /volume1 になります${NC}"
    else
        if [ ! -z "$recommended_usb" ]; then
            echo -e "${GREEN}  USB_PATH: ${recommended_usb}${NC}"
            if [ ${#usb_devices[@]} -gt 1 ]; then
                echo -e "${BLUE}  # 他の利用可能なUSBデバイス:${NC}"
                for device_path in "${usb_devices[@]}"; do
                    if [ "$device_path" != "$recommended_usb" ]; then
                        echo -e "${BLUE}  # ${device_path}${NC}"
                    fi
                done
            fi
        else
            echo -e "${YELLOW}  USB_PATH: /mnt/@usb/sdd1  # 実際のパスに変更してください${NC}"
        fi
        
        if [ ${#internal_volumes[@]} -gt 1 ]; then
            echo -e "${GREEN}  MEDIA_PATH: ${internal_volumes[0]}${NC}"
            echo -e "${BLUE}  # 他の利用可能な内蔵ボリューム:${NC}"
            for vol_path in "${internal_volumes[@]:1}"; do
                echo -e "${BLUE}  # MEDIA_PATH: ${vol_path}${NC}"
            done
        else
            echo -e "${GREEN}  MEDIA_PATH: /volume1${NC}"
        fi
    fi
    
    echo -e "${GREEN}  CONFIG_PATH: /volume1/docker/configs${NC}"
    
    echo ""
    
    # 重要な注意事項
    echo -e "${WHITE}重要な注意事項:${NC}"
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}  📱 これはmacOS開発環境での検出結果です${NC}"
        echo -e "${BLUE}  🔄 実際のUGREEN NAS環境では値が異なります${NC}"
        echo -e "${GREEN}  🎯 本番デプロイ前にUGREEN NAS上でこのスクリプトを実行してください${NC}"
    else
        if [ "$pgid" = "100" ]; then
            echo -e "${GREEN}  ✓ PGID=100はUGREEN NASの正しい設定です${NC}"
        else
            echo -e "${YELLOW}  ! PGID=${pgid}は特殊な値です。問題が発生した場合は100に変更してみてください${NC}"
        fi
    fi
    
    echo -e "${BLUE}  • 設定値をコピーしてYAMLファイルに貼り付けてください${NC}"
    echo -e "${BLUE}  • IPアドレスとパスは実際の環境に合わせて調整してください${NC}"
    echo -e "${BLUE}  • ポート競合がある場合は代替ポートを使用してください${NC}"
    
    if [ ${#usb_devices[@]} -gt 0 ]; then
        echo ""
        echo -e "${WHITE}Duplicatiバックアップ設定のヒント:${NC}"
        echo -e "${BLUE}  • 推奨USBパスをDuplicatiの保存先に設定してください${NC}"
        echo -e "${BLUE}  • バックアップ先は内蔵ドライブとは別のUSBデバイスを使用${NC}"
        if [ ${#usb_devices[@]} -gt 1 ]; then
            echo -e "${BLUE}  • 複数のUSBデバイスがある場合は容量の大きいものを推奨${NC}"
            echo -e "${BLUE}  • 冗長化のため複数デバイスへの分散バックアップも検討${NC}"
        fi
    fi
    
    echo ""
}

# 次のステップガイド
show_next_steps() {
    print_section "📝 次のステップ"
    
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}📱 macOS開発環境での推奨ワークフロー:${NC}"
        echo ""
        echo -e "${WHITE}1. 🔧 ローカル開発・テスト${NC}"
        echo -e "${BLUE}   - Docker Desktop をインストール・起動${NC}"
        echo -e "${BLUE}   - essential-stack.yml をダウンロードして動作確認${NC}"
        echo -e "${BLUE}   - 設定値を調整してローカルテスト実行${NC}"
        echo ""
        echo -e "${WHITE}2. 🏠 UGREEN NAS本番デプロイ${NC}"
        echo -e "${GREEN}   - UGREEN NAS上でこのスクリプトを再実行${NC}"
        echo -e "${GREEN}   - 実際のNAS環境の設定値を取得${NC}"
        echo -e "${GREEN}   - 本番用設定でDocker Stackをデプロイ${NC}"
        echo ""
        echo -e "${BLUE}💡 この段階的アプローチにより、理論と実践のギャップを埋められます${NC}"
        echo ""
    else
        echo -e "${WHITE}1. Portainer導入${NC}"
        echo -e "${BLUE}   sudo docker run -d \\${NC}"
        echo -e "${BLUE}     --name portainer \\${NC}"
        echo -e "${BLUE}     --restart always \\${NC}"
        echo -e "${BLUE}     -p 9000:9000 \\${NC}"
        echo -e "${BLUE}     -v /var/run/docker.sock:/var/run/docker.sock \\${NC}"
        echo -e "${BLUE}     -v /volume1/docker/configs/portainer:/data \\${NC}"
        echo -e "${BLUE}     portainer/portainer-ce:latest${NC}"
        echo ""
        echo -e "${WHITE}2. ブラウザでアクセス${NC}"
        echo -e "${BLUE}   http://${local_ip}:9000${NC}"
        echo ""
        echo -e "${WHITE}3. 神5コンテナ導入${NC}"
        echo -e "${BLUE}   GitHubから神3スタックYAMLをダウンロードし、Portainerでデプロイ${NC}"
        echo -e "${BLUE}   https://github.com/davetanaka/ugreen-nas-docker-helper${NC}"
        echo ""
        echo -e "${WHITE}4. 詳細ガイド参照${NC}"
        echo -e "${BLUE}   完全セットアップガイドで詳細な手順を確認してください${NC}"
        echo ""
    fi
}

# フッター表示
print_footer() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${WHITE}UGREEN NAS Docker Helper プロジェクト${NC}"
    echo -e "${BLUE}GitHub: https://github.com/davetanaka/ugreen-nas-docker-helper${NC}"
    if [[ "$OS" == "macOS" ]]; then
        echo -e "${YELLOW}📱 macOS開発環境での検出完了${NC}"
        echo -e "${GREEN}🎯 次は UGREEN NAS上での本番実行を推奨します${NC}"
    else
        echo -e "${GREEN}🏠 UGREEN NAS本番環境での検出完了${NC}"
        echo -e "${YELLOW}理論と実践のギャップを埋めて、NASライフを豊かに！${NC}"
    fi
    echo -e "${CYAN}=================================================${NC}"
}

# メイン実行
main() {
    # OS検出
    detect_os
    
    clear
    print_header
    
    collect_system_info
    collect_storage_info
    collect_network_info
    collect_docker_info
    collect_security_info
    generate_recommendations
    show_next_steps
    
    print_footer
}

# エラーハンドリング
set -e
trap 'print_error "スクリプト実行中にエラーが発生しました"; exit 1' ERR

# スクリプト実行
main "$@"
