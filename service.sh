#!/system/bin/sh

MODDIR="/data/adb/modules/mosdns"
LOG_FILE="$MODDIR/log/mosdns_server.log"
PID_FILE="$MODDIR/mosdns.pid"
CRON_DIR="$MODDIR/cron"
UPDATE_SCRIPT="$MODDIR/scripts/update_files.sh"

# 创建必要目录
mkdir -p "$MODDIR/log" "$CRON_DIR"

# 删除所有旧日志文件
echo "正在清理所有旧日志文件..." >> "$LOG_FILE"
rm -f "$MODDIR/log"/*.log

# 记录服务启动时间
echo "==== 服务启动 [$(date '+%Y-%m-%d %H:%M:%S')] ====" >> "$LOG_FILE"

# 检测 KernelSU 并设置 busybox 路径
if [ -f "/data/adb/ksud" ]; then
    BUSYBOX="/data/adb/ksu/bin/busybox"
else
    BUSYBOX="$(magisk --path)/.magisk/busybox/busybox"
fi

# 等待系统启动完成
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
    echo "等待系统启动..." >> "$LOG_FILE"
done
sleep 10

# 清理现有进程和PID文件
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

# 启动MosDNS服务
echo "尝试启动MosDNS服务..." >> "$LOG_FILE"
sh "$MODDIR/scripts/start.sh" >> "$LOG_FILE" 2>&1

# 检查启动结果
if [ $? -eq 0 ] && [ -f "$PID_FILE" ]; then
    echo "MosDNS 服务已启动" >> "$LOG_FILE"
    
    # 设置定时任务
    echo "0 8,21 * * * $BUSYBOX sh $UPDATE_SCRIPT --silent >> $LOG_FILE 2>&1" > "$CRON_DIR/root"
    echo "0 */12 * * * $BUSYBOX ps | grep '[c]rond' >/dev/null && echo \"[crond检查] crond 正在运行 [\$(date '+\%Y-\%m-\%d \%H:\%M:\%S')]\" >> $LOG_FILE || echo \"[crond检查] crond 未运行，需检查！ [\$(date '+\%Y-\%m-\%d \%H:\%M:\%S')]\" >> $LOG_FILE" >> "$CRON_DIR/root"
    chmod 644 "$CRON_DIR/root"
    
    # 启动crond
    $BUSYBOX crond -c "$CRON_DIR/"
    echo "定时更新服务已启动 (BusyBox: $BUSYBOX)" >> "$LOG_FILE"
    $BUSYBOX ps | grep '[c]rond' >> "$LOG_FILE"
else
    echo "MosDNS 服务启动失败" >> "$LOG_FILE"
fi

exit 0