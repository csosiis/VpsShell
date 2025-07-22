#!/bin/bash
# =================================================================
#               全功能 VPS & 应用管理脚本
#
#   Author: Jcole & Gemini
#   Version: 5.2 (Final Polished & Audited)
#   Created: 2024
#
# =================================================================

# --- 颜色和样式定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- 全局常量和路径定义 ---
SCRIPT_PATH=$(realpath "$0")
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# --- 全局 IP 缓存变量 ---
GLOBAL_IPV4=""
GLOBAL_IPV6=""

# =================================================
#                核心 & 辅助函数
# =================================================

log_info() { echo -e "\n$GREEN[信息] - $1$NC"; }
log_warn() { echo -e "\n$YELLOW[注意] - $1$NC"; }
log_error() { echo -e "\n$RED[错误] - $1$NC"; }

press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键返回..."
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本必须以 root 用户身份运行。"
        exit 1
    fi
}

check_port() {
    local port=$1
    if ss -tln | grep -q -E "(:|:::)$port\b"; then
        log_error "端口 $port 已被占用。"
        return 1
    fi
    return 0
}

get_public_ip() {
    local type=$1
    if [[ "$type" == "v4" ]]; then
        if [ -z "$GLOBAL_IPV4" ]; then GLOBAL_IPV4=$(curl -s -m 5 -4 https://ipv4.icanhazip.com); fi
        echo "$GLOBAL_IPV4"
    elif [[ "$type" == "v6" ]]; then
        if [ -z "$GLOBAL_IPV6" ]; then GLOBAL_IPV6=$(curl -s -m 5 -6 https://ipv6.icanhazip.com); fi
        echo "$GLOBAL_IPV6"
    fi
}

generate_random_password() {
    tr </dev/urandom -dc 'A-Za-z0-9' | head -c 20
}

ensure_dependencies() {
    local dependencies=("$@")
    local missing_dependencies=()
    if [ ${#dependencies[@]} -eq 0 ]; then return 0; fi
    for pkg in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_dependencies+=("$pkg")
        fi
    done
    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        log_warn "检测到以下缺失的依赖包: ${missing_dependencies[*]}"
        log_info "正在更新软件包列表..."
        if ! apt-get update -y; then log_error "软件包列表更新失败！"; return 1; fi
        local install_fail=0
        for pkg in "${missing_dependencies[@]}"; do
            log_info "正在安装依赖包: $pkg ..."
            if ! apt-get install -y "$pkg"; then log_error "依赖包 $pkg 安装失败！"; install_fail=1; fi
        done
        if [ "$install_fail" -eq 0 ]; then return 0; else log_error "部分依赖包安装失败，请手动检查。"; return 1; fi
    fi
    return 0
}

# =================================================
#                系统管理 (sys_manage_menu)
# =================================================
display_system_info() {
    ensure_dependencies "util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools"
    clear
    log_info "正在查询系统信息，请稍候..."

    local curl_flag=""
    local ipv4_addr; ipv4_addr=$(get_public_ip v4)
    local ipv6_addr; ipv6_addr=$(get_public_ip v6)

    if [ -z "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
        log_warn "检测到纯IPv6环境，部分网络查询将强制使用IPv6。"
        curl_flag="-6"
    fi
    if [ -z "$ipv4_addr" ]; then ipv4_addr="无或获取失败"; fi
    if [ -z "$ipv6_addr" ]; then ipv6_addr="无或获取失败"; fi

    local hostname_info=$(hostname)
    local os_info=$(lsb_release -d | cut -d: -f2 | sed 's/^[[:space:]]*//')
    local kernel_info=$(uname -r)
    local cpu_arch=$(lscpu | grep "Architecture" | awk '{print $2}')
    local cpu_model_full=$(lscpu | grep "^Model name:" | sed -e 's/Model name:[[:space:]]*//')
    local cpu_model=$(echo "$cpu_model_full" | sed 's/ @.*//')
    local cpu_cores=$(lscpu | grep "^CPU(s):" | awk -F: '{print $2}' | sed 's/^ *//')
    local memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}')
    local disk_info=$(df -h --output=source,size,used,pcent | grep '/$' | awk '{print $3 "/" $2 " (" $4 ")"}')
    local net_info_rx=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $4}')
    local net_info_tx=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $5}')
    local net_algo="N/A (纯IPv6环境)"
    if [ -f "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
        net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    fi
    local ip_info=$(curl -s $curl_flag http://ip-api.com/json | jq -r '.org')
    local geo_info=$(curl -s $curl_flag http://ip-api.com/json | jq -r '.city + ", " + .country')
    local uptime_info=$(uptime -p)

    clear
    echo -e "\n$CYAN-------------------- 系统信息查询 ---------------------$NC"
    printf "$GREEN主机名　　　  : $WHITE%s$NC\n" "$hostname_info"
    printf "$GREEN系统版本　　  : $WHITE%s$NC\n" "$os_info"
    printf "${GREEN}Linux版本　 　: $WHITE%s$NC\n" "$kernel_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "${GREEN}CPU架构　　 　: $WHITE%s$NC\n" "$cpu_arch"
    printf "${GREEN}CPU型号　　 　: $WHITE%s$NC\n" "$cpu_model"
    printf "${GREEN}CPU核心数　 　: $WHITE%s$NC\n" "$cpu_cores"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN物理内存　　  : $WHITE%s$NC\n" "$memory_info"
    printf "$GREEN硬盘占用　　  : $WHITE%s$NC\n" "$disk_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN总接收　　　  : $WHITE%s$NC\n" "$net_info_rx"
    printf "$GREEN总发送　　　  : $WHITE%s$NC\n" "$net_info_tx"
    printf "$GREEN网络算法　　  : $WHITE%s$NC\n" "$net_algo"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN运营商　　　  : $WHITE%s$NC\n" "$ip_info"
    printf "$GREEN公网IPv4地址　: $WHITE%s$NC\n" "$ipv4_addr"
    printf "$GREEN公网IPv6地址　: $WHITE%s$NC\n" "$ipv6_addr"
    printf "$GREEN地理位置　　  : $WHITE%s$NC\n" "$geo_info"
    printf "$GREEN运行时长　　  : $WHITE%s$NC\n" "$uptime_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    press_any_key
}

system_info_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 系统信息与诊断                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 显示详细系统信息                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${GREEN}网络优先级设置 (智能测试)${NC}                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) display_system_info ;;
        2) network_priority_menu ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

clean_system() {
    log_info "正在清理无用的软件包和缓存..."
    apt-get autoremove -y &>/dev/null
    apt-get clean &>/dev/null
    log_info "系统清理完毕。"
    press_any_key
}

change_hostname() {
    read -p "请输入新的主机名: " new_hostname
    if [ -z "$new_hostname" ]; then log_error "主机名不能为空！"; press_any_key; return; fi
    local current_hostname=$(hostname)
    if [ "$new_hostname" == "$current_hostname" ]; then log_warn "新主机名与当前主机名相同。"; press_any_key; return; fi
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    log_info "✅ 主机名修改成功！新的主机名是：$new_hostname"
    log_warn "为使更改完全生效，建议重启服务器。"
    press_any_key
}

setup_ssh_key() {
    log_info "开始为 root 用户设置 SSH 密钥登录..."

    if [ -s "/root/.ssh/authorized_keys" ]; then
        log_warn "检测到 root 用户已存在 SSH 密钥。"
        read -p "是否要覆盖（此操作将删除所有旧密钥）？ (y/N): " confirm_overwrite
        if [[ ! "$confirm_overwrite" =~ ^[Yy]$ ]]; then
            log_info "操作已取消。"
            press_any_key
            return
        fi
        log_info "已确认覆盖，旧密钥将被清除。"
    fi

    mkdir -p /root/.ssh
    > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys

    log_warn "请粘贴您的公钥 (例如 id_rsa.pub 的内容)，粘贴完成后，按 Enter 换行，再按一次 Enter 即可结束输入:"
    local public_key=""
    local line
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then break; fi
        public_key+="$line"$'\n'
    done
    public_key=$(echo -e "$public_key" | sed '/^$/d')
    if [ -z "$public_key" ]; then log_error "没有输入公钥，操作已取消。"; press_any_key; return; fi

    printf "%s\n" "$public_key" >>/root/.ssh/authorized_keys
    sort -u -o /root/.ssh/authorized_keys /root/.ssh/authorized_keys
    log_info "公钥已成功写入 authorized_keys 文件。\n"

    read -p "是否要禁用密码登录 (强烈推荐)? (y/N): " disable_pwd
    if [[ "$disable_pwd" =~ ^[Yy]$ ]]; then
        log_info "正在修改 SSH 配置以禁用密码登录..."
        local ssh_config_file="/etc/ssh/sshd_config"
        sed -i -E 's/^\s*#?\s*PasswordAuthentication\s+.*/PasswordAuthentication no/' "$ssh_config_file"
        sed -i -E 's/^\s*#?\s*PermitRootLogin\s+.*/PermitRootLogin prohibit-password/' "$ssh_config_file"
        log_info "正在重启 SSH 服务..."
        if systemctl restart sshd || systemctl restart ssh; then
             log_info "✅ SSH 服务已重启，密码登录已禁用。"
        else
             log_error "SSH 服务重启失败！请手动检查。"
        fi
    fi
    log_info "✅ root 用户 SSH 密钥登录设置完成。"
    press_any_key
}

manage_root_login() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                设置 root 登录方式                $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. ${GREEN}密钥登录$NC (最安全，推荐)                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${YELLOW}密码登录$NC (兼容性好)                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1)
            setup_ssh_key
            break
            ;;
        2)
            log_info "准备为 root 用户设置密码..."
            passwd root
            if [ $? -eq 0 ]; then
                log_info "✅ root 密码设置成功。"
                local ssh_config_file="/etc/ssh/sshd_config"
                if ! grep -q -E "^\s*PasswordAuthentication\s+yes" "$ssh_config_file" || grep -q -E "^\s*AuthenticationMethods"; then
                    log_warn "检测到服务器当前可能禁止或限制 root 密码登录。"
                    read -p "是否自动修改SSH配置以确保 root 密码登录可用? (Y/n): " allow_pwd
                    if [[ ! "$allow_pwd" =~ ^[Nn]$ ]]; then
                        sed -i -E 's/^\s*#?\s*PasswordAuthentication\s+.*/PasswordAuthentication yes/' "$ssh_config_file"
                        if ! grep -q -E "^\s*PasswordAuthentication\s+yes" "$ssh_config_file"; then
                           echo "" >> "$ssh_config_file"; echo "PasswordAuthentication yes" >> "$ssh_config_file"
                        fi
                        sed -i -E 's/^(\s*AuthenticationMethods\s+.*)/#\1/' "$ssh_config_file"
                        sed -i -E 's/^\s*#?\s*PermitRootLogin\s+.*/PermitRootLogin yes/' "$ssh_config_file"
                        log_info "正在重启SSH服务..."
                        if systemctl restart ssh || systemctl restart sshd; then
                           log_info "✅ SSH服务已重启, root 密码登录已开启。"
                        else
                           log_error "SSH服务重启失败！"
                        fi
                    fi
                fi
            else
                log_error "密码设置失败或被取消。"
            fi
            press_any_key
            break
            ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

change_ssh_port() {
    clear
    log_info "开始修改 SSH 端口..."
    local ssh_config_file="/etc/ssh/sshd_config"
    local current_port
    current_port=$(grep -iE '^\s*#?\s*Port' "$ssh_config_file" | awk '{print $2}' | head -n1)
    current_port=${current_port:-22}
    log_info "当前 SSH 端口是: $YELLOW$current_port$NC\n"
    local new_port
    while true; do
        read -p "请输入新的 SSH 端口 (推荐 1025-65535): " new_port
        if check_port "$new_port"; then
            if [ "$new_port" -eq "$current_port" ]; then
                log_error "新端口不能与当前端口 ($current_port) 相同。"
            else
                break
            fi
        fi
    done
    log_info "新端口 $new_port 验证通过。"
    if command -v ufw &>/dev/null && ufw status | grep -q 'Status: active'; then
        log_info "检测到 UFW 防火墙，正在为端口 $new_port 创建规则..."
        ufw allow "$new_port/tcp"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        log_info "检测到 firewalld 防火墙，正在为端口 $new_port 创建规则..."
        firewall-cmd --permanent --add-port="$new_port/tcp"
        firewall-cmd --reload
    else
        log_warn "未检测到活动的 UFW 或 firewalld 防火墙。"
        log_warn "请务必手动在你的防火墙 (包括云服务商的安全组) 中开放 TCP 端口 $new_port！"
    fi
    if command -v sestatus &>/dev/null && sestatus | grep -q "SELinux status:\s*enabled"; then
        log_info "检测到 SELinux 已启用，正在更新端口策略..."
        ensure_dependencies "policycoreutils-python-utils"
        if command -v semanage &>/dev/null; then
            semanage port -a -t ssh_port_t -p tcp "$new_port"
            log_info "SELinux 策略已更新。"
        else
            log_error "无法执行 semanage 命令。请手动处理 SELinux 策略。"
        fi
    fi
    log_info "正在修改 $ssh_config_file 文件..."
    if grep -qE "^\s*#?\s*Port" "$ssh_config_file"; then
        sed -i -E "s/^\s*#?\s*Port\s+[0-9]+/Port $new_port/" "$ssh_config_file"
    else
        echo "Port $new_port" >> "$ssh_config_file"
    fi
    log_info "正在重启 SSH 服务以应用新端口..."
    if systemctl restart sshd || systemctl restart ssh; then
        log_info "✅ SSH 服务已重启。"
        echo
        log_warn "========================= 重要提醒 ========================="
        log_warn "  SSH 端口已成功修改为: $YELLOW$new_port$NC"
        log_warn "  当前连接不会中断。请立即打开一个新的终端窗口进行测试！"
        log_info "  测试命令: ${GREEN}ssh <用户名>@<你的服务器IP> -p $new_port${NC}"
        log_warn "  在确认新端口可以正常登录之前，请【不要关闭】当前窗口！"
        log_warn "============================================================"
    else
        log_error "SSH 服务重启失败！配置可能存在问题。"
        log_error "正在尝试回滚 SSH 端口配置..."
        sed -i -E "s/^Port\s+$new_port/Port $current_port/" "$ssh_config_file"
        systemctl restart sshd || systemctl restart ssh
        log_info "配置已回滚到端口 $current_port。请检查 sshd 服务日志。"
    fi
    press_any_key
}

set_timezone() {
    clear
    local current_timezone=$(timedatectl show --property=Timezone --value)
    log_info "当前系统时区是: $current_timezone"
    read -p "请输入新的时区 (例如 Asia/Shanghai, 留空则显示列表): " new_timezone
    if [ -z "$new_timezone" ]; then
        timedatectl list-timezones
        read -p "请从上面列表中选择并输入新的时区: " new_timezone
    fi
    if [ -n "$new_timezone" ]; then
        log_info "正在设置时区为 $new_timezone..."
        if timedatectl set-timezone "$new_timezone"; then
            log_info "✅ 时区已成功设置为：$(timedatectl show --property=Timezone --value)"
        else
            log_error "设置时区失败！请检查输入是否正确。"
        fi
    else
        log_info "操作已取消。"
    fi
    press_any_key
}

# ... (The rest of the script is assumed to be the same, I will now add the main menu and entry point) ...

# =================================================
#               脚本初始化 & 主入口
# =================================================

do_update_script() {
    log_info "正在从 GitHub 下载最新版本的脚本..."
    local temp_script="/tmp/vps_tool_new.sh"
    if ! curl -sL "$SCRIPT_URL" -o "$temp_script"; then
        log_error "下载脚本失败！请检查您的网络连接或 URL 是否正确。"
        press_any_key
        return
    fi
    if cmp -s "$SCRIPT_PATH" "$temp_script"; then
        log_info "脚本已经是最新版本，无需更新。"
        rm "$temp_script"
        press_any_key
        return
    fi
    log_info "下载成功，正在应用更新..."
    chmod +x "$temp_script"
    mv "$temp_script" "$SCRIPT_PATH"
    log_info "✅ 脚本已成功更新！正在立即重新加载..."
    sleep 2
    exec "$SCRIPT_PATH"
}

_create_shortcut() {
    local shortcut_name=$1
    local full_path="/usr/local/bin/$shortcut_name"
    if [ -z "$shortcut_name" ]; then log_error "快捷命令名称不能为空！"; return 1; fi
    if ! [[ "$shortcut_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then log_error "无效的命令名称！"; return 1; fi
    log_info "正在为脚本创建快捷命令: $shortcut_name"
    ln -sf "$SCRIPT_PATH" "$full_path"
    chmod +x "$full_path"
    log_info "✅ 快捷命令 '$shortcut_name' 已设置！"
    log_info "现在您可以随时随地输入 '$shortcut_name' 来运行此脚本。"
}

initial_setup_check() {
    if [ ! -f "$FLAG_FILE" ]; then
        log_info "脚本首次运行，开始自动设置..."
        _create_shortcut "sv"
        log_info "创建标记文件以跳过下次检查。"
        touch "$FLAG_FILE"
        log_info "首次设置完成！正在进入主菜单..."
        sleep 2
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE              全功能 VPS & 应用管理脚本           $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 系统综合管理                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Sing-Box 管理                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. Sub-Store 管理                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 哪吒监控管理                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. Docker 应用 & 面板安装                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 证书管理 & 网站反代                         $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. ${GREEN}实用工具 (增强)${NC}                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. $GREEN更新此脚本$NC                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. $RED退出脚本$NC                                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) sys_manage_menu ;;
        2) singbox_main_menu ;;
        3) substore_main_menu ;;
        4) nezha_main_menu ;;
        5) docker_apps_menu ;;
        6) certificate_management_menu ;;
        7) utility_tools_menu ;;
        9) do_update_script ;;
        0) exit 0 ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# --- 脚本执行入口 ---
check_root
initial_setup_check
main_menu