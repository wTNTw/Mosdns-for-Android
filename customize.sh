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

# 检查是否是升级安装（直接检测已安装的模块路径）
UPGRADE_INSTALL=false
INSTALLED_MODULE_PATH="/data/adb/modules/mosdns"
DATA_DIR="/data/adb/Mosdns"
if [ -d "$INSTALLED_MODULE_PATH" ]; then
    # 检查是否包含模块相关文件
    if [ -f "$INSTALLED_MODULE_PATH/module.prop" ] || [ -f "$INSTALLED_MODULE_PATH/service.sh" ] || [ -f "$INSTALLED_MODULE_PATH/setting.conf" ]; then
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
        ui_print "- 保留原来的配置文件和数据文件夹"
        ui_print "- 更新其他所有文件和脚本"
        # 备份旧的数据（从 /data/adb/Mosdns 或模块目录）
        BACKUP_DIR="$DATA_DIR/bin/backup"
        mkdir -p "$BACKUP_DIR"
        
        # 只备份配置文件 setting.conf 和 config.yaml
        if [ -d "$DATA_DIR" ]; then
            # 如果 DATA_DIR 存在，只备份其中的配置文件
            cp -f "$DATA_DIR/setting.conf" "$BACKUP_DIR/setting.conf.bak" 2>/dev/null
            cp -f "$DATA_DIR/config.yaml" "$BACKUP_DIR/config.yaml.bak" 2>/dev/null
        else
            # 否则备份模块目录中的配置文件
            cp -f "$MODPATH/setting.conf" "$BACKUP_DIR/setting.conf.bak" 2>/dev/null
            cp -f "$MODPATH/config.yaml" "$BACKUP_DIR/config.yaml.bak" 2>/dev/null
        fi
        
        # 解压所有文件，但排除需要移动的文件夹和文件
        unzip -o "$ZIPFILE" -x "setting.conf" "config.yaml" -d $MODPATH >/dev/null 2>&1
        
        # 恢复旧的配置文件
        cp -f "$BACKUP_DIR/setting.conf.bak" "$DATA_DIR/setting.conf" 2>/dev/null
        cp -f "$BACKUP_DIR/config.yaml.bak" "$DATA_DIR/config.yaml" 2>/dev/null
        rm -rf "$BACKUP_DIR"
        ;;
    *)
        ui_print "- 使用新的配置文件"
        # 备份旧的数据到 /data/adb/Mosdns/bin/backup
        BACKUP_DIR="$DATA_DIR/bin/backup"
        mkdir -p "$BACKUP_DIR"
        
        # 只备份配置文件 setting.conf 和 config.yaml
        if [ -d "$DATA_DIR" ]; then
            cp -f "$DATA_DIR/setting.conf" "$BACKUP_DIR/setting.conf.bak" 2>/dev/null
            cp -f "$DATA_DIR/config.yaml" "$BACKUP_DIR/config.yaml.bak" 2>/dev/null
        else
            cp -f "$MODPATH/setting.conf" "$BACKUP_DIR/setting.conf.bak" 2>/dev/null
            cp -f "$MODPATH/config.yaml" "$BACKUP_DIR/config.yaml.bak" 2>/dev/null
        fi
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
    mkdir -p "$MODPATH"
    
    # 使用默认配置文件进行全新安装
    ui_print "- 使用默认配置文件进行全新安装"
    unzip -o "$ZIPFILE" -d $MODPATH >/dev/null 2>&1
fi

ui_print "- 创建数据目录结构..."
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/log" "$DATA_DIR/cron" "$DATA_DIR/scripts" "$DATA_DIR/bin/backup" "$DATA_DIR/update" "$DATA_DIR/bin/rules"

# 复制文件夹和文件到 DATA_DIR，覆盖现有文件
cp -rf "$MODPATH/bin" "$DATA_DIR/" 2>/dev/null
cp -rf "$MODPATH/scripts" "$DATA_DIR/" 2>/dev/null
cp -rf "$MODPATH/update" "$DATA_DIR/" 2>/dev/null
cp -rf "$MODPATH/log" "$DATA_DIR/" 2>/dev/null
cp -rf "$MODPATH/cron" "$DATA_DIR/" 2>/dev/null
cp -f "$MODPATH/setting.conf" "$DATA_DIR/" 2>/dev/null
cp -f "$MODPATH/config.yaml" "$DATA_DIR/" 2>/dev/null

# 清理 MODPATH 中的文件，避免残留
rm -rf "$MODPATH/bin" "$MODPATH/scripts" "$MODPATH/update" "$MODPATH/log" "$MODPATH/cron" "$MODPATH/setting.conf" "$MODPATH/config.yaml" 2>/dev/null

touch "$DATA_DIR/log/mosdns_server.log"

ui_print "- 设置文件权限..."

