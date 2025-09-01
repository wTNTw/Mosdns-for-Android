#!/system/bin/sh

SKIPUNZIP=1

ui_print "***************************************"
ui_print "    MosDNS 模块安装脚本"
ui_print "***************************************"

ui_print "- 检测系统环境..."
ROOT_TYPE="Unknown"

if [ -f "/data/adb/ksud" ]; then
    ui_print "- 检测到 KernelSU 环境"
    ROOT_TYPE="KernelSU"
elif [ -f "/data/adb/magisk" ]; then
    ui_print "- 检测到 Magisk 环境"
    ROOT_TYPE="Magisk"
elif [ -f "/data/adb/apd" ] || command -v apd >/dev/null 2>&1; then
    ui_print "- 检测到 Apatch 环境"
    ROOT_TYPE="Apatch"
elif [ -f "/system/bin/su" ] || [ -f "/system/xbin/su" ]; then
    ui_print "- 检测到传统 root 环境"
    ROOT_TYPE="Traditional"
else
    ui_print "! 警告: 未检测到支持的 root 环境，使用兼容模式"
    ROOT_TYPE="Unknown"
fi

ui_print "- 最终检测结果: $ROOT_TYPE"

# 检查是否是升级安装（模块目录存在且包含有效文件）
UPGRADE_INSTALL=false
if [ -d "$MODPATH" ]; then
    # 检查是否包含模块相关文件（非空目录）
    if [ -f "$MODPATH/module.prop" ] || [ -f "$MODPATH/service.sh" ] || [ -f "$MODPATH/setting.conf" ]; then
        UPGRADE_INSTALL=true
    fi
fi

