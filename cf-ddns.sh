#!/usr/bin/env bash
# ====================================================
# Cloudflare 轻量级 DDNS 脚本 (免 ZoneID / 仅需邮箱+域名+Token / 按秒定时)
# ====================================================

# 确保 HOME 变量在 Systemd 或特殊环境下始终有效
if [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
    HOME=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)
    [ -z "$HOME" ] && HOME="/root"
fi

CONFIG_DIR="${CONFIG_DIR:-$HOME/.cf_ddns}"
CONFIG_FILE="$CONFIG_DIR/config.conf"
INTERVAL_FILE="$CONFIG_DIR/interval.conf"
LOG_FILE="$CONFIG_DIR/ddns.log"
IP_CACHE_FILE="$CONFIG_DIR/last_ip.txt"
LAST_CHECK_FILE="$CONFIG_DIR/last_check.txt"
PID_FILE="$CONFIG_DIR/ddns.pid"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SERVICE_FILE="/etc/systemd/system/cf-ddns.service"

mkdir -p "$CONFIG_DIR"

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# 按任意键返回提示
pause_return() {
    echo ""
    echo -ne "${YELLOW}按任意键返回菜单...${RESET}"
    if ! read -r -n 1 -s _; then
        read -r _
    fi
    echo ""
}

# 写入日志 (自动保留最近200行)
log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 200 ]; then
        tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

# 统一封装 Cloudflare API 请求 (自动兼容新版 Bearer Token 与 Email+Key)
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local auth_mode="${AUTH_MODE:-Bearer}"

    if [ "$auth_mode" = "Bearer" ]; then
        if [ -n "$data" ]; then
            curl -s -X "$method" "https://api.cloudflare.com/client/v4${endpoint}" \
                -H "Authorization: Bearer ${CF_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "$data"
        else
            curl -s -X "$method" "https://api.cloudflare.com/client/v4${endpoint}" \
                -H "Authorization: Bearer ${CF_TOKEN}" \
                -H "Content-Type: application/json"
        fi
    else
        if [ -n "$data" ]; then
            curl -s -X "$method" "https://api.cloudflare.com/client/v4${endpoint}" \
                -H "X-Auth-Email: ${CF_EMAIL}" \
                -H "X-Auth-Key: ${CF_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "$data"
        else
            curl -s -X "$method" "https://api.cloudflare.com/client/v4${endpoint}" \
                -H "X-Auth-Email: ${CF_EMAIL}" \
                -H "X-Auth-Key: ${CF_TOKEN}" \
                -H "Content-Type: application/json"
        fi
    fi
}

# 获取本机公网 IP
get_public_ip() {
    local type="$1"
    local ip=""
    if [ "$type" = "AAAA" ]; then
        for url in "https://ipv6.icanhazip.com" "https://api6.ipify.org" "https://v6.ident.me"; do
            ip=$(curl -s -6 --max-time 4 "$url" | tr -d '[:space:]')
            [ -n "$ip" ] && break
        done
    else
        for url in "https://ipv4.icanhazip.com" "https://api.ipify.org" "https://ident.me"; do
            ip=$(curl -s -4 --max-time 4 "$url" | tr -d '[:space:]')
            [ -n "$ip" ] && break
        done
    fi
    echo "$ip"
}

