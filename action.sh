#!/system/bin/sh

MODDIR="/data/adb/modules/mosdns"
SCRIPTS_DIR="$MODDIR/scripts"
LOG_FILE="$MODDIR/log/mosdns_server.log"
TMP_MENU="/dev/key_tmp"
KEYCHECK="$MODDIR/bin/keycheck"
UPDATE_SCRIPT="$SCRIPTS_DIR/update_files.sh"
LAST_UPDATE_FILE="$MODDIR/log/last_update_time"
PID_FILE="$MODDIR/mosdns.pid"
METRICS_URL="http://127.0.0.1:5336/metrics"
CACHE_FILE="$MODDIR/log/metrics_cache"
CACHE_TIMEOUT=2

# 设置UTF-8环境
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 检查依赖
check_dependencies() {
    for cmd in curl bc awk stat; do
        command -v $cmd >/dev/null || {
            echo "缺少依赖: $cmd，请安装后重试"
            exit 1
        }
    done
}

# 美化菜单框
draw_box() {
    # 根据截图精确调整的宽度设置
    local box_width=80    # 总显示宽度
    local inner_width=79  # 内容区宽度
    
    # 装饰字符
    local border_h="-"    # 水平线
    local corner_tl="+"   # 左上角
    local corner_tr="+"   # 右上角
    local corner_bl="+"   # 左下角
    local corner_br="+"   # 右下角
    local menu_prefix="[ ]" # 菜单项前缀

    # 顶部装饰线
    echo ""
    echo "# 执行"
    echo ""
    echo "$corner_tl$(printf "%${inner_width}s" | tr ' ' "$border_h")$corner_tr"

    # 内容行处理
    while IFS= read -r line; do
        # 清理行内容
        line=$(echo "$line" | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
        
        # 计算显示宽度（中文算2字符，英文算1字符）
        display_width=$(echo "$line" | awk '{
            width = 0
            len = length($0)
            for (i=1; i<=len; i++) {
                c = substr($0,i,1)
                width += (c ~ /[^\x00-\x7F]/) ? 2 : 1
            }
            print width
        }')
        
        # 计算左右填充空格数
        total_padding=$((inner_width - display_width))
        left_padding=$((total_padding / 2))
        right_padding=$((total_padding - left_padding))
        
        # 特殊处理菜单项
        if [[ "$line" == *"MosDNS"* ]] || [[ "$line" == *"检查"* ]] || [[ "$line" == *"查看"* ]] || [[ "$line" == *"退出"* ]]; then
            line="$menu_prefix $line"
            # 重新计算带菜单前缀的宽度
            display_width=$(echo "$line" | awk '{
                width = 0
                len = length($0)
                for (i=1; i<=len; i++) {
                    c = substr($0,i,1)
                    width += (c ~ /[^\x00-\x7F]/) ? 2 : 1
                }
                print width
            }')
            total_padding=$((inner_width - display_width))
            left_padding=$((total_padding / 2))
            right_padding=$((total_padding - left_padding))
        fi
        
        # 打印居中内容行
        printf "%${left_padding}s%s%${right_padding}s\n" "" "$line" ""
    done <<EOF
$1
EOF

    # 底部装饰线
    echo "$corner_bl$(printf "%${inner_width}s" | tr ' ' "$border_h")$corner_br"
    echo ""
}

# 获取metrics
get_metrics() {
    if [ -f "$CACHE_FILE" ]; then
        CACHE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || date +%s -r "$CACHE_FILE")
        NOW=$(date +%s)
        [ $((NOW - CACHE_TIME)) -lt $CACHE_TIMEOUT ] && cat "$CACHE_FILE" && return
    fi

    METRICS=$(curl -s --connect-timeout 1 "$METRICS_URL")
    if [ $? -eq 0 ] && [ -n "$METRICS" ]; then
        echo "$METRICS" > "$CACHE_FILE"
        echo "$METRICS"
    elif [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo ""
    fi
}

# 状态信息获取
get_status_info() {
    [ -f "$PID_FILE" ] && STATUS_MSG="状态: 运行中 (PID: $(cat "$PID_FILE"))" || STATUS_MSG="状态: 已停止"
    [ -f "$LAST_UPDATE_FILE" ] && LAST_UPDATE_MSG="更新时间: $(cat "$LAST_UPDATE_FILE")" || LAST_UPDATE_MSG="更新时间: 未知"

    METRICS=$(get_metrics)

    if [ -n "$METRICS" ]; then
        # 显示启动时间（替代原来的运行时长）
        START_TIME=$(echo "$METRICS" | awk '/^process_start_time_seconds / {printf "%d", $2}')
        if [ -n "$START_TIME" ] && [ "$START_TIME" -gt 1600000000 ]; then  # 验证是合理时间戳（>2020年）
            START_STR=$(date -d "@$START_TIME" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$START_TIME" "+%Y-%m-%d %H:%M:%S")
            RUNTIME_MSG="启动时间: ${START_STR:-无效时间}"
        else
            RUNTIME_MSG="启动时间: --"
            echo "[ERROR] 无效启动时间: $START_TIME" >> "$LOG_FILE"
        fi

        # 内存占用计算
        RSS_MEM=$(echo "$METRICS" | awk '/^process_resident_memory_bytes / {print $2}')
        if [ -n "$RSS_MEM" ]; then
            MEM_MB=$(echo "$RSS_MEM" | awk '{printf "%.1f", $1/1024/1024}')
            MEM_MSG="内存占用: ${MEM_MB}MB"
        else
            MEM_MSG="内存占用: --.-MB"
        fi

        QUERY_TOTAL=$(echo "$METRICS" | awk '/^mosdns_plugin_cache_query_total / {print $2}')
        HIT_TOTAL=$(echo "$METRICS" | awk '/^mosdns_plugin_cache_hit_total / {print $2}')
        if [ -n "$QUERY_TOTAL" ]; then
            [ -n "$HIT_TOTAL" ] && HIT_RATE=$(echo "scale=1; $HIT_TOTAL*100/($QUERY_TOTAL+1)" | bc) && QUERY_MSG="查询统计: $QUERY_TOTAL (命中率: $HIT_RATE%)" || QUERY_MSG="查询统计: $QUERY_TOTAL"
        else
            QUERY_MSG="查询统计: 0"
        fi

        GOROUTINES=$(echo "$METRICS" | awk '/^go_goroutines / {print $2}')
        THREAD_MSG="协程数: ${GOROUTINES:---}"

        LATENCY_1MS=$(echo "$METRICS" | awk '/le="1"/ && /mosdns_plugin_collector_response_latency_millisecond_bucket/ {print $2}')
        LATENCY_COUNT=$(echo "$METRICS" | awk '/mosdns_plugin_collector_response_latency_millisecond_count/ {print $2}')
        if [ -n "$LATENCY_COUNT" ] && [ "$LATENCY_COUNT" -gt 0 ]; then
            FAST_RATE=$(echo "scale=1; $LATENCY_1MS*100/$LATENCY_COUNT" | bc)
            LATENCY_MSG="快速响应: ${FAST_RATE}% <1ms"
        else
            LATENCY_MSG="快速响应: --%"
        fi
    else
        RUNTIME_MSG="启动时间: --"
        MEM_MSG="内存占用: --.-MB"
        QUERY_MSG="查询统计: --"
        THREAD_MSG="协程数: --"
        LATENCY_MSG="快速响应: --%"
    fi

    # 一言处理
    if [ -f "$MODDIR/log/latest_yiyan.txt" ]; then
        YIYAN_CONTENT=$(head -n 1 "$MODDIR/log/latest_yiyan.txt" | tr -d '\r\n')
        TERM_WIDTH=42
        MAX_LEN=$((TERM_WIDTH - 10))
        if [ ${#YIYAN_CONTENT} -gt $MAX_LEN ]; then
            YIYAN_MSG="一言: ${YIYAN_CONTENT:0:$MAX_LEN}..."
        else
            YIYAN_MSG="一言: $YIYAN_CONTENT"
        fi
    else
        YIYAN_MSG="一言: 暂无"
    fi

    STATUS_DISPLAY="$STATUS_MSG
$LAST_UPDATE_MSG
$RUNTIME_MSG
$MEM_MSG
$QUERY_MSG
$THREAD_MSG
$LATENCY_MSG
$YIYAN_MSG"
}

# 显示菜单
show_menu() {
    clear
    get_status_info
    draw_box "$STATUS_DISPLAY"
    echo "  ↑ 确认选择   ↓ 导航菜单"
    echo ""

    i=1
    while IFS=':' read -r LABEL CMD; do
      ARROW="  "
      [ "$i" -eq "$INDEX" ] && ARROW="  ➤"
      printf "%s %-36s\n" "$ARROW" "$LABEL"
      i=$((i + 1))
    done < "$TMP_MENU"
    echo ""
}

# 音量键检测
wait_for_key() {
    chmod +x "$KEYCHECK" 2>/dev/null
    local last_key=0 same_count=0 refresh_count=0 refresh_interval=10
    while :; do
        "$KEYCHECK"
        KEY=$?
        refresh_count=$((refresh_count + 1))
        [ $refresh_count -ge $refresh_interval ] && return 99

        if [ $KEY -ne $last_key ]; then
            last_key=$KEY
            same_count=1
            continue
        fi

        same_count=$((same_count + 1))
        if [ $same_count -ge 2 ]; then
            [ $KEY -eq 41 ] || [ $KEY -eq 42 ] && return $KEY
            same_count=0
        fi
        sleep 0.1
    done
}

# 更新操作
perform_update() {
    draw_box "正在检查更新..."
    if [ -x "$UPDATE_SCRIPT" ]; then
        sh "$UPDATE_SCRIPT" --now >> "$LOG_FILE" 2>&1
        [ $? -eq 0 ] && draw_box "✓ 更新成功完成" || draw_box "✗ 更新失败，请查看日志"
    else
        draw_box "⚠ 更新脚本不存在"
    fi
    sleep 2
}

# 初始化
check_dependencies
echo "
启动 MosDNS 服务:start.sh
停止 MosDNS 服务:stop.sh
检查更新:update_files.sh
查看日志:log
退出菜单:exit
" | sed '/^$/d' > "$TMP_MENU"

TOTAL=$(wc -l < "$TMP_MENU")
INDEX=1

# 主循环
while :; do
    show_menu
    wait_for_key
    key=$?

    case $key in
        42)
            SELECTED=$(sed -n "${INDEX}p" "$TMP_MENU")
            CMD=$(echo "$SELECTED" | cut -d: -f2)

            case "$CMD" in
                start.sh)
                    sh "$SCRIPTS_DIR/$CMD"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动服务" >> "$LOG_FILE"
                    draw_box "✓ MosDNS 服务已启动"
                    sleep 1
                    ;;
                stop.sh)
                    sh "$SCRIPTS_DIR/$CMD"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 停止服务" >> "$LOG_FILE"
                    draw_box "✗ MosDNS 服务已停止"
                    sleep 1
                    ;;
                update_files.sh)
                    perform_update
                    ;;
                log)
                    draw_box "最近日志内容"
                    tail -n 8 "$LOG_FILE" | while read -r line; do echo "  ${line:0:60}"; done
                    echo "按任意键返回..."
                    wait_for_key
                    ;;
                exit)
                    break
                    ;;
            esac
            ;;
        41)
            INDEX=$((INDEX % TOTAL + 1))
            ;;
        99)
            continue
            ;;
    esac
done

rm -f "$TMP_MENU" "$CACHE_FILE"
exit 0