# 设置 DATA_DIR 权限
chmod 755 "$DATA_DIR"
for dir in log cron bin scripts update bin/rules; do
    if [ -d "$DATA_DIR/$dir" ]; then
        find "$DATA_DIR/$dir" -type f -exec chmod 644 {} \; 2>/dev/null
    fi
done

ui_print "- 设置可执行文件权限..."
for file in "$MODPATH/service.sh" "$MODPATH/uninstall.sh" "$MODPATH/action.sh" \
            "$MODPATH/customize.sh" "$DATA_DIR/bin/mosdns" "$DATA_DIR/bin/keycheck" \
            "$DATA_DIR/update/curl"; do
    if [ -f "$file" ]; then
        chmod 755 "$file" 2>/dev/null
        ui_print "  - 设置可执行: $(basename "$file")"
    fi
done

ui_print "- 设置脚本执行权限..."
for script in start.sh stop.sh update_status.sh update_files.sh iptables.sh; do
    if [ -f "$DATA_DIR/scripts/$script" ]; then
        chmod 755 "$DATA_DIR/scripts/$script"
        ui_print "  - 设置可执行: scripts/$script"
    fi
done

# 设置配置文件权限
ui_print "- 设置配置文件权限..."
for config_file in "$DATA_DIR/setting.conf" "$DATA_DIR/config.yaml"; do
    if [ -f "$config_file" ]; then
        chmod 644 "$config_file" 2>/dev/null
        ui_print "  - 设置权限: $(basename "$config_file")"
    fi
done

# 为所有 root 环境创建服务脚本
ui_print "- 配置启动脚本..."
SERVICE_DIR="/data/adb/service.d"
mkdir -p "$SERVICE_DIR"

# 移动并重命名 service.sh 到 service.d 目录
if [ -f "$MODPATH/service.sh" ]; then
    mv "$MODPATH/service.sh" "$SERVICE_DIR/mosdns_service.sh"
    chmod 755 "$SERVICE_DIR/mosdns_service.sh"
    ui_print "- 已移动服务脚本到: $SERVICE_DIR/mosdns_service.sh"
else
    ui_print "! 警告: 未找到 service.sh 文件"
fi

# 为不同 root 环境设置特定配置
if [ "$ROOT_TYPE" = "KernelSU" ]; then
    ui_print "- 配置 KernelSU 启动环境..."
    # KernelSU 已经使用 service.d 机制，无需额外配置
elif [ "$ROOT_TYPE" = "Magisk" ]; then
    ui_print "- 配置 Magisk 启动环境..."
    # Magisk 使用 service.d 机制，无需额外配置
elif [ "$ROOT_TYPE" = "Apatch" ]; then
    ui_print "- 按照 APM 指南配置 Apatch 模块..."
    ui_print "- 设置 Apatch 特定文件权限..."
    
    for script in uninstall.sh action.sh customize.sh; do
        if [ -f "$MODPATH/$script" ]; then
            chmod 755 "$MODPATH/$script"
            ui_print "  - 设置可执行: $script"
        fi
    done
    
    if [ -d "$DATA_DIR/scripts" ]; then
        for script in "$DATA_DIR/scripts"/*.sh; do
            if [ -f "$script" ]; then
                chmod 755 "$script"
                ui_print "  - 设置可执行: scripts/$(basename "$script")"
            fi
        done
    fi
    
    if [ -f "$DATA_DIR/bin/mosdns" ]; then
        chmod 755 "$DATA_DIR/bin/mosdns"
        ui_print "  - 设置可执行: bin/mosdns"
    fi
    
    ui_print "- Apatch 模块配置完成"
    ui_print "- 模块将使用 service.d 机制启动"
fi

# 安装完成提示
ui_print ""
ui_print "***************************************"
ui_print "       安装完成!"
ui_print "***************************************"
ui_print "- 模块路径: $MODPATH"
ui_print "- 配置文件: $DATA_DIR/config.yaml"
ui_print "- 设置文件: $DATA_DIR/setting.conf"
ui_print "- 日志文件: $DATA_DIR/log/mosdns_server.log"
ui_print "- 数据目录: $DATA_DIR"
ui_print ""
ui_print "使用说明:"
ui_print "1. 编辑 $DATA_DIR/config.yaml 配置 DNS 规则"
ui_print "2. 编辑 $DATA_DIR/setting.conf 自定义模块设置"
ui_print "3. 重启设备使配置生效"
ui_print "4. 使用终端命令或模块界面管理服务"
ui_print ""
ui_print "常用命令:"
ui_print "启动: sh $DATA_DIR/scripts/start.sh"
ui_print "停止: sh $DATA_DIR/scripts/stop.sh"
ui_print "状态: sh $DATA_DIR/scripts/iptables.sh status"
ui_print "***************************************"

exit 0