# 验证配置信息并保存 (供初次配置与单项修改共用)
verify_and_save_config() {
    local v_email="$1"
    local v_domain="$2"
    local v_token="$3"
    local v_type="$4"
    local v_proxy="$5"

    CF_EMAIL="$v_email"
    CF_TOKEN="$v_token"
    AUTH_MODE="Bearer"

    echo -e "${YELLOW}正在通过 Token 自动验证并定位域名信息...${RESET}"

    # 验证新版 Bearer Token 是否有效，若无效则尝试 Email + Global Key 兼容模式
    local test_resp
    test_resp=$(cf_api "GET" "/zones?per_page=1")
    if ! echo "$test_resp" | grep -q '"success":true'; then
        AUTH_MODE="Key"
        test_resp=$(cf_api "GET" "/zones?per_page=1")
        if ! echo "$test_resp" | grep -q '"success":true'; then
            echo -e "${RED}验证失败！请检查邮箱或 Token 是否正确，或是否包含 DNS 编辑权限。${RESET}"
            return 1
        fi
    fi

    # 自动从完整域名逐级向上匹配所属主域名，免去手动输入 Zone ID
    local candidate="$v_domain"
    local zone_id=""
    local zone_name=""
    local zone_resp

    while [ "${candidate#*.}" != "$candidate" ]; do
        zone_resp=$(cf_api "GET" "/zones?name=${candidate}")
        zone_id=$(echo "$zone_resp" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -n "$zone_id" ]; then
            zone_name="$candidate"
            break
        fi
        candidate="${candidate#*.}"
    done

    if [ -z "$zone_id" ]; then
        echo -e "${RED}未能自动匹配到域名 ${v_domain} 所属的站点，请确认该域名已托管在当前 Cloudflare 账号或 Token 权限范围内！${RESET}"
        return 1
    fi

    # 自动查询现有解析记录 ID
    local record_resp record_id
    record_resp=$(cf_api "GET" "/zones/${zone_id}/dns_records?type=${v_type}&name=${v_domain}")
    record_id=$(echo "$record_resp" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)

    cat > "$CONFIG_FILE" <<EOF
CF_EMAIL="${v_email}"
CF_TOKEN="${v_token}"
AUTH_MODE="${AUTH_MODE}"
ZONE_NAME="${zone_name}"
ZONE_ID="${zone_id}"
RECORD_NAME="${v_domain}"
RECORD_TYPE="${v_type}"
RECORD_ID="${record_id}"
PROXIED="${v_proxy}"
EOF
    chmod 600 "$CONFIG_FILE"
    rm -f "$IP_CACHE_FILE"

    echo -e "${GREEN}验证成功！已自动绑定主域名: ${zone_name}${RESET}"
    if [ -n "$record_id" ]; then
        echo -e "${GREEN}已自动关联现有 ${v_type} 记录: ${v_domain}${RESET}"
    else
        echo -e "${YELLOW}当前尚无 ${v_domain} (${v_type}) 记录，将在同步时自动创建。${RESET}"
    fi

    # 立即执行一次同步
    update_ddns "interactive"
    return 0
}

# 交互式全新配置向导
configure_ddns() {
    echo -e "\n${CYAN}--- 初次配置 Cloudflare DDNS (免 Zone ID 新模式) ---${RESET}"
    read -rp "1. 请输入 Cloudflare 邮箱: " input_email
    read -rp "2. 请输入 DDNS 域名 (如 ddns.example.com): " input_domain
    read -rp "3. 请输入 Cloudflare API Token: " input_token

    input_email=$(echo "$input_email" | tr -d '[:space:]')
    input_domain=$(echo "$input_domain" | tr -d '[:space:]')
    input_token=$(echo "$input_token" | tr -d '[:space:]')

    if [ -z "$input_email" ] || [ -z "$input_domain" ] || [ -z "$input_token" ]; then
        echo -e "${RED}错误：邮箱、域名和 Token 均不能为空！${RESET}"
        return 1
    fi

    read -rp "解析类型 [1: IPv4(默认) / 2: IPv6]: " type_choice
    [ "$type_choice" = "2" ] && input_type="AAAA" || input_type="A"

    read -rp "是否开启小黄云 CDN 代理 [1: 关闭(默认) / 2: 开启]: " proxy_choice
    [ "$proxy_choice" = "2" ] && input_proxy="true" || input_proxy="false"

    verify_and_save_config "$input_email" "$input_domain" "$input_token" "$input_type" "$input_proxy"
}

