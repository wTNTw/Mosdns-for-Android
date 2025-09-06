#!/system/bin/sh

MODULE_DIR="/data/adb/modules/mosdns"
DATADIR="/data/adb/Mosdns"
FILE_DIR="$DATADIR/bin"
TEMP_DIR="$DATADIR/update"
LOG_DIR="$DATADIR/log"
LOG_FILE="$LOG_DIR/mosdns_update.log"
LOCAL_CURL="$TEMP_DIR/curl"
TEST_URL="https://www.google.com/generate_204"

FILES="https://raw.githubusercontent.com/pmkol/easymosdns/rules/china_ip_list.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/rules/gfw_ip_list.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/rules/china_domain_list.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/rules/gfw_domain_list.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/rules/cdn_domain_list.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/rules/ad_domain_list.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/main/ecs_cn_domain.txt \
       https://raw.githubusercontent.com/pmkol/easymosdns/main/ecs_noncn_domain.txt"


mkdir -p "$TEMP_DIR" "$LOG_DIR" "$FILE_DIR" "$DATADIR/backup" "$FILE_DIR/rules"

log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

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

check_network() {
    if ! "$LOCAL_CURL" -sI --connect-timeout 10 "$TEST_URL" >/dev/null 2>&1; then
        log "ERROR" "网络连接检查失败，无法访问测试URL: $TEST_URL"
        return 1
    fi
    log "DEBUG" "网络连接检查通过"
    return 0
}

backup_file() {
    local file_path="$1"
    local filename="$(basename "$file_path")"
    local relative_path="${file_path#$FILE_DIR/}"
    local backup_dir="$DATADIR/backup/$(dirname "$relative_path")"
    local backup_file="$DATADIR/backup/$relative_path"
    
    mkdir -p "$backup_dir"
    if [ -f "$file_path" ]; then
        cp "$file_path" "$backup_file"
        log "DEBUG" "已备份: $file_path → $backup_file"
        return 0
    fi
    log "WARN" "无原始文件可备份: $file_path"
    return 1
}

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

process_hosts() {
    local input_file="$1"
    local output_file="$FILE_DIR/hosts.txt"
    
    awk '{
        if ($0 ~ /^#/) {
            print $0
        } else if (NF >= 2) {
            printf "%s", $2
            for (i=3; i<=NF; i++) {
                printf " %s", $i
            }
            printf " %s\n", $1
        }
    }' "$input_file" > "$output_file"
    
    if [ -s "$output_file" ]; then
        chmod 644 "$output_file"
        log "INFO" "hosts.txt生成成功 (大小: $(du -h "$output_file" | cut -f1))"
        return 0
    else
        log "ERROR" "hosts.txt生成失败"
        return 1
    fi
}

update_file() {
    local url="$1"
    local filename=$(basename "$url")
    local target_file="$FILE_DIR/rules/$filename"
    local temp_file="$TEMP_DIR/$filename.tmp"

    if [ "$filename" = "hosts" ]; then
        backup_file "$FILE_DIR/hosts.txt"
        
        log "INFO" "开始更新hosts.txt"
        if download_with_retry "$url" "$temp_file" && \
           [ -s "$temp_file" ] && [ $(stat -c%s "$temp_file") -gt 0 ]; then
            if process_hosts "$temp_file"; then
                rm -f "$temp_file"
                return 0
            fi
        fi
        
        log "ERROR" "hosts.txt更新失败"
        return 1
    fi
    
    backup_file "$target_file"
    log "INFO" "开始更新: $filename"
    if download_with_retry "$url" "$temp_file" && \
       [ -s "$temp_file" ] && [ $(stat -c%s "$temp_file") -gt 0 ]; then
        mv -f "$temp_file" "$target_file"
        chmod 644 "$target_file"
        log "INFO" "更新成功: $filename (大小: $(du -h "$target_file" | cut -f1))"
        return 0
    fi
    
    log "ERROR" "更新失败: $filename"
    return 1
}


update_mosdns_core() {
    local mosdns_url="https://github.com/pmkol/mosdns-x/releases/latest/download/mosdns-linux-arm64.zip"
    local temp_zip="$TEMP_DIR/mosdns-linux-arm64.zip"
    local temp_extract="$TEMP_DIR/mosdns_extract"
    
    log "INFO" "开始更新 mosdns 核心"
    
    if ! download_with_retry "$mosdns_url" "$temp_zip"; then
        log "ERROR" "下载 mosdns 核心失败"
        return 1
    fi
    
    mkdir -p "$temp_extract"
    
    if ! unzip -o "$temp_zip" -d "$temp_extract" >/dev/null 2>&1; then
        log "ERROR" "解压 mosdns 核心失败"
        rm -rf "$temp_extract" "$temp_zip"
        return 1
    fi
    
    local mosdns_bin=$(find "$temp_extract" -name "mosdns" -type f -executable | head -n 1)
    if [ -z "$mosdns_bin" ]; then
        log "ERROR" "在 zip 文件中未找到 mosdns 可执行文件"
        rm -rf "$temp_extract" "$temp_zip"
        return 1
    fi
    
    backup_file "$FILE_DIR/mosdns"
    
    if cp -f "$mosdns_bin" "$FILE_DIR/mosdns" && chmod 755 "$FILE_DIR/mosdns"; then
        log "INFO" "mosdns 核心更新成功"
        rm -rf "$temp_extract" "$temp_zip"
        return 0
    else
        log "ERROR" "复制 mosdns 可执行文件失败"
        rm -rf "$temp_extract" "$temp_zip"
        return 1
    fi
}

main() {
    check_curl || return 1
    
    if ! check_network; then
        log "ERROR" "网络不可用，停止更新"
        return 1
    fi
    
    log "INFO" "=== 开始文件更新 ==="
    
    log "INFO" "--- 更新规则文件 ---"
    for url in $FILES; do
        update_file "$url" || log "ERROR" "文件更新失败: $url"
    done
    
    log "INFO" "--- 更新 mosdns 核心 ---"
    update_mosdns_core || log "ERROR" "mosdns 核心更新失败"
    
    log "INFO" "=== 文件更新完成 ==="
    date '+%Y-%m-%d %H:%M:%S' > "$LOG_DIR/last_update_time"
    sleep 5
    if [ -f "$DATADIR/scripts/update_status.sh" ]; then
        sh "$DATADIR/scripts/update_status.sh"
        log "INFO" "已调用 update_status.sh 更新 module.prop"
    else
        log "ERROR" "update_status.sh 不存在，无法更新 module.prop"
    fi

    return 0
}

main "$@"
