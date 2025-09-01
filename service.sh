#!/system/bin/sh

ACTION="$1"
MODDIR="/data/adb/modules/mosdns"
LOG_FILE="$MODDIR/log/mosdns_server.log"
PID_FILE="$MODDIR/mosdns.pid"
CRON_DIR="$MODDIR/cron"
UPDATE_SCRIPT="$MODDIR/scripts/update_files.sh"
SETTINGS_FILE="$MODDIR/setting.conf"

if [ -f "$SETTINGS_FILE" ]; then
    # 使用 grep 提取有效的变量赋值行，避免注释和空行导致 source 错误
    grep -E '^[[:space:]]*[[:alpha:]_][[:alnum:]_]*=' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    . "${SETTINGS_FILE}.tmp"
    rm -f "${SETTINGS_FILE}.tmp"
    
    # 去除变量值中的换行符和空格
    MOSDNS_PORT=$(echo "$MOSDNS_PORT" | tr -d '[:space:]')
    ENABLE_IPTABLES=$(echo "$ENABLE_IPTABLES" | tr -d '[:space:]')
    ENABLE_CRONTAB=$(echo "$ENABLE_CRONTAB" | tr -d '[:space:]')
    CRON_SCHEDULE=$(echo "$CRON_SCHEDULE" | tr -d '[:space:]')
fi

MOSDNS_PORT="${MOSDNS_PORT:-5335}"
ENABLE_IPTABLES="${ENABLE_IPTABLES:-true}"
ENABLE_CRONTAB="${ENABLE_CRONTAB:-true}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 8,21 * * *}"

# 调试信息：输出当前配置值
echo "==== 配置调试信息 [$(date '+%Y-%m-%d %H:%M:%S')] ====" >> "$LOG_FILE"
echo "MOSDNS_PORT: $MOSDNS_PORT" >> "$LOG_FILE"
echo "ENABLE_IPTABLES: $ENABLE_IPTABLES" >> "$LOG_FILE"
echo "ENABLE_CRONTAB: $ENABLE_CRONTAB" >> "$LOG_FILE"
echo "CRON_SCHEDULE: $CRON_SCHEDULE" >> "$LOG_FILE"

start_service() {
    if [ -f "$MODDIR/disable" ]; then
        echo "模块已被禁用（检测到disable文件），跳过启动" >> "$LOG_FILE"
        exit 0
    fi
    
    mkdir -p "$MODDIR/log" "$CRON_DIR"
    echo "正在清理所有旧日志文件..." >> "$LOG_FILE"
    rm -f "$MODDIR/log/"*.log
    echo "==== 服务启动 [$(date '+%Y-%m-%d %H:%M:%S')] ====" >> "$LOG_FILE"
    
    if [ -f "/data/adb/ksud" ]; then
        BUSYBOX="/data/adb/ksu/bin/busybox"
    else
        BUSYBOX="$(magisk --path)/.magisk/busybox/busybox"
    fi
    
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 5
        echo "等待系统启动..." >> "$LOG_FILE"
    done
    sleep 10
    
    if [ -f "$PID_FILE" ]; then
        echo "检测到残留的 PID 文件，正在清理..." >> "$LOG_FILE"
        PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$PID" ]; then
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
    
    echo "清理 crond 服务..." >> "$LOG_FILE"
    $BUSYBOX pkill -f "crond -c $CRON_DIR/"
    
    echo "尝试启动MosDNS服务..." >> "$LOG_FILE"
    sh "$MODDIR/scripts/start.sh" >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ] && [ -f "$PID_FILE" ]; then
        echo "MosDNS 服务已启动" >> "$LOG_FILE"
        
        if [ "$ENABLE_IPTABLES" = "true" ]; then
            echo "启用iptables DNS转发..." >> "$LOG_FILE"
            sh "$MODDIR/scripts/iptables.sh" enable >> "$LOG_FILE" 2>&1
        else
            echo "iptables DNS转发已禁用（配置设置）" >> "$LOG_FILE"
        fi
        
        if [ "$ENABLE_CRONTAB" = "true" ]; then
            echo "设置定时任务..." >> "$LOG_FILE"
            echo "$CRON_SCHEDULE $BUSYBOX sh $UPDATE_SCRIPT --silent >> $LOG_FILE 2>&1" > "$CRON_DIR/root"
            echo "0 */12 * * * $BUSYBOX ps | grep '[c]rond' >/dev/null && echo \"[crond检查] crond 正在运行 [\$(date '+\%Y-\%m-\%d \%H:\%M:\%S')]\" >> $LOG_FILE || echo \"[crond检查] crond 未运行，需检查！ [\$(date '+\%Y-\%m-\%d \%H:\%M:\%S')]\" >> $LOG_FILE" >> "$CRON_DIR/root"
            chmod 644 "$CRON_DIR/root"
            
            $BUSYBOX crond -c "$CRON_DIR/"
            echo "定时更新服务已启动 (BusyBox: $BUSYBOX)" >> "$LOG_FILE"
            $BUSYBOX ps | grep '[c]rond' >> "$LOG_FILE"
        else
            echo "定时更新服务已禁用（配置设置）" >> "$LOG_FILE"
        fi
    else
        echo "MosDNS 服务启动失败" >> "$LOG_FILE"
    fi
}

case "$ACTION" in
    "start"|"boot")
        start_service
        ;;
    
    "stop")
        echo "停止MosDNS服务..." >> "$LOG_FILE"
        sh "$MODDIR/scripts/stop.sh" >> "$LOG_FILE" 2>&1
        
        if [ "$ENABLE_IPTABLES" = "true" ]; then
            echo "禁用iptables DNS转发..." >> "$LOG_FILE"
            sh "$MODDIR/scripts/iptables.sh" disable >> "$LOG_FILE" 2>&1
        fi
        
        echo "停止定时更新服务..." >> "$LOG_FILE"
        $BUSYBOX pkill -f "crond -c $CRON_DIR/"
        ;;
    
    *)
        echo "未知操作: $ACTION，使用默认启动行为" >> "$LOG_FILE"
        # 默认情况下执行启动逻辑
        start_service
        ;;
esac

exit 0