# 二级菜单：按需修改现有配置
modify_config_menu() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "\n${RED}当前尚未配置 DDNS，请先在主菜单选择 [1] 完成初次配置！${RESET}"
        pause_return
        return 1
    fi

    while true; do
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"

        local proxy_status_str
        if [ "$PROXIED" = "true" ]; then
            proxy_status_str="${GREEN}开启 (true)${RESET}"
        else
            proxy_status_str="${YELLOW}关闭 (false)${RESET}"
        fi

        local masked_token="已配置"
        if [ ${#CF_TOKEN} -gt 8 ]; then
            masked_token="${CF_TOKEN:0:4}****${CF_TOKEN: -4}"
        fi

        echo -e "\n${CYAN}=========================================${RESET}"
        echo -e "${CYAN}          修改 DDNS 配置 (二级菜单)      ${RESET}"
        echo -e "${CYAN}=========================================${RESET}"
        echo -e "  1. 修改 Cloudflare 邮箱  [当前: ${YELLOW}${CF_EMAIL}${RESET}]"
        echo -e "  2. 修改 DDNS 域名        [当前: ${GREEN}${RECORD_NAME}${RESET}]"
        echo -e "  3. 修改 API Token        [当前: ${YELLOW}${masked_token}${RESET}]"
        echo -e "  4. 切换解析类型 (A/AAAA) [当前: ${CYAN}${RECORD_TYPE}${RESET}]"
        echo -e "  5. 切换小黄云 CDN 开关   [当前: ${proxy_status_str}]"
        echo -e "  0. 返回主菜单"
        echo -e "${CYAN}=========================================${RESET}"
        read -rp "请输入要修改的选项 [0-5]: " sub_choice

        case "$sub_choice" in
            1)
                read -rp "请输入新的 Cloudflare 邮箱: " new_email
                new_email=$(echo "$new_email" | tr -d '[:space:]')
                if [ -z "$new_email" ]; then
                    echo -e "${RED}邮箱不能为空，已取消修改！${RESET}"
                else
                    verify_and_save_config "$new_email" "$RECORD_NAME" "$CF_TOKEN" "$RECORD_TYPE" "$PROXIED"
                fi
                pause_return
                ;;
            2)
                read -rp "请输入新的 DDNS 域名 (如 ddns.example.com): " new_domain
                new_domain=$(echo "$new_domain" | tr -d '[:space:]')
                if [ -z "$new_domain" ]; then
                    echo -e "${RED}域名不能为空，已取消修改！${RESET}"
                else
                    verify_and_save_config "$CF_EMAIL" "$new_domain" "$CF_TOKEN" "$RECORD_TYPE" "$PROXIED"
                fi
                pause_return
                ;;
            3)
                read -rp "请输入新的 Cloudflare API Token: " new_token
                new_token=$(echo "$new_token" | tr -d '[:space:]')
                if [ -z "$new_token" ]; then
                    echo -e "${RED}Token 不能为空，已取消修改！${RESET}"
                else
                    verify_and_save_config "$CF_EMAIL" "$RECORD_NAME" "$new_token" "$RECORD_TYPE" "$PROXIED"
                fi
                pause_return
                ;;
            4)
                echo -e "当前解析类型为: ${CYAN}${RECORD_TYPE}${RESET}"
                read -rp "请选择新的解析类型 [1: IPv4(A) / 2: IPv6(AAAA)]: " new_type_choice
                local new_type
                if [ "$new_type_choice" = "1" ]; then
                    new_type="A"
                elif [ "$new_type_choice" = "2" ]; then
                    new_type="AAAA"
                else
                    echo -e "${RED}输入无效，已取消修改！${RESET}"
                    pause_return
                    continue
                fi
                verify_and_save_config "$CF_EMAIL" "$RECORD_NAME" "$CF_TOKEN" "$new_type" "$PROXIED"
                pause_return
                ;;
            5)
                echo -e "当前小黄云 CDN 状态为: ${proxy_status_str}"
                read -rp "请选择小黄云状态 [1: 关闭(false) / 2: 开启(true)]: " new_proxy_choice
                local new_proxy
                if [ "$new_proxy_choice" = "1" ]; then
                    new_proxy="false"
                elif [ "$new_proxy_choice" = "2" ]; then
                    new_proxy="true"
                else
                    echo -e "${RED}输入无效，已取消修改！${RESET}"
                    pause_return
                    continue
                fi
                sed -i "s/^PROXIED=.*/PROXIED=\"${new_proxy}\"/" "$CONFIG_FILE"
                rm -f "$IP_CACHE_FILE"
                echo -e "${GREEN}小黄云状态已更新为: ${new_proxy}，正在同步至 Cloudflare...${RESET}"
                update_ddns "interactive"
                pause_return
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}无效选项，请重新输入！${RESET}"
                pause_return
                ;;
        esac
    done
}