if [ "$UPGRADE_INSTALL" = true ]; then
    ui_print "- 检查正在运行的 MosDNS 进程..."
    if pgrep -f "mosdns" >/dev/null; then
        ui_print "- 停止正在运行的 MosDNS 进程..."
        pkill -f "mosdns"
        sleep 2
    fi

    ui_print "- 发现现有安装，是否保留旧配置？"
    ui_print "- （音量上键 = 是, 音量下键 = 否）"
    key_click=""
    while [ "$key_click" = "" ]; do
        key_click="$(getevent -qlc 1 | awk '{ print $3 }' | grep 'KEY_')"
        sleep 0.2
    done
    case "$key_click" in
    "KEY_VOLUMEUP")
        ui_print "- 保留原来的配置文件和 bin 文件夹"
        ui_print "- 更新其他所有文件和脚本"
        # 备份旧的 setting.conf 和 bin 文件夹
        BACKUP_DIR="$MODPATH/bin/backup"
        mkdir -p "$BACKUP_DIR"
        cp -f "$MODPATH/setting.conf" "$BACKUP_DIR/setting.conf.bak" 2>/dev/null
        cp -rf "$MODPATH/bin" "$BACKUP_DIR/bin.bak" 2>/dev/null
        
        # 解压所有文件，但排除 setting.conf 和 bin 文件夹
        unzip -o "$ZIPFILE" -x "setting.conf" "bin/*" -d $MODPATH >/dev/null 2>&1
        
        # 恢复旧的 setting.conf 和 bin 文件夹
        cp -f "$BACKUP_DIR/setting.conf.bak" "$MODPATH/setting.conf" 2>/dev/null
        cp -rf "$BACKUP_DIR/bin.bak" "$MODPATH/bin" 2>/dev/null
        rm -rf "$BACKUP_DIR"
        ;;
    *)
        ui_print "- 使用新的配置文件"
        BACKUP_DIR="$MODPATH/bin/backup"
        mkdir -p "$BACKUP_DIR"
        cp -f "$MODPATH/setting.conf" "$BACKUP_DIR/setting.conf.bak" 2>/dev/null
        cp -f "$MODPATH/config.yaml" "$BACKUP_DIR/config.yaml.bak" 2>/dev/null
        ui_print "- 旧配置已备份到 $BACKUP_DIR"
        
        # 清理旧文件并重新解压所有文件
        rm -rf "$MODPATH"/*
        unzip -o "$ZIPFILE" -d $MODPATH >/dev/null 2>&1
        ;;
    esac
else
    ui_print "- 第一次安装，清理并创建目录..."
    # 确保目录完全干净
    rm -rf "$MODPATH"/*
    mkdir -p "$MODPATH/log" "$MODPATH/cron" "$MODPATH/scripts" "$MODPATH/bin" "$MODPATH/update"
    
    # 使用默认配置文件进行全新安装
    ui_print "- 使用默认配置文件进行全新安装"
    unzip -o "$ZIPFILE" -d $MODPATH >/dev/null 2>&1
fi

ui_print "- 创建模块目录结构..."
mkdir -p "$MODPATH/log" "$MODPATH/cron" "$MODPATH/scripts" "$MODPATH/bin/backup" "$MODPATH/update"
touch "$MODPATH/log/mosdns_server.log"

ui_print "- 设置文件权限..."

for dir in log cron; do
    find "$MODPATH/$dir" -type f -exec chmod 644 {} \; 2>/dev/null
done

ui_print "- 设置可执行文件权限..."
for file in "$MODPATH/service.sh" "$MODPATH/uninstall.sh" "$MODPATH/action.sh" \
            "$MODPATH/customize.sh" "$MODPATH/bin/mosdns" "$MODPATH/bin/keycheck" \
            "$MODPATH/update/curl"; do
    if [ -f "$file" ]; then
        chmod 755 "$file" 2>/dev/null
        ui_print "  - 设置可执行: $(basename "$file")"
    fi
done

ui_print "- 设置脚本执行权限..."
for script in start.sh stop.sh update_status.sh update_files.sh iptables.sh; do
    if [ -f "$MODPATH/scripts/$script" ]; then
        chmod 755 "$MODPATH/scripts/$script"
        ui_print "  - 设置可执行: scripts/$script"
    fi
done

# 设置配置文件权限
ui_print "- 设置配置文件权限..."
for config_file in "$MODPATH/setting.conf" "$MODPATH/config.yaml"; do
    if [ -f "$config_file" ]; then
        chmod 644 "$config_file" 2>/dev/null
        ui_print "  - 设置权限: $(basename "$config_file")"
    fi
done

if [ "$ROOT_TYPE" = "KernelSU" ]; then
    ui_print "- 配置 KernelSU 启动脚本..."
    SERVICE_DIR="/data/adb/service.d"
    mkdir -p "$SERVICE_DIR"
    
    cat > "$SERVICE_DIR/mosdns_service.sh" <<EOF
#!/system/bin/sh

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

if [ "$ROOT_TYPE" = "Magisk" ]; then
    ui_print "- 配置 Magisk 启动环境..."
    chmod 755 "$MODPATH/service.sh"
fi

if [ "$ROOT_TYPE" = "Apatch" ]; then
    ui_print "- 按照 APM 指南配置 Apatch 模块..."
    chmod 755 "$MODPATH/service.sh"
    ui_print "- 设置 Apatch 特定文件权限..."
    
    for script in service.sh uninstall.sh action.sh customize.sh; do
        if [ -f "$MODPATH/$script" ]; then
            chmod 755 "$MODPATH/$script"
            ui_print "  - 设置可执行: $script"
        fi
    done
    
    if [ -d "$MODPATH/scripts" ]; then
        for script in "$MODPATH/scripts"/*.sh; do
            if [ -f "$script" ]; then
                chmod 755 "$script"
                ui_print "  - 设置可执行: scripts/$(basename "$script")"
            fi
        done
    fi
    
    if [ -f "$MODPATH/bin/mosdns" ]; then
        chmod 755 "$MODPATH/bin/mosdns"
        ui_print "  - 设置可执行: bin/mosdns"
    fi
    
    ui_print "- Apatch 模块配置完成"
    ui_print "- 模块将使用标准 service.sh 机制启动"
fi

# 安装完成提示
ui_print ""
ui_print "***************************************"
ui_print "       安装完成!"
ui_print "***************************************"
ui_print "- 模块路径: $MODPATH"
ui_print "- 配置文件: $MODPATH/config.yaml"
ui_print "- 设置文件: $MODPATH/setting.conf"
ui_print "- 日志文件: $MODPATH/log/mosdns_server.log"
ui_print ""
ui_print "使用说明:"
ui_print "1. 编辑 $MODPATH/config.yaml 配置 DNS 规则"
ui_print "2. 编辑 $MODPATH/setting.conf 自定义模块设置"
ui_print "3. 重启设备使配置生效"
ui_print "4. 使用终端命令或模块界面管理服务"
ui_print ""
ui_print "常用命令:"
ui_print "启动: sh $MODPATH/scripts/start.sh"
ui_print "停止: sh $MODPATH/scripts/stop.sh"
ui_print "状态: sh $MODPATH/scripts/iptables.sh status"
ui_print "***************************************"

exit 0