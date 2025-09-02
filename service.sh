#!/system/bin/sh

# 检测 Magisk 版本以确定模块目录
module_dir="/data/adb/modules/mosdns"
[ -n "$(magisk -v 2>/dev/null | grep lite)" ] && module_dir="/data/adb/lite_modules/mosdns"

# 数据目录
data_dir="/data/adb/Mosdns"
scripts_dir="$data_dir/scripts"
log_file="$data_dir/log/mosdns_server.log"

# 确保目录存在
mkdir -p "$data_dir/log" "$data_dir/cron"

# 初始化日志
echo "==== MosDNS 服务启动 [$(date '+%Y-%m-%d %H:%M:%S')] ====" > "$log_file"
echo "模块目录: $module_dir" >> "$log_file"
echo "脚本目录: $scripts_dir" >> "$log_file"

# 导入配置
settings_file="$data_dir/setting.conf"
if [ -f "$settings_file" ]; then
    # 安全地读取配置
    grep -E '^[[:space:]]*[[:alpha:]_][[:alnum:]_]*=' "$settings_file" > "${settings_file}.tmp"
    . "${settings_file}.tmp"
    rm -f "${settings_file}.tmp"
    
    # 清理配置值
    MOSDNS_PORT=$(echo "$MOSDNS_PORT" | tr -d '[:space:]')
    ENABLE_IPTABLES=$(echo "$ENABLE_IPTABLES" | tr -d '[:space:]')
    ENABLE_CRONTAB=$(echo "$ENABLE_CRONTAB" | tr -d '[:space:]')
    CRON_SCHEDULE=$(echo "$CRON_SCHEDULE" | tr -d '[:space:]')
fi

# 设置默认值
MOSDNS_PORT="${MOSDNS_PORT:-5335}"
ENABLE_IPTABLES="${ENABLE_IPTABLES:-true}"
ENABLE_CRONTAB="${ENABLE_CRONTAB:-false}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 8,21 * * *}"

# 调试信息
echo "配置参数:" >> "$log_file"
echo "MOSDNS_PORT: $MOSDNS_PORT" >> "$log_file"
echo "ENABLE_IPTABLES: $ENABLE_IPTABLES" >> "$log_file"
echo "ENABLE_CRONTAB: $ENABLE_CRONTAB" >> "$log_file"
echo "CRON_SCHEDULE: $CRON_SCHEDULE" >> "$log_file"

# 启动服务函数
start_service() {
    echo "启动 MosDNS 服务..." >> "$log_file"
    sh "$scripts_dir/start.sh" >> "$log_file" 2>&1
    
    if [ $? -eq 0 ] && [ -f "$data_dir/mosdns.pid" ]; then
        echo "MosDNS 服务启动成功" >> "$log_file"
        return 0
    else
        echo "MosDNS 服务启动失败" >> "$log_file"
        return 1
    fi
}

# 停止服务函数
stop_service() {
    echo "停止 MosDNS 服务..." >> "$log_file"
    sh "$scripts_dir/stop.sh" >> "$log_file" 2>&1
    
    if [ "$ENABLE_IPTABLES" = "true" ]; then
        echo "禁用 iptables DNS 转发..." >> "$log_file"
        sh "$scripts_dir/iptables.sh" disable >> "$log_file" 2>&1
    fi
    
    # 停止定时任务
    if [ -f "/data/adb/ksud" ]; then
        busybox="/data/adb/ksu/bin/busybox"
    elif [ -f "/data/adb/ap/bin/busybox" ]; then
        busybox="/data/adb/ap/bin/busybox"
    else
        busybox="$(magisk --path)/.magisk/busybox/busybox"
    fi
    $busybox pkill -f "crond -c $data_dir/cron/"
}

# 主服务逻辑
(
    # 等待系统启动完成
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 5
        echo "等待系统启动..." >> "$log_file"
    done
    
    # 额外等待确保网络就绪
    sleep 10
    
    # 等待网络路由表就绪
    while [ ! -f /data/misc/net/rt_tables ]; do
        sleep 3
        echo "等待网络路由表就绪..." >> "$log_file"
    done
    
    # 开机启动时清理旧文件
    echo "清理旧文件..." >> "$log_file"
    : > "$log_file"  # 清空日志文件
    rm -f "$data_dir/mosdns.pid"  # 删除PID文件
    rm -f "$data_dir/cron/root"  # 清理cron目录
    
    # 检查模块是否被禁用
    if [ -f "$module_dir/disable" ]; then
        echo "模块已被禁用，跳过启动" >> "$log_file"
        # 更新模块状态为已停止
        if [ -f "$scripts_dir/update_status.sh" ]; then
            sh "$scripts_dir/update_status.sh" --status STOPPED >> "$log_file" 2>&1
        fi
        exit 0
    fi
    
    # 启动服务
    start_service
)&

# 启动模块状态监控 - 轮询检查 disable 文件
(
    # 等待服务启动完成
    sleep 10
    
    while true; do
        # 检查模块是否被禁用
        if [ -f "$module_dir/disable" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 检测到模块被禁用，停止服务..." >> "$log_file"
            
            # 停止 MosDNS 服务
            sh "$scripts_dir/stop.sh" >> "$log_file" 2>&1
            
            # 更新模块状态为已停止
            if [ -f "$scripts_dir/update_status.sh" ]; then
                sh "$scripts_dir/update_status.sh" --status STOPPED >> "$log_file" 2>&1
            fi
            
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服务已停止，监控进程退出" >> "$log_file"
            exit 0
        fi
        
        # 每5秒检查一次
        sleep 5
    done
)&

echo "MosDNS 服务监控初始化完成" >> "$log_file"
exit 0