# 核心更新逻辑
update_ddns() {
    local mode="$1"

    if [ ! -f "$CONFIG_FILE" ]; then
        [ "$mode" = "interactive" ] && echo -e "${RED}未找到配置文件，请先选择 [1] 进行配置！${RESET}"
        log_msg "错误: 配置文件不存在 ($CONFIG_FILE)"
        return 1
    fi

    # shellcheck source=/dev/null
    . "$CONFIG_FILE"

    current_ip=$(get_public_ip "$RECORD_TYPE")
    date '+%Y-%m-%d %H:%M:%S' > "$LAST_CHECK_FILE"

    if [ -z "$current_ip" ]; then
        log_msg "错误: 无法获取本机公网 ${RECORD_TYPE} 地址"
        [ "$mode" = "interactive" ] && echo -e "${RED}无法获取本机公网 IP，请检查网络连接！${RESET}"
        return 1
    fi

    cached_ip=""
    [ -f "$IP_CACHE_FILE" ] && cached_ip=$(cat "$IP_CACHE_FILE" | tr -d '[:space:]')

    if [ "$current_ip" = "$cached_ip" ] && [ "$mode" != "interactive" ]; then
        return 0
    fi

    [ "$mode" = "interactive" ] && echo -e "当前公网 IP: ${CYAN}${current_ip}${RESET}，正在同步至 Cloudflare..."

    if [ -z "$RECORD_ID" ]; then
        record_resp=$(cf_api "GET" "/zones/${ZONE_ID}/dns_records?type=${RECORD_TYPE}&name=${RECORD_NAME}")
        RECORD_ID=$(echo "$record_resp" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    fi

    local endpoint method
    if [ -z "$RECORD_ID" ]; then
        endpoint="/zones/${ZONE_ID}/dns_records"
        method="POST"
    else
        endpoint="/zones/${ZONE_ID}/dns_records/${RECORD_ID}"
        method="PUT"
    fi

    local payload="{\"type\":\"${RECORD_TYPE}\",\"name\":\"${RECORD_NAME}\",\"content\":\"${current_ip}\",\"ttl\":60,\"proxied\":${PROXIED}}"
    update_resp=$(cf_api "$method" "$endpoint" "$payload")

    if echo "$update_resp" | grep -q '"success":true'; then
        new_id=$(echo "$update_resp" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        if [ -z "$RECORD_ID" ] && [ -n "$new_id" ]; then
            sed -i "s/^RECORD_ID=.*/RECORD_ID=\"${new_id}\"/" "$CONFIG_FILE"
        fi
        echo "$current_ip" > "$IP_CACHE_FILE"
        log_msg "更新成功: ${RECORD_NAME} (${RECORD_TYPE}) -> ${current_ip} (Proxied: ${PROXIED})"
        [ "$mode" = "interactive" ] && echo -e "${GREEN}DDNS 更新成功！${RECORD_NAME} -> ${current_ip} (小黄云: ${PROXIED})${RESET}"
    else
        log_msg "更新失败: ${update_resp}"
        [ "$mode" = "interactive" ] && echo -e "${RED}更新失败，返回信息: ${update_resp}${RESET}"
        return 1
    fi
}

# 后台守护循环 (按秒执行)
run_daemon() {
    local arg_interval="$1"
    echo $$ > "$PID_FILE"
    trap 'kill $(jobs -p) 2>/dev/null; rm -f "$PID_FILE"; exit 0' TERM INT

    local init_interval="${arg_interval:-120}"
    if [ -f "$INTERVAL_FILE" ]; then
        local file_int
        file_int=$(tr -cd '0-9' < "$INTERVAL_FILE")
        [ -n "$file_int" ] && init_interval="$file_int"
    fi
    log_msg "后台定时任务已启动 (PID: $$ | 间隔: ${init_interval} 秒)"

    while true; do
        interval="${arg_interval:-120}"
        if [ -f "$INTERVAL_FILE" ]; then
            local tmp_int
            tmp_int=$(tr -cd '0-9' < "$INTERVAL_FILE")
            [ -n "$tmp_int" ] && interval="$tmp_int"
        fi
        update_ddns "daemon"
        sleep "$interval" &
        wait $!
    done
}

# 停止后台任务
stop_timer() {
    local quiet="$1"
    if [ "$(id -u)" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -f "$SERVICE_FILE" ]; then
        systemctl stop cf-ddns.service >/dev/null 2>&1
        systemctl disable cf-ddns.service >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload >/dev/null 2>&1
    fi

    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(tr -cd '0-9' < "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # 先终止子进程 (sleep)，再终止主进程
            pkill -P "$pid" 2>/dev/null
            kill "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi

    # 彻底清理可能残留的同名守护进程
    pkill -f "${SCRIPT_PATH} --daemon" 2>/dev/null

    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab - 2>/dev/null
    [ "$quiet" != "quiet" ] && echo -e "${GREEN}已停止后台 DDNS 定时任务。${RESET}"
}

# 开启 / 修改后台定时任务 (按秒)
setup_timer() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}请先选择 [1] 完成配置！${RESET}"
        return 1
    fi

    echo -e "\n${CYAN}--- 设置后台定时任务 (按秒执行) ---${RESET}"
    read -rp "定时任务设置时间（默认120秒，支持最小5秒）：" raw_interval
    # 清理所有空白符与回车符
    interval=$(echo "$raw_interval" | tr -d '[:space:]')
    interval=${interval:-120}

    # 兼容 bash 与 sh (dash) 的纯数字校验
    case "$interval" in
        ''|*[!0-9]*)
            echo -e "${YELLOW}输入包含非数字字符，已自动使用默认值 120 秒。${RESET}"
            interval=120
            ;;
        *)
            if [ "$interval" -lt 5 ]; then
                echo -e "${YELLOW}输入小于 5 秒，已自动设为最小允许值 5 秒。${RESET}"
                interval=5
            fi
            ;;
    esac

    echo "$interval" > "$INTERVAL_FILE"
    stop_timer "quiet"

    if [ "$(id -u)" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudflare Lightweight DDNS Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="HOME=${HOME}"
Environment="CONFIG_DIR=${CONFIG_DIR}"
ExecStart=/bin/bash ${SCRIPT_PATH} --daemon ${interval}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now cf-ddns.service >/dev/null 2>&1
        echo -e "${GREEN}后台定时任务已启动 (Systemd 服务，支持开机自启)！检测间隔：每 ${interval} 秒。${RESET}"
    else
        nohup env HOME="$HOME" CONFIG_DIR="$CONFIG_DIR" /bin/bash "$SCRIPT_PATH" --daemon "$interval" >/dev/null 2>&1 &
        (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "@reboot env HOME=\"$HOME\" CONFIG_DIR=\"$CONFIG_DIR\" nohup /bin/bash ${SCRIPT_PATH} --daemon ${interval} >/dev/null 2>&1 &") | crontab - 2>/dev/null
        echo -e "${GREEN}后台定时任务已启动 (Nohup 守护进程)！检测间隔：每 ${interval} 秒。${RESET}"
    fi
}

