#!/bin/bash
# =================================================================
#               全功能 VPS & 应用管理脚本
#
#   Author: Jcole & 编码助手
#   Version: 5.0 (Added Portability, Docker Mgmt, More Tools & Refactoring)
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
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/$SUBSTORE_SERVICE_NAME"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# --- 全局 IP 缓存变量 ---
GLOBAL_IPV4=""
GLOBAL_IPV6=""

# --- 全局系统环境检测变量 ---
PKG_MANAGER=""
OS_ID=""
OS_VERSION_CODENAME=""


# =================================================
#           错误处理 & 脚本退出清理
# =================================================
# 定义一个数组来追踪所有临时文件
TEMP_FILES=()

cleanup_on_exit() {
    # 只有当 TEMP_FILES 数组不为空时才执行
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        log_info "脚本退出，正在清理临时文件..."
        for temp_file in "${TEMP_FILES[@]}"; do
            if [ -f "$temp_file" ]; then
                rm -f "$temp_file"
            fi
        done
    fi
}

# 注册 trap，无论脚本如何退出（正常退出、Ctrl+C、错误），都会执行 cleanup_on_exit 函数
trap cleanup_on_exit EXIT INT TERM

# 创建临时文件时，使用此函数来注册它们以便自动清理
# 用法: register_temp_file "/path/to/temp/file"
register_temp_file() {
    TEMP_FILES+=("$1")
}


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
        if [ -z "$GLOBAL_IPV4" ]; then
            GLOBAL_IPV4=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
        fi
        echo "$GLOBAL_IPV4"
    elif [[ "$type" == "v6" ]]; then
        if [ -z "$GLOBAL_IPV6" ]; then
            GLOBAL_IPV6=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
        fi
        echo "$GLOBAL_IPV6"
    fi
}

generate_random_port() {
    echo $((RANDOM % 64512 + 1024))
}

generate_random_password() {
    tr </dev/urandom -dc 'A-Za-z0-9' | head -c 20
}

_is_port_available() {
    local port_to_check=$1
    local used_ports_array_name=$2
    eval "local used_ports=(\"\${$used_ports_array_name[@]}\")"
    if ss -tlnu | grep -q -E ":$port_to_check\s"; then
        log_warn "端口 $port_to_check 已被系统其他服务占用。"
        return 1
    fi
    for used_port in "${used_ports[@]}"; do
        if [ "$port_to_check" == "$used_port" ]; then
            log_warn "端口 $port_to_check 即将被本次操作中的其他协议使用。"
            return 1
        fi
    done
    return 0
}

_is_domain_valid() {
    local domain_to_check=$1
    if [[ $domain_to_check =~ ^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- 新增：可移植性相关的函数 ---

detect_os_and_package_manager() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION_CODENAME=$VERSION_CODENAME
    else
        log_error "无法检测到操作系统类型。"
        exit 1
    fi

    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        log_error "无法检测到支持的包管理器 (apt, yum, dnf)。"
        exit 1
    fi
    # log_info "检测到系统: $OS_ID, 包管理器: $PKG_MANAGER"
}

# 统一的包安装函数
install_packages() {
    local packages_to_install=("$@")
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        return 0
    fi
    log_info "正在安装包: ${packages_to_install[*]}"
    case "$PKG_MANAGER" in
        apt)
            apt-get install -y "${packages_to_install[@]}"
            ;;
        yum|dnf)
            "$PKG_MANAGER" install -y "${packages_to_install[@]}"
            ;;
        *)
            log_error "未知的包管理器: $PKG_MANAGER"
            return 1
            ;;
    esac
}

# 确保依赖包已安装（已适配多发行版）
ensure_dependencies() {
    local dependencies=("$@")
    local missing_dependencies=()
    if [ ${#dependencies[@]} -eq 0 ]; then
        return 0
    fi

    for pkg in "${dependencies[@]}"; do
        local is_installed=false
        case "$PKG_MANAGER" in
            apt)
                if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                    is_installed=true
                fi
                ;;
            yum|dnf)
                if rpm -q "$pkg" &>/dev/null; then
                    is_installed=true
                fi
                # 特殊处理 policycoreutils-python-utils 在 CentOS/RHEL 上的包名
                if [ "$pkg" == "policycoreutils-python-utils" ] && [ "$PKG_MANAGER" == "dnf" ]; then
                     if rpm -q "policycoreutils-python-utils" &>/dev/null || rpm -q "python3-policycoreutils" &>/dev/null; then
                        is_installed=true
                     fi
                fi
                ;;
        esac
        if ! $is_installed; then
             missing_dependencies+=("$pkg")
        fi
    done

    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        log_warn "检测到以下缺失的依赖包: ${missing_dependencies[*]}"
        if [ "$PKG_MANAGER" == "apt" ]; then
            log_info "正在更新软件包列表 (apt)..."
            if ! apt-get update -y; then
                log_error "软件包列表更新失败，请检查网络或源配置！"
                return 1
            fi
        fi

        if ! install_packages "${missing_dependencies[@]}"; then
            log_error "部分依赖包安装失败，请手动检查。"
            return 1
        fi
    else
        log_info "所需依赖均已安装。"
    fi
    return 0
}


# =================================================
#                系统管理 (sys_manage_menu)
# =================================================
sys_manage_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   系统综合管理                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 系统信息查询                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 清理系统垃圾                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 修改主机名                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 设置 root 登录 (密钥/密码)                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 修改 SSH 端口                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 设置系统时区                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE网络优化$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. 设置网络优先级 (IPv4/v6)                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. DNS 工具箱 (优化/备份/恢复)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. BBR 拥塞控制管理                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  10. 安装 WARP 网络接口                          $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  11. ${GREEN}实用工具 (增强)${NC}                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) show_system_info ;;
        2) clean_system ;;
        3) change_hostname ;;
        4) manage_root_login ;;
        5) change_ssh_port ;;
        6) set_timezone ;;
        7) network_priority_menu ;;
        8) dns_toolbox_menu ;;
        9) manage_bbr ;;
        10) install_warp ;;
        11) utility_tools_menu ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

