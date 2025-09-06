#!/system/bin/sh

MODDIR="/data/adb/modules/mosdns"
DATADIR="/data/adb/Mosdns"
SCRIPTS_DIR="$DATADIR/scripts"
LOG_FILE="$DATADIR/log/mosdns_server.log"
TMP_MENU="/dev/key_tmp"
KEYCHECK="$DATADIR/bin/keycheck"
UPDATE_SCRIPT="$SCRIPTS_DIR/update_files.sh"
LAST_UPDATE_FILE="$DATADIR/log/last_update_time"
PID_FILE="$DATADIR/mosdns.pid"
METRICS_URL="http://127.0.0.1:5336/metrics"
CACHE_FILE="$DATADIR/log/metrics_cache"
CACHE_TIMEOUT=2

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

check_dependencies() {
    for cmd in curl bc awk stat; do
        command -v $cmd >/dev/null || {
            echo "缺少依赖: $cmd，请安装后重试"
            exit 1
        }
    done
}

draw_box() {
    local box_width=80
    local inner_width=79
    local border_h="-"
    local corner_tl="+"
    local corner_tr="+"
    local corner_bl="+"
    local corner_br="+"
    local menu_prefix="[ ]"

    echo ""
    echo "# 执行"
    echo ""
    echo "$corner_tl$(printf "%${inner_width}s" | tr ' ' "$border_h")$corner_tr"

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
        if [[ "$line" == *"MosDNS"* ]] || [[ "$line" == *"检查"* ]] || [[ "$line" == *"查看"* ]] || [[ "$line" == *"退出"* ]]; then
            line="$menu_prefix $line"
        fi
        printf "  %s\n" "$line"
    done <<EOF
$1
EOF

    echo "$corner_bl$(printf "%${inner_width}s" | tr ' ' "$border_h")$corner_br"
    echo ""
}

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

get_status_info() {
    [ -f "$PID_FILE" ] && STATUS_MSG="状态: 运行中 (PID: $(cat "$PID_FILE"))" || STATUS_MSG="状态: 已停止"
    [ -f "$LAST_UPDATE_FILE" ] && LAST_UPDATE_MSG="更新时间: $(cat "$LAST_UPDATE_FILE")" || LAST_UPDATE_MSG="更新时间: 未知"
    AUTO_UPDATE_MSG="自动更新: $CRONTAB_STATUS"

    METRICS=$(get_metrics)

    if [ -n "$METRICS" ]; then
        START_TIME=$(echo "$METRICS" | awk '/^process_start_time_seconds / {printf "%d", $2}')
        if [ -n "$START_TIME" ] && [ "$START_TIME" -gt 1600000000 ]; then
            START_STR=$(date -d "@$START_TIME" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$START_TIME" "+%Y-%m-%d %H:%M:%S")
            RUNTIME_MSG="启动时间: ${START_STR:-无效时间}"
        else
            RUNTIME_MSG="启动时间: --"
            echo "[ERROR] 无效启动时间: $START_TIME" >> "$LOG_FILE"
        fi

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

    if [ -f "$DATADIR/log/latest_yiyan.txt" ]; then
        YIYAN_CONTENT=$(head -n 1 "$DATADIR/log/latest_yiyan.txt" | tr -d '\r\n')
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
$YIYAN_MSG
$AUTO_UPDATE_MSG"
}

show_menu() {
    clear
    read_settings
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

check_dependencies

read_settings() {
    SETTINGS_FILE="$DATADIR/setting.conf"
    if [ -f "$SETTINGS_FILE" ]; then
        grep -E '^[[:space:]]*[[:alpha:]_][[:alnum:]_]*=' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        . "${SETTINGS_FILE}.tmp"
        rm -f "${SETTINGS_FILE}.tmp"
    fi

    ENABLE_IPTABLES="${ENABLE_IPTABLES:-true}"
    IPTABLES_STATUS=$([ "$ENABLE_IPTABLES" = "true" ] && echo "启用" || echo "禁用")
    ENABLE_CRONTAB="${ENABLE_CRONTAB:-true}"
    CRONTAB_STATUS=$([ "$ENABLE_CRONTAB" = "true" ] && echo "启用" || echo "禁用")
}

read_settings

echo "
启动 MosDNS 服务:start.sh
停止 MosDNS 服务:stop.sh
启用 iptables DNS 转发:enable_iptables
禁用 iptables DNS 转发:disable_iptables
启用自动更新:enable_autoupdate
禁用自动更新:disable_autoupdate
检查更新:update_files.sh
查看日志:log
退出菜单:exit
" | sed '/^$/d' > "$TMP_MENU"

TOTAL=$(wc -l < "$TMP_MENU")
INDEX=1

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
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过菜单启动服务" >> "$LOG_FILE"
                    draw_box "✓ MosDNS 服务已启动"
                    sleep 1
                    ;;
                stop.sh)
                    sh "$SCRIPTS_DIR/$CMD"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过菜单停止服务" >> "$LOG_FILE"
                    draw_box "✗ MosDNS 服务已停止"
                    sleep 1
                    ;;
                enable_iptables)
                    if [ -f "$SETTINGS_FILE" ]; then
                        if grep -q "ENABLE_IPTABLES" "$SETTINGS_FILE"; then
                            sed -i 's/^ENABLE_IPTABLES=.*/ENABLE_IPTABLES=true/' "$SETTINGS_FILE"
                        else
                            echo "ENABLE_IPTABLES=true" >> "$SETTINGS_FILE"
                        fi
                        draw_box "✓ iptables DNS 转发已启用"
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过菜单启用 iptables" >> "$LOG_FILE"
                        read_settings
                    else
                        draw_box "✗ 配置文件不存在"
                    fi
                    sleep 1
                    ;;
                disable_iptables)
                    if [ -f "$SETTINGS_FILE" ]; then
                        if grep -q "ENABLE_IPTABLES" "$SETTINGS_FILE"; then
                            sed -i 's/^ENABLE_IPTABLES=.*/ENABLE_IPTABLES=false/' "$SETTINGS_FILE"
                        else
                            echo "ENABLE_IPTABLES=false" >> "$SETTINGS_FILE"
                        fi
                        draw_box "✗ iptables DNS 转发已禁用"
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过菜单禁用 iptables" >> "$LOG_FILE"
                        read_settings
                    else
                        draw_box "✗ 配置文件不存在"
                    fi
                    sleep 1
                    ;;
                enable_autoupdate)
                    if [ -f "$SETTINGS_FILE" ]; then
                        if grep -q "ENABLE_CRONTAB" "$SETTINGS_FILE"; then
                            sed -i 's/^ENABLE_CRONTAB=.*/ENABLE_CRONTAB=true/' "$SETTINGS_FILE"
                        else
                            echo "ENABLE_CRONTAB=true" >> "$SETTINGS_FILE"
                        fi
                        draw_box "✓ 自动更新已启用"
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过菜单启用自动更新" >> "$LOG_FILE"
                        read_settings
                    else
                        draw_box "✗ 配置文件不存在"
                    fi
                    sleep 1
                    ;;
                disable_autoupdate)
                    if [ -f "$SETTINGS_FILE" ]; then
                        if grep -q "ENABLE_CRONTAB" "$SETTINGS_FILE"; then
                            sed -i 's/^ENABLE_CRONTAB=.*/ENABLE_CRONTAB=false/' "$SETTINGS_FILE"
                        else
                            echo "ENABLE_CRONTAB=false" >> "$SETTINGS_FILE"
                        fi
                        draw_box "✗ 自动更新已禁用"
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过菜单禁用自动更新" >> "$LOG_FILE"
                        read_settings
                    else
                        draw_box "✗ 配置文件不存在"
                    fi
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