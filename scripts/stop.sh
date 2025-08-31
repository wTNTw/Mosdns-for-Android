#!/system/bin/sh

MODDIR="/data/adb/modules/mosdns"
PID_FILE="$MODDIR/mosdns.pid"
LOG_FILE="$MODDIR/log/mosdns_server.log"
METRICS_CACHE="$MODDIR/log/metrics_cache"
UPDATE_SCRIPT="$MODDIR/scripts/update_status.sh"
PROCESS_NAME="mosdns"

echo "[$(date '+%H:%M:%S')] 停止 MosDNS 服务..." >> "$LOG_FILE"

get_exact_pids() {
    pgrep -f "$PROCESS_NAME" | while read pid; do
        if grep -qE "bin/(mosdns|$PROCESS_NAME)" "/proc/$pid/cmdline" 2>/dev/null; then
            exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
            [ -n "$exe" ] && [[ "$exe" == *"mosdns"* ]] && echo "$pid"
        fi
    done | sort -u
}

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    echo "[$(date '+%H:%M:%S')] 从PID文件终止主进程: $PID" >> "$LOG_FILE"
    if kill -0 "$PID" 2>/dev/null; then
        if kill -9 "$PID" 2>> "$LOG_FILE"; then
            rm -f "$PID_FILE"
            echo "[$(date '+%H:%M:%S')] 服务已成功停止" >> "$LOG_FILE"
        else
            echo "[$(date '+%H:%M:%S')] 警告: 无法终止进程 $PID" >> "$LOG_FILE"
        fi
    else
        echo "[$(date '+%H:%M:%S')] 进程 $PID 已不存在，清理PID文件" >> "$LOG_FILE"
        rm -f "$PID_FILE"
    fi
fi

PIDS=$(get_exact_pids)
if [ -n "$PIDS" ]; then
    echo "[$(date '+%H:%M:%S')] 找到有效的MosDNS进程: $PIDS" >> "$LOG_FILE"
    kill -9 $PIDS 2>> "$LOG_FILE"
    
    sleep 0.5
    REMAINING=$(get_exact_pids)
    if [ -n "$REMAINING" ]; then
        echo "[$(date '+%H:%M:%S')] 警告: 以下进程仍存活: $REMAINING" >> "$LOG_FILE"
    else
        echo "[$(date '+%H:%M:%S')] 所有进程已成功终止" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%H:%M:%S')] 未找到有效的MosDNS进程" >> "$LOG_FILE"
fi

if [ -f "$METRICS_CACHE" ]; then
    if rm -f "$METRICS_CACHE"; then
        echo "[$(date '+%H:%M:%S')] 已删除metrics缓存文件" >> "$LOG_FILE"
    else
        echo "[$(date '+%H:%M:%S')] 警告: 无法删除metrics缓存文件" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%H:%M:%S')] metrics缓存文件不存在，无需清理" >> "$LOG_FILE"
fi

if [ -x "$UPDATE_SCRIPT" ]; then
    echo "[$(date '+%H:%M:%S')] 正在更新 module.prop..." >> "$LOG_FILE"
    if "$UPDATE_SCRIPT" >> "$LOG_FILE" 2>&1; then
        echo "[$(date '+%H:%M:%S')] module.prop 更新成功" >> "$LOG_FILE"
    else
        echo "[$(date '+%H:%M:%S')] 警告: module.prop 更新失败" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%H:%M:%S')] 警告: update_status.sh 不存在或不可执行" >> "$LOG_FILE"
fi

exit 0