show_system_info() {
    # 适配多发行版的依赖包名
    local deps=("util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools")
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        deps=("util-linux" "procps-ng" "vnstat" "jq" "redhat-lsb-core" "curl" "net-tools")
    fi
    ensure_dependencies "${deps[@]}"

    clear
    log_info "正在查询系统信息，请稍候..."
    if ! command -v lsb_release &>/dev/null || ! command -v lscpu &>/dev/null; then
        log_error "缺少核心查询命令 (如 lsb_release, lscpu)，请先执行依赖安装。"
        press_any_key
        return
    fi
    log_info "正在获取网络信息..."

    local curl_flag=""
    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    local ipv6_addr
    ipv6_addr=$(get_public_ip v6)

    if [ -z "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
        log_warn "检测到纯IPv6环境，部分网络查询将强制使用IPv6。"
        curl_flag="-6"
    fi

    if [ -z "$ipv4_addr" ]; then ipv4_addr="无或获取失败"; fi
    if [ -z "$ipv6_addr" ]; then ipv6_addr="无或获取失败"; fi

    local hostname_info
    hostname_info=$(hostname)
    local os_info
    os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^[[:space:]]*//')
    local kernel_info
    kernel_info=$(uname -r)
    local cpu_arch
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    local cpu_model_full
    cpu_model_full=$(lscpu | grep "^Model name:" | sed -e 's/Model name:[[:space:]]*//')
    local cpu_model
    cpu_model=$(echo "$cpu_model_full" | sed 's/ @.*//')
    local cpu_freq_from_model
    cpu_freq_from_model=$(echo "$cpu_model_full" | sed -n 's/.*@ *//p')
    local cpu_cores
    cpu_cores=$(lscpu | grep "^CPU(s):" | awk -F: '{print $2}' | sed 's/^ *//')
    local load_info
    load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    local memory_info
    memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}')
    local disk_info
    disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')
    local net_info_rx
    net_info_rx=$(vnstat --oneline | awk -F';' '{print $4}')
    local net_info_tx
    net_info_tx=$(vnstat --oneline | awk -F';' '{print $5}')

    local net_algo="N/A (纯IPv6环境)"
    if [ -f "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
        net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    fi

    local ip_info
    ip_info=$(curl -s $curl_flag http://ip-api.com/json | jq -r '.org')
    local dns_info
    dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local geo_info
    geo_info=$(curl -s $curl_flag http://ip-api.com/json | jq -r '.city + ", " + .country')
    local timezone
    timezone=$(timedatectl show --property=Timezone --value)
    local uptime_info
    uptime_info=$(uptime -p)
    local current_time
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    clear
    echo -e "\n$CYAN-------------------- 系统信息查询 ---------------------$NC"
    printf "$GREEN主机名　　　  : $WHITE%s$NC\n" "$hostname_info"
    printf "$GREEN系统版本　　  : $WHITE%s$NC\n" "$os_info"
    printf "${GREEN}Linux版本　 　: $WHITE%s$NC\n" "$kernel_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "${GREEN}CPU架构　　 　: $WHITE%s$NC\n" "$cpu_arch"
    printf "${GREEN}CPU型号　　 　: $WHITE%s$NC\n" "$cpu_model"
    printf "${GREEN}CPU频率　　 　: $WHITE%s$NC\n" "$cpu_freq_from_model"
    printf "${GREEN}CPU核心数　 　: $WHITE%s$NC\n" "$cpu_cores"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "${GREEN}CPU占用　　 　: $WHITE%s$NC\n" "$cpu_usage"
    printf "$GREEN系统负载　　  : $WHITE%s$NC\n" "$load_info"
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
    printf "${GREEN}DNS地址　　 　: $WHITE%s$NC\n" "$dns_info"
    printf "$GREEN地理位置　　  : $WHITE%s$NC\n" "$geo_info"
    printf "$GREEN系统时间　　  : $WHITE%s$NC\n" "$timezone $current_time"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN运行时长　　  : $WHITE%s$NC\n" "$uptime_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    press_any_key
}

clean_system() {
    log_info "正在清理无用的软件包和缓存..."
    set -e
    case "$PKG_MANAGER" in
        apt)
            apt autoremove -y
            apt clean
            ;;
        yum|dnf)
            "$PKG_MANAGER" autoremove -y
            "$PKG_MANAGER" clean all
            ;;
    esac
    set +e
    log_info "系统清理完毕。"
    press_any_key
}

change_hostname() {
    log_info "准备修改主机名...\n"
    read -p "请输入新的主机名: " new_hostname
    if [ -z "$new_hostname" ]; then
        log_error "主机名不能为空！"
        press_any_key
        return
    fi
    local current_hostname
    current_hostname=$(hostname)
    if [ "$new_hostname" == "$current_hostname" ]; then
        log_warn "新主机名与当前主机名相同，无需修改。"
        press_any_key
        return
    fi
    set -e
    hostnamectl set-hostname "$new_hostname"
    echo "$new_hostname" >/etc/hostname
    # 使用 .bak 后缀自动备份
    sed -i.bak "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    set +e
    log_info "✅ 主机名修改成功！新的主机名是：$new_hostname"
    log_info "当前主机名是：$(hostname)"
    press_any_key
}
# =================================================
#                 DNS 工具箱
# =================================================
apply_dns_config() {
    local dns_string="$1"

    if [ -z "$dns_string" ]; then
        log_error "没有提供任何DNS服务器地址，操作中止。"
        return
    fi

    # 判断是否由 systemd-resolved 管理
    if systemctl is-active --quiet systemd-resolved; then
        log_info "检测到 systemd-resolved 服务，将通过标准方式配置..."

        # 自动备份
        sed -i.bak -e "s/^#\?DNS=.*/DNS=$dns_string/" \
               -e "s/^#\?Domains=.*/Domains=~./" /etc/systemd/resolved.conf
        if ! grep -q "DNS=" /etc/systemd/resolved.conf; then echo "DNS=$dns_string" >> /etc/systemd/resolved.conf; fi
        if ! grep -q "Domains=" /etc/systemd/resolved.conf; then echo "Domains=~." >> /etc/systemd/resolved.conf; fi

        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        log_info "正在重启 systemd-resolved 服务..."
        systemctl restart systemd-resolved
        log_info "✅ systemd-resolved DNS 配置完成！"
    else
        log_info "未检测到 systemd-resolved，将直接修改 /etc/resolv.conf..."
        local resolv_content=""
        for server in $dns_string; do
            resolv_content+="nameserver $server\n"
        done
        # 自动备份
        cp /etc/resolv.conf /etc/resolv.conf.bak
        echo -e "$resolv_content" > /etc/resolv.conf
        log_info "✅ /etc/resolv.conf 文件已更新！"
    fi

    echo
    log_info "配置后的真实上游DNS如下 (通过 resolvectl status 查看):"
    echo -e "$WHITE"
    resolvectl status | grep 'DNS Server'
    echo -e "$NC"
    press_any_key
}

recommend_best_dns() {
    clear
    log_info "开始自动测试延迟以寻找最佳 DNS..."

    local ping_pkg="iputils-ping"
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        ping_pkg="iputils"
    fi
    ensure_dependencies "$ping_pkg"

    declare -A dns_providers
    dns_providers["Cloudflare"]="1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001"
    dns_providers["Google"]="8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844"
    dns_providers["Quad9"]="9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9"
    dns_providers["OpenDNS"]="208.67.222.222 208.67.220.220 2620:119:35::35 2620:119:53::53"

    local ping_cmd="ping"
    local ip_type="v4"
    if ! get_public_ip v4 >/dev/null 2>&1 || [ -z "$(get_public_ip v4)" ]; then
        log_warn "未检测到IPv4网络，将切换到IPv6模式进行测试。"
        ping_cmd="ping"
        ip_type="v6"
    fi

    declare -A results
    declare -A ip_to_provider_map
    echo
    for provider in "${!dns_providers[@]}"; do
        local all_ips=${dns_providers[$provider]}
        local ip_to_test=""

        if [ "$ip_type" == "v6" ]; then
            ping_cmd="ping -6"
            ip_to_test=$(echo "$all_ips" | awk '{for(i=1;i<=NF;i++) if($i ~ /:/) {print $i; exit}}')
        else
            ping_cmd="ping -4"
            ip_to_test=$(echo "$all_ips" | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')
        fi

        if [ -z "$ip_to_test" ]; then
            log_warn "未能为 $provider 找到合适的 $ip_type 地址，跳过测试。"
            continue
        fi

        ip_to_provider_map[$ip_to_test]=$provider
        echo -ne "$CYAN  正在测试: $provider ($ip_to_test)...$NC"
        local avg_latency
        avg_latency=$($ping_cmd -c 4 -W 1 "$ip_to_test" | tail -1 | awk -F '/' '{print $5}')

        if [ -n "$avg_latency" ]; then
            results[$ip_to_test]=$avg_latency
            echo -e "$GREEN  延迟: $avg_latency ms$NC"
        else
            results[$ip_to_test]="9999" # 代表超时
            echo -e "$RED  请求超时!$NC"
        fi
    done

    echo
    log_info "测试结果（按延迟从低到高排序）:"
    local sorted_results
    sorted_results=$(for ip in "${!results[@]}"; do
        echo "${results[$ip]} $ip"
    done | sort -n)

    echo -e "$WHITE"
    echo "$sorted_results" | while read -r latency ip; do
        provider_name=${ip_to_provider_map[$ip]}
        printf "  %-12s (%-15s) -> %s ms\n" "$provider_name" "$ip" "$latency"
    done | sed 's/9999/超时/'
    echo -e "$NC"

    local best_ip
    best_ip=$(echo "$sorted_results" | head -n 1 | awk '{print $2}')
    local backup_ip
    backup_ip=$(echo "$sorted_results" | head -n 2 | tail -n 1 | awk '{print $2}')

    if [ -z "$best_ip" ] || [ "$(echo "${results[$best_ip]}" | cut -d'.' -f1)" == "9999" ]; then
        log_error "所有DNS服务器测试超时，无法给出有效建议。"
        press_any_key
        return
    fi

    local best_dns_provider_name=${ip_to_provider_map[$best_ip]}
    local best_dns_full_list=${dns_providers[$best_dns_provider_name]}
    local final_dns_to_apply="$best_dns_full_list"

    echo
    log_info "优化建议:"
    echo -e "$GREEN  最佳DNS提供商 (主): $best_dns_provider_name ($best_ip)$NC"

    if [ -n "$backup_ip" ] && [ "$best_ip" != "$backup_ip" ] && [ "$(echo "${results[$backup_ip]}" | cut -d'.' -f1)" != "9999" ]; then
        local backup_dns_provider_name=${ip_to_provider_map[$backup_ip]}
        local backup_dns_full_list=${dns_providers[$backup_dns_provider_name]}
        final_dns_to_apply="$final_dns_to_apply $backup_dns_full_list"
        echo -e "$YELLOW  备用DNS提供商 (备): $backup_dns_provider_name ($backup_ip)$NC"
    fi

    echo
    read -p "是否要立即应用此优化建议? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "正在应用推荐配置..."
        local unique_servers
        unique_servers=$(echo "$final_dns_to_apply" | tr ' ' '\n' | sort -u | tr '\n' ' ')
        apply_dns_config "$unique_servers"
    else
        log_info "操作已取消。"
        press_any_key
    fi
}

dns_toolbox_menu() {
    local backup_file="/etc/vps_toolkit_dns_backup"
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   DNS 工具箱                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

        if command -v resolvectl &>/dev/null; then
            local status_output
            status_output=$(resolvectl status)
            local current_dns_list
            current_dns_list=$(echo "$status_output" | grep 'Current DNS Server:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
            if [ -z "$current_dns_list" ]; then
                current_dns_list=$(echo "$status_output" | grep 'DNS Servers:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
            fi
            if [ -n "$current_dns_list" ]; then
                 echo -e "$CYAN║$NC  当前DNS: $YELLOW$current_dns_list$NC $CYAN║$NC"
            else
                 echo -e "$CYAN║$NC  当前DNS: ${RED}读取失败$NC                               $CYAN║$NC"
            fi
        fi

        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. ${GREEN}自动测试并推荐最佳 DNS$NC                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 手动选择 DNS 进行优化                       $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 备份当前 DNS 配置                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"

        if [ -f "$backup_file" ]; then
            echo -e "$CYAN║$NC   4. ${GREEN}从备份恢复 DNS 配置$NC                         $CYAN║$NC"
        else
            echo -e "$CYAN║$NC   4. ${RED}从备份恢复 DNS 配置 (无备份)${NC}                $CYAN║$NC"
        fi

        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) recommend_best_dns ;;
        2) optimize_dns ;;
        3) backup_dns_config ;;
        4) restore_dns_config ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

backup_dns_config() {
    local backup_file="/etc/vps_toolkit_dns_backup"
    log_info "开始备份当前 DNS 配置..."

    if [ -f "$backup_file" ]; then
        log_warn "检测到已存在的备份文件。是否覆盖？"
        read -p "请输入 (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "操作已取消。"
            press_any_key
            return
        fi
    fi

    if systemctl is-active --quiet systemd-resolved; then
        cp /etc/systemd/resolved.conf "$backup_file.systemd"
        echo "systemd-resolved" > "$backup_file.mode"
        log_info "已将 systemd-resolved 配置文件备份到 $backup_file.systemd"
    else
        cp /etc/resolv.conf "$backup_file.resolv"
        echo "resolvconf" > "$backup_file.mode"
        log_info "已将 /etc/resolv.conf 文件备份到 $backup_file.resolv"
    fi

    touch "$backup_file"
    log_info "✅ DNS 备份完成！"
    press_any_key
}

restore_dns_config() {
    local backup_file="/etc/vps_toolkit_dns_backup"
    if [ ! -f "$backup_file" ]; then
        log_error "未找到任何 DNS 备份文件，无法恢复。"
        press_any_key
        return
    fi

    log_info "准备从备份中恢复 DNS 配置..."
    read -p "这将覆盖当前的 DNS 设置，确定要继续吗？ (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi

    local backup_mode
    backup_mode=$(cat "$backup_file.mode")

    if [ "$backup_mode" == "systemd-resolved" ]; then
        log_info "正在恢复 systemd-resolved 配置..."
        mv "$backup_file.systemd" /etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        log_info "✅ systemd-resolved 配置已恢复并重启服务。"
    elif [ "$backup_mode" == "resolvconf" ]; then
        log_info "正在恢复 /etc/resolv.conf 文件..."
        mv "$backup_file.resolv" /etc/resolv.conf
        log_info "✅ /etc/resolv.conf 文件已恢复。"
    else
        log_error "未知的备份模式，恢复失败！"
        press_any_key
        return
    fi

    rm -f "$backup_file" "$backup_file.mode"
    log_info "当前的DNS配置如下："
    echo -e "$WHITE"
    cat /etc/resolv.conf
    echo -e "$NC"
    press_any_key
}

optimize_dns() {
    clear
    log_info "正在检测您当前的 DNS 配置..."
    if command -v resolvectl &>/dev/null; then
        local status_output
        status_output=$(resolvectl status)
        local current_dns_list
        current_dns_list=$(echo "$status_output" | grep 'Current DNS Server:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
        if [ -z "$current_dns_list" ]; then
            current_dns_list=$(echo "$status_output" | grep 'DNS Servers:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
        fi
    else
        current_dns_list=$(grep '^nameserver' /etc/resolv.conf | awk '{printf "%s ", $2}')
    fi
    if [ -n "$current_dns_list" ]; then log_info "当前系统使用的 DNS 服务器是: $YELLOW$current_dns_list$NC"; else log_warn "未检测到当前配置的 DNS 服务器。"; fi
    echo

    declare -A dns_providers
    dns_providers["Cloudflare"]="1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:470t:4700::1001"
    dns_providers["Google"]="8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844"
    dns_providers["OpenDNS"]="208.67.222.222 208.67.220.220 2620:119:35::35 2620:119:53::53"
    dns_providers["Quad9"]="9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9"
    local options=("Cloudflare" "Google" "OpenDNS" "Quad9" "返回")

    echo -e "$CYAN--- 请选择一个或多个 DNS 提供商 (可多选，用空格隔开) ---$NC\n"
    for i in "${!options[@]}"; do
        local option_name=${options[$i]}
        if [ "$option_name" == "返回" ]; then
            echo -e "$((i + 1)). $option_name\n"
        else
            local ips=${dns_providers[$option_name]}
            printf " %2d. %-12s\n" "$((i + 1))" "$option_name"
            printf "      ${YELLOW}%s${NC}\n\n" "$ips"
        fi
    done

    local choices
    read -p "请输入选项: " -a choices
    if [ ${#choices[@]} -eq 0 ]; then log_error "未输入任何选项！"; press_any_key; return; fi

    local combined_servers_str=""
    local selected_providers_str=""
    for choice in "${choices[@]}"; do
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#options[@]} ]]; then log_error "包含无效选项: $choice"; press_any_key; return; fi
        local selected_option=${options[$((choice-1))]}
        if [ "$selected_option" == "返回" ]; then return; fi
        combined_servers_str+="${dns_providers[$selected_option]} "
        selected_providers_str+="$selected_option, "
    done

    selected_providers_str=${selected_providers_str%, }
    log_info "你选择了: $selected_providers_str DNS"

    local servers_to_apply
    servers_to_apply="$(echo "$combined_servers_str" | tr ' ' '\n' | sort -u | tr '\n' ' ')"

    apply_dns_config "$servers_to_apply"
}

test_and_recommend_priority() {
    clear
    log_info "开始进行 IPv4 与 IPv6 网络质量测试..."
    ensure_dependencies "bc"

    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    local ipv6_addr
    ipv6_addr=$(get_public_ip v6)

    if [ -z "$ipv4_addr" ] || [ -z "$ipv6_addr" ]; then
        log_error "您的服务器不是一个标准的双栈网络环境，无法进行有意义的比较。"
        press_any_key
        return
    fi

    local test_url="http://cachefly.cachefly.net/100kb.test"
    log_info "将通过两种协议分别连接测试点: $test_url"

    local time_v4 time_v6

    log_info "正在测试 IPv4 连接速度..."
    time_v4=$(timeout 10 curl -4 -s -w '%{time_total}' -o /dev/null "$test_url" 2>/dev/null)

    log_info "正在测试 IPv6 连接速度..."
    time_v6=$(timeout 10 curl -6 -s -w '%{time_total}' -o /dev/null "$test_url" 2>/dev/null)

    echo
    log_info "测试结果:"

    local recommendation=""

    if [ -n "$time_v4" ] && [ "$(echo "$time_v4 > 0" | bc)" -eq 1 ]; then
        echo -e "$GREEN  IPv4 连接耗时: $time_v4 秒$NC"
    else
        time_v4="999" # 标记为失败
        echo -e "$RED  IPv4 连接失败或超时$NC"
    fi

    if [ -n "$time_v6" ] && [ "$(echo "$time_v6 > 0" | bc)" -eq 1 ]; then
        echo -e "$GREEN  IPv6 连接耗时: $time_v6 秒$NC"
    else
        time_v6="999" # 标记为失败
        echo -e "$RED  IPv6 连接失败或超时$NC"
    fi

    echo
    if [ "$time_v6" == "999" ] && [ "$time_v4" != "999" ]; then
        recommendation="IPv4"
        log_warn "测试发现 IPv6 连接存在问题，强烈建议您设置为【IPv4 优先】以保证网络稳定性。"
    elif [ "$time_v4" == "999" ] && [ "$time_v6" != "999" ]; then
        recommendation="IPv6"
        log_info "测试发现 IPv4 连接存在问题，您的网络环境可能更适合【IPv6 优先】。"
    elif [ "$time_v4" != "999" ] && [ "$time_v6" != "999" ]; then
        if (( $(echo "$time_v6 > $time_v4 * 1.3" | bc -l) )); then
            recommendation="IPv4"
            log_info "测试结果表明，您的 IPv4 连接速度明显优于 IPv6，推荐设置为【IPv4 优先】。"
        else
            recommendation="IPv6"
            log_info "测试结果表明，您的 IPv6 连接质量良好，推荐设置为【IPv6 优先】以使用现代网络。"
        fi
    else
        log_error "两种协议均连接失败，无法给出建议。请检查您的服务器网络配置。"
        press_any_key
        return
    fi

    echo
    read -p "是否要采纳此建议并应用设置? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 确保 /etc/gai.conf 存在
        touch /etc/gai.conf
        if [ "$recommendation" == "IPv6" ]; then
            log_info "正在设置为 [IPv6 优先]..."
            sed -i.bak '/^precedence ::ffff:0:0\/96/s/^/#/' /etc/gai.conf
            log_info "✅ 已成功设置为 IPv6 优先。"
        elif [ "$recommendation" == "IPv4" ]; then
            log_info "正在设置为 [IPv4 优先]..."
            # 先删除可能存在的被注释的行，再添加新的行，避免重复
            sed -i.bak '/^#\?precedence ::ffff:0:0\/96/d' /etc/gai.conf
            echo "precedence ::ffff:0:0/96  100" >>/etc/gai.conf
            log_info "✅ 已成功设置为 IPv4 优先。"
        fi
    else
        log_info "操作已取消。"
    fi
    press_any_key
}

network_priority_menu() {
    while true; do
        clear
        local current_setting="未知"
        if [ ! -f /etc/gai.conf ] || ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
             current_setting="${GREEN}IPv6 优先${NC}"
        else
             current_setting="${YELLOW}IPv4 优先${NC}"
        fi

        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 网络优先级设置                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC  当前设置: $current_setting                             $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. ${GREEN}自动测试并推荐最佳设置$NC                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 手动设置为 [IPv6 优先]                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 手动设置为 [IPv4 优先]                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1)
            test_and_recommend_priority
            ;;
        2)
            log_info "正在手动设置为 [IPv6 优先]..."
            touch /etc/gai.conf
            sed -i.bak '/^precedence ::ffff:0:0\/96/s/^/#/' /etc/gai.conf
            log_info "✅ 已成功设置为 IPv6 优先。"
            press_any_key
            ;;
        3)
            log_info "正在手动设置为 [IPv4 优先]..."
            touch /etc/gai.conf
            sed -i.bak '/^#\?precedence ::ffff:0:0\/96/d' /etc/gai.conf
            echo "precedence ::ffff:0:0/96  100" >>/etc/gai.conf
            log_info "✅ 已成功设置为 IPv4 优先。"
            press_any_key
            ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

setup_ssh_key() {
    log_info "开始设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    log_warn "请粘贴您的公钥 (例如 id_rsa.pub 的内容)，粘贴完成后，按 Enter 换行，再按一次 Enter 即可结束输入:"
    local public_key=""
    local line
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            break
        fi
        public_key+="$line"$'\n'
    done
    public_key=$(echo -e "$public_key" | sed '/^$/d')
    if [ -z "$public_key" ]; then
        log_error "没有输入公钥，操作已取消。"
        press_any_key
        return
    fi
    printf "%s\n" "$public_key" >>~/.ssh/authorized_keys
    sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
    log_info "公钥已成功添加到 authorized_keys 文件中。\n"
    read -p "是否要禁用密码登录 (强烈推荐)? (y/N): " disable_pwd
    if [[ "$disable_pwd" =~ ^[Yy]$ ]]; then
        log_info "正在修改 SSH 配置以禁用密码登录..."
        # 使用 .bak 后缀自动备份
        sed -i.bak -e 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' \
               -e 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

        log_info "正在重启 SSH 服务..."
        if systemctl restart sshd || systemctl restart ssh; then
             log_info "✅ SSH 服务已重启，密码登录已禁用。"
        else
             log_error "SSH 服务重启失败！请手动检查 'systemctl status ssh' 或 'sshd'。"
        fi
    fi
    log_info "✅ SSH 密钥登录设置完成。"
    press_any_key
}

manage_root_login() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                设置 root 登录方式                $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. ${GREEN}设置 SSH 密钥登录$NC (更安全，推荐)            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${YELLOW}设置 root 密码登录$NC (方便，兼容性好)         $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1)
            setup_ssh_key
            break
            ;;
        2)
            set_root_password
            break
            ;;
        0)
            break
            ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}

set_root_password() {
    log_info "开始设置 root 密码..."
    read -s -p "请输入新的 root 密码: " new_password
    echo ""
    read -s -p "请再次输入新的 root 密码以确认: " confirm_password
    echo ""

    if [ -z "$new_password" ]; then
        log_error "密码不能为空，操作已取消。"
        press_any_key
        return
    fi

    if [ "$new_password" != "$confirm_password" ]; then
        log_error "两次输入的密码不匹配，操作已取消。"
        press_any_key
        return
    fi

    log_info "正在更新 root 密码..."
    if ! echo "root:$new_password" | chpasswd; then
        log_error "密码更新失败！请检查 chpasswd 命令是否可用。"
        press_any_key
        return
    fi
    log_info "✅ root 密码已成功更新。"

    log_info "正在修改 SSH 配置文件以允许 root 用户通过密码登录..."

    # 自动备份
    sed -i.bak -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
           -e 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

    log_info "配置修改完成，正在重启 SSH 服务以应用更改..."
    if systemctl restart sshd || systemctl restart ssh; then
        log_info "✅ SSH 服务已重启。root 密码登录功能已成功设置！"
    else
        log_error "SSH 服务重启失败！请手动执行 'sudo systemctl status sshd' 进行检查。"
    fi

    press_any_key
}
set_timezone() {
    clear
    local current_timezone
    current_timezone=$(timedatectl show --property=Timezone --value)
    log_info "当前系统时区是: $current_timezone"
    log_info "请选择新的时区：\n"
    options=("Asia/Shanghai" "Asia/Taipei" "Asia/Hong_Kong" "Asia/Tokyo" "Europe/London" "America/New_York" "UTC" "返回上一级菜单")
    PS3="请输入选项: "
    select opt in "${options[@]}"; do
        if [[ "$opt" == "返回上一级菜单" ]]; then
            log_info "操作已取消。"
            break
        elif [[ -n "$opt" ]]; then
            log_info "正在设置时区为 $opt..."
            timedatectl set-timezone "$opt"
            log_info "✅ 时区已成功设置为：$opt"
            break
        else
            log_error "无效选项，请输入列表中的数字。"
        fi
    done
    unset PS3
    press_any_key
}
change_ssh_port() {
    clear
    log_info "开始修改 SSH 端口..."

    local current_port
    current_port=$(grep -iE '^#?Port' /etc/ssh/sshd_config | grep -oE '[0-9]+' | head -1)
    current_port=${current_port:-22}

    log_info "当前 SSH 端口是: $YELLOW$current_port$NC\n"

    local new_port
    while true; do
        read -p "请输入新的 SSH 端口 (推荐 1025-65535): " new_port
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
            log_error "无效的端口号。请输入 1-65535 之间的数字。"
        elif [ "$new_port" -eq "$current_port" ]; then
            log_error "新端口不能与当前端口 ($current_port) 相同。"
        elif ss -tln | grep -q ":$new_port\b"; then
            log_error "端口 $new_port 已被其他服务占用，请更换一个。"
        else
            break
        fi
    done

    log_info "新端口 $new_port 验证通过。"

    # 步骤1：处理防火墙 (至关重要)
    if command -v ufw &>/dev/null && ufw status | grep -q 'Status: active'; then
        log_info "检测到 UFW 防火墙，正在为端口 $new_port 创建规则..."
        ufw allow "$new_port/tcp"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        log_info "检测到 firewalld 防火墙，正在为端口 $new_port 创建规则..."
        firewall-cmd --permanent --add-port="$new_port/tcp"
        firewall-cmd --reload
    else
        log_warn "未检测到活动的 UFW 或 firewalld 防火墙。"
        log_warn "请务必手动在你的防火墙 (包括云服务商的安全组) 中开放 TCP 端口 $new_port，否则重启SSH后你将无法连接！"
    fi

    # 步骤2: 处理 SELinux (针对 CentOS/RHEL 等系统)
    if command -v sestatus &>/dev/null && sestatus | grep -q "SELinux status:\s*enabled"; then
        log_info "检测到 SELinux 已启用，正在更新端口策略..."
        # 适配多发行版
        local semanage_dep="policycoreutils-python-utils"
        if [ "$PKG_MANAGER" == "dnf" ]; then
            semanage_dep="python3-policycoreutils"
        fi
        ensure_dependencies "$semanage_dep"
        if command -v semanage &>/dev/null; then
            semanage port -a -t ssh_port_t -p tcp "$new_port"
            log_info "SELinux 策略已更新。"
        else
            log_error "无法执行 semanage 命令。请手动处理 SELinux 策略，否则 SSH 服务可能启动失败！"
        fi
    fi

    # 步骤3：修改 SSH 配置文件
    log_info "正在修改 /etc/ssh/sshd_config 文件..."
    # 自动备份
    sed -i.bak -E "s/^#?Port\s+[0-9]+/Port $new_port/" /etc/ssh/sshd_config

    # 步骤4：重启 SSH 服务
    log_info "正在重启 SSH 服务以应用新端口..."
    if systemctl restart sshd || systemctl restart ssh; then
        log_info "✅ SSH 服务已重启。"
        echo
        log_warn "========================= 重要提醒 ========================="
        log_warn "  SSH 端口已成功修改为: $YELLOW$new_port$NC"
        log_warn "  当前连接不会中断。请立即打开一个新的终端窗口进行测试！"
        log_info "  测试命令: ${GREEN}ssh root@<你的服务器IP> -p $new_port${NC}"
        log_warn "  在确认新端口可以正常登录之前，请【不要关闭】当前窗口！"
        log_warn "============================================================"

    else
        log_error "SSH 服务重启失败！配置可能存在问题。"
        log_error "正在尝试回滚 SSH 端口配置..."
        mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        systemctl restart sshd || systemctl restart ssh
        log_info "配置已回滚到端口 $current_port。请检查 sshd 服务日志。"
    fi

    press_any_key
}
manage_bbr() {
    clear
    log_info "开始检查并管理 BBR..."
    local kernel_version
    kernel_version=$(uname -r | cut -d- -f1)

    if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
         log_warn "在 CentOS/RHEL 系统上，推荐使用 ELRepo 的最新主线内核以获得最佳 BBR 支持。"
    fi

    if [ "$(printf '%s\n' "4.9" "$kernel_version" | sort -V | head -n1)" != "4.9" ]; then
        log_error "您的内核版本 ($kernel_version) 过低，无法开启 BBR。请升级内核至 4.9 或更高版本。"
        press_any_key
        return
    fi

    log_info "内核版本 $kernel_version 符合要求。"
    local current_congestion_control
    current_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control)
    log_info "当前 TCP 拥塞控制算法为: $YELLOW$current_congestion_control$NC"
    local current_queue_discipline
    current_queue_discipline=$(sysctl -n net.core.default_qdisc)
    log_info "当前网络队列管理算法为: $YELLOW$current_queue_discipline$NC"

    echo -e "\n请选择要执行的操作:"
    echo -e "\n1. 启用 BBR (原始版本)"
    echo -e "\n${GREEN}2. 启用 BBR + FQ${NC} (推荐)"
    echo -e "\n0. 返回\n"
    read -p "请输入选项: " choice

    local sysctl_conf="/etc/sysctl.d/99-bbr.conf"
    rm -f "$sysctl_conf"
    touch "$sysctl_conf"

    case $choice in
    1)
        log_info "正在启用 BBR..."
        echo "net.ipv4.tcp_congestion_control = bbr" >>"$sysctl_conf"
        ;;
    2)
        log_info "正在启用 BBR + FQ..."
        echo "net.core.default_qdisc = fq" >>"$sysctl_conf"
        echo "net.ipv4.tcp_congestion_control = bbr" >>"$sysctl_conf"
        ;;
    0)
        log_info "操作已取消。"
        return
        ;;
    *)
        log_error "无效选项！"
        press_any_key
        return
        ;;
    esac
    log_info "正在应用配置..."
    sysctl -p "$sysctl_conf"
    log_info "✅ 配置已应用！请检查上面的新算法是否已生效。"
    press_any_key
}

