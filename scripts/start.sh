#!/system/bin/sh

# 检测 Magisk 版本确定模块目录
MODDIR="/data/adb/modules/mosdns"
[ -n "$(magisk -v 2>/dev/null | grep lite)" ] && MODDIR="/data/adb/lite_modules/mosdns"

DATADIR="/data/adb/Mosdns"
CORE="$DATADIR/bin"
CONFIG_FILE="$DATADIR/config.yaml"
LOG_FILE="$DATADIR/log/mosdns_server.log"
PID_FILE="$DATADIR/mosdns.pid"
UPDATE_SCRIPT="$DATADIR/scripts/update_files.sh"
SETTINGS_FILE="$DATADIR/setting.conf"
SCRIPTS_DIR="$DATADIR/scripts"

# 创建必要目录
mkdir -p "$DATADIR/log" "$DATADIR/cron"

# 检查模块是否被禁用
if [ -f "$MODDIR/disable" ]; then
    echo "[$(date '+%H:%M:%S')] 模块已被禁用，跳过启动" >> "$LOG_FILE"
    # 更新模块状态为已停止
    if [ -f "$SCRIPTS_DIR/update_status.sh" ]; then
        sh "$SCRIPTS_DIR/update_status.sh" --status STOPPED >> "$LOG_FILE" 2>&1
    fi
    exit 0
fi

# 导入并清理配置
if [ -f "$SETTINGS_FILE" ]; then
    grep -E '^[[:space:]]*[[:alpha:]_][[:alnum:]_]*=' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    . "${SETTINGS_FILE}.tmp"
    rm -f "${SETTINGS_FILE}.tmp"
    
    MOSDNS_PORT=$(echo "$MOSDNS_PORT" | tr -d '[:space:]')
    ENABLE_IPTABLES=$(echo "$ENABLE_IPTABLES" | tr -d '[:space:]')
    ENABLE_CRONTAB=$(echo "$ENABLE_CRONTAB" | tr -d '[:space:]')
fi

# 默认配置值
MOSDNS_PORT="${MOSDNS_PORT:-5335}"
ENABLE_IPTABLES="${ENABLE_IPTABLES:-true}"
ENABLE_CRONTAB="${ENABLE_CRONTAB:-false}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 8,21 * * *}"

# 获取 busybox 路径
get_busybox_path() {
    if [ -f "/data/adb/ksud" ]; then
        echo "/data/adb/ksu/bin/busybox"
    elif [ -f "/data/adb/ap/bin/busybox" ]; then
        echo "/data/adb/ap/bin/busybox"
    else
        echo "$(magisk --path)/.magisk/busybox/busybox"
    fi
}

BUSYBOX=$(get_busybox_path)

update_config_port() {
    local port="$1"
    local config_file="$CONFIG_FILE"
    
    if [ ! -f "${config_file}.orig" ]; then
        cp "$config_file" "${config_file}.orig"
    fi
    
    sed -i "s/addr: 127\.0\.0\.1:[0-9]\+/addr: 127.0.0.1:${port}/g" "$config_file"
    
    if grep -q "addr: 127.0.0.1:${port}" "$config_file"; then
        echo "[$(date '+%H:%M:%S')] 成功更新config.yaml监听端口为: ${port}" >> "$LOG_FILE"
        return 0
    else
        echo "[$(date '+%H:%M:%S')] 错误: 更新config.yaml端口失败" >> "$LOG_FILE"
        return 1
    fi
}

if [ -f "$CONFIG_FILE" ]; then
    CURRENT_PORT=$(grep -E "addr: 127\.0\.0\.1:[0-9]+" "$CONFIG_FILE" | head -1 | sed 's/.*:\([0-9]*\).*/\1/')
    CURRENT_PORT=$(echo "$CURRENT_PORT" | tr -d '[:space:]')
    MOSDNS_PORT=$(echo "$MOSDNS_PORT" | tr -d '[:space:]')
    
    if [ -n "$CURRENT_PORT" ] && [ -n "$MOSDNS_PORT" ] && [ "$CURRENT_PORT" != "$MOSDNS_PORT" ]; then
        echo "[$(date '+%H:%M:%S')] 检测到端口不一致，正在更新config.yaml..." >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] 当前端口: $CURRENT_PORT, 目标端口: $MOSDNS_PORT" >> "$LOG_FILE"
        update_config_port "$MOSDNS_PORT"
    else
        echo "[$(date '+%H:%M:%S')] 端口一致，无需更新config.yaml" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%H:%M:%S')] 警告: config.yaml不存在，跳过端口更新" >> "$LOG_FILE"
fi

mkdir -p "$DATADIR/log"
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
port="$MOSDNS_PORT"