# 查看当前状态与日志
show_status() {
    echo -e "\n${CYAN}--- 当前配置与运行状态 ---${RESET}"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        . "$CONFIG_FILE"
        echo -e "绑定邮箱: ${CF_EMAIL}"
        echo -e "监控域名: ${GREEN}${RECORD_NAME}${RESET} (${RECORD_TYPE})"
        echo -e "鉴权模式: ${AUTH_MODE} Token"
        echo -e "CDN 代理: ${PROXIED}"
        echo -e "缓存 IP : ${YELLOW}$([ -f "$IP_CACHE_FILE" ] && cat "$IP_CACHE_FILE" || echo "尚无缓存")${RESET}"
        echo -e "最后检测: ${CYAN}$([ -f "$LAST_CHECK_FILE" ] && cat "$LAST_CHECK_FILE" || echo "尚无记录")${RESET}"
    else
        echo -e "配置状态: ${RED}尚未配置${RESET}"
    fi

    local cur_interval="120"
    if [ -f "$INTERVAL_FILE" ]; then
        local tmp_int
        tmp_int=$(tr -cd '0-9' < "$INTERVAL_FILE")
        [ -n "$tmp_int" ] && cur_interval="$tmp_int"
    fi

    if [ -f "$PID_FILE" ] && kill -0 "$(tr -cd '0-9' < "$PID_FILE")" 2>/dev/null; then
        echo -e "定时状态: ${GREEN}后台运行中${RESET} (PID: $(tr -cd '0-9' < "$PID_FILE") | 间隔: ${cur_interval} 秒)"
    else
        echo -e "定时状态: ${YELLOW}未运行${RESET}"
    fi

    echo -e "\n${CYAN}--- 最近 15 条运行日志 ---${RESET}"
    if [ -f "$LOG_FILE" ]; then
        tail -n 15 "$LOG_FILE"
    else
        echo "暂无日志记录。"
    fi
}

# 卸载脚本与清理所有数据
uninstall_ddns() {
    echo -e "\n${RED}=================== 警告 ===================${RESET}"
    echo -e "${YELLOW}即将彻底卸载 Cloudflare DDNS 脚本！该操作将：${RESET}"
    echo "  1. 停止并移除后台定时任务与开机自启服务"
    echo "  2. 删除所有配置文件、IP缓存与运行日志 ($CONFIG_DIR)"
    echo "  3. 删除当前脚本文件自身 ($SCRIPT_PATH)"
    echo -e "${RED}============================================${RESET}"
    read -rp "确认要彻底卸载吗？[y/N]: " confirm_uninst

    case "$confirm_uninst" in
        [yY][eE][sS]|[yY])
            stop_timer "quiet"
            rm -rf "$CONFIG_DIR"
            rm -f "$SCRIPT_PATH"
            echo -e "${GREEN}卸载完成！所有服务、配置及脚本文件均已彻底清除。${RESET}"
            exit 0
            ;;
        *)
            echo -e "${CYAN}已取消卸载操作。${RESET}"
            ;;
    esac
}

# 后台守护调用入口
if [ "$1" = "--daemon" ]; then
    run_daemon "$2"
    exit 0
fi

# SSH 交互式主菜单
while true; do
    echo -e "\n${CYAN}=========================================${RESET}"
    echo -e "${CYAN}     Cloudflare 轻量级 DDNS 管理脚本     ${RESET}"
    echo -e "${CYAN}=========================================${RESET}"
    echo "  1. 初次配置 DDNS (仅需邮箱 + 域名 + Token)"
    echo "  2. 修改现有配置 (邮箱/域名/Token/小黄云等)"
    echo "  3. 立即执行一次 DDNS 同步 (测试/强制刷新)"
    echo "  4. 开启 / 修改后台定时任务 (按秒设置)"
    echo "  5. 停止后台定时任务"
    echo "  6. 查看当前状态与运行日志"
    echo "  7. 彻底卸载脚本 (停止服务并清除所有文件)"
    echo "  0. 退出脚本"
    echo -e "${CYAN}=========================================${RESET}"
    read -rp "请输入数字选择功能 [0-7]: " choice

    case "$choice" in
        1) configure_ddns; pause_return ;;
        2) modify_config_menu ;;
        3) update_ddns "interactive"; pause_return ;;
        4) setup_timer; pause_return ;;
        5) stop_timer; pause_return ;;
        6) show_status; pause_return ;;
        7) uninstall_ddns; pause_return ;;
        0) echo "已退出。"; exit 0 ;;
        *) echo -e "${RED}无效选项，请重新输入！${RESET}"; pause_return ;;
    esac
done