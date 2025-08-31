#!/system/bin/sh

MODULE_DIR="/data/adb/modules/mosdns"
FILE_DIR="$MODULE_DIR/bin"
TEMP_DIR="$MODULE_DIR/update"
LOG_DIR="$MODULE_DIR/log"
LOG_FILE="$LOG_DIR/mosdns_update.log"
LOCAL_CURL="$TEMP_DIR/curl"
TEST_URL="https://www.google.com/generate_204"

# 需要更新的文件列表
FILES="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
       https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat \
       https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat \
       https://raw.hellogithub.com/hosts"

# 初始化环境
mkdir -p "$TEMP_DIR" "$LOG_DIR" "$FILE_DIR" "$FILE_DIR/backup"

# 日志记录函数
log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# 检查模块自带curl
check_curl() {
    if [ ! -x "$LOCAL_CURL" ]; then
        log "ERROR" "模块curl不可执行: $LOCAL_CURL"
        return 1
    fi
    if ! "$LOCAL_CURL" --version >/dev/null 2>&1; then
        log "ERROR" "模块curl测试失败"
        return 1
    fi
}

# 检查网络连接
check_network() {
    if ! "$LOCAL_CURL" -sI --connect-timeout 10 "$TEST_URL" >/dev/null 2>&1; then
        log "ERROR" "网络连接检查失败，无法访问测试URL: $TEST_URL"
        return 1
    fi
    log "DEBUG" "网络连接检查通过"
    return 0
}

# 文件备份
backup_file() {
    local file_path="$1"
    local backup_dir="$(dirname "$file_path")/backup"
    local filename="$(basename "$file_path")"
    
    mkdir -p "$backup_dir"
    if [ -f "$file_path" ]; then
        cp "$file_path" "$backup_dir/$filename"
        log "DEBUG" "已备份: $file_path → $backup_dir/$filename"
        return 0
    fi
    log "WARN" "无原始文件可备份: $file_path"
    return 1
}

# 增强下载函数
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_delay=5
    local curl_cmd="$LOCAL_CURL -L -s -o"

    for i in $(seq 1 $max_retries); do
        if $curl_cmd "$output" "$url" --connect-timeout 20 --retry 2; then
            return 0
        fi
        log "WARN" "下载失败 (尝试 $i/$max_retries): $url"
        sleep $retry_delay
    done
    return 1
}

# 处理hosts文件格式并保存为hosts.txt
process_hosts() {
    local input_file="$1"
    local output_file="$FILE_DIR/hosts.txt"  # 固定输出为hosts.txt
    
    # 处理格式：将IP和域名位置互换，并保留注释
    awk '{
        if ($0 ~ /^#/) { 
            print $0 
        } else if (NF >= 2) {
            # 将域名放在前面，IP放在后面
            printf "%s", $2
            for (i=3; i<=NF; i++) {
                printf " %s", $i
            }
            printf " %s\n", $1
        }
    }' "$input_file" > "$output_file"
    
    # 检查处理后的文件是否有效
    if [ -s "$output_file" ]; then
        chmod 644 "$output_file"
        log "INFO" "hosts.txt生成成功 (大小: $(du -h "$output_file" | cut -f1))"
        return 0
    else
        log "ERROR" "hosts.txt生成失败"
        return 1
    fi
}

# 更新数据文件
update_file() {
    local url="$1"
    local filename=$(basename "$url")
    local target_file="$FILE_DIR/$filename"
    local temp_file="$TEMP_DIR/$filename.tmp"

    # 特殊处理hosts文件
    if [ "$filename" = "hosts" ]; then
        backup_file "$FILE_DIR/hosts.txt"  # 备份旧的hosts.txt
        
        log "INFO" "开始更新hosts.txt"
        if download_with_retry "$url" "$temp_file" && \
           [ -s "$temp_file" ] && [ $(stat -c%s "$temp_file") -gt 1024 ]; then
            if process_hosts "$temp_file"; then
                rm -f "$temp_file"
                return 0
            fi
        fi
        
        log "ERROR" "hosts.txt更新失败"
        return 1
    fi
    
    # 其他文件正常处理
    backup_file "$target_file"
    log "INFO" "开始更新: $filename"
    if download_with_retry "$url" "$temp_file" && \
       [ -s "$temp_file" ] && [ $(stat -c%s "$temp_file") -gt 10240 ]; then
        mv -f "$temp_file" "$target_file"
        chmod 644 "$target_file"
        log "INFO" "更新成功: $filename (大小: $(du -h "$target_file" | cut -f1))"
        return 0
    fi
    
    log "ERROR" "更新失败: $filename"
    return 1
}

# 主函数
main() {
    check_curl || return 1
    
    if ! check_network; then
        log "ERROR" "网络不可用，停止更新"
        return 1
    fi
    
    log "INFO" "=== 开始文件更新 ==="
    for url in $FILES; do
        update_file "$url" || log "ERROR" "文件更新失败: $url"
    done
    
    log "INFO" "=== 文件更新完成 ==="
    # 刷新 last_update_time 文件
    date '+%Y-%m-%d %H:%M:%S' > "$LOG_DIR/last_update_time"
    sleep 5
    # 调用 update_status.sh 更新 module.prop
    if [ -f "$MODULE_DIR/scripts/update_status.sh" ]; then
        sh "$MODULE_DIR/scripts/update_status.sh"
        log "INFO" "已调用 update_status.sh 更新 module.prop"
    else
        log "ERROR" "update_status.sh 不存在，无法更新 module.prop"
    fi

    return 0
}

main "$@"