{
    if command -v fuser &>/dev/null; then
        fuser -k "${port}/udp" 2>/dev/null
    else
        pids=$(lsof -i :$port -t 2>/dev/null || ss -lptn "sport = :$port" 2>/dev/null | awk '{print $6}' | cut -d= -f2 | sort -u)
        if [ -n "$pids" ]; then
            echo "$pids" | xargs kill -TERM 2>/dev/null
            sleep 1
            echo "$pids" | xargs kill -KILL 2>/dev/null
        fi
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
    
    TEMP_PID="$DATADIR/temp_pid.$$"
    echo "$PID" > "$TEMP_PID" && mv "$TEMP_PID" "$PID_FILE"
    
    if [ -f "$PID_FILE" ]; then
        chmod 644 "$PID_FILE"
        echo "[$(date '+%H:%M:%S')] 成功写入PID文件 (PID: $PID)" >> "$LOG_FILE"
        
        echo "[$(date '+%H:%M:%S')] 应用配置设置..." >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] ENABLE_IPTABLES=$ENABLE_IPTABLES, ENABLE_CRONTAB=$ENABLE_CRONTAB" >> "$LOG_FILE"
        
        # 应用 iptables 设置
        if [ "$ENABLE_IPTABLES" = "true" ]; then
            echo "[$(date '+%H:%M:%S')] 启用iptables DNS转发..." >> "$LOG_FILE"
            sh "$DATADIR/scripts/iptables.sh" enable >> "$LOG_FILE" 2>&1
        else
            echo "[$(date '+%H:%M:%S')] iptables DNS转发已禁用" >> "$LOG_FILE"
        fi
        
        # 应用定时任务设置
        if [ "$ENABLE_CRONTAB" = "true" ]; then
            echo "[$(date '+%H:%M:%S')] 设置定时任务..." >> "$LOG_FILE"
            CRON_DIR="$DATADIR/cron"
            mkdir -p "$CRON_DIR"
            
            if [ ! -x "$BUSYBOX" ]; then
                echo "[$(date '+%H:%M:%S')] 警告: BusyBox不可用，跳过定时任务" >> "$LOG_FILE"
                continue
            fi
            
            echo "$CRON_SCHEDULE $BUSYBOX sh $UPDATE_SCRIPT --silent >> $LOG_FILE 2>&1" > "$CRON_DIR/root"
            echo "0 */6 * * * $BUSYBOX ps | grep '[c]rond' >/dev/null && echo \"[crond检查] crond 正在运行 [\$(date '+\%Y-\%m-\%d \%H:\%M:\%S')]\" >> $LOG_FILE || echo \"[crond检查] crond 未运行，需检查！ [\$(date '+\%Y-\%m-\%d \%H:\%M:\%S')]\" >> $LOG_FILE" >> "$CRON_DIR/root"
            chmod 644 "$CRON_DIR/root"
            
            $BUSYBOX crond -c "$CRON_DIR/"
            echo "[$(date '+%H:%M:%S')] 定时更新服务已启动" >> "$LOG_FILE"
        else
            echo "[$(date '+%H:%M:%S')] 定时更新服务已禁用" >> "$LOG_FILE"
        fi
        
        # 更新模块状态
        UPDATE_STATUS_SCRIPT="$DATADIR/scripts/update_status.sh"
        if [ -f "$UPDATE_STATUS_SCRIPT" ]; then
            echo "[$(date '+%H:%M:%S')] 更新模块状态..." >> "$LOG_FILE"
            sh "$UPDATE_STATUS_SCRIPT" --status RUNNING --pid "$PID" >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                echo "[$(date '+%H:%M:%S')] 已更新 module.prop 状态" >> "$LOG_FILE"
            else
                echo "[$(date '+%H:%M:%S')] 警告: 更新 module.prop 状态失败" >> "$LOG_FILE"
            fi
        else
            echo "[$(date '+%H:%M:%S')] 错误: update_status.sh 不存在" >> "$LOG_FILE"
        fi
        exit 0
    else
        echo "[$(date '+%H:%M:%S')] 错误: 最终未能创建PID文件" >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] 调试: 当前目录权限:" >> "$LOG_FILE"
        ls -ld "$DATADIR" >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] 调试: 当前用户: $(whoami)" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "[$(date '+%H:%M:%S')] 启动失败: 无法获取PID" >> "$LOG_FILE"
    exit 1
fi

stop_service() {
    echo "[$(date '+%H:%M:%S')] 停止 MosDNS 服务..." >> "$LOG_FILE"
    # 停止 mosdns 进程
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if [ -n "$PID" ]; then
            kill "$PID" 2>/dev/null
            sleep 1
            kill -9 "$PID" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi

    # 停止定时任务
    if [ -f "/data/adb/ksud" ]; then
        busybox="/data/adb/ksu/bin/busybox"
    elif [ -f "/data/adb/ap/bin/busybox" ]; then
        busybox="/data/adb/ap/bin/busybox"
    else
        busybox="$(magisk --path)/.magisk/busybox/busybox"
    fi
    $busybox pkill -f "crond -c $DATADIR/cron/"

    # 更新模块状态
    if [ -f "$SCRIPTS_DIR/update_status.sh" ]; then
        sh "$SCRIPTS_DIR/update_status.sh" --status STOPPED >> "$LOG_FILE" 2>&1
    fi
    echo "[$(date '+%H:%M:%S')] MosDNS 服务已停止" >> "$LOG_FILE"
}

monitor_disable() {
    (
        sleep 10
        while true; do
            if [ -f "$MODDIR/disable" ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 检测到模块被禁用，停止服务..." >> "$LOG_FILE"
                stop_service
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服务已停止，监控进程退出" >> "$LOG_FILE"
                exit 0
            fi
            sleep 5
        done
    ) &
}

case "$1" in
    start|"")
        monitor_disable
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        sleep 2
        monitor_disable
        ;;
    status)
        if is_process_running; then
            echo "MosDNS 服务正在运行 (PID: $(cat "$PID_FILE" 2>/dev/null))"
            exit 0
        else
            echo "MosDNS 服务未运行"
            exit 1
        fi
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac