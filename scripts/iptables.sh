#!/system/bin/sh

MODDIR="/data/adb/modules/mosdns"
DATADIR="/data/adb/Mosdns"
SETTINGS_FILE="$DATADIR/setting.conf"

if [ -f "$SETTINGS_FILE" ]; then
    grep -E '^[[:space:]]*[[:alpha:]_][[:alnum:]_]*=' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    . "${SETTINGS_FILE}.tmp"
    rm -f "${SETTINGS_FILE}.tmp"
fi

MOSDNS_PORT="${MOSDNS_PORT:-5335}"

MOSDNS_PORT=$(echo "$MOSDNS_PORT" | tr -d '[:space:]')

ACTION="$1"

usage() {
    echo "DNS转发控制脚本"
    echo "使用方法:"
    echo "  $0 enable    # 启用DNS转发"
    echo "  $0 disable   # 禁用DNS转发"
    echo "  $0 status    # 查看当前状态"
    exit 1
}

enable_forward() {
    echo "[INFO] 启用DNS转发..."

    while iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$MOSDNS_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:$MOSDNS_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done

    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT

    echo "[SUCCESS] IPv4 DNS转发已启用 (REDIRECT) → 127.0.0.1:$MOSDNS_PORT"

    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done
        while ip6tables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done
        ip6tables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null
        ip6tables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null
        echo "[SUCCESS] IPv6 DNS转发已启用 (REDIRECT) → [::1]:$MOSDNS_PORT"
    else
        echo "[INFO] IPv6工具不可用，跳过IPv6 DNS转发"
    fi

    return 0
}

disable_forward() {
    echo "[INFO] 禁用DNS转发..."

    while iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:$MOSDNS_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:$MOSDNS_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done

    while ip6tables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done
    while ip6tables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $MOSDNS_PORT 2>/dev/null; do :; done
    while ip6tables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination [::1]:$MOSDNS_PORT 2>/dev/null; do :; done
    while ip6tables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination [::1]:$MOSDNS_PORT 2>/dev/null; do :; done

    echo "[INFO] 执行网络恢复措施..."

    if command -v ndc >/dev/null 2>&1; then
        echo "[INFO] 使用ndc刷新DNS缓存..."
        ndc resolver flushdefaultif || true
        ndc resolver clearnetdns || true
        for i in $(seq 0 10); do
            ndc resolver flushif wlan$i || true
            ndc resolver flushif rmnet$i || true
        done
    fi

    if command -v svc >/dev/null 2>&1; then
        echo "[INFO] 重启移动数据服务..."
        svc data disable || true
        sleep 2
        svc data enable || true
        sleep 1
    fi

    echo "[INFO] 清除系统DNS设置..."
    setprop net.dns1 "" || true
    setprop net.dns2 "" || true
    setprop net.dns3 "" || true
    setprop net.dns4 "" || true

    echo "[INFO] 重启网络守护进程..."
    killall -HUP netd 2>/dev/null || true
    pkill -f /system/bin/netd 2>/dev/null || true

    if command -v cmd >/dev/null 2>&1; then
        echo "[INFO] 使用cmd重启网络连接..."
        cmd connectivity restart-network 2>/dev/null || true
    fi

    if command -v service >/dev/null 2>&1; then
        echo "[INFO] 重启网络管理器服务..."
        service call connectivity 33 2>/dev/null || true
    fi

    echo "[INFO] 刷新网络路由和ARP缓存..."
    ip route flush cache 2>/dev/null || true
    ip -6 route flush cache 2>/dev/null || true
    ip neigh flush all 2>/dev/null || true

    echo "[INFO] 等待网络重新连接..."
    sleep 3

    echo "[SUCCESS] DNS转发已禁用，网络恢复完成"
    return 0
}

check_status() {
    echo "[INFO] 当前DNS转发状态:"
    local ipv4_enabled=0
    local ipv6_enabled=0

    if iptables -t nat -L OUTPUT -n 2>/dev/null | grep -q "REDIRECT.*$MOSDNS_PORT"; then
        ipv4_enabled=1
        echo "IPv4: ✅ 已启用 (REDIRECT)"
    else
        echo "IPv4: ❌ 未启用"
    fi

    if ip6tables -t nat -L OUTPUT -n 2>/dev/null | grep -q "REDIRECT.*$MOSDNS_PORT"; then
        ipv6_enabled=1
        echo "IPv6: ✅ 已启用 (REDIRECT)"
    else
        echo "IPv6: ❌ 未启用"
    fi

    if [ $ipv4_enabled -eq 1 ] || [ $ipv6_enabled -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

main() {
    case "$ACTION" in
        "enable")
            enable_forward
            ;;
        "disable")
            disable_forward
            ;;
        "status")
            check_status
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"