install_warp() {
    clear
    log_info "开始安装 WARP..."
    log_warn "本功能将使用 fscarmen 的多功能 WARP 脚本。"
    log_warn "脚本将引导您完成安装，请根据其提示进行选择。"
    press_any_key
    bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh)
    log_info "WARP 脚本执行完毕。按任意键返回主菜单。"
    press_any_key
}
# =================================================
#           实用工具 (增强) - 新增及优化
# =================================================

fail2ban_menu() {
    ensure_dependencies "fail2ban"
    if ! command -v fail2ban-client &>/dev/null; then
        log_error "Fail2Ban 未能成功安装，请检查依赖。"
        press_any_key
        return
    fi

    if [ ! -f /etc/fail2ban/jail.local ]; then
        log_info "未检测到 jail.local, 正在创建并启用 sshd 防护..."
        cat > /etc/fail2ban/jail.local <<-'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
        systemctl restart fail2ban
    fi


    while true; do
        clear
        if ! systemctl is-active --quiet fail2ban; then
            echo -e "$RED Fail2Ban 服务未运行！$NC"
            read -p "服务未运行，是否立即启动? (Y/n): " start_f2b
            if [[ ! "$start_f2b" =~ ^[Nn]$ ]]; then
                systemctl start fail2ban
                sleep 1
            else
                press_any_key
                return
            fi
        fi

        local status
        status=$(fail2ban-client status)
        local jail_count
        jail_count=$(echo "$status" | grep "Jail list" | sed -E 's/.*Jail list:\s*//')
        local sshd_status
        sshd_status=$(fail2ban-client status sshd 2>/dev/null) # 2>/dev/null 避免在 jail 不存在时报错
        local banned_count="0"
        local total_banned="0"
        if [ -n "$sshd_status" ]; then
            banned_count=$(echo "$sshd_status" | grep "Currently banned" | awk '{print $NF}')
            total_banned=$(echo "$sshd_status" | grep "Total banned" | awk '{print $NF}')
        fi


        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                  Fail2Ban 防护管理               $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  当前状态: ${GREEN}● 活动$NC, Jails: ${jail_count}                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  SSH 防护: 当前封禁 ${RED}$banned_count$NC,   历史共封禁 ${YELLOW}$total_banned$NC            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 查看 Fail2Ban 状态 (及SSH防护详情)          $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 查看最近的日志                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${YELLOW}手动解封一个 IP 地址$NC                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 重启 Fail2Ban 服务                          $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. ${RED}卸载 Fail2Ban$NC                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1)
            clear
            log_info "Fail2Ban 总体状态:"
            fail2ban-client status
            echo -e "\n$CYAN----------------------------------------------------$NC"
            log_info "SSHD 防护详情:"
            fail2ban-client status sshd
            press_any_key
            ;;
        2)
            clear
            log_info "显示最近 50 条 Fail2Ban 日志:"
            tail -50 /var/log/fail2ban.log
            press_any_key
            ;;
        3)
            read -p "请输入要解封的 IP 地址: " ip_to_unban
            if [ -n "$ip_to_unban" ]; then
                log_info "正在为 SSH 防护解封 IP: $ip_to_unban..."
                fail2ban-client set sshd unbanip "$ip_to_unban"
            else
                log_error "IP 地址不能为空！"
            fi
            press_any_key
            ;;
        4)
            log_info "正在重启 Fail2Ban..."
            systemctl restart fail2ban
            sleep 1
            log_info "服务已重启。"
            ;;
        5)
            read -p "确定要卸载 Fail2Ban 吗？(y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                log_info "正在停止并卸载 Fail2Ban..."
                systemctl stop fail2ban
                if [ "$PKG_MANAGER" == "apt" ]; then
                    apt-get remove --purge -y fail2ban
                else
                    "$PKG_MANAGER" remove -y fail2ban
                fi
                rm -rf /etc/fail2ban
                log_info "✅ Fail2Ban 已卸载。"
                press_any_key
                return
            fi
            ;;
        0) return ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

list_normal_users() {
    clear
    log_info "正在列出所有普通用户 (UID >= 1000)..."

    local user_list
    user_list=$(awk -F: '$3 >= 1000 && $3 != 65534 {
        printf "  - 用户名: \033[1;37m%-15s\033[0m UID: %-5s Shell: %s\n", $1, $3, $7
        printf "    主目录: %s\n\n", $6
    }' /etc/passwd)

    if [ -n "$user_list" ]; then
        echo -e "$CYAN--------------------------------------------------------------------$NC"
        echo -e "$user_list"
        echo -e "$CYAN--------------------------------------------------------------------$NC"
    else
        log_warn "未找到任何普通用户。"
    fi

    press_any_key
}

manage_users_menu() {
    ensure_dependencies "sudo" "shadow" # shadow provides useradd/usermod on some systems
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 Sudo 用户管理                    $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 列出所有普通用户                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 创建一个新的 Sudo 用户                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${RED}删除一个用户及其主目录$NC                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1)
            list_normal_users
            ;;
        2)
            clear
            echo -e "请为新用户选择主要的登录方式:\n"
            echo -e "  1. ${YELLOW}密码登录$NC (创建一个带密码的新用户)"
            echo -e "  2. ${GREEN}密钥登录$NC (创建用户, 并从现有用户复制公钥)"
            echo -e "\n  0. 返回\n"
            read -p "请输入选项: " login_choice

            if [[ "$login_choice" != "1" && "$login_choice" != "2" ]]; then
                continue
            fi

            read -p "请输入新用户名 (必须以小写字母开头): " username
            if [ -z "$username" ]; then log_error "用户名不能为空！"; press_any_key; continue; fi
            if ! [[ "$username" =~ ^[a-z][a-z0-9_-]*$ ]]; then log_error "用户名格式不正确！"; press_any_key; continue; fi
            if id "$username" &>/dev/null; then log_error "用户 '$username' 已存在！"; press_any_key; continue; fi

            useradd -m -s /bin/bash "$username"
            if [ $? -ne 0 ]; then
                log_error "创建用户 '$username' 失败！"
                press_any_key
                continue
            fi

            local sudo_group="sudo"
            if [ "$OS_ID" == "centos" ] || [ "$OS_ID" == "rhel" ] || [ "$OS_ID" == "fedora" ]; then
                sudo_group="wheel"
            fi
            usermod -aG "$sudo_group" "$username"
            log_info "✅ 用户 '$username' 已创建并添加到 $sudo_group 组。"

            if [ "$login_choice" == "1" ]; then
                log_info "请为用户 '$username' 设置密码。"
                passwd "$username"
                if [ $? -eq 0 ]; then
                    log_info "✅ 密码设置成功！"

                    local ssh_config_file="/etc/ssh/sshd_config"
                    if ! grep -q -E "^\s*PasswordAuthentication\s+yes" "$ssh_config_file" || grep -q -E "^\s*AuthenticationMethods"; then
                        echo
                        log_warn "检测到服务器当前可能禁止或限制密码登录。"
                        read -p "是否要自动修改SSH配置以确保密码登录可用? (Y/n): " allow_pwd
                        if [[ ! "$allow_pwd" =~ ^[Nn]$ ]]; then
                            sed -i.bak -E 's/^\s*#?\s*PasswordAuthentication\s+.*/PasswordAuthentication yes/' "$ssh_config_file"
                            if ! grep -q -E "^\s*PasswordAuthentication\s+yes" "$ssh_config_file"; then
                                echo "" >> "$ssh_config_file"; echo "PasswordAuthentication yes" >> "$ssh_config_file"
                            fi
                            sed -i.bak -E 's/^(\s*AuthenticationMethods\s+.*)/#\1/' "$ssh_config_file"

                            log_info "正在重启SSH服务以应用更改..."
                            if systemctl restart ssh || systemctl restart sshd; then
                                log_info "✅ SSH服务已重启, 密码登录应该已开启。"
                            else
                                log_error "SSH服务重启失败！请手动检查。"
                            fi
                        else
                            log_warn "您选择了不修改配置，新用户 '$username' 可能无法通过SSH登录。"
                        fi
                    fi
                else
                    log_error "密码设置失败或被取消！"
                fi
                press_any_key

            elif [ "$login_choice" == "2" ]; then
                log_info "正在为用户 '$username' 配置密钥登录..."
                passwd -l "$username" >/dev/null

                local source_user=""
                local source_key_file=""
                if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && [ -f "/home/$SUDO_USER/.ssh/authorized_keys" ]; then
                    source_user="$SUDO_USER"
                    source_key_file="/home/$source_user/.ssh/authorized_keys"
                else
                    local potential_users=()
                    while IFS= read -r user; do potential_users+=("$user"); done < <(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
                    potential_users+=("root")

                    for user in "${potential_users[@]}"; do
                        local key_path
                        if [ "$user" == "root" ]; then key_path="/root/.ssh/authorized_keys"; else key_path="/home/$user/.ssh/authorized_keys"; fi

                        if [ -s "$key_path" ]; then
                            source_user="$user"
                            source_key_file="$key_path"
                            break
                        fi
                    done
                fi

                if [ -n "$source_user" ]; then
                    log_info "检测到来自用户 '$source_user' 的可用公钥。"
                    mkdir -p "/home/$username/.ssh"
                    cp "$source_key_file" "/home/$username/.ssh/authorized_keys"
                    chown -R "$username:$username" "/home/$username/.ssh"
                    chmod 700 "/home/$username/.ssh"
                    chmod 600 "/home/$username/.ssh/authorized_keys"
                    log_info "✅ SSH 公钥已成功复制。"

                    echo
                    read -p "是否要配置sudo使其无需密码? (推荐 Y/n): " sudo_nopasswd
                    if [[ ! "$sudo_nopasswd" =~ ^[Nn]$ ]]; then
                        local sudo_config_file="/etc/sudoers.d/90-$username-nopasswd"
                        echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudo_config_file"
                        chmod 440 "$sudo_config_file"
                        log_info "✅ Sudo 已配置为免密。下次 '$username' 登录后可直接使用 sudo。"
                    fi
                    log_warn "现在, 你应该可以使用与 '$source_user' 相同的密钥直接登录 '$username' 用户了。"
                else
                    log_error "未在系统中找到任何可用的 SSH 公钥文件进行复制！"
                    log_warn "用户 '$username' 已创建但未配置密钥，且密码已被锁定。"
                fi
                press_any_key
            fi
            ;;
        3)
            clear
            log_info "正在获取可删除的普通用户列表..."

            local deletable_users=()
            mapfile -t deletable_users < <(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)

            if [ ${#deletable_users[@]} -eq 0 ]; then
                log_warn "未找到任何可删除的普通用户。"
                press_any_key
                continue
            fi

            log_info "请选择要删除的用户:\n"
            for i in "${!deletable_users[@]}"; do
                if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" == "${deletable_users[$i]}" ]; then
                     echo -e "   $((i + 1)). ${deletable_users[$i]} ${RED}(当前Sudo用户, 不可删除)${NC}"
                else
                     echo -e "   $((i + 1)). ${deletable_users[$i]}"
                fi
            done
            echo -e "\n   0. 返回\n"

            read -p "请输入选项: " choice_del
            if ! [[ "$choice_del" =~ ^[0-9]+$ ]]; then log_error "无效输入。"; press_any_key; continue; fi
            if [ "$choice_del" -eq 0 ]; then continue; fi
            if [ "$choice_del" -lt 1 ] || [ "$choice_del" -gt ${#deletable_users[@]} ]; then
                log_error "无效选项！"
                press_any_key
                continue
            fi

            local user_to_delete=${deletable_users[$((choice_del - 1))]}

            if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" == "$user_to_delete" ]; then
                log_error "为了系统安全，不能删除当前正在使用的 Sudo 用户 ('$SUDO_USER')！"
                press_any_key
                continue
            fi
            if [ "$user_to_delete" == "root" ]; then log_error "不能删除 root 用户！"; press_any_key; continue; fi

            read -p "警告：这将永久删除用户 '$user_to_delete' 及其主目录下的所有文件！确定吗？(y/N): " confirm_del
            if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                deluser --remove-home "$user_to_delete"
                rm -f "/etc/sudoers.d/90-$user_to_delete-nopasswd"
                log_info "✅ 用户 '$user_to_delete' 已被删除。"
            else
                log_info "操作已取消。"
            fi
            press_any_key
            ;;
        0) return ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
setup_auto_updates() {
    if [ "$PKG_MANAGER" != "apt" ]; then
        log_error "此功能目前仅支持基于 APT 的系统 (Debian/Ubuntu)。"
        press_any_key
        return
    fi

    ensure_dependencies "unattended-upgrades" "apt-listchanges"
    if [ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        log_error "unattended-upgrades 配置文件不存在，配置失败。"
        press_any_key
        return
    fi
    log_info "正在为您配置自动安全更新..."
    dpkg-reconfigure --priority=low -f noninteractive unattended-upgrades
    log_info "✅ unattended-upgrades 已配置并启用。"
    log_warn "系统现在会自动安装重要的安全更新。"
    press_any_key
}

performance_test_menu() {
     while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 VPS 性能测试                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. VPS 综合性能测试 (bench.sh)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 网络速度测试 (speedtest-cli)                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${GREEN}实时资源监控 (btop)${NC}                         $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. ${CYAN}流媒体解锁测试${NC}                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1)
            log_info "正在执行 bench.sh 脚本..."
            ensure_dependencies "curl"
            curl -Lso- bench.sh | bash
            press_any_key
            ;;
        2)
            log_info "正在执行 speedtest-cli..."
            ensure_dependencies "speedtest-cli"
            speedtest-cli
            press_any_key
            ;;
        3)
            log_info "正在启动 btop..."
            local btop_dep="btop"
            if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
                log_warn "在 CentOS/RHEL 上, btop 通常位于 EPEL 仓库。"
                log_warn "如果安装失败，请先手动安装 epel-release 包。"
            fi
            ensure_dependencies "$btop_dep"
            btop
            ;;
        4)
            log_info "正在执行流媒体解锁测试脚本 (by lmc999)..."
            ensure_dependencies "bash" "curl" "jq"
            bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)
            press_any_key
            ;;
        0) return ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

backup_directory() {
    clear
    log_info "开始手动备份指定目录..."

    local source_dir
    read -e -p "请输入需要备份的目录的绝对路径 (例如 /var/www): " source_dir
    if [ ! -d "$source_dir" ]; then
        log_error "目录 '$source_dir' 不存在或不是一个目录！"
        press_any_key
        return
    fi

    local backup_dest
    read -e -p "请输入备份文件存放的目标目录 [默认: /root]: " backup_dest
    backup_dest=${backup_dest:-"/root"}
    if [ ! -d "$backup_dest" ]; then
        log_warn "目标目录 '$backup_dest' 不存在，将尝试创建它..."
        mkdir -p "$backup_dest"
        if [ $? -ne 0 ]; then
            log_error "创建目标目录失败！"
            press_any_key
            return
        fi
    fi

    local dir_name
    dir_name=$(basename "$source_dir")
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_filename="${dir_name}_backup_${timestamp}.tar.gz"
    local full_backup_path="$backup_dest/$backup_filename"

    log_info "准备将 '$source_dir' 备份到 '$full_backup_path' ..."
    if tar -czvf "$full_backup_path" -C "$(dirname "$source_dir")" "$dir_name"; then
        log_info "✅ 备份成功！文件大小: $(du -sh "$full_backup_path" | awk '{print $1}')"
    else
        log_error "备份过程中发生错误！"
        rm -f "$full_backup_path"
    fi

    press_any_key
}

