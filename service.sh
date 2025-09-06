#!/system/bin/sh

# 检测 Magisk 版本以确定模块目录
module_dir="/data/adb/modules/mosdns"
[ -n "$(magisk -v 2>/dev/null | grep lite)" ] && module_dir="/data/adb/lite_modules/mosdns"

# 数据目录
data_dir="/data/adb/Mosdns"
log_file="$data_dir/log/mosdns_server.log"

# 确保目录存在
mkdir -p "$data_dir/log"

# 初始化日志
echo "==== MosDNS 服务启动 [$(date '+%Y-%m-%d %H:%M:%S')] ====" > "$log_file"
echo "模块目录: $module_dir" >> "$log_file"

# 主服务逻辑，仅负责开机启动
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
    rm -f "$data_dir/mosdns.pid"
    rm -f "$data_dir/cron/root"

    # 启动服务，全部交由 start.sh 处理
    sh "$data_dir/scripts/start.sh" >> "$log_file" 2>&1
)&

echo "MosDNS 服务开机启动流程完成" >> "$log_file"
exit 0