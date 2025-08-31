#!/system/bin/sh

MODDIR="/data/adb/modules/mosdns"
CORE="$MODDIR/bin"
CONFIG_FILE="$MODDIR/config.yaml"
LOG_FILE="$MODDIR/log/mosdns_server.log"
PID_FILE="$MODDIR/mosdns.pid"
UPDATE_SCRIPT="$MODDIR/scripts/update_status.sh"

mkdir -p "$MODDIR/log"
touch "$LOG_FILE" 2>/dev/null || {
    echo "[$(date '+%H:%M:%S')] 错误: 无法创建日志文件" >&2
    exit 1
}

is_process_running() {
    pgrep -f "mosdns start -c $CONFIG_FILE" >/dev/null
    return $?
}

if is_process_running; then
    echo "[$(date '+%H:%M:%S')] 服务已在运行" >> "$LOG_FILE"
    exit 0
fi

echo "[$(date '+%H:%M:%S')] 释放端口..." >> "$LOG_FILE"
port="5335"
if [ -f "$CONFIG_FILE" ]; then
    port=$(grep -E 'listen.*:' "$CONFIG_FILE" | head -1 | sed 's/.*:\([0-9]*\).*/\1/')
    [ -z "$port" ] && port="5335"
fi

{
    if command -v fuser &>/dev/null; then
        fuser -k "${port}/udp"
    else
        netstat -tuln 2>/dev/null | grep ":$port" | awk '{print $7}' | cut -d'/' -f1 | xargs kill -9
    fi
} >> "$LOG_FILE" 2>&1
sleep 1

echo "[$(date '+%H:%M:%S')] 启动服务..." >> "$LOG_FILE"
cd "$CORE" && nohup ./mosdns start -c "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &

PID=""
for i in 1 2 3 4 5; do
    sleep 1
    PID=$(pgrep -f "mosdns start -c $CONFIG_FILE")
    [ -n "$PID" ] && break
done

if [ -n "$PID" ]; then
    echo "[$(date '+%H:%M:%S')] 调试: 尝试写入PID文件 (PID: $PID)" >> "$LOG_FILE"
    ls -ld "$MODDIR" >> "$LOG_FILE"
    touch "$PID_FILE" 2>> "$LOG_FILE"
    
    TEMP_PID=$(mktemp -p "$MODDIR")
    echo "$PID" > "$TEMP_PID" && mv "$TEMP_PID" "$PID_FILE"
    
    if [ -f "$PID_FILE" ]; then
        chmod 644 "$PID_FILE"
        echo "[$(date '+%H:%M:%S')] 成功写入PID文件 (PID: $PID)" >> "$LOG_FILE"
        
        if [ -x "$UPDATE_SCRIPT" ]; then
            "$UPDATE_SCRIPT" --status RUNNING "$PID" >> "$LOG_FILE" 2>&1
            echo "[$(date '+%H:%M:%S')] 已更新 module.prop 状态" >> "$LOG_FILE"
        else
            echo "[$(date '+%H:%M:%S')] 警告: update_status.sh 不可用" >> "$LOG_FILE"
        fi
        exit 0
    else
        echo "[$(date '+%H:%M:%S')] 错误: 最终未能创建PID文件" >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] 调试: 当前目录权限:" >> "$LOG_FILE"
        ls -ld "$MODDIR" >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] 调试: 当前用户: $(whoami)" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "[$(date '+%H:%M:%S')] 启动失败: 无法获取PID" >> "$LOG_FILE"
    exit 1
fi