start_temp_web_server() {
    ensure_dependencies "python3"
    clear
    read -e -p "请输入要分享的目录 [默认: /root]: " dir
    dir=${dir:-"/root"}
    if [ ! -d "$dir" ]; then log_error "目录不存在！"; press_any_key; return; fi

    read -p "请输入要监听的端口 [默认: 8000]: " port
    port=${port:-8000}
    if ! check_port "$port"; then press_any_key; return; fi

    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    log_info "Web 服务器即将启动..."
    log_info "您可以通过以下地址访问:"
    log_info "http://$ipv4_addr:$port"
    log_warn "在当前目录下按 Ctrl+C 即可停止服务。"
    press_any_key

    (cd "$dir" && python3 -m http.server "$port")
}

upload_file_to_transfer() {
    ensure_dependencies "curl"
    clear
    read -e -p "请输入要上传的文件的完整路径: " file_path
    if [ ! -f "$file_path" ]; then
        log_error "文件 '$file_path' 不存在！"
        press_any_key
        return
    fi
    log_info "正在上传文件，请稍候..."

    local upload_url
    upload_url=$(curl --progress-bar --upload-file "$file_path" "https://transfer.sh/$(basename "$file_path")")

    echo ""
    if [[ "$upload_url" == https* ]]; then
        log_info "✅ 文件上传完成，下载链接如下:"
        echo -e "\n$YELLOW$upload_url$NC\n"
    else
        log_error "文件上传失败。服务器返回: $upload_url"
    fi
    press_any_key
}

file_sharing_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                  简易文件分享                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 启动临时 Web 服务器 (分享目录)              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 上传单个文件 (获取分享链接)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) start_temp_web_server ;;
        2) upload_file_to_transfer ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


utility_tools_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 实用工具 (增强)                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE安全与加固$CYAN ───────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. Fail2Ban 防护管理                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Sudo 用户管理                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 配置自动安全更新                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟───────────────── $WHITE性能 & 分享 & 备份$CYAN ─────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. VPS 性能测试                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 手动备份指定目录                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 简易文件分享                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) fail2ban_menu ;;
        2) manage_users_menu ;;
        3) setup_auto_updates ;;
        4) performance_test_menu ;;
        5) backup_directory ;;
        6) file_sharing_menu ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#               Sing-Box 管理 (singbox_main_menu)
# =================================================

is_singbox_installed() {
    if command -v sing-box &>/dev/null; then return 0; else return 1; fi
}

singbox_do_install() {
    ensure_dependencies "curl"
    if is_singbox_installed; then
        log_info "Sing-Box 已经安装，跳过安装过程。"
        press_any_key
        return
    fi
    log_info "正在安装Sing-Box ..."
    set -e
    bash <(curl -fsSL https://sing-box.app/deb-install.sh)
    set +e
    if ! is_singbox_installed; then
        log_error "Sing-Box 安装失败，请检查网络或脚本输出。"
        exit 1
    fi
    log_info "✅ Sing-Box 安装成功！"
    log_info "正在自动定位服务文件并修改运行权限..."
    local service_file_path
    service_file_path=$(systemctl status sing-box | grep -oP 'Loaded: loaded \(\K[^;]+')
    if [ -n "$service_file_path" ] && [ -f "$service_file_path" ]; then
        log_info "找到服务文件位于: $service_file_path"
        sed -i.bak 's/User=sing-box/User=root/' "$service_file_path"
        sed -i.bak 's/Group=sing-box/Group=root/' "$service_file_path"
        systemctl daemon-reload
        log_info "服务权限修改完成。"
    else
        log_error "无法自动定位 sing-box.service 文件！跳过权限修改。可能会导致证书读取失败。"
    fi
    local config_dir="/etc/sing-box"
    mkdir -p "$config_dir"
    if [ ! -f "$SINGBOX_CONFIG_FILE" ]; then
        log_info "正在创建兼容性更强的 Sing-Box 默认配置文件..."
        cat >"$SINGBOX_CONFIG_FILE" <<EOL
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {},
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      }
    ]
  }
}
EOL
    fi
    log_info "正在启用并重启 Sing-Box 服务..."
    systemctl enable sing-box.service
    systemctl restart sing-box
    log_info "✅ Sing-Box 配置文件初始化完成并已启动！"
    press_any_key
}

singbox_do_uninstall() {
    if ! is_singbox_installed; then
        log_warn "Sing-Box 未安装，无需卸载。"
        press_any_key
        return
    fi
    read -p "你确定要完全卸载 Sing-Box 吗？所有配置文件和节点信息都将被删除！(y/N): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        log_info "卸载操作已取消。"
        press_any_key
        return
    fi

    log_info "正在停止并禁用 Sing-Box 服务..."
    systemctl stop sing-box &>/dev/null
    systemctl disable sing-box &>/dev/null
    log_info "正在删除 Sing-Box 服务文件..."
    rm -f /etc/systemd/system/sing-box.service
    rm -f /etc/sing-box/config.json
    log_info "正在从所有常见路径删除 Sing-Box 可执行文件..."
    rm -f /usr/local/bin/sing-box
    rm -f /usr/bin/sing-box
    rm -f /bin/sing-box
    rm -f /usr/local/sbin/sing-box
    rm -f /sbin/sing-box
    log_info "正在删除 Sing-Box 配置文件和日志..."
    rm -rf /etc/sing-box
    rm -rf /var/log/sing-box
    log_info "正在重载 systemd 配置..."
    systemctl daemon-reload
    if command -v sing-box &>/dev/null; then
        log_error "卸载失败！系统中仍能找到 'sing-box' 命令。"
        log_warn "请手动执行 'whereis sing-box' 查找并删除残留文件。"
    else
        log_info "✅ Sing-Box 已成功卸载。"
    fi
    press_any_key
}

_create_self_signed_cert() {
    local domain_name="$1"
    local cert_dir="/etc/sing-box/certs"
    local cert_path="$cert_dir/$domain_name.cert.pem"
    local key_path="$cert_dir/$domain_name.key.pem"
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        log_info "检测到已存在的自签名证书，将直接使用。"
        return 0
    fi
    log_info "\n正在为域名 $domain_name 生成自签名证书..."
    mkdir -p "$cert_dir"
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=$domain_name"
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        log_info "✅ 自签名证书创建成功！"
        log_info "证书路径: $cert_path"
        log_info "密钥路径: $key_path"
        return 0
    else
        log_error "自签名证书创建失败！"
        return 1
    fi
}

_singbox_prompt_for_protocols() {
    local -n protocols_ref=$1
    local -n is_one_click_ref=$2

    clear
    echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
    echo -e "$CYAN║$WHITE              Sing-Box 节点协议选择               $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC   1. VLESS + WSS                                 $CYAN║$NC"
    echo -e "$CYAN║$NC   2. VMess + WSS                                 $CYAN║$NC"
    echo -e "$CYAN║$NC   3. Trojan + WSS                                $CYAN║$NC"
    echo -e "$CYAN║$NC   4. Hysteria2 (UDP)                             $CYAN║$NC"
    echo -e "$CYAN║$NC   5. TUIC v5 (UDP)                               $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC   6. $GREEN一键生成以上全部 5 种协议节点$NC               $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
    echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

    read -p "请输入选项: " protocol_choice

    case $protocol_choice in
    1) protocols_ref=("VLESS") ;;
    2) protocols_ref=("VMess") ;;
    3) protocols_ref=("Trojan") ;;
    4) protocols_ref=("Hysteria2") ;;
    5) protocols_ref=("TUIC") ;;
    6)
        protocols_ref=("VLESS" "VMess" "Trojan" "Hysteria2" "TUIC")
        is_one_click_ref=true
        ;;
    0) return 1 ;;
    *)
        log_error "无效选择，操作中止。"
        press_any_key
        return 1
        ;;
    esac
    return 0
}

_singbox_handle_certificate_setup() {
    local -n cert_path_ref=$1
    local -n key_path_ref=$2
    local -n connect_addr_ref=$3
    local -n sni_domain_ref=$4
    local -n insecure_params_ref=$5

    clear
    echo -e "\n请选择证书类型：\n\n${GREEN}1. 使用 Let's Encrypt 域名证书 (推荐)$NC\n\n2. 使用自签名证书 (IP 直连)\n"
    read -p "请输入选项 (1-2): " cert_choice

    if [ "$cert_choice" == "1" ]; then
        echo ""
        while true; do
            read -p "请输入您已解析到本机的域名: " domain
            if [[ -z "$domain" ]]; then log_error "域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确。"; else break; fi
        done
        if ! apply_ssl_certificate "$domain"; then log_error "证书处理失败。"; return 1; fi
        cert_path_ref="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_path_ref="/etc/letsencrypt/live/$domain/privkey.pem"
        connect_addr_ref="$domain"
        sni_domain_ref="$domain"
    elif [ "$cert_choice" == "2" ]; then
        insecure_params_ref["ws"]="&allowInsecure=1"
        insecure_params_ref["vmess"]=", \"skip-cert-verify\": true"
        insecure_params_ref["hy2"]="&insecure=1"
        insecure_params_ref["tuic"]="&allow_insecure=1"

        local ipv4_addr=$(get_public_ip v4)
        local ipv6_addr=$(get_public_ip v6)
        if [ -n "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
            echo -e "\n请选择用于节点链接的地址：\n\n1. IPv4: $ipv4_addr\n\n2. IPv6: $ipv6_addr\n"
            read -p "请输入选项 (1-2): " ip_choice
            if [ "$ip_choice" == "2" ]; then connect_addr_ref="[$ipv6_addr]"; else connect_addr_ref="$ipv4_addr"; fi
        elif [ -n "$ipv4_addr" ]; then log_info "将自动使用 IPv4 地址。"; connect_addr_ref="$ipv4_addr";
        elif [ -n "$ipv6_addr" ]; then log_info "将自动使用 IPv6 地址。"; connect_addr_ref="[$ipv6_addr]";
        else log_error "无法获取任何公网 IP 地址！"; return 1; fi

        read -p "请输入 SNI 伪装域名 [默认: www.bing.com]: " sni_input
        sni_domain_ref=${sni_input:-"www.bing.com"}
        if ! _create_self_signed_cert "$sni_domain_ref"; then log_error "自签名证书处理失败。"; return 1; fi
        cert_path_ref="/etc/sing-box/certs/$sni_domain_ref.cert.pem"
        key_path_ref="/etc/sing-box/certs/$sni_domain_ref.key.pem"
    else
        log_error "无效证书选择。"; return 1;
    fi
    log_info "证书处理完毕。"
    return 0
}

_singbox_prompt_for_ports() {
    local -n protocols_ref=$1
    local -n ports_ref=$2
    local -n used_ports_this_run_ref=$3
    local is_one_click=$4

    if $is_one_click; then
        log_info "您已选择一键模式，请为每个协议指定端口。"
        for p in "${protocols_ref[@]}"; do
            while true; do
                local port_prompt="请输入 [$p] 的端口 [回车则随机]: "
                if [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]]; then port_prompt="请输入 [$p] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
                read -p "$(echo -e "$port_prompt")" port_input
                if [ -z "$port_input" ]; then port_input=$(generate_random_port); log_info "已为 [$p] 生成随机端口: $port_input"; fi
                if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then log_error "端口号需为 1-65535。";
                elif _is_port_available "$port_input" "used_ports_this_run_ref"; then
                    ports_ref[$p]=$port_input
                    used_ports_this_run_ref+=("$port_input")
                    break
                fi
            done
        done
    else
        local protocol_name=${protocols_ref[0]}
        while true; do
            local port_prompt="请输入 [$protocol_name] 的端口 [回车则随机]: "
            if [[ "$protocol_name" == "Hysteria2" || "$protocol_name" == "TUIC" ]]; then port_prompt="请输入 [$protocol_name] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
            read -p "$(echo -e "$port_prompt")" port_input
            if [ -z "$port_input" ]; then port_input=$(generate_random_port); log_info "已生成随机端口: $port_input"; fi
            if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then log_error "端口号需为 1-65535。";
            elif _is_port_available "$port_input" "used_ports_this_run_ref"; then
                ports_ref[$protocol_name]=$port_input
                used_ports_this_run_ref+=("$port_input")
                break
            fi
        done
    fi
}

_singbox_build_protocol_config_and_link() {
    local protocol=$1
    local -n args_ref=$2
    local -n config_ref=$3
    local -n link_ref=$4

    local tag=${args_ref[tag]}
    local current_port=${args_ref[port]}
    local uuid=${args_ref[uuid]}
    local password=${args_ref[password]}
    local connect_addr=${args_ref[connect_addr]}
    local sni_domain=${args_ref[sni_domain]}
    local cert_path=${args_ref[cert_path]}
    local key_path=${args_ref[key_path]}
    local insecure_ws=${args_ref[insecure_ws]}
    local insecure_vmess=${args_ref[insecure_vmess]}
    local insecure_hy2=${args_ref[insecure_hy2]}
    local insecure_tuic=${args_ref[insecure_tuic]}

    local tls_config_tcp="{\"enabled\":true,\"server_name\":\"$sni_domain\",\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\"}"
    local tls_config_udp="{\"enabled\":true,\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\",\"alpn\":[\"h3\"]}"

    case $protocol in
    "VLESS" | "VMess" | "Trojan")
        config_ref="{\"type\":\"${protocol,,}\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[$(if
            [[ "$protocol" == "VLESS" || "$protocol" == "VMess" ]]
        then echo "{\"uuid\":\"$uuid\"}"; else echo "{\"password\":\"$password\"}"; fi)],\"tls\":$tls_config_tcp,\"transport\":{\"type\":\"ws\",\"path\":\"/\"}}"

        if [[ "$protocol" == "VLESS" ]]; then
            link_ref="vless://$uuid@$connect_addr:$current_port?type=ws&security=tls&sni=$sni_domain&host=$sni_domain&path=%2F${insecure_ws}#$tag"
        elif [[ "$protocol" == "VMess" ]]; then
            local vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$connect_addr\",\"port\":\"$current_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$sni_domain\",\"path\":\"/\",\"tls\":\"tls\"${insecure_vmess}}"
            link_ref="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
        else
            link_ref="trojan://$password@$connect_addr:$current_port?security=tls&sni=$sni_domain&type=ws&host=$sni_domain&path=/${insecure_ws}#$tag"
        fi
        ;;
    "Hysteria2")
        config_ref="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"password\":\"$password\"}],\"tls\":$tls_config_udp,\"up_mbps\":100,\"down_mbps\":1000}"
        link_ref="hysteria2://$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3${insecure_hy2}#$tag"
        ;;
    "TUIC")
        config_ref="{\"type\":\"tuic\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"uuid\":\"$uuid\",\"password\":\"$password\"}],\"tls\":$tls_config_udp}"
        link_ref="tuic://$uuid:$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3&congestion_control=bbr${insecure_tuic}#$tag"
        ;;
    esac
}

singbox_add_node_orchestrator() {
    ensure_dependencies "jq" "uuid-runtime" "curl" "openssl"

    local protocols_to_create=()
    local is_one_click=false
    if ! _singbox_prompt_for_protocols protocols_to_create is_one_click; then return; fi

    local cert_path key_path connect_addr sni_domain
    declare -A insecure_params
    if ! _singbox_handle_certificate_setup cert_path key_path connect_addr sni_domain insecure_params; then press_any_key; return; fi

    declare -A ports
    local used_ports_for_this_run=()
    _singbox_prompt_for_ports protocols_to_create ports used_ports_for_this_run "$is_one_click"

    read -p "请输入自定义标识 (如 Google, 回车则默认用 Jcole): " custom_id
    custom_id=${custom_id:-"Jcole"}

    local geo_info_json=$(curl -s ip-api.com/json)
    local country_code=$(echo "$geo_info_json" | jq -r '.countryCode // "N/A"')
    local region_name=$(echo "$geo_info_json" | jq -r '.regionName // "N/A"' | sed 's/ //g')

    local success_count=0
    local final_node_link=""
    local protocols_with_self_signed=()
    if [ ${#insecure_params[@]} -gt 0 ]; then
        protocols_with_self_signed=("${protocols_to_create[@]}")
    fi

    for protocol in "${protocols_to_create[@]}"; do
        local tag_base="$country_code-$region_name-$custom_id"
        local base_tag_for_protocol="$tag_base-$protocol"
        local tag=$(_get_unique_tag "$base_tag_for_protocol")
        log_info "已为 [$protocol] 节点分配唯一 Tag: $tag"

        declare -A build_args
        build_args[tag]="$tag"
        build_args[port]=${ports[$protocol]}
        build_args[uuid]=$(uuidgen)
        build_args[password]=$(generate_random_password)
        build_args[connect_addr]="$connect_addr"
        build_args[sni_domain]="$sni_domain"
        build_args[cert_path]="$cert_path"
        build_args[key_path]="$key_path"
        build_args[insecure_ws]=${insecure_params[ws]}
        build_args[insecure_vmess]=${insecure_params[vmess]}
        build_args[insecure_hy2]=${insecure_params[hy2]}
        build_args[insecure_tuic]=${insecure_params[tuic]}

        local config node_link
        _singbox_build_protocol_config_and_link "$protocol" build_args config node_link

        if _add_protocol_inbound "$protocol" "$config" "$node_link"; then
            ((success_count++))
            final_node_link="$node_link"
        fi
    done

    if [ "$success_count" -gt 0 ]; then
        log_info "共成功添加 $success_count 个节点，正在重启 Sing-Box..."
        systemctl restart sing-box
        sleep 2
        if systemctl is-active --quiet sing-box; then
            log_info "Sing-Box 重启成功。"
            if [ "$success_count" -eq 1 ] && ! $is_one_click; then
                log_info "✅ 节点添加成功！分享链接如下："
                echo -e "$CYAN--------------------------------------------------------------$NC"
                echo -e "\n$YELLOW$final_node_link$NC\n"
                echo -e "$CYAN--------------------------------------------------------------$NC"
            else
                log_info "正在跳转到节点管理页面..."
                sleep 1
            fi

            if [ ${#protocols_with_self_signed[@]} -gt 0 ]; then
                echo -e "\n$YELLOW========================= 重要操作提示 =========================$NC"
                for p in "${protocols_with_self_signed[@]}"; do
                    if [[ "$p" == "VMess" ]]; then
                        echo -e "\n${YELLOW}[VMess 节点]$NC"
                        log_warn "如果连接不通, 请在 Clash Verge 等客户端中, 手动找到该"
                        log_warn "节点的编辑页面, 勾选 ${GREEN}'跳过证书验证' (Skip Cert Verify)${YELLOW} 选项。"
                    fi
                    if [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]]; then
                        echo -e "\n${YELLOW}[$p 节点]$NC"
                        log_warn "这是一个 UDP 协议节点, 请务必确保您服务器的防火墙"
                        log_warn "已经放行了此节点使用的 UDP 端口: ${GREEN}${ports[$p]}${NC}"
                    fi
                done
                echo -e "\n$YELLOW==============================================================$NC"
            fi

            if [ "$success_count" -gt 1 ] || $is_one_click; then view_node_info; else press_any_key; fi
        else
            log_error "Sing-Box 重启失败！请使用 'journalctl -u sing-box -f' 查看详细日志。"
            log_warn "配置文件可能出错，旧的配置文件已备份为 $SINGBOX_CONFIG_FILE.tmp"
            press_any_key
        fi
    else
        log_error "没有任何节点被成功添加。"
        press_any_key
    fi
}


_get_unique_tag() {
    local base_tag="$1"
    local final_tag="$base_tag"
    local counter=2
    while jq -e --arg t "$final_tag" 'any(.inbounds[]; .tag == $t)' "$SINGBOX_CONFIG_FILE" >/dev/null; do
        final_tag="$base_tag-$counter"
        ((counter++))
    done
    echo "$final_tag"
}

_add_protocol_inbound() {
    local protocol=$1 config=$2 node_link=$3
    log_info "正在为 [$protocol] 协议添加入站配置..."
    local tmp_file="$SINGBOX_CONFIG_FILE.tmp"
    register_temp_file "$tmp_file"

    if ! jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" >"$tmp_file"; then
        log_error "[$protocol] 协议配置写入失败！请检查JSON格式。"
        return 1
    fi
    mv "$tmp_file" "$SINGBOX_CONFIG_FILE"
    echo "$node_link" >>"$SINGBOX_NODE_LINKS_FILE"
    log_info "✅ [$protocol] 协议配置添加成功！"
    return 0
}

view_node_info() {
    while true; do
        clear;
        if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
            log_warn "暂无配置的节点！"
            echo -e "\n1. 新增节点\n\n0. 返回上一级菜单\n"
            read -p "请输入选项: " choice
            if [[ "$choice" == "1" ]]; then singbox_add_node_orchestrator; continue; else return; fi
        fi

        log_info "当前已配置的节点链接信息："
        echo -e "${CYAN}--------------------------------------------------------------${NC}"

        mapfile -t node_lines < "$SINGBOX_NODE_LINKS_FILE"

        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local node_name
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "VMess节点"')
            fi
            echo -e "\n${GREEN}$((i + 1)). ${WHITE}${node_name}${NC}\n\n${line}"
            echo -e "\n${CYAN}--------------------------------------------------------------${NC}"
        done

        echo -e "\n1. 新增节点  2. 删除节点  3. 推送节点  4. ${YELLOW}生成临时订阅链接 (需Nginx)${NC}  5. ${BLUE}生成TUIC客户端配置(开发中)${NC}\n\n0. 返回上一级菜单\n"
        read -p "请输入选项: " choice

        case $choice in
            1) singbox_add_node_orchestrator; continue ;;
            2) delete_nodes; continue ;;
            3)  push_to_sub_store; continue ;;
            4) generate_subscription_link; continue ;;
            5) generate_tuic_client_config; continue ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

delete_nodes() {
    while true; do
        clear
        if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
            log_warn "没有节点可以删除。"
            press_any_key
            return
        fi
        mapfile -t node_lines <"$SINGBOX_NODE_LINKS_FILE"
        declare -A node_tags_map
        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local tag
            tag=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            node_tags_map[$i]=$tag
        done

        log_info "请选择要删除的节点 (可多选，用空格分隔, 输入 'all' 删除所有):\n"

        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local node_name=${node_tags_map[$i]}
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC\n"

        done
        read -p "请输入编号 (输入 0 返回上一级菜单): " -a nodes_to_delete
        local is_cancel=false
        for choice in "${nodes_to_delete[@]}"; do
            if [[ "$choice" == "0" ]]; then
                is_cancel=true
                break
            fi
        done
        if $is_cancel; then
            log_info "操作已取消，返回上一级菜单。"
            break
        fi
        if [[ "${nodes_to_delete[0]}" == "all" ]]; then
            read -p "你确定要删除所有节点吗？(y/N): " confirm_delete
            if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
                log_info "正在删除所有节点..."
                local tmp_file="$SINGBOX_CONFIG_FILE.tmp"
                register_temp_file "$tmp_file"
                jq '.inbounds = []' "$SINGBOX_CONFIG_FILE" >"$tmp_file" && mv "$tmp_file" "$SINGBOX_CONFIG_FILE"
                rm -f "$SINGBOX_NODE_LINKS_FILE"
                log_info "✅ 所有节点已删除。"
            else
                log_info "操作已取消。"
            fi
            systemctl restart sing-box
            break
        else
            local indices_to_delete=()
            local tags_to_delete=()
            local has_invalid_input=false
            for node_num in "${nodes_to_delete[@]}"; do
                if ! [[ "$node_num" =~ ^[0-9]+$ ]] || [[ $node_num -lt 1 || $node_num -gt ${#node_lines[@]} ]]; then
                    log_error "包含无效的编号: $node_num"
                    has_invalid_input=true
                    break
                fi
                indices_to_delete+=($((node_num - 1)))
                tags_to_delete+=("${node_tags_map[$((node_num - 1))]}")
            done
            if $has_invalid_input; then
                press_any_key
                continue
            fi
            if [ ${#indices_to_delete[@]} -eq 0 ]; then
                log_warn "未输入任何有效节点编号。"
                press_any_key
                continue
            fi
            log_info "正在从 config.json 中删除节点: ${tags_to_delete[*]}"

            local tmp_file1="$SINGBOX_CONFIG_FILE.tmp"
            local tmp_file2="$SINGBOX_CONFIG_FILE.tmp.2"
            register_temp_file "$tmp_file1"
            register_temp_file "$tmp_file2"
            cp "$SINGBOX_CONFIG_FILE" "$tmp_file1"

            for tag in "${tags_to_delete[@]}"; do
                jq --arg t "$tag" 'del(.inbounds[] | select(.tag == $t))' "$tmp_file1" >"$tmp_file2" && mv "$tmp_file2" "$tmp_file1"
            done
            mv "$tmp_file1" "$SINGBOX_CONFIG_FILE"

            local remaining_lines=()
            for i in "${!node_lines[@]}"; do
                local should_keep=true
                for del_idx in "${indices_to_delete[@]}"; do if [[ $i -eq $del_idx ]]; then
                    should_keep=false
                    break
                fi; done
                if $should_keep; then remaining_lines+=("${node_lines[$i]}"); fi
            done
            if [ ${#remaining_lines[@]} -eq 0 ]; then
                rm -f "$SINGBOX_NODE_LINKS_FILE"
            else
                printf "%s\n" "${remaining_lines[@]}" >"$SINGBOX_NODE_LINKS_FILE"
            fi
            log_info "✅ 所选节点已删除。"
            systemctl restart sing-box
            break
        fi
    done
    press_any_key
}

push_to_sub_store() {
    ensure_dependencies "curl" "jq"
    if [ ! -s "$SINGBOX_NODE_LINKS_FILE" ]; then
        log_warn "没有可推送的节点。"
        press_any_key
        return
    fi
    mapfile -t all_node_lines < "$SINGBOX_NODE_LINKS_FILE"

    local selected_links=()
    echo ""
    read -p "是否要手动选择节点? (默认推送全部, 输入 'y' 手动选择): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log_info "请选择要推送的节点 (可多选，用空格分隔):"
        echo ""
        for i in "${!all_node_lines[@]}"; do
            local line="${all_node_lines[$i]}"
            local node_name
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC\n"
        done
        read -p "请输入编号 (输入 0 返回): " -a selected_indices
        for index in "${selected_indices[@]}"; do
            if [[ "$index" == "0" ]]; then press_any_key; return; fi
            if ! [[ "$index" =~ ^[0-9]+$ ]] || [[ $index -lt 1 || $index -gt ${#all_node_lines[@]} ]]; then
                log_error "包含无效编号: $index"
                press_any_key
                return
            fi
            selected_links+=("${all_node_lines[$((index - 1))]}")
        done
    else
        log_info "已选择推送所有 ${#all_node_lines[@]} 个节点。"
        selected_links=("${all_node_lines[@]}")
    fi

    if [ ${#selected_links[@]} -eq 0 ]; then
        log_warn "未选择任何有效节点。"
        press_any_key
        return
    fi

    local sub_store_config_file="/etc/sing-box/sub-store-config.txt"
    local sub_store_subs
    if [ -f "$sub_store_config_file" ]; then
        sub_store_subs=$(grep "sub_store_subs=" "$sub_store_config_file" | cut -d'=' -f2)
    fi
    echo ""
    read -p "请输入 Sub-Store 的订阅标识 (name) [默认: $sub_store_subs]: " input_subs
    sub_store_subs=${input_subs:-$sub_store_subs}
    if [ -z "$sub_store_subs" ]; then
        log_error "Sub-Store 订阅标识不能为空！"
        press_any_key
        return
    fi

    echo ""
    local action
    read -p "请输入 action 参数 [默认: update]: " action
    action=${action:-"update"}

    local links_str
    links_str=$(printf "%s\n" "${selected_links[@]}")

    local node_json
    node_json=$(jq -n \
        --arg name "$sub_store_subs" \
        --arg link "$links_str" \
        --arg action "$action" \
        '{
            "token": "sanjose",
            "action": $action,
            "name": $name,
            "link": $link
        }')
    local response
    response=$(curl -s -X POST "https://store.wiitwo.eu.org/data" \
        -H "Content-Type: application/json" \
        -d "$node_json")

    if echo "$response" | jq -e '.success' >/dev/null; then
        echo "sub_store_subs=$sub_store_subs" >"$sub_store_config_file"
        log_info "✅ 节点信息已成功推送到 Sub-Store！"
        local success_message
        success_message=$(echo "$response" | jq -r '.message')
        log_info "服务器响应: $success_message"
    else
        local error_message
        error_message=$(echo "$response" | jq -r '.message // "未知错误"')
        log_error "推送到 Sub-Store 失败，服务器响应: $error_message"
    fi
    press_any_key
}

generate_subscription_link() {
    ensure_dependencies "nginx" "curl"
    if ! command -v nginx &>/dev/null; then
        log_error "Nginx 未安装，无法生成可访问的订阅链接。"
        press_any_key
        return
    fi
    if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
        log_warn "没有可用的节点来生成订阅链接。"
        press_any_key
        return
    fi
    local host=""
    if is_substore_installed && grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE"; then
        host=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
        log_info "检测到 Sub-Store 已配置域名，将使用: $host"
    fi
    if [ -z "$host" ]; then
        host=$(get_public_ip v4)
        log_info "未检测到配置的域名，将使用公网 IP: $host"
    fi
    if [ -z "$host" ]; then
        log_error "无法确定主机地址 (域名或IP)，操作中止。"
        press_any_key
        return
    fi
    local sub_dir="/var/www/html"
    mkdir -p "$sub_dir"
    local sub_filename
    sub_filename=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 16)
    local sub_filepath="$sub_dir/$sub_filename"

    # 注册临时文件以便自动删除
    register_temp_file "$sub_filepath"

    mapfile -t node_lines <"$SINGBOX_NODE_LINKS_FILE"
    local all_links_str
    all_links_str=$(printf "%s\n" "${node_lines[@]}")
    local base64_content
    base64_content=$(echo -n "$all_links_str" | base64 -w0)
    echo "$base64_content" >"$sub_filepath"
    local sub_url="http://$host/$sub_filename"
    clear
    log_info "已生成临时订阅链接，请立即复制使用！"
    log_warn "此链接将在您退出脚本后被自动删除。"
    echo -e "$CYAN--------------------------------------------------------------$NC"
    echo -e "\n$YELLOW$sub_url$NC\n"
    echo -e "$CYAN--------------------------------------------------------------$NC"
    press_any_key
}

generate_tuic_client_config() {
    clear
    log_warn "TUIC 客户端配置生成功能正在开发中..."
    log_info "此功能旨在为您选择的 TUIC 节点生成一个可以直接在客户端使用的 config.json 文件。"
    press_any_key
}

singbox_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sing-Box 管理                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        local STATUS_COLOR
        if is_singbox_installed; then
            if systemctl is-active --quiet sing-box; then STATUS_COLOR="$GREEN● 活动$NC"; else STATUS_COLOR="$RED● 不活动$NC"; fi
            echo -e "$CYAN║$NC  当前状态: $STATUS_COLOR                                $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 新增节点                                    $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   2. 管理节点                                    $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   3. 启动 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   4. 停止 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   5. 重启 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   6. 查看日志                                    $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   7. $RED卸载 Sing-Box$NC                               $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

            read -p "请输入选项: " choice
            case $choice in
            1) singbox_add_node_orchestrator ;; 2) view_node_info ;;
            3) systemctl start sing-box; log_info "命令已发送"; sleep 1 ;;
            4) systemctl stop sing-box; log_info "命令已发送"; sleep 1 ;;
            5) systemctl restart sing-box; log_info "命令已发送"; sleep 1 ;;
            6) clear; journalctl -u sing-box -f --no-pager ;;
            7) singbox_do_uninstall ;; 0) break ;; *) log_error "无效选项！"; sleep 1 ;;
            esac
        else
            echo -e "$CYAN║$NC  当前状态: $YELLOW● 未安装$NC                              $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 安装 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

            read -p "请输入选项: " choice
            case $choice in
            1) singbox_do_install ;; 0) break ;; *) log_error "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}
# =================================================
#                Sub-Store 管理
# =================================================

is_substore_installed() {
    if [ -f "$SUBSTORE_SERVICE_FILE" ]; then return 0; else return 1; fi
}

substore_do_install() {
    ensure_dependencies "curl" "unzip" "git"

    log_info "开始执行 Sub-Store 安装流程..."
    set -e

    log_info "正在安装 FNM (Node.js 版本管理器)..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /root/.fnm --skip-shell

    export PATH="/root/.fnm:$PATH"
    eval "$(fnm env)"
    log_info "FNM 安装完成。"

    log_info "正在使用 FNM 安装 Node.js (lts/iron)..."
    fnm install lts/iron
    fnm use lts/iron

    log_info "正在安装 pnpm..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    log_info "Node.js 和 PNPM 环境准备就绪。"

    log_info "正在下载并设置 Sub-Store 项目文件..."
    mkdir -p "$SUBSTORE_INSTALL_DIR"
    cd "$SUBSTORE_INSTALL_DIR" || exit 1
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"
    log_info "开始配置系统服务...\n"

    local API_KEY
    local random_api_key
    random_api_key=$(generate_random_password)
    read -p "请输入 Sub-Store 的 API 密钥 [回车则随机生成]: " user_api_key
    API_KEY=${user_api_key:-$random_api_key}
    if [ -z "$API_KEY" ]; then API_KEY=$(generate_random_password); fi
    log_info "最终使用的 API 密钥为: ${API_KEY}\n"
    local FRONTEND_PORT
    while true; do
        read -p "请输入前端访问端口 [默认: 3000]: " port_input
        FRONTEND_PORT=${port_input:-"3000"}
        if check_port "$FRONTEND_PORT"; then break; fi
    done
    local BACKEND_PORT
    while true; do
        echo ""
        read -p "请输入后端 API 端口 [默认: 3001]: " backend_port_input
        BACKEND_PORT=${backend_port_input:-"3001"}
        if [ "$BACKEND_PORT" == "$FRONTEND_PORT" ]; then log_error "后端端口不能与前端端口相同!"; else
            if check_port "$BACKEND_PORT"; then break; fi
        fi
    done

    cat <<EOF >"$SUBSTORE_SERVICE_FILE"
[Unit]
Description=Sub-Store Service
After=network-online.target
Wants=network-online.target
[Service]
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/${API_KEY}"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=${SUBSTORE_INSTALL_DIR}/frontend"
Environment="SUB_STORE_FRONTEND_HOST=::"
Environment="SUB_STORE_FRONTEND_PORT=${FRONTEND_PORT}"
Environment="SUB_STORE_DATA_BASE_PATH=${SUBSTORE_INSTALL_DIR}"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=${BACKEND_PORT}"
ExecStart=/root/.fnm/fnm exec --using lts/iron node ${SUBSTORE_INSTALL_DIR}/sub-store.bundle.js
Type=simple
User=root
Group=root
Restart=on-failure
RestartSec=5s
LimitNOFILE=32767
ExecStartPre=/bin/sh -c "ulimit -n 51200"
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF

    log_info "正在启动并启用 sub-store 服务..."
    systemctl daemon-reload
    systemctl enable "$SUBSTORE_SERVICE_NAME" >/dev/null
    systemctl start "$SUBSTORE_SERVICE_NAME"
    log_info "正在检测服务状态 (等待 5 秒)..."
    sleep 5
    set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ 服务状态正常 (active)。"
        substore_view_access_link
    else
        log_error "服务启动失败！请使用日志功能排查。"
    fi

    read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then substore_setup_reverse_proxy; else press_any_key; fi
}

