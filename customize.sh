#!/system/bin/sh

SKIPUNZIP=0
MODPATH="data/adb/modules/mosdns"  # 兼容 Magisk 和 KernelSU 的模块路径

ui_print "***************************************"
ui_print " 三无 MosDNS 模块安装脚本 "
ui_print "***************************************"

# 初始化模块目录
mkdir -p "$MODPATH/log" "$MODPATH/cron.d" "$MODPATH/scripts"
touch "$MODPATH/log/mosdns_server.log" "$MODPATH/service.lock"

# 设置文件权限 (644)
for dir in log cron.d; do
    find "$MODPATH/$dir" -type f -exec chmod 644 {} \;
done

# 设置可执行文件权限 (755)
chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/uninstall.sh"
chmod 755 "$MODPATH/bin/mosdns"
chmod 755 "$MODPATH/bin/keycheck"
chmod 755 "$MODPATH/scripts/start.sh"
chmod 755 "$MODPATH/scripts/stop.sh"
chmod 755 "$MODPATH/scripts/update_files.sh"
chmod 755 "$MODPATH/scripts/update_status.sh"

# 设置脚本权限
for script in start.sh stop.sh update_status.sh update_files.sh; do
    [ -f "$MODPATH/scripts/$script" ] && chmod 755 "$MODPATH/scripts/$script"
done

# KernelSU 特殊处理
if [ -f "/data/adb/ksud" ]; then
    ui_print "- 检测到 KernelSU 环境"
    SERVICE_DIR="/data/adb/service.d"
    mkdir -p "$SERVICE_DIR"
    
    # 创建简化版开机启动脚本
    cat > "$SERVICE_DIR/mosdns_service.sh" <<EOF
#!/system/bin/sh

# MosDNS 模块的 KernelSU 启动桥接脚本
# 实际功能由模块主服务实现

MODDIR="$MODPATH"
MODULE_SERVICE="\$MODDIR/service.sh"

if [ -f "\$MODULE_SERVICE" ]; then
    sh "\$MODULE_SERVICE" "\$@"
else
    echo "错误：未找到 MosDNS 模块主服务脚本 (\$MODULE_SERVICE)" >&2
    exit 1
fi

exit 0
EOF

    chmod 755 "$SERVICE_DIR/mosdns_service.sh"
    ui_print "- 已创建 KernelSU 启动脚本: $SERVICE_DIR/mosdns_service.sh"
fi

# 安装完成提示
ui_print "- 文件权限设置完成"
ui_print "- 请重启设备以生效"
ui_print "***************************************"
ui_print " 提示：此模块为Mosdns V4版本，编辑 $MODPATH/config.yaml 配置DNS"
ui_print "***************************************"

exit 0