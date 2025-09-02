#!/system/bin/sh

MODULE_DIR="/data/adb/modules/mosdns"
DATADIR="/data/adb/Mosdns"
LOG_DIR="$DATADIR/log"
LOG_FILE="$LOG_DIR/mosdns_update.log"
LOCAL_CURL="$DATADIR/update/curl"
PID_FILE="$DATADIR/mosdns.pid"
YIYAN_API="https://v1.hitokoto.cn/?encode=text"
YIYAN_FILE="$LOG_DIR/latest_yiyan.txt"
MODULE_PROP="$MODULE_DIR/module.prop"
LAST_UPDATE_FILE="$LOG_DIR/last_update_time"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

get_yiyan() {
    local yiyan=$("$LOCAL_CURL" -s "$YIYAN_API" | tr -d '\n\r')
    [ -z "$yiyan" ] && [ -f "$YIYAN_FILE" ] && yiyan=$(head -n 1 "$YIYAN_FILE")
    echo "${yiyan:-生活不止眼前的苟且，还有诗和远方}" | cut -c -30 > "$YIYAN_FILE"
    cat "$YIYAN_FILE"
}

handle_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --status) SERVICE_STATUS="$2"; shift 2 ;;
            --pid) SERVICE_PID="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
}

check_service() {
    local pid="N/A"
    local status="STOPPED"
    local retry=0
    local api_available=0
    
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ]; then
            if busybox ps -o pid= -p "$pid" >/dev/null 2>&1; then
                status="RUNNING"
            else
                if [ -d "/proc/$pid" ] && grep -q "mosdns" "/proc/$pid/cmdline" 2>/dev/null; then
                    status="RUNNING"
                else
                    log "WARN" "PID文件存在但进程不存在 (PID: $pid)"
                    rm -f "$PID_FILE"
                    pid="N/A"
                fi
            fi
        else
            log "WARN" "PID文件存在但内容为空"
            rm -f "$PID_FILE"
        fi
    fi
    
    if [ "$status" != "RUNNING" ]; then
        while [ $retry -lt 2 ]; do
            if "$LOCAL_CURL" -s -o /dev/null --connect-timeout 2 "http://127.0.0.1:5336/metrics"; then
                api_available=1
                break
            fi
            retry=$((retry + 1))
            sleep 1
        done
        
        if [ $api_available -eq 1 ]; then
            pid=$(busybox ps -ef | grep -i "[m]osdns" | grep -v "crond" | grep -v "grep" | busybox awk '{print $1}' | head -n 1)
            if [ -n "$pid" ]; then
                status="RUNNING"
                if ! echo "$pid" > "$PID_FILE" 2>/dev/null; then
                    log "ERROR" "无法写入PID文件"
                fi
            else
                log "WARN" "API可访问但未找到mosdns进程"
                status="ERROR"
            fi
        fi
    fi
    
    echo "$status $pid"
}

update_module_prop() {
    local status="$1"
    local pid="${2:-N/A}"
    local yiyan=$(get_yiyan)
    local last_update="N/A"
    
    [ -f "$LAST_UPDATE_FILE" ] && last_update=$(cat "$LAST_UPDATE_FILE")

    case "$status" in
        "RUNNING") status_display="🟢运行中" ;;
        "ERROR") status_display="🟡异常" ;;
        *) status_display="🔴已停止" ;;
    esac

    cat > "$MODULE_PROP" <<EOF
id=mosdns
name=MosDNS
version=$(date '+%Y%m%d')
versionCode=1
author=wukon
description=🛠️功能:高性能DNS服务|广告过滤|DoT/DoH支持 📡状态:$status_display 🆔PID:$pid 🕒更新:$last_update 💬一言:$yiyan
updateJson=https://example.com/update.json
EOF

    chmod 644 "$MODULE_PROP"
}

main() {
    handle_arguments "$@"
    
    if [ -n "$SERVICE_STATUS" ] && [ -n "$SERVICE_PID" ]; then
        update_module_prop "$SERVICE_STATUS" "$SERVICE_PID"
        log "INFO" "通过参数更新状态: $SERVICE_STATUS (PID: $SERVICE_PID)"
    else
        set -- $(check_service)
        service_status=$1
        pid=$2
        update_module_prop "$service_status" "$pid"
        log "INFO" "状态已更新: $service_status (PID: $pid)"
    fi
}

main "$@"