substore_do_uninstall() {
    if ! is_substore_installed; then
        log_warn "Sub-Store 未安装，无需卸载。"
        press_any_key
        return
    fi

    read -p "你确定要完全卸载 Sub-Store 吗？所有配置文件都将被删除！(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi
    set -e
    log_info "正在停止并禁用 Sub-Store 服务..."
    systemctl stop "$SUBSTORE_SERVICE_NAME"
    systemctl disable "$SUBSTORE_SERVICE_NAME"
    log_info "正在删除服务文件..."
    rm -f "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    log_info "正在删除 Sub-Store 安装目录..."
    rm -rf "$SUBSTORE_INSTALL_DIR"
    set +e
    log_info "✅ Sub-Store 已成功卸载。"
    press_any_key
}

update_sub_store_app() {
    if ! is_substore_installed; then
        log_warn "Sub-Store 未安装，无法更新。"
        press_any_key
        return
    fi
    log_info "正在准备更新 Sub-Store..."
    cd "$SUBSTORE_INSTALL_DIR" || { log_error "无法进入安装目录: $SUBSTORE_INSTALL_DIR"; return; }

    log_info "正在下载最新的后端 bundle..."
    if ! curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js.new; then
        log_error "下载后端文件失败！"
        rm -f sub-store.bundle.js.new
        press_any_key
        return
    fi

    log_info "正在下载最新的前端资源..."
    if ! curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip.new; then
        log_error "下载前端资源失败！"
        rm -f dist.zip.new sub-store.bundle.js.new
        press_any_key
        return
    fi

    log_info "正在备份旧文件并应用更新..."
    mv sub-store.bundle.js sub-store.bundle.js.bak
    mv sub-store.bundle.js.new sub-store.bundle.js

    rm -rf frontend.bak
    mv frontend frontend.bak
    unzip -q -o dist.zip.new && mv dist frontend && rm dist.zip.new

    log_info "文件更新完毕，正在重启服务..."
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 3
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ Sub-Store 更新成功并已重启！"
    else
        log_error "服务重启失败，请使用日志功能排查问题。"
    fi
    press_any_key
}

substore_view_access_link() {
    if ! is_substore_installed; then
        log_warn "Sub-Store 未安装，无法查看链接。"
        return
    fi
    clear
    local frontend_port
    frontend_port=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')
    local api_key
    api_key=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')
    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    local proxy_domain
    proxy_domain=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')

    echo -e "$CYAN-------------------- Sub-Store 访问信息 ---------------------$NC\n"

    if [ -n "$proxy_domain" ]; then
        log_info "检测到反向代理域名，请使用以下链接访问："
        local backend_url="https://$proxy_domain$api_key"
        local final_url="https://$proxy_domain/?api=$backend_url"
        echo -e "\n  $YELLOW$final_url$NC\n"
        echo -e "$CYAN-----------------------------------------------------------$NC"
    fi

    log_info "您也可以通过 IP 地址访问 (如果防火墙允许):"
    local ip_backend_url="http://$ipv4_addr:$frontend_port$api_key"
    local ip_final_url="http://$ipv4_addr:$frontend_port/?api=$ip_backend_url"
    echo -e "\n  $YELLOW$ip_final_url$NC\n"
    echo -e "$CYAN-----------------------------------------------------------$NC"
}

substore_setup_reverse_proxy() {
    if ! is_substore_installed; then log_warn "请先安装 Sub-Store"; press_any_key; return; fi

    local frontend_port
    frontend_port=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')
    local domain

    log_info "此功能将为您自动配置 Web 服务器 (如 Nginx 或 Caddy) 进行反向代理。"
    log_info "您需要一个域名，并已将其 A/AAAA 记录解析到本服务器的 IP 地址。\n"

    read -p "请输入您的域名: " domain
    if [ -z "$domain" ]; then
        log_error "域名不能为空，操作已取消。"
        press_any_key
        return
    fi

    setup_auto_reverse_proxy "$domain" "$frontend_port"

    if [ $? -eq 0 ]; then
        log_info "正在将域名保存到服务配置中以供显示..."
        if grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE"; then
            sed -i.bak "s|SUB_STORE_REVERSE_PROXY_DOMAIN=.*|SUB_STORE_REVERSE_PROXY_DOMAIN=\"$domain\"|" "$SUBSTORE_SERVICE_FILE"
        else
            sed -i.bak "/^\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=$domain\"" "$SUBSTORE_SERVICE_FILE"
        fi
        systemctl daemon-reload
        log_info "✅ Sub-Store 反向代理设置完成！"
        log_info "正在显示最新的访问链接..."
        sleep 1
        substore_view_access_link
    else
        log_error "自动反向代理配置失败，请检查之前的错误信息。"
    fi

    press_any_key
}

substore_reset_ports() {
    if ! is_substore_installed; then log_warn "Sub-Store 未安装"; press_any_key; return; fi
    log_info "准备重置 Sub-Store 端口..."
    local NEW_FRONTEND_PORT
    while true; do
        read -p "请输入新的前端访问端口 [默认: 3000]: " port_input
        NEW_FRONTEND_PORT=${port_input:-"3000"}
        if check_port "$NEW_FRONTEND_PORT"; then break; fi
    done
    local NEW_BACKEND_PORT
    while true; do
        read -p "请输入新的后端 API 端口 [默认: 3001]: " backend_port_input
        NEW_BACKEND_PORT=${backend_port_input:-"3001"}
        if [ "$NEW_BACKEND_PORT" == "$NEW_FRONTEND_PORT" ]; then log_error "后端端口不能与前端端口相同!"; else
            if check_port "$NEW_BACKEND_PORT"; then break; fi
        fi
    done

    sed -i.bak "s/SUB_STORE_FRONTEND_PORT=.*/SUB_STORE_FRONTEND_PORT=${NEW_FRONTEND_PORT}/" "$SUBSTORE_SERVICE_FILE"
    sed -i.bak "s/SUB_STORE_BACKEND_API_PORT=.*/SUB_STORE_BACKEND_API_PORT=${NEW_BACKEND_PORT}/" "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    log_info "✅ 端口已更新，服务已重启。新的前端端口为: $NEW_FRONTEND_PORT"
    press_any_key
}

substore_reset_api_key() {
    if ! is_substore_installed; then log_warn "Sub-Store 未安装"; press_any_key; return; fi
    log_info "准备重置 API 密钥..."
    local NEW_API_KEY
    read -p "请输入新的 API 密钥 [回车则随机生成]: " user_api_key
    NEW_API_KEY=${user_api_key:-$(generate_random_password)}

    sed -i.bak "s|SUB_STORE_FRONTEND_BACKEND_PATH=.*|SUB_STORE_FRONTEND_BACKEND_PATH=/${NEW_API_KEY}|" "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    log_info "✅ API 密钥已更新，服务已重启。"
    log_info "新的 API 密钥是: $YELLOW$NEW_API_KEY$NC"
    press_any_key
}

substore_manage_menu() {
    while true; do
        clear
        local rp_menu_text="设置反向代理 (推荐)"
        if grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null; then
            rp_menu_text="更换反代域名"
        fi

        local STATUS_COLOR
        if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
            STATUS_COLOR="$GREEN● 活动$NC"
        else
            STATUS_COLOR="$RED● 不活动$NC"
        fi

        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                  Sub-Store 管理                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC  当前状态: $STATUS_COLOR                                $CYAN║$NC"
        echo -e "$CYAN╟──────────────────── $WHITE服务控制$CYAN ────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 启动服务            2. 停止服务             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 重启服务            4. 查看状态             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 查看日志                                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────── $WHITE参数配置$CYAN ────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 查看访问链接                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. 重置端口                                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. 重置 API 密钥                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. $YELLOW$rp_menu_text$NC                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) systemctl start "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
        2) systemctl stop "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
        3) systemctl restart "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
        4) clear; systemctl status "$SUBSTORE_SERVICE_NAME" -l --no-pager; press_any_key ;;
        5) clear; journalctl -u "$SUBSTORE_SERVICE_NAME" -f --no-pager ;;
        6) substore_view_access_link; press_any_key ;;
        7) substore_reset_ports ;;
        8) substore_reset_api_key ;;
        9) substore_setup_reverse_proxy ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

substore_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sub-Store 管理                 $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        local STATUS_COLOR
        if is_substore_installed; then
            if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then STATUS_COLOR="$GREEN● 活动$NC"; else STATUS_COLOR="$RED● 不活动$NC"; fi
            echo -e "$CYAN║$NC  当前状态: $STATUS_COLOR                                $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 管理 Sub-Store (启停/日志/配置)             $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   2. $GREEN更新 Sub-Store 应用$NC                         $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   3. $RED卸载 Sub-Store$NC                              $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) substore_manage_menu ;; 2) update_sub_store_app ;;
            3) substore_do_uninstall ;; 0) break ;; *) log_warn "无效选项！"; sleep 1 ;;
            esac
        else
            echo -e "$CYAN║$NC  当前状态: $YELLOW● 未安装$NC                              $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 安装 Sub-Store                              $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) substore_do_install ;; 0) break ;; *) log_warn "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}
# =================================================
#               哪吒监控 (nezha_main_menu)
# =================================================

is_nezha_agent_v0_installed() { [ -f "/etc/systemd/system/nezha-agent-v0.service" ]; }
is_nezha_agent_v1_installed() { [ -f "/etc/systemd/system/nezha-agent-v1.service" ]; }
is_nezha_agent_phoenix_installed() { [ -f "/etc/systemd/system/nezha-agent-phoenix.service" ]; }

uninstall_nezha_agent_v0() {
    if ! is_nezha_agent_v0_installed; then
        log_warn "San Jose V0 探针未安装，无需卸载。"
    else
        log_info "正在停止并禁用 nezha-agent-v0 服务..."
        systemctl stop nezha-agent-v0.service &>/dev/null
        systemctl disable nezha-agent-v0.service &>/dev/null
        rm -f /etc/systemd/system/nezha-agent-v0.service
        rm -rf /opt/nezha/agent-v0
        systemctl daemon-reload
        log_info "✅ SanJose V0 探针已成功卸载。"
    fi
    press_any_key
}

uninstall_nezha_agent_v1() {
    if ! is_nezha_agent_v1_installed; then
        log_warn "Nezha V1 探针未安装，无需卸载。"
    else
        log_info "正在停止并禁用 nezha-agent-v1 服务..."
        systemctl stop nezha-agent-v1.service &>/dev/null
        systemctl disable nezha-agent-v1.service &>/dev/null
        rm -f /etc/systemd/system/nezha-agent-v1.service
        rm -rf /opt/nezha/agent-v1
        systemctl daemon-reload
        log_info "✅ Nezha V1 探针已成功卸载。"
    fi
    press_any_key
}

uninstall_nezha_agent_phoenix() {
    if ! is_nezha_agent_phoenix_installed; then
        log_warn "Phoenix Nezha V1 探针未安装，无需卸载。"
    else
        log_info "正在停止并禁用 nezha-agent-phoenix 服务..."
        systemctl stop nezha-agent-phoenix.service &>/dev/null
        systemctl disable nezha-agent-phoenix.service &>/dev/null
        rm -f /etc/systemd/system/nezha-agent-phoenix.service
        rm -rf /opt/nezha/agent-phoenix
        systemctl daemon-reload
        log_info "✅ Phoenix Nezha V1 探针已成功卸载。"
    fi
    press_any_key
}

install_and_adapt_nezha_agent() {
    local version_id="$1"
    local official_script_url="$2"
    local install_command="$3"
    local service_name="nezha-agent-$version_id"
    local install_dir="/opt/nezha/agent-$version_id"
    local service_file="/etc/systemd/system/$service_name.service"

    log_info "正在为 Nezha Agent ($version_id) 执行通用安装流程..."

    if [ -f "$service_file" ]; then
        log_warn "检测到旧的 ($version_id) 安装，将先执行卸载..."
        systemctl stop "$service_name" &>/dev/null
        systemctl disable "$service_name" &>/dev/null
        rm -f "$service_file"
        rm -rf "$install_dir"
        systemctl daemon-reload
        log_info "旧版本清理完毕。"
    fi

    ensure_dependencies "curl" "wget" "unzip"

    local script_tmp_path="/tmp/nezha_install_${version_id}.sh"
    register_temp_file "$script_tmp_path"
    log_info "正在下载官方安装脚本..."
    if ! curl -L "$official_script_url" -o "$script_tmp_path"; then
        log_error "下载官方脚本失败！"
        press_any_key
        return 1
    fi
    chmod +x "$script_tmp_path"

    log_info "第1步：执行官方原版脚本进行标准安装..."
    eval "$install_command"
    rm "$script_tmp_path"

    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
        log_error "官方脚本未能成功创建标准服务，操作中止。"
        press_any_key
        return 1
    fi
    log_info "标准服务安装成功，即将开始改造..."
    sleep 1

    log_info "第2步：停止标准服务并重命名文件以实现隔离..."
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null
    mv /etc/systemd/system/nezha-agent.service "$service_file"
    mv /opt/nezha/agent "$install_dir"

    log_info "第3步：修改新的服务文件，使其指向正确的路径..."
    sed -i.bak "s|/opt/nezha/agent|$install_dir|g" "$service_file"

    log_info "第4步：重载并启动改造后的 '$service_name' 服务..."
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl start "$service_name"

    log_info "检查最终服务状态..."
    sleep 2
    if systemctl is-active --quiet "$service_name"; then
        log_info "✅ Nezha Agent ($version_id) (隔离版) 已成功安装并启动！"
    else
        log_error "Nezha Agent ($version_id) (隔离版) 最终启动失败！"
        log_warn "显示详细状态以供诊断:"
        systemctl status "$service_name" --no-pager -l
    fi
    press_any_key
}

_nezha_v1_style_installer() {
    local version_id="$1"
    local friendly_name="$2"
    local server_info="$3"
    local server_secret="$4"

    local user_command
    read -p "您正在安装 $friendly_name 探针，请输入安装指令以继续: " user_command
    if [ "$user_command" != "csos" ]; then
        log_error "指令错误，安装已中止。"
        press_any_key
        return 1
    fi

    local NZ_TLS="false"
    local script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh"
    local command_to_run="export NZ_SERVER='$server_info' NZ_TLS='$NZ_TLS' NZ_CLIENT_SECRET='$server_secret'; bash /tmp/nezha_install_${version_id}.sh"

    install_and_adapt_nezha_agent "$version_id" "$script_url" "$command_to_run"
}

install_nezha_agent_v0() {
    local server_key
    read -p "请输入San Jose V0哪吒面板密钥: " server_key
    if [ -z "$server_key" ]; then
        log_error "面板密钥不能为空！操作中止。"
        press_any_key
        return
    fi

    local server_addr="nz.wiitwo.eu.org"
    local server_port="443"
    local tls_option="--tls"
    local script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/install_en.sh"
    local command_to_run="bash /tmp/nezha_install_v0.sh install_agent $server_addr $server_port $server_key $tls_option"

    install_and_adapt_nezha_agent "v0" "$script_url" "$command_to_run"
}

install_nezha_agent_v1() {
    _nezha_v1_style_installer "v1" "London V1" "nz.ssong.eu.org:8008" "Pln0X91X18urAudToiwDGVlZhkpUb0Qv"
}

install_nezha_agent_phoenix() {
    _nezha_v1_style_installer "phoenix" "Phoenix V1" "nz.chat.nyc.mn:8008" "XuqVRw4XcOtDDFwz8ipJN9v7HcQZe7M3"
}

install_nezha_dashboard_v0() {
    ensure_dependencies "wget"
    log_info "即将运行 fscarmen 的 V0 面板安装/管理脚本..."
    press_any_key
    bash <(wget -qO- https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh)
    log_info "脚本执行完毕。"
    press_any_key
}

install_nezha_dashboard_v1() {
    ensure_dependencies "curl"
    log_info "即将运行官方 V1 面板安装/管理脚本..."
    press_any_key
    curl -L https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
    log_info "脚本执行完毕。"
    press_any_key
}

nezha_agent_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE               哪吒探针 (Agent) 管理              $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"

        local v0_status
        if is_nezha_agent_v0_installed; then v0_status="${GREEN}(已安装)$NC"; else v0_status="${YELLOW}(未安装)$NC"; fi
        local v1_status
        if is_nezha_agent_v1_installed; then v1_status="${GREEN}(已安装)$NC"; else v1_status="${YELLOW}(未安装)$NC"; fi
        local phoenix_status
        if is_nezha_agent_phoenix_installed; then phoenix_status="${GREEN}(已安装)$NC"; else phoenix_status="${YELLOW}(未安装)$NC"; fi

        echo -e "$CYAN║$NC   1. 安装/重装 San Jose V0 探针 $v0_status         $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. $RED卸载 San Jose V0 探针$NC                       $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 安装/重装 London V1 探针 $v1_status           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. $RED卸载 London V1 探针$NC                         $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 安装/重装 Phoenix V1 探针 $phoenix_status          $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. $RED卸载 Phoenix V1 探针$NC                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_agent_v0 ;;
        2) uninstall_nezha_agent_v0 ;;
        3) install_nezha_agent_v1 ;;
        4) uninstall_nezha_agent_v1 ;;
        5) install_nezha_agent_phoenix ;;
        6) uninstall_nezha_agent_phoenix ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

nezha_dashboard_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                哪吒面板 (Dashboard) 管理         $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 安装/管理 V0 面板 (by fscarmen)             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 安装/管理 V1 面板 (Official)                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        log_warn "面板安装脚本均来自第三方，其内部已集成卸载和管理功能。"
        log_warn "如需卸载或管理，请再次运行对应的安装选项即可。"

        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_dashboard_v0 ;;
        2) install_nezha_dashboard_v1 ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

nezha_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 哪吒监控管理                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. Agent 管理 (本机探针)                       $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Dashboard 管理 (服务器面板)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) nezha_agent_menu ;;
        2) nezha_dashboard_menu ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#           新增：Docker 通用管理 (V2.0 增强版)
# =================================================

# 通用的辅助函数，用于选择一个项目（容器或镜像）并对其执行操作
_docker_select_and_perform_action() {
    local item_type="$1"       # "容器" 或 "镜像"
    local list_command="$2"    # 'docker ps -a' 或 'docker images'
    local action_command="$3"  # 'docker start', 'docker stop', 'docker rm' 等
    local prompt_message="$4"  # "请输入要启动的容器..."
    local confirmation_needed=$5 # "true" 或 "false"
    local confirmation_message="$6" # "确定要强制删除吗？"

    clear
    log_info "当前所有${item_type}列表:"
    eval "$list_command"
    echo ""

    local target_id
    read -p "$prompt_message" target_id
    if [ -z "$target_id" ]; then
        log_error "${item_type}名称或ID不能为空！"
        press_any_key
        return
    fi

    if [ "$confirmation_needed" = "true" ]; then
        read -p "$confirmation_message (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "操作已取消。"
            press_any_key
            return
        fi
    fi

    log_info "正在对 ${item_type} [$target_id] 执行操作..."
    if eval "$action_command '$target_id'"; then
        log_info "✅ 操作成功！"
    else
        log_error "操作失败！请检查 ${item_type} 名称/ID 是否正确，或查看 Docker 的错误提示。"
    fi
    press_any_key
}

# --- 容器管理函数 ---
docker_list_containers() {
    clear
    log_info "列出所有 Docker 容器 (包括已停止的):"
    docker ps -a
    press_any_key
}

docker_start_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker start" "请输入要启动的容器名称或ID: "
}

docker_stop_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker stop" "请输入要停止的容器名称或ID: "
}

docker_restart_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker restart" "请输入要重启的容器名称或ID: "
}

docker_view_logs() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker logs -f" "请输入要查看日志的容器名称或ID: "
}

docker_remove_stopped_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker rm" \
    "请输入要删除的【已停止】容器名称或ID: " "true" \
    "警告：此操作将永久删除容器，但保留其命名数据卷。确定吗？"
}

docker_force_remove_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker rm -fv" \
    "请输入要【强制】删除的容器名称或ID: " "true" \
    "警告：此操作将强制停止并永久删除容器，并会删除其关联的【匿名】数据卷！确定吗？"
}

# --- 镜像管理函数 ---
docker_list_images() {
    clear
    log_info "列出所有 Docker 镜像:"
    docker images
    press_any_key
}

docker_remove_image() {
    _docker_select_and_perform_action "镜像" "docker images" "docker rmi" \
    "请输入要删除的镜像名称或ID: " "true" \
    "警告：如果该镜像正被容器使用，删除会失败。确定要删除吗？"
}

docker_prune_images() {
    clear
    log_warn "此操作将删除所有未被任何容器使用的“悬空”镜像 (dangling images)。"
    read -p "这是一个安全的清理操作，确定要继续吗? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "正在执行清理..."
        docker image prune -af
        log_info "✅ 未使用镜像清理完成。"
    else
        log_info "操作已取消。"
    fi
    press_any_key
}

# --- 系统级管理函数 ---
docker_prune_system() {
    clear
    log_warn "此操作将删除所有已停止的容器、未被任何容器使用的网络、"
    log_warn "所有悬空镜像 (dangling images) 以及所有悬空构建缓存。"
    read -p "这是一个全面的清理操作，确定要继续吗? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "正在执行清理..."
        docker system prune -af
        log_info "✅ 系统清理完成。"
    else
        log_info "操作已取消。"
    fi
    press_any_key
}

install_portainer() {
    if ! _install_docker_and_compose; then press_any_key; return; fi
    clear
    log_info "正在准备安装 Portainer-CE (Docker 管理面板)..."

    local https_port http_port
    while true; do
        read -p "请输入 Portainer 的 HTTPS 访问端口 (默认: 9443): " https_port
        https_port=${https_port:-"9443"}
        if check_port "$https_port"; then break; fi
    done
    while true; do
        read -p "请输入 Portainer 的 HTTP 端口 (默认: 8000): " http_port
        http_port=${http_port:-"8000"}
        if [[ "$http_port" == "$https_port" ]]; then
            log_error "HTTP 端口不能与 HTTPS 端口相同！"
        elif check_port "$http_port"; then
            break
        fi
    done

    log_info "正在安装 Portainer..."
    docker volume create portainer_data
    docker run -d \
        -p "$http_port:8000" \
        -p "$https_port:9443" \
        --name portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest

    sleep 5
    if docker ps | grep -q "portainer"; then
        log_info "✅ Portainer 已成功启动！"

        read -p "安装已完成，是否立即为其设置反向代理 (需提前解析好域名)？(Y/n): " setup_proxy_choice
        if [[ ! "$setup_proxy_choice" =~ ^[Nn]$ ]]; then
            local domain
            while true; do
                read -p "请输入您为 Portainer 准备的域名: " domain
                if [[ -z "$domain" ]]; then log_error "域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确。"; else break; fi
            done

            if setup_auto_reverse_proxy "$domain" "$https_port"; then
                log_info "✅ Portainer 反向代理设置完成！"
                log_info "请通过以下地址访问 (Caddy 会自动处理证书，Nginx 会使用 Let's Encrypt):"
                log_info "https://$domain"
            else
                log_error "反向代理设置失败，请检查之前的错误信息。"
            fi
        else
            local public_ip=$(get_public_ip v4)
            log_info "好的，您选择不设置反向代理。请通过 IP 地址访问进行初始化设置:"
            log_info "https://$public_ip:$https_port"
            log_warn "首次访问浏览器可能会提示证书不安全，请选择“继续前往”。"
        fi
    else
        log_error "Portainer 启动失败，请检查 Docker 日志。"
    fi
    press_any_key
}


# --- 子菜单定义 ---

docker_container_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                     容器管理                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 列出所有容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 启动一个容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 停止一个容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 重启一个容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 查看容器实时日志                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. ${YELLOW}删除已停止的容器$NC                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. ${RED}强制删除容器 (并清理数据)${NC}                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) docker_list_containers ;;
        2) docker_start_container ;;
        3) docker_stop_container ;;
        4) docker_restart_container ;;
        5) docker_view_logs ;;
        6) docker_remove_stopped_container ;;
        7) docker_force_remove_container ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

docker_image_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                     镜像管理                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
       echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 列出所有镜像                                $CYAN║$NC"
       echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${YELLOW}删除一个指定镜像$NC                            $CYAN║$NC"
       echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${RED}清理所有未使用的镜像${NC}                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) docker_list_images ;;
        2) docker_remove_image ;;
        3) docker_prune_images ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# --- 主管理菜单 (V2.0) ---
docker_manage_menu() {
    if ! command -v docker &>/dev/null; then
        _install_docker_and_compose
        if ! command -v docker &>/dev/null; then
             log_error "Docker 安装失败，无法进入管理菜单。"
             press_any_key
             return
        fi
    fi

    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 Docker 通用管理                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. ${GREEN}容器管理${NC} (启停/删除/日志)                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${GREEN}镜像管理${NC} (删除/清理)                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${RED}清理 Docker 系统 (释放空间)${NC}                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 安装 Portainer 图形化管理面板               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) docker_container_menu ;;
        2) docker_image_menu ;;
        3) docker_prune_system ;;
        4) install_portainer ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# =================================================
#           Docker 应用 & 面板 (docker_apps_menu)
# =================================================

_install_docker_and_compose() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "Docker 和 Docker Compose V2 已安装。"
        return 0
    fi
    log_warn "未检测到完整的 Docker 环境，开始执行官方标准安装流程..."

    case "$PKG_MANAGER" in
        apt)
            ensure_dependencies "ca-certificates" "curl" "gnupg"
            log_info "正在添加 Docker 官方 GPG 密钥..."
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            log_info "正在添加 Docker 软件仓库..."
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS_ID $OS_VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            set -e
            apt-get update -y
            log_info "正在安装 Docker Engine, CLI, Containerd, 和 Docker Compose 插件..."
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        yum|dnf)
            ensure_dependencies "curl"
            if [ "$PKG_MANAGER" == "yum" ]; then ensure_dependencies "yum-utils"; fi
            log_info "正在添加 Docker 软件仓库..."
            local repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
            if [ "$OS_ID" == "fedora" ]; then repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"; fi

            if command -v dnf &>/dev/null; then
                dnf config-manager --add-repo "$repo_url"
            elif command -v yum-config-manager &>/dev/null; then
                 yum-config-manager --add-repo "$repo_url"
            else
                log_error "缺少 config-manager, 无法自动添加仓库。"
                return 1
            fi

            set -e
            log_info "正在安装 Docker Engine, CLI, Containerd, 和 Docker Compose 插件..."
            "$PKG_MANAGER" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac

    set +e
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "✅ Docker 和 Docker Compose V2 已成功安装！"
        systemctl start docker
        systemctl enable docker
        return 0
    else
        log_error "Docker 环境安装失败！请检查上面的日志输出。"
        return 1
    fi
}

uninstall_docker_compose_project() {
    local app_name=$1
    local default_dir=$2
    local project_dir

    read -e -p "请输入要卸载的 $app_name 的安装目录 [默认: $default_dir]: " project_dir
    project_dir=${project_dir:-$default_dir}

    if [ ! -f "$project_dir/docker-compose.yml" ]; then
        log_error "目录 $project_dir 下未找到 docker-compose.yml 文件，请确认路径。"
        press_any_key
        return
    fi

    log_info "准备卸载位于 $project_dir 的 $app_name..."
    cd "$project_dir" || { log_error "无法进入目录 $project_dir"; press_any_key; return 1; }

    read -p "警告：这将停止并永久删除 $app_name 的所有容器和数据卷！此操作不可逆！是否继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi

    log_info "正在停止并移除容器和数据卷..."
    docker compose down --volumes

    cd ..
    read -p "是否要删除项目目录 $project_dir 及其所有文件？(y/N): " confirm_delete_dir
    if [[ "$confirm_delete_dir" =~ ^[Yy]$ ]]; then
        log_info "正在删除项目目录 $project_dir ..."
        rm -rf "$project_dir"
        log_info "项目目录已删除。"
    fi

    log_info "✅ $app_name 卸载完成。"
    press_any_key
}

install_sui() {
    ensure_dependencies "curl"
    log_info "正在准备安装 S-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
    log_info "S-ui 安装脚本执行完毕。"
    press_any_key
}

install_3xui() {
    ensure_dependencies "curl"
    log_info "正在准备安装 3X-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    log_info "3X-ui 安装脚本执行完毕。"
    press_any_key
}

install_wordpress() {
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建 WordPress。"
        press_any_key
        return
    fi
    clear
    log_info "开始使用 Docker Compose 搭建 WordPress..."

    local project_dir
    while true; do
        read -e -p "请输入新 WordPress 项目的安装目录 [默认: /root/wordpress]: " project_dir
        project_dir=${project_dir:-"/root/wordpress"}
        if [ -f "$project_dir/docker-compose.yml" ]; then
            log_error "错误：目录 \"$project_dir\" 下已存在一个 WordPress 站点！"
            read -p "是否要先卸载它？(y/N): " uninstall_choice
            if [[ "$uninstall_choice" =~ ^[Yy]$ ]]; then
                uninstall_wordpress
                if [ -d "$project_dir" ]; then continue; else break; fi
            else
                log_warn "请为新的 WordPress 站点选择一个不同的、全新的目录。"
                continue
            fi
        else
            break
        fi
    done
    mkdir -p "$project_dir" || {
        log_error "无法创建目录 $project_dir！"
        press_any_key
        return 1
    }
    cd "$project_dir" || {
        log_error "无法进入目录 $project_dir！"
        press_any_key
        return 1
    }
    log_info "新的 WordPress 将被安装在: $(pwd)"

    local db_password
    read -s -p "请输入新的数据库 root 和用户密码 [默认随机生成]: " db_password
    db_password=${db_password:-$(generate_random_password)}
    echo ""
    log_info "数据库密码已设置为: $db_password"

    local wp_port
    while true; do
        read -p "请输入 WordPress 的外部访问端口 (例如 8080): " wp_port
        if [[ ! "$wp_port" =~ ^[0-9]+$ ]] || [ "$wp_port" -lt 1 ] || [ "$wp_port" -gt 65535 ]; then
            log_error "端口号必须是 1-65535 之间的数字。"
        elif ! check_port "$wp_port"; then
            :
        else break; fi
    done

    local domain
    while true; do
        read -p "请输入您的网站访问域名 (例如 blog.example.com): " domain
        if [[ -z "$domain" ]]; then log_error "网站域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确，请重新输入。"; else break; fi
    done
    local site_url="https://$domain"
    log_info "正在生成 docker-compose.yml 文件..."
    cat >docker-compose.yml <<EOF
version: '3.8'

services:
  db:
    image: mysql:8.0
    container_name: ${project_dir##*/}_db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_DATABASE=wordpress
      - MYSQL_USER=wp_user
      - MYSQL_PASSWORD=$db_password
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - wordpress_net

  wordpress:
    depends_on:
      - db
    image: wordpress:latest
    container_name: ${project_dir##*/}_app
    restart: always
    ports:
      - "$wp_port:80"
    environment:
      - WORDPRESS_DB_HOST=db:3306
      - WORDPRESS_DB_USER=wp_user
      - WORDPRESS_DB_PASSWORD=$db_password
      - WORDPRESS_DB_NAME=wordpress
      - WORDPRESS_SITEURL=$site_url
      - WORDPRESS_HOME=$site_url
    volumes:
      - wp_files:/var/www/html
    networks:
      - wordpress_net

volumes:
  db_data:
  wp_files:

networks:
  wordpress_net:
EOF
    if [ ! -f "docker-compose.yml" ]; then
        log_error "docker-compose.yml 文件创建失败！"
        press_any_key
        return
    fi

    log_info "正在使用 Docker Compose 启动 WordPress 和数据库服务..."
    log_warn "首次启动需要下载镜像，可能需要几分钟时间，请耐心等待..."
    docker compose up -d

    log_info "正在检查服务状态..."
    sleep 5
    docker compose ps

    log_info "✅ WordPress 容器已成功启动！"

    read -p "是否立即为其设置反向代理 (需提前解析好域名)？(Y/n): " setup_proxy_choice
    if [[ ! "$setup_proxy_choice" =~ ^[Nn]$ ]]; then
        setup_auto_reverse_proxy "$domain" "$wp_port"
        log_info "WordPress 配置流程完毕！您现在应该可以通过 $site_url 访问您的网站了。"
    else
        log_info "好的，您选择不设置反向代理。"
        log_info "您可以通过以下 IP 地址完成 WordPress 的初始化安装："
        local ipv4
        ipv4=$(get_public_ip v4)
        if [ -n "$ipv4" ]; then log_info "IPv4 地址: http://$ipv4:$wp_port"; fi
        log_warn "请注意，直接使用 IP 访问可能会导致网站样式或功能异常。"
    fi
    press_any_key
}

uninstall_wordpress() {
    uninstall_docker_compose_project "WordPress" "/root/wordpress"
}

get_latest_maccms_tag() {
    local repo_api="https://api.github.com/repos/magicblack/maccms10/tags"
    local latest_tag
    latest_tag=$(curl -s "$repo_api" | grep -Po '"name":.*?[^\\]",' | head -1 | awk -F'"' '{print $4}')
    echo "$latest_tag"
}

download_maccms_source() {
    local version=$1
    local url="https://github.com/magicblack/maccms10/archive/refs/tags/${version}.zip"
    log_info "开始下载苹果CMS源码压缩包，版本: $version"
    if ! curl -L -o source.zip "$url"; then
        log_error "源码压缩包下载失败！请检查网络连接。"
        return 1
    fi
    if ! file source.zip | grep -q "Zip archive data"; then
        log_error "下载的文件不是有效的zip压缩包，可能下载失败或版本号错误！"
        rm -f source.zip
        return 1
    fi
    log_info "源码压缩包下载并校验通过。"
    return 0
}

install_maccms() {
    log_info "开始安装苹果CMS"
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建苹果CMS。"
        press_any_key
        return
    fi
    ensure_dependencies "unzip" "file"

    local project_dir
    read -e -p "请输入安装目录 [默认: /root/maccms]: " project_dir
    project_dir=${project_dir:-"/root/maccms"}

    if [ -f "$project_dir/docker-compose.yml" ]; then
        log_warn "检测到安装目录已存在 Docker 项目，请选择其他目录或先卸载。"
        press_any_key
        return 1
    fi

    local db_root_password db_user_password
    read -s -p "请输入 MariaDB root 密码 [默认随机]: " db_root_password
    db_root_password=${db_root_password:-$(generate_random_password)}
    echo ""
    read -s -p "请输入 maccms_user 用户密码 [默认随机]: " db_user_password
    db_user_password=${db_user_password:-$(generate_random_password)}
    echo ""

    local db_name="maccms"
    local db_user="maccms_user"
    local db_port="3306"
    local web_port
    read -p "请输入外部访问端口 [默认: 8880]: " web_port
    web_port=${web_port:-"8880"}

    mkdir -p "$project_dir/nginx" "$project_dir/source"
    cd "$project_dir" || { log_error "无法进入目录 $project_dir"; return 1; }

    local maccms_version
    maccms_version=$(get_latest_maccms_tag)
    if [ -z "$maccms_version" ]; then
        log_error "获取 maccms 版本失败"
        press_any_key
        return 1
    fi
    log_info "获取到最新版标签: $maccms_version"

    if ! download_maccms_source "$maccms_version"; then
        press_any_key
        return 1
    fi

    unzip -q source.zip || { log_error "解压失败"; return 1; }
    rm -f source.zip

    local dir="maccms10-${maccms_version#v}"
    if [ ! -d "$dir" ]; then
        log_error "解压后目录不存在"
        return 1
    fi

    mv "$dir"/* "$project_dir/source/"
    mv "$dir"/.* "$project_dir/source/" 2>/dev/null || true
    rm -rf "$dir"

    chown -R 82:82 "$project_dir/source"

    cat >"$project_dir/nginx/default.conf" <<'EOF'
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html index.htm;
    location / {
        if (!-e $request_filename) {
            rewrite ^/index.php(.*)$ /index.php?s=$1 last;
            rewrite ^/admin.php(.*)$ /admin.php?s=$1 last;
            rewrite ^/api.php(.*)$ /api.php?s=$1 last;
            rewrite ^(.*)$ /index.php?s=$1 last;
            break;
        }
    }
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass   php:9000;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include        fastcgi_params;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

    cat >"$project_dir/docker-compose.yml" <<EOF
services:
  db:
    image: mariadb:10.6
    container_name: ${project_dir##*/}_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: "$db_root_password"
      MYSQL_DATABASE: "$db_name"
      MYSQL_USER: "$db_user"
      MYSQL_PASSWORD: "$db_user_password"
    volumes:
      - db_data:/var/lib/mysql

  php:
    image: php:7.4-fpm
    container_name: ${project_dir##*/}_php
    volumes:
      - ./source:/var/www/html
    restart: always
    depends_on:
      - db

  nginx:
    image: nginx:1.21-alpine
    container_name: ${project_dir##*/}_nginx
    ports:
      - "$web_port:80"
    volumes:
      - ./source:/var/www/html
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
    restart: always
    depends_on:
      - php

volumes:
  db_data:
EOF

    log_info "正在启动服务..."
    docker compose up -d
    sleep 5
    docker compose ps

    log_info "正在修复文件权限..."
    docker exec -i "${project_dir##*/}_php" chown -R www-data:www-data /var/www/html
    docker exec -i "${project_dir##*/}_php" chmod -R 777 /var/www/html/runtime
    docker exec -i "${project_dir##*/}_php" chmod 666 /var/www/html/application/database.php || true

    log_info "正在写入数据库配置文件..."
    docker exec -i "${project_dir##*/}_php" bash -c "cat > /var/www/html/application/database.php <<EOF
<?php
return [
    'type'     => 'mysql',
    'hostname' => 'db',
    'database' => '$db_name',
    'username' => '$db_user',
    'password' => '$db_user_password',
    'hostport' => '$db_port',
    'charset'  => 'utf8mb4',
    'prefix'   => 'mac_',
];
EOF
"
    local public_ip
    public_ip=$(get_public_ip v4)
    log_info "✅ 安装完成，信息如下："
    echo "--------------------------------------------"
    echo "网站地址: http://$public_ip:$web_port"
    echo "数据库信息："
    echo "  主机: db"
    echo "  端口: $db_port"
    echo "  数据库: $db_name"
    echo "  用户: $db_user"
    echo "  用户密码: $db_user_password"
    echo "  Root密码: $db_root_password"
    echo "--------------------------------------------"
    press_any_key
}

uninstall_maccms() {
    uninstall_docker_compose_project "苹果CMS" "/root/maccms"
}

install_uptime_kuma() {
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建 Uptime Kuma。"
        press_any_key; return;
    fi
    clear
    log_info "开始使用 Docker Compose 搭建 Uptime Kuma..."

    local project_dir="/root/uptime-kuma"
    mkdir -p "$project_dir"
    cd "$project_dir" || return 1

    local web_port
    while true; do
        read -p "请输入 Uptime Kuma 的外部访问端口 [默认: 3001]: " web_port
        web_port=${web_port:-"3001"}
        if check_port "$web_port"; then break; fi
    done

    cat > docker-compose.yml <<EOF
version: '3.8'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    ports:
      - "$web_port:3001"
    volumes:
      - uptime_kuma_data:/app/data

volumes:
  uptime_kuma_data:
EOF

    log_info "正在启动 Uptime Kuma 服务..."
    docker compose up -d

    log_info "检查服务状态..."
    sleep 5
    docker compose ps

    local public_ip=$(get_public_ip v4)
    log_info "✅ Uptime Kuma 安装完成！"
    log_info "请通过 http://$public_ip:$web_port 访问。"
    press_any_key
}

uninstall_uptime_kuma() {
    uninstall_docker_compose_project "Uptime Kuma" "/root/uptime-kuma"
}

docker_apps_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE              Docker 应用 & 面板安装              $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 安装 UI 面板 (S-ui / 3x-ui)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟────────────────── $WHITE WordPress $CYAN ───────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 搭建 WordPress                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${RED}卸载 WordPress$NC                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE苹果CMS$CYAN ──────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 搭建苹果CMS影视站                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. ${RED}卸载苹果CMS$NC                                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────── $WHITEUptime Kuma$CYAN ────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. ${GREEN}安装 Uptime Kuma 监控面板${NC}                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. ${RED}卸载 Uptime Kuma${NC}                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) ui_panels_menu ;;
        2) install_wordpress ;;
        3) uninstall_wordpress ;;
        4) install_maccms ;;
        5) uninstall_maccms ;;
        6) install_uptime_kuma ;;
        7) uninstall_uptime_kuma ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

ui_panels_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 UI 面板安装选择                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 安装 S-ui 面板                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 安装 3X-ui 面板                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        read -p "请输入选项: " choice
        case $choice in
            1) install_sui; break ;;
            2) install_3xui; break ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# =================================================
#           证书 & 反代 (certificate_management_menu)
# =================================================

list_certificates() {
    if ! command -v certbot &>/dev/null; then
        log_error "Certbot 未安装，无法管理证书。"
        return 1
    fi

    log_info "正在获取所有证书列表..."
    local certs_output
    certs_output=$(certbot certificates 2>/dev/null)

    if [[ -z "$certs_output" || ! "$certs_output" =~ "Found the following certs:" ]]; then
        log_warn "未找到任何由 Certbot 管理的证书。"
        return 2
    fi

    echo "$certs_output" | awk '
        /Certificate Name:/ {
            cert_name = $3
        }
        /Domains:/ {
            domains = $2
            for (i=3; i<=NF; i++) domains = domains " " $i
        }
        /Expiry Date:/ {
            expiry_date = $3 " " $4 " " $5
            gsub(/\(.*\)/, "", expiry_date)
            gsub(/^[ \t]+|[ \t]+$/, "", expiry_date)

            status = ""
            if (index($0, "VALID")) {
                status = "\033[0;32m(VALID)\033[0m"
            } else if (index($0, "EXPIRED")) {
                status = "\033[0;31m(EXPIRED)\033[0m"
            }

            printf "\n  - 证书名称: \033[1;37m%s\033[0m\n", cert_name
            printf "    域名: \033[0;33m%s\033[0m\n", domains
            printf "    到期时间: %s %s\n", expiry_date, status
        }
    '
    echo -e "\n${CYAN}--------------------------------------------------------------${NC}"
    return 0
}

delete_certificate_and_proxy() {
    clear
    log_info "准备删除证书及其关联配置..."

    if ! list_certificates; then
        press_any_key
        return
    fi

    read -p "请输入要删除的证书名称 (Certificate Name): " cert_name
    if [ -z "$cert_name" ]; then
        log_error "证书名称不能为空！"
        press_any_key
        return
    fi

    read -p "警告：这将永久删除证书 '$cert_name' 及其相关的 Nginx 配置文件。此操作不可逆！是否继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi

    log_info "正在执行删除操作..."
    set -e

    certbot delete --cert-name "$cert_name" --non-interactive

    local nginx_conf="/etc/nginx/sites-available/$cert_name.conf"
    if [ -f "$nginx_conf" ]; then
        log_warn "检测到残留的 Nginx 配置文件，正在清理..."
        rm -f "/etc/nginx/sites-enabled/$cert_name.conf"
        rm -f "$nginx_conf"
        nginx -t && systemctl reload nginx
        log_info "✅ Nginx 残留配置已清理。"
    fi

    set +e
    log_info "✅ 证书 '$cert_name' 已成功删除。"
    press_any_key
}

renew_certificates() {
    if ! command -v certbot &>/dev/null; then
        log_error "Certbot 未安装，无法续签。"
        press_any_key
        return
    fi

    log_info "正在尝试为所有证书续期..."
    log_warn "Certbot 会自动跳过那些距离到期日还很长的证书。"
    certbot renew
    log_info "✅ 证书续期检查完成。"
    press_any_key
}

_handle_caddy_cert() {
    log_error "脚本的自动证书功能与 Caddy 冲突。请手动配置 Caddyfile。"
    return 1
}

_handle_nginx_cert() {
    local domain_name="$1"
    log_info "检测到 Nginx，将使用 '--nginx' 插件模式。"
    if ! systemctl is-active --quiet nginx; then
        log_info "Nginx 服务未运行，正在启动..."
        systemctl start nginx
    fi
    local NGINX_CONF_PATH="/etc/nginx/sites-available/$domain_name.conf"
    if [ ! -f "$NGINX_CONF_PATH" ]; then
        log_info "为域名验证创建临时的 HTTP Nginx 配置文件..."
        cat <<EOF >"$NGINX_CONF_PATH"
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name;
    root /var/www/html;
    index index.html index.htm;
}
EOF
        if [ ! -L "/etc/nginx/sites-enabled/$domain_name.conf" ]; then
            ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"
        fi
        log_info "正在重载 Nginx 以应用临时配置..."
        if ! nginx -t; then
            log_error "Nginx 临时配置测试失败！请检查 Nginx 状态。"
            rm -f "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/$domain_name.conf"
            return 1
        fi
        systemctl reload nginx
    else
        log_warn "检测到已存在的 Nginx 配置文件，将直接在此基础上尝试申请证书。"
    fi
    log_info "正在使用 'certbot --nginx' 模式为 $domain_name 申请证书..."
    certbot --nginx -d "$domain_name" --non-interactive --agree-tos --email "temp@$domain_name" --redirect
    if [ -f "/etc/letsencrypt/live/$domain_name/fullchain.pem" ]; then
        log_info "✅ Nginx 模式证书申请成功！"
        return 0
    else
        log_error "Nginx 模式证书申请失败！"
        return 1
    fi
}

apply_ssl_certificate() {
    local domain_name="$1"
    local cert_dir="/etc/letsencrypt/live/$domain_name"
    if [ -d "$cert_dir" ]; then
        log_info "检测到域名 $domain_name 的证书已存在，跳过申请流程。"
        return 0
    fi
    log_info "证书不存在，开始智能检测环境并为 $domain_name 申请新证书..."

    local certbot_dep="certbot"
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        # On RHEL/CentOS, it's better to install from EPEL
        log_warn "在 RHEL/CentOS 上, Certbot 通常位于 EPEL 仓库。"
        log_warn "如果安装失败，请先手动安装 epel-release 包。"
    fi
    ensure_dependencies "$certbot_dep"

    if command -v caddy &>/dev/null; then
        _handle_caddy_cert
    else
        log_info "未检测到 Caddy，将默认使用 Nginx 模式。"
        local nginx_certbot_dep="python3-certbot-nginx"
        if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
            nginx_certbot_dep="python3-certbot-nginx"
        fi
        ensure_dependencies "nginx" "$nginx_certbot_dep"
        _handle_nginx_cert "$domain_name"
    fi
    return $?
}

_configure_nginx_proxy() {
    local domain="$1"
    local port="$2"
    local conf_path="/etc/nginx/sites-available/$domain.conf"
    log_info "正在为 $domain -> http://127.0.0.1:$port 创建 Nginx 配置文件..."
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
    if [ ! -f "$cert_path" ]; then
        log_error "未找到预期的证书文件，无法配置 HTTPS。"
        return 1
    fi
    cat >"$conf_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    ssl_certificate $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    if [ ! -L "/etc/nginx/sites-enabled/$domain.conf" ]; then
        ln -s "$conf_path" "/etc/nginx/sites-enabled/"
    fi
    log_info "正在测试并重载 Nginx 配置..."
    if ! nginx -t; then
        log_error "Nginx 配置测试失败！请手动检查。"
        return 1
    fi
    systemctl reload nginx
    log_info "✅ Nginx 反向代理配置成功！"
    return 0
}

_configure_caddy_proxy() {
    local domain="$1"
    local port="$2"
    local caddyfile="/etc/caddy/Caddyfile"
    log_info "检测到 Caddy，将自动添加配置到 Caddyfile..."
    if grep -q "^\s*$domain" "$caddyfile"; then
        log_warn "Caddyfile 中似乎已存在关于 $domain 的配置，跳过添加。"
        log_info "请手动检查您的 Caddyfile 文件。"
        return 0
    fi
    # 【修正】将这里的非标准空格替换为标准空格
    echo -e "\n# Auto-generated by vps-toolkit for $domain\n$domain {\n    reverse_proxy 127.0.0.1:$port\n}" >>"$caddyfile"
    log_info "正在重载 Caddy 服务..."
    if ! caddy fmt --overwrite "$caddyfile"; then
        log_error "Caddyfile 格式化失败，请检查配置。"
    fi
    if ! systemctl reload caddy; then
        log_error "Caddy 服务重载失败！请手动检查。"
        return 1
    fi
    log_info "✅ Caddy 反向代理配置成功！Caddy 会自动处理 HTTPS。"
    return 0
}

setup_auto_reverse_proxy() {
    local domain_input="$1"
    local local_port="$2"
    clear
    log_info "欢迎使用通用反向代理设置向导。\n"

    if [ -z "$domain_input" ]; then
        while true; do
            read -p "请输入您要设置反代的域名: " domain_input
            if [[ -z "$domain_input" ]]; then log_error "域名不能为空！\n"; elif ! _is_domain_valid "$domain_input"; then log_error "域名格式不正确。\n"; else break; fi
        done
    else
        log_info "将为预设域名 $domain_input 进行操作。\n"
    fi
    if [ -z "$local_port" ]; then
        while true; do
            read -p "请输入要代理到的本地端口 (例如 8080): " local_port
            if [[ ! "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then log_error "端口号必须是 1-65535 之间的数字。"; else break; fi
        done
    else
        log_info "将代理到预设的本地端口: $local_port"
    fi

    local status=1
    if command -v caddy &>/dev/null; then
        _configure_caddy_proxy "$domain_input" "$local_port"
        status=$?
    elif command -v nginx &>/dev/null; then
        if ! apply_ssl_certificate "$domain_input"; then
            log_error "证书处理失败，无法继续配置 Nginx 反代。"
            status=1
        else
            _configure_nginx_proxy "$domain_input" "$local_port"
            status=$?
        fi
    else
        log_warn "未检测到任何 Web 服务器。将为您自动安装 Nginx..."
        ensure_dependencies "nginx"
        if command -v nginx &>/dev/null; then
            setup_auto_reverse_proxy "$domain_input" "$local_port"
            status=$?
        else
            log_error "Nginx 安装失败，无法继续。"
            status=1
        fi
    fi

    if [ -z "$1" ]; then
        press_any_key
    fi
    return $status
}

certificate_management_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE               证书管理 & 网站反代                $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 新建网站反代 (自动申请证书)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 查看/列出所有证书                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 手动续签所有证书                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. ${RED}删除证书 (并清理反代配置)${NC}                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) setup_auto_reverse_proxy ;;
        2) clear; list_certificates; press_any_key ;;
        3) renew_certificates ;;
        4) delete_certificate_and_proxy ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# =================================================
#           脚本初始化 & 主入口
# =================================================

do_update_script() {
    log_info "正在从 GitHub 下载最新版本的脚本..."
    local temp_script="/tmp/vps_tool_new.sh"
    register_temp_file "$temp_script"

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
    if ! [[ "$shortcut_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then log_error "无效的命令名称！只能包含字母、数字、下划线和连字符。"; return 1; fi

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
        echo -e "$CYAN║$NC   5. ${GREEN}Docker 通用管理${NC}                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. Docker 应用 & 面板安装                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. 证书管理 & 网站反代                         $CYAN║$NC"
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
        5) docker_manage_menu ;;
        6) docker_apps_menu ;;
        7) certificate_management_menu ;;
        9) do_update_script ;;
        0) exit 0 ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# --- 脚本执行入口 ---
check_root
detect_os_and_package_manager
initial_setup_check
main_menu