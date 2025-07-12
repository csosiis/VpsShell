#!/bin/bash

# =================================================================
# 全局变量与样式定义
# =================================================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 服务与文件路径常量
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/$SUBSTORE_SERVICE_NAME"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# =================================================================
# 日志与交互函数
# =================================================================

# =================================================
# 函数: log_info
# 说明: 以绿色文本输出一条信息级别的日志。
# 用法: log_info "您的信息"
# =================================================
log_info() { echo -e "${GREEN}[信息] - $1${NC}"; }

# =================================================
# 函数: log_warn
# 说明: 以黄色文本输出一条警告级别的日志。
# 用法: log_warn "您的警告信息"
# =================================================
log_warn() { echo -e "${YELLOW}[注意] - $1${NC}"; }

# =================================================
# 函数: log_error
# 说明: 以红色文本输出一条错误级别的日志。
# 用法: log_error "您的错误信息"
# =================================================
log_error() { echo -e "${RED}[错误] - $1${NC}"; }

# =================================================
# 函数: press_any_key
# 说明: 提示用户“按任意键返回...”，并等待用户按下任意键后继续执行。
# =================================================
press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键返回..."
}

# =================================================================
# 系统检查与辅助函数
# =================================================================

# =================================================
# 函数: check_root
# 说明: 检查脚本是否以 root 用户身份运行。如果不是，则打印错误信息并退出。
# =================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本必须以 root 用户身份运行。"
        exit 1
    fi
}

# =================================================
# 函数: check_port
# 说明: 检查给定的端口是否已被系统的 TCP 或 UDP 服务监听。
# 用法: check_port <端口号>
# 返回: 0 表示端口可用，1 表示端口被占用。
# =================================================
check_port() {
    local port="$1"
    if ss -tln | grep -q -E "(:|:::)${port}\b"; then
        log_error "端口 ${port} 已被占用。"
        return 1
    fi
    return 0
}

# =================================================
# 函数: generate_random_port
# 说明: 生成一个 1024 到 65535 之间的随机端口号。
# =================================================
generate_random_port() {
    echo $((RANDOM % 64512 + 1024))
}

# =================================================
# 函数: generate_random_password
# 说明: 生成一个由大小写字母和数字组成的20位随机密码。
# =================================================
generate_random_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
}

# =================================================
# 函数: _is_port_available
# 说明: 检查端口是否可用，不仅检查系统已占用的端口，还检查在本次操作中即将被分配的端口。
# 用法: _is_port_available <待检查端口> <已用端口数组名>
# =================================================
_is_port_available() {
    local port_to_check="$1"
    local used_ports_array_name="$2"
    eval "local used_ports=(\"\${${used_ports_array_name}[@]}\")"

    if ss -tlnu | grep -q -E ":${port_to_check}\s"; then
        echo ""
        log_warn "端口 ${port_to_check} 已被系统其他服务占用。"
        return 1
    fi

    for used_port in "${used_ports[@]}"; do
        if [ "$port_to_check" == "$used_port" ]; then
            echo ""
            log_warn "端口 ${port_to_check} 即将被本次操作中的其他协议使用。"
            return 1
        fi
    done
    return 0
}

# =================================================
# 函数: _is_domain_valid
# 说明: 使用正则表达式验证给定的字符串是否为有效的域名格式。
# 用法: _is_domain_valid <域名>
# =================================================
_is_domain_valid() {
    local domain_to_check="$1"
    if [[ "$domain_to_check" =~ ^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# =================================================
# 函数: ensure_dependencies
# 说明: 确保指定的软件包列表都已安装。如果检测到未安装的包，则自动更新并安装它们。
# 用法: ensure_dependencies "pkg1" "pkg2" ...
# =================================================
ensure_dependencies() {
    local dependencies=("$@")
    local missing_dependencies=()
    if [ ${#dependencies[@]} -eq 0 ]; then
        return 0
    fi

    log_info "正在按需检查依赖: ${dependencies[*]}..."
    for pkg in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_dependencies+=("$pkg")
        fi
    done

    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        log_warn "检测到以下缺失的依赖包: ${missing_dependencies[*]}"
        log_info "正在更新软件包列表并开始安装..."
        set -e
        apt-get update -y
        for pkg in "${missing_dependencies[@]}"; do
            log_info "正在安装 $pkg..."
            apt-get install -y "$pkg"
        done
        set +e
        log_info "按需依赖已安装完毕。"
    else
        log_info "所需依赖均已安装。"
    fi
    echo ""
}

# =================================================================
# 系统管理与优化 (sys_manage_menu)
# =================================================================

# =================================================
# 函数: show_system_info
# 说明: 查询并以美观的格式显示当前服务器的详细系统、硬件、网络和地理位置信息。
# =================================================
show_system_info() {
    ensure_dependencies "util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools"
    clear
    log_info "正在查询系统信息，请稍候..."

    # 优化点：一次 curl 调用获取所有 ip-api 信息
    local ip_api_json
    ip_api_json=$(curl -s -m 5 http://ip-api.com/json)
    if [[ -z "$ip_api_json" ]]; then
        log_error "无法从 ip-api.com 获取地理位置信息，请检查网络。"
    fi

    # 获取网络信息
    local ipv4_addr
    ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
    [ -z "$ipv4_addr" ] && ipv4_addr="获取失败"

    local ipv6_addr
    ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
    [ -z "$ipv6_addr" ] && ipv6_addr="无或获取失败"

    # 获取其他系统信息
    local hostname_info
    hostname_info=$(hostname)
    local os_info
    os_info=$(lsb_release -ds)
    local kernel_info
    kernel_info=$(uname -r)
    local cpu_arch
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    local cpu_model_full
    cpu_model_full=$(grep "^Model name" /proc/cpuinfo | head -1 | awk -F: '{print $2}' | sed 's/^[ \t]*//')
    local cpu_model
    cpu_model=$(echo "$cpu_model_full" | sed 's/ @.*//')
    local cpu_freq_from_model
    cpu_freq_from_model=$(echo "$cpu_model_full" | sed -n 's/.*@ *//p')
    local cpu_cores
    cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    local load_info
    load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    local memory_info
    memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}')
    local disk_info
    disk_info=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    local net_info_rx
    net_info_rx=$(vnstat --oneline | awk -F';' '{print $4}')
    local net_info_tx
    net_info_tx=$(vnstat --oneline | awk -F';' '{print $5}')
    local net_algo
    net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    local ip_info
    ip_info=$(echo "$ip_api_json" | jq -r '.org // "N/A"')
    local dns_info
    dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local geo_info
    geo_info=$(echo "$ip_api_json" | jq -r '(.city // "N/A") + ", " + (.country // "N/A")')
    local timezone
    timezone=$(timedatectl show --property=Timezone --value)
    local uptime_info
    uptime_info=$(uptime -p)
    local current_time
    current_time=$(date "+%Y-%m-%d %H:%M:%S")

    # 优化点：从 /proc/stat 获取CPU占用率，比 top 更快更轻量
    local cpu_usage
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    local prev_idle=$idle
    local prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    sleep 1
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    local current_idle=$idle
    local current_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local total_diff=$((current_total - prev_total))
    local idle_diff=$((current_idle - prev_idle))
    cpu_usage=$(printf "%.2f%%" "$(echo "100 * ($total_diff - $idle_diff) / $total_diff" | bc -l)")

    clear
    echo ""
    echo -e "$CYAN-------------------- 系统信息查询 ---------------------$NC"
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

# =================================================
# 函数: clean_system
# 说明: 自动移除不再需要的软件包并清理 APT 缓存，释放磁盘空间。
# =================================================
clean_system() {
    log_info "正在清理无用的软件包和缓存..."
    set -e
    apt autoremove -y
    apt clean
    set +e
    log_info "系统清理完毕。"
    press_any_key
}

# =================================================
# 函数: change_hostname
# 说明: 引导用户输入新的主机名，并修改系统相关配置文件以永久更改主机名。
# =================================================
change_hostname() {
    echo ""
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
    sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    set +e

    log_info "✅ 主机名修改成功！新的主机名是：$new_hostname"
    log_warn "为确保所有服务都识别到新主机名，建议重启系统。"
    press_any_key
}

# =================================================
# 函数: optimize_dns
# 说明: 自动检测服务器的 IPv6 支持情况，并配置一组经过优选的公共 DNS 服务器。
# =================================================
optimize_dns() {
    ensure_dependencies "net-tools"
    log_info "开始优化DNS地址..."
    log_info "正在检查IPv6支持..."

    if ping6 -c 1 google.com >/dev/null 2>&1; then
        log_info "检测到IPv6支持，配置IPv6优先的DNS..."
        cat <<EOF >/etc/resolv.conf
nameserver 2a00:1098:2b::1
nameserver 2a00:1098:2c::1
nameserver 2a01:4f8:c2c:123f::1
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
    else
        log_info "未检测到IPv6支持，仅配置IPv4 DNS..."
        cat <<EOF >/etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
    fi

    log_info "✅ DNS优化完成！当前的DNS配置如下："
    echo -e "$WHITE"
    cat /etc/resolv.conf
    echo -e "$NC"
    press_any_key
}

# =================================================
# 函数: set_network_priority
# 说明: 允许用户选择优先使用 IPv6 或 IPv4 进行网络连接，通过修改 gai.conf 实现。
# =================================================
set_network_priority() {
    clear
    echo -e "请选择网络优先级设置:\n"
    echo -e "1. IPv6 优先 (默认)\n"
    echo -e "2. IPv4 优先\n"
    echo -e "0. 返回主菜单\n"
    read -p "请输入选择: " choice

    case $choice in
    1)
        log_info "正在设置 IPv6 优先..."
        sed -i '/^precedence ::ffff:0:0\/96/s/^/#/' /etc/gai.conf
        log_info "✅ IPv6 优先已设置。"
        ;;
    2)
        log_info "正在设置 IPv4 优先..."
        if ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
            echo "precedence ::ffff:0:0/96  100" >>/etc/gai.conf
        fi
        log_info "✅ IPv4 优先已设置。"
        ;;
    0) return ;;
    *) log_error "无效选择。" ;;
    esac
    press_any_key
}

# =================================================
# 函数: setup_ssh_key
# 说明: 引导用户添加 SSH 公钥，并可选择禁用密码登录，以提高服务器安全性。
# =================================================
setup_ssh_key() {
    log_info "开始设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

    echo ""
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
    log_info "公钥已成功添加到 authorized_keys 文件中。"

    echo ""
    read -p "是否要禁用密码登录 (强烈推荐)? (y/N): " disable_pwd
    if [[ "$disable_pwd" =~ ^[Yy]$ ]]; then
        sed -i 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        log_info "正在重启 SSH 服务..."
        systemctl restart sshd
        log_info "✅ SSH 密码登录已禁用。"
    fi
    log_info "✅ SSH 密钥登录设置完成。"
    press_any_key
}

# =================================================
# 函数: set_timezone
# 说明: 提供一个菜单，让用户可以方便地将系统时区设置为常见的亚洲、欧洲或美洲时区。
# =================================================
set_timezone() {
    clear
    local current_timezone
    current_timezone=$(timedatectl show --property=Timezone --value)
    log_info "当前系统时区是: $current_timezone"
    echo ""
    log_info "请选择新的时区："
    echo ""

    options=("Asia/Shanghai" "Asia/Taipei" "Asia/Hong_Kong" "Asia/Tokyo" "Europe/London" "America/New_York" "UTC" "返回上一级菜单")
    PS3=$'\n'"请输入选项 (1-${#options[@]}): "

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

# =================================================
# 函数: manage_bbr
# 说明: 检查内核版本是否支持BBR，并允许用户启用 BBR 或 BBR + FQ 队列管理算法以优化网络。
# =================================================
manage_bbr() {
    clear
    log_info "开始检查并管理 BBR..."
    local kernel_version
    kernel_version=$(uname -r | cut -d- -f1)

    if ! dpkg --compare-versions "$kernel_version" "ge" "4.9"; then
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
    echo ""
    echo "请选择要执行的操作:"
    echo ""
    echo "1. 启用 BBR (原始版本)"
    echo "2. 启用 BBR + FQ (推荐)"
    echo "0. 返回"
    echo ""
    read -p "请输入选项: " choice

    local sysctl_conf="/etc/sysctl.conf"
    sed -i '/net.core.default_qdisc/d' "$sysctl_conf"
    sed -i '/net.ipv4.tcp_congestion_control/d' "$sysctl_conf"

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
    sysctl -p
    echo ""
    log_info "✅ 配置已应用！请检查下面的新算法是否已生效："
    sysctl net.ipv4.tcp_congestion_control
    sysctl net.core.default_qdisc
    press_any_key
}

# =================================================
# 函数: install_warp
# 说明: 调用 fscarmen 的多功能 WARP 脚本，为服务器添加或管理 Cloudflare WARP 网络接口。
# =================================================
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


# =================================================================
# X-ui / S-ui 面板安装
# =================================================================

# =================================================
# 函数: install_sui
# 说明: 执行 alireza0 的 S-ui (f-u-i) 面板官方安装脚本。
# =================================================
install_sui() {
    ensure_dependencies "curl"
    log_info "正在准备安装 S-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
    log_info "S-ui 安装脚本执行完毕。"
    press_any_key
}

# =================================================
# 函数: install_3xui
# 说明: 执行 mhsanaei 的 3x-ui 面板官方安装脚本。
# =================================================
install_3xui() {
    ensure_dependencies "curl"
    log_info "正在准备安装 3X-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    log_info "3X-ui 安装脚本执行完毕。"
    press_any_key
}


# =================================================================
# Sing-Box 核心功能
# =================================================================

# =================================================
# 函数: is_singbox_installed
# 说明: 检查 'sing-box' 命令是否存在，判断 Sing-Box 是否已安装。
# =================================================
is_singbox_installed() {
    command -v sing-box &>/dev/null
}

# =================================================
# 函数: check_and_prompt_install_singbox
# 说明: 检查 Sing-Box 是否已安装，如果未安装，则提示用户是否立即安装。
# 返回: 0 表示已安装或已成功安装，1 表示用户取消安装。
# =================================================
check_and_prompt_install_singbox() {
    if ! is_singbox_installed; then
        log_warn "Sing-Box 尚未安装。"
        read -p "您是否希望先安装 Sing-Box？(y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            singbox_do_install
        else
            log_info "操作已取消。"
            return 1
        fi
    fi
    return 0
}

# =================================================
# 函数: singbox_do_install
# 说明: 执行 Sing-Box 官方安装脚本，并进行初始化配置，包括创建默认配置文件和修改服务用户为root。
# =================================================
singbox_do_install() {
    ensure_dependencies "curl"
    if is_singbox_installed; then
        echo ""
        log_info "Sing-Box 已经安装，跳过安装过程。"
        press_any_key
        return
    fi

    log_info "正在安装 Sing-Box..."
    set -e
    bash <(curl -fsSL https://sing-box.app/deb-install.sh)
    set +e

    if ! is_singbox_installed; then
        log_error "Sing-Box 安装失败，请检查网络或脚本输出。"
        exit 1
    fi

    echo ""
    log_info "✅ Sing-Box 安装成功！"
    log_info "正在自动定位服务文件并修改运行权限..."
    local service_file_path
    service_file_path=$(systemctl status sing-box | grep -oP 'Loaded: loaded \(\K[^;]+')

    if [ -n "$service_file_path" ] && [ -f "$service_file_path" ]; then
        log_info "找到服务文件位于: $service_file_path"
        sed -i 's/User=sing-box/User=root/' "$service_file_path"
        sed -i 's/Group=sing-box/Group=root/' "$service_file_path"
        systemctl daemon-reload
        log_info "服务权限修改完成。"
    else
        log_error "无法自动定位 sing-box.service 文件！跳过权限修改。可能会导致证书读取失败。"
    fi

    mkdir -p "/etc/sing-box"
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

    echo ""
    log_info "正在启用并重启 Sing-Box 服务..."
    systemctl enable sing-box.service
    systemctl restart sing-box

    if systemctl is-active --quiet sing-box; then
        log_info "✅ Sing-Box 配置文件初始化完成并已启动！"
    else
        log_error "Sing-Box 启动失败，请使用日志功能查看详情。"
    fi

    press_any_key
}


# =================================================
# 函数: singbox_do_uninstall
# 说明: 完全卸载 Sing-Box，包括删除服务、二进制文件、配置文件和日志。
# =================================================
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

    echo ""
    log_info "正在停止并禁用 Sing-Box 服务..."
    systemctl stop sing-box &>/dev/null
    systemctl disable sing-box &>/dev/null

    log_info "正在删除 Sing-Box 相关文件..."
    rm -f /etc/systemd/system/sing-box.service
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/sing-box
    rm -rf /var/log/sing-box

    log_info "正在重载 systemd 配置..."
    systemctl daemon-reload

    if is_singbox_installed; then
        log_error "卸载失败！系统中仍能找到 'sing-box' 命令。"
        log_warn "请手动执行 'whereis sing-box' 查找并删除残留文件。"
    else
        log_info "✅ Sing-Box 已成功卸载。"
    fi
    press_any_key
}

# =================================================================
# Sing-Box 证书与节点管理
# =================================================================

# =================================================
# 函数: _handle_caddy_cert
# 说明: (证书申请辅助函数) 处理已安装 Caddy 的情况，提示用户冲突并中止。
# =================================================
_handle_caddy_cert() {
    log_info "检测到 Caddy 已安装。"
    log_error "脚本的自动证书功能与 Caddy 冲突。"
    log_error "请先卸载 Caddy，或手动配置 Caddyfile 并创建无TLS的 Sing-Box 节点。"
    log_error "操作已中止，以防止生成错误的配置。"
    return 1
}

# =================================================
# 函数: _handle_nginx_cert
# 说明: (证书申请辅助函数) 使用 certbot 的 nginx 插件为指定域名申请或续签证书。
# =================================================
_handle_nginx_cert() {
    local domain_name="$1"
    log_info "检测到 Nginx，将使用 '--nginx' 插件模式。"
    if ! systemctl is-active --quiet nginx; then
        log_info "Nginx 服务未运行，正在启动..."
        systemctl start nginx
    fi

    # 使用 --nginx 插件时，Certbot 会自动处理 Nginx 配置，无需手动创建临时文件。
    log_info "正在使用 'certbot --nginx' 模式为 ${domain_name} 申请证书..."
    certbot --nginx -d "$domain_name" --non-interactive --agree-tos --email "temp@$domain_name" --redirect

    if [ -f "/etc/letsencrypt/live/${domain_name}/fullchain.pem" ]; then
        log_info "✅ Nginx 模式证书申请成功！"
        return 0
    else
        log_error "Nginx 模式证书申请失败！"
        return 1
    fi
}


# =================================================
# 函数: _handle_standalone_cert
# 说明: (证书申请辅助函数) 当没有 Web 服务器时，使用 certbot 的 standalone 模式申请证书。
# =================================================
_handle_standalone_cert() {
    local domain_name="$1"
    log_info "未检测到支持的 Web 服务器，回退到 '--standalone' 独立模式。"
    log_warn "此模式需要临时占用 80 端口，可能会暂停其他服务。"

    local stopped_service=""
    if systemctl is-active --quiet nginx; then
        log_info "临时停止 Nginx..."
        systemctl stop nginx
        stopped_service="nginx"
    fi

    certbot certonly --standalone -d "$domain_name" --non-interactive --agree-tos --email "temp@$domain_name"

    if [ -n "$stopped_service" ]; then
        log_info "正在重启 $stopped_service..."
        systemctl start "$stopped_service"
    fi

    if [ -f "/etc/letsencrypt/live/$domain_name/fullchain.pem" ]; then
        log_info "✅ Standalone 模式证书申请成功！"
        return 0
    else
        log_error "Standalone 模式证书申请失败！"
        return 1
    fi
}

# =================================================
# 函数: apply_ssl_certificate
# 说明: 智能检测服务器环境（Caddy, Nginx），并调用相应的辅助函数来为指定域名申请 Let's Encrypt 证书。
# =================================================
apply_ssl_certificate() {
    local domain_name="$1"
    local cert_dir="/etc/letsencrypt/live/$domain_name"

    if [ -d "$cert_dir" ]; then
        echo ""
        log_info "检测到域名 $domain_name 的证书已存在，跳过申请流程。"
        return 0
    fi

    log_info "证书不存在，开始智能检测环境并为 $domain_name 申请新证书..."
    ensure_dependencies "certbot"

    if command -v caddy &>/dev/null; then
        _handle_caddy_cert "$domain_name"
    elif command -v nginx &>/dev/null; then
        ensure_dependencies "python3-certbot-nginx"
        _handle_nginx_cert "$domain_name"
    else
        # 如果都没有，默认安装 Nginx 并使用它来申请
        log_warn "未检测到 Caddy 或 Nginx，将自动安装 Nginx 用于证书申请。"
        ensure_dependencies "nginx" "python3-certbot-nginx"
        _handle_nginx_cert "$domain_name"
    fi

    return $?
}

# =================================================
# 函数: view_node_info
# 说明: 显示一个管理界面，列出所有已生成的节点链接，并提供新增、删除、推送节点或生成订阅链接的选项。
# =================================================
view_node_info() {
    while true; do
        clear; echo "";
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

        echo -e "\n1. 新增节点  2. 删除节点 3. 推送节点  4. ${YELLOW}生成临时订阅链接 (需Nginx)${NC}    0. 返回上一级菜单\n"
        read -p "请输入选项: " choice

        case $choice in
            1) singbox_add_node_orchestrator; continue ;;
            2) delete_nodes; continue ;;
            3) push_nodes; continue ;;
            4) generate_subscription_link; continue ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# =================================================
# 函数: delete_nodes
# 说明: 允许用户通过菜单选择一个或多个节点，并从 Sing-Box 配置文件和节点链接文件中将其删除。
# =================================================
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

        echo ""
        log_info "请选择要删除的节点 (可多选，用空格分隔, 输入 'all' 删除所有):"
        echo ""
        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local node_name=${node_tags_map[$i]}
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC\n"
        done

        read -p "请输入编号 (输入 0 返回上一级菜单): " -a nodes_to_delete
        if [[ " ${nodes_to_delete[*]} " =~ " 0 " ]]; then
            log_info "操作已取消。"
            break
        fi

        if [[ "${nodes_to_delete[0]}" == "all" ]]; then
            read -p "你确定要删除所有节点吗？(y/N): " confirm_delete
            if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
                log_info "正在删除所有节点..."
                # 将 inbounds 数组设置为空数组
                jq '.inbounds = []' "$SINGBOX_CONFIG_FILE" >"$SINGBOX_CONFIG_FILE.tmp" && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
                rm -f "$SINGBOX_NODE_LINKS_FILE"
                log_info "✅ 所有节点已删除。"
                systemctl restart sing-box
            else
                log_info "操作已取消。"
            fi
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
                log_warn "未选择任何有效节点。"
                press_any_key
                continue
            fi

            log_info "正在从 config.json 中删除节点: ${tags_to_delete[*]}"
            cp "$SINGBOX_CONFIG_FILE" "$SINGBOX_CONFIG_FILE.tmp"
            for tag in "${tags_to_delete[@]}"; do
                jq --arg t "$tag" 'del(.inbounds[] | select(.tag == $t))' "$SINGBOX_CONFIG_FILE.tmp" >"$SINGBOX_CONFIG_FILE.tmp.2" && mv "$SINGBOX_CONFIG_FILE.tmp.2" "$SINGBOX_CONFIG_FILE.tmp"
            done
            mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"

            # 更新节点链接文件
            local temp_links_file=$(mktemp)
            for i in "${!node_lines[@]}"; do
                if ! [[ " ${indices_to_delete[*]} " =~ " $i " ]]; then
                    echo "${node_lines[$i]}" >> "$temp_links_file"
                fi
            done
            mv "$temp_links_file" "$SINGBOX_NODE_LINKS_FILE"

            log_info "✅ 所选节点已删除。"
            systemctl restart sing-box
            break
        fi
    done
    press_any_key
}


# =================================================================
# 节点推送与订阅
# =================================================================

# =================================================
# 函数: select_nodes_for_push
# 说明: 提供一个菜单让用户选择要推送的节点（单个、多个或全部），并将选择结果存入全局数组 'selected_links'。
# =================================================
select_nodes_for_push() {
    mapfile -t node_lines <"$SINGBOX_NODE_LINKS_FILE"
    if [ ${#node_lines[@]} -eq 0 ]; then
        log_warn "没有可推送的节点。"
        return 1
    fi

    clear
    echo -e "\n请选择要推送的节点：\n"
    echo -e "1. 推送所有节点\n"
    echo -e "2. 推送单个/多个节点\n"
    echo -e "0. 返回\n"
    read -p "请输入选项: " push_choice

    selected_links=()
    case $push_choice in
    1)
        log_info "已选择推送所有节点。"
        selected_links=("${node_lines[@]}")
        ;;
    2)
        echo ""
        log_info "请选择要推送的节点 (可多选，用空格分隔):"
        echo ""
        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local node_name
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC\n"
        done
        read -p "请输入编号 (输入 0 返回): " -a selected_indices

        for index in "${selected_indices[@]}"; do
            if [[ "$index" == "0" ]]; then return 1; fi
            if ! [[ "$index" =~ ^[0-9]+$ ]] || [[ $index -lt 1 || $index -gt ${#node_lines[@]} ]]; then
                log_error "包含无效编号: $index"
                return 1
            fi
            selected_links+=("${node_lines[$((index - 1))]}")
        done
        ;;
    0) return 1 ;;
    *) log_error "无效选项！"; return 1 ;;
    esac

    if [ ${#selected_links[@]} -eq 0 ]; then
        log_warn "未选择任何有效节点。"
        return 1
    fi
    return 0
}

# =================================================
# 函数: push_to_sub_store
# 说明: 将用户选择的节点推送到一个公共的 Sub-Store 后端服务，并保存订阅标识。
# =================================================
push_to_sub_store() {
    ensure_dependencies "curl" "jq"
    if ! select_nodes_for_push; then
        press_any_key
        return
    fi

    local sub_store_config_file="/etc/sing-box/sub-store-config.txt"
    local sub_store_subs=""
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

    local links_str
    links_str=$(printf "%s\n" "${selected_links[@]}")
    local node_json
    node_json=$(jq -n --arg name "$sub_store_subs" --arg link "$links_str" '{
        "token": "sanjose",
        "name": $name,
        "link": $link
    }')

    echo ""
    log_info "正在推送到 Sub-Store..."
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
        echo ""
        log_error "推送到 Sub-Store 失败，服务器响应: $error_message"
    fi
    press_any_key
}

# =================================================
# 函数: push_to_telegram
# 说明: 将用户选择的节点信息通过 Telegram Bot 推送到指定的 Chat ID。
# =================================================
push_to_telegram() {
    if ! select_nodes_for_push; then
        press_any_key
        return
    fi

    local tg_config_file="/etc/sing-box/telegram-bot-config.txt"
    local tg_api_token=""
    local tg_chat_id=""
    if [ -f "$tg_config_file" ]; then
        source "$tg_config_file"
    fi

    if [ -z "$tg_api_token" ] || [ -z "$tg_chat_id" ]; then
        log_info "首次推送到 Telegram，请输入您的 Bot 信息。"
        read -p "请输入 Telegram Bot API Token: " tg_api_token
        read -p "请输入 Telegram Chat ID: " tg_chat_id
    fi

    local message_lines=("节点推送成功，详情如下：" "")
    message_lines+=("${selected_links[@]}")
    local IFS=$'\n'
    local message_text="${message_lines[*]}"
    unset IFS

    echo ""
    log_info "正在将节点合并为单条消息推送到 Telegram..."
    response=$(curl -s -X POST "https://api.telegram.org/bot$tg_api_token/sendMessage" \
        --data-urlencode "chat_id=$tg_chat_id" \
        --data-urlencode "text=$message_text")

    if ! echo "$response" | jq -e '.ok' >/dev/null; then
        log_error "推送失败！ Telegram API 响应: $(echo "$response" | jq -r '.description // .')"
        read -p "是否要清除已保存的 Telegram 配置并重试? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            rm -f "$tg_config_file"
        fi
        press_any_key
        return
    fi

    echo "tg_api_token=$tg_api_token" >"$tg_config_file"
    echo "tg_chat_id=$tg_chat_id" >>"$tg_config_file"
    log_info "✅ 节点信息已成功推送到 Telegram！"
    press_any_key
}

# =================================================
# 函数: push_nodes
# 说明: 提供一个菜单，让用户选择将节点推送到 Sub-Store 或 Telegram Bot。
# =================================================
push_nodes() {
    ensure_dependencies "jq" "curl"
    clear
    echo -e "$WHITE--- 推送节点 ---$NC\n"
    echo "1. 推送到 Sub-Store"
    echo "2. 推送到 Telegram Bot"
    echo ""
    echo "0. 返回"
    read -p "请选择推送方式: " push_choice

    case $push_choice in
    1) push_to_sub_store ;;
    2) push_to_telegram ;;
    0) return ;;
    *) log_error "无效选项！"; press_any_key ;;
    esac
}

# =================================================
# 函数: generate_subscription_link
# 说明: 将所有节点信息编码为 Base64，并通过 Nginx 托管生成一个临时的、用完即删的订阅链接。
# =================================================
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
        host=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
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

    # 将节点链接文件内容进行 Base64 编码
    local base64_content
    base64_content=$(base64 -w 0 < "$SINGBOX_NODE_LINKS_FILE")
    echo "$base64_content" > "$sub_filepath"

    local sub_url="http://$host/$sub_filename"

    clear
    log_info "已生成临时订阅链接，请立即复制使用！"
    log_warn "此链接将在您按键返回后被自动删除。"
    echo -e "$CYAN--------------------------------------------------------------$NC"
    echo -e "\n$YELLOW$sub_url$NC\n"
    echo -e "$CYAN--------------------------------------------------------------$NC"
    press_any_key

    rm -f "$sub_filepath"
    log_info "临时订阅文件已删除。"
}



# =================================================================
# Sub-Store 安装与管理
# =================================================================

# =================================================
# 函数: is_substore_installed
# 说明: 通过检查 Sub-Store 的 systemd 服务文件是否存在，来判断 Sub-Store 是否已安装。
# =================================================
is_substore_installed() {
    [ -f "$SUBSTORE_SERVICE_FILE" ]
}

# =================================================
# 函数: substore_do_install
# 说明: 自动安装和配置 Sub-Store，包括使用 FNM 安装正确的 Node.js 版本、下载项目文件和设置 systemd 服务。
# =================================================
substore_do_install() {
    ensure_dependencies "curl" "unzip" "git"
    echo ""
    log_info "开始执行 Sub-Store 安装流程..."
    set -e

    # 使用 FNM 官方安装脚本
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
    cd "$SUBSTORE_INSTALL_DIR" || { log_error "无法进入目录 $SUBSTORE_INSTALL_DIR"; exit 1; }
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"

    log_info "开始配置系统服务..."
    echo ""
    local API_KEY
    read -p "请输入 Sub-Store 的 API 密钥 [回车则随机生成]: " user_api_key
    API_KEY=${user_api_key:-$(generate_random_password)}
    log_info "最终使用的 API 密钥为: ${API_KEY}"

    local FRONTEND_PORT
    while true; do
        read -p "请输入前端访问端口 [默认: 3000]: " port_input
        FRONTEND_PORT=${port_input:-"3000"}
        if check_port "$FRONTEND_PORT"; then break; fi
    done

    local BACKEND_PORT
    while true; do
        read -p "请输入后端 API 端口 [默认: 3001]: " backend_port_input
        BACKEND_PORT=${backend_port_input:-"3001"}
        if [ "$BACKEND_PORT" == "$FRONTEND_PORT" ]; then
            log_error "后端端口不能与前端端口相同!"
        elif check_port "$BACKEND_PORT"; then
            break
        fi
    done

    # 使用 fnm exec 确保 systemd 服务能找到正确的 node 版本
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
    echo ""
    read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        substore_setup_reverse_proxy
    else
        press_any_key
    fi
}


# =================================================
# 函数: substore_do_uninstall
# 说明: 完全卸载 Sub-Store，包括停止服务、删除项目文件和 systemd 配置文件。
# =================================================
substore_do_uninstall() {
    if ! is_substore_installed; then
        log_warn "Sub-Store 未安装。"
        press_any_key
        return
    fi
    echo ""
    log_warn "你确定要卸载 Sub-Store 吗？此操作不可逆！"
    echo ""
    read -p "请输入 Y 确认: " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_info "取消卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用服务..."
    systemctl stop "$SUBSTORE_SERVICE_NAME" &>/dev/null
    systemctl disable "$SUBSTORE_SERVICE_NAME" &>/dev/null
    log_info "正在删除服务文件..."
    rm -f "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    log_info "正在删除项目文件和 Node.js 环境..."
    rm -rf "$SUBSTORE_INSTALL_DIR"
    rm -rf "/root/.fnm"
    rm -rf "/root/.local/share/pnpm"
    # 可以选择性地删除 bash 配置文件中由 fnm 和 pnpm 添加的行
    sed -i '/fnm/d' ~/.bashrc
    sed -i '/PNPM_HOME/d' ~/.bashrc
    log_info "✅ Sub-Store 已成功卸载。"
    press_any_key
}


# =================================================
# 函数: update_sub_store_app
# 说明: 从 GitHub 下载最新的 Sub-Store 前后端文件，并重启服务以完成更新。
# =================================================
update_sub_store_app() {
    ensure_dependencies "curl" "unzip"
    echo ""
    log_info "开始更新 Sub-Store 应用..."
    if ! is_substore_installed; then
        log_error "Sub-Store 尚未安装，无法更新。"
        press_any_key
        return
    fi
    set -e
    cd "$SUBSTORE_INSTALL_DIR" || { log_error "无法进入目录 $SUBSTORE_INSTALL_DIR"; exit 1; }
    log_info "正在下载最新的后端文件 (sub-store.bundle.js)..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    log_info "正在下载最新的前端文件 (dist.zip)..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    log_info "正在部署新版前端..."
    rm -rf frontend
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    set +e
    log_info "正在重启 Sub-Store 服务以应用更新..."
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ Sub-Store 更新成功并已重启！"
    else
        log_error "Sub-Store 更新后重启失败！请使用 '查看日志' 功能进行排查。"
    fi
    press_any_key
}

# =================================================
# 函数: substore_view_access_link
# 说明: 读取 Sub-Store 配置文件，并显示基于 IP 或反代域名的完整访问链接。
# =================================================
substore_view_access_link() {
    echo ""
    log_info "正在读取配置并生成访问链接..."
    if ! is_substore_installed; then
        echo ""
        log_error "Sub-Store尚未安装。"
        press_any_key
        return
    fi
    local REVERSE_PROXY_DOMAIN
    REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    local API_KEY
    API_KEY=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    local FRONTEND_PORT
    FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')

    echo -e "\n===================================================================="
    if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
        local ACCESS_URL="https://$REVERSE_PROXY_DOMAIN/subs?api=https://$REVERSE_PROXY_DOMAIN$API_KEY"
        echo -e "\n您的 Sub-Store 反代访问链接如下：\n\n$YELLOW$ACCESS_URL$NC\n"
    else
        local SERVER_IP_V4
        SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com)
        if [ -n "$SERVER_IP_V4" ]; then
            local ACCESS_URL_V4="http://$SERVER_IP_V4:$FRONTEND_PORT/subs?api=http://$SERVER_IP_V4:$FRONTEND_PORT$API_KEY"
            echo -e "\n您的 Sub-Store IPv4 访问链接如下：\n\n$YELLOW$ACCESS_URL_V4$NC\n"
        else
            log_warn "无法获取 IPv4 地址，请检查网络或手动拼接链接。"
        fi
    fi
    echo -e "===================================================================="
}

# =================================================
# 函数: substore_reset_ports
# 说明: 允许用户重新设置 Sub-Store 的前端和后端端口，并自动更新 Nginx 反代配置（如果存在）。
# =================================================
substore_reset_ports() {
    log_info "开始重置 Sub-Store 端口..."
    if ! is_substore_installed; then
        log_error "Sub-Store 尚未安装，无法重置端口。"
        press_any_key
        return
    fi
    local CURRENT_FRONTEND_PORT
    CURRENT_FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    local CURRENT_BACKEND_PORT
    CURRENT_BACKEND_PORT=$(grep 'SUB_STORE_BACKEND_API_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    log_info "当前前端端口: $CURRENT_FRONTEND_PORT"
    log_info "当前后端端口: $CURRENT_BACKEND_PORT"
    echo ""

    local NEW_FRONTEND_PORT
    while true; do
        read -p "请输入新的前端访问端口 [直接回车则不修改: $CURRENT_FRONTEND_PORT]: " NEW_FRONTEND_PORT
        NEW_FRONTEND_PORT=${NEW_FRONTEND_PORT:-$CURRENT_FRONTEND_PORT}
        if [ "$NEW_FRONTEND_PORT" == "$CURRENT_FRONTEND_PORT" ]; then break; fi
        if check_port "$NEW_FRONTEND_PORT"; then break; fi
    done

    local NEW_BACKEND_PORT
    while true; do
        read -p "请输入新的后端 API 端口 [直接回车则不修改: $CURRENT_BACKEND_PORT]: " NEW_BACKEND_PORT
        NEW_BACKEND_PORT=${NEW_BACKEND_PORT:-$CURRENT_BACKEND_PORT}
        if [ "$NEW_BACKEND_PORT" == "$NEW_FRONTEND_PORT" ]; then
            log_error "后端端口不能与前端端口相同！"
            continue
        fi
        if [ "$NEW_BACKEND_PORT" == "$CURRENT_BACKEND_PORT" ]; then break; fi
        if check_port "$NEW_BACKEND_PORT"; then break; fi
    done

    log_info "正在更新服务文件..."
    set -e
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_PORT=.*|Environment=\"SUB_STORE_FRONTEND_PORT=${NEW_FRONTEND_PORT}\"|" "$SUBSTORE_SERVICE_FILE"
    sed -i "s|^Environment=\"SUB_STORE_BACKEND_API_PORT=.*|Environment=\"SUB_STORE_BACKEND_API_PORT=${NEW_BACKEND_PORT}\"|" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载并重启服务..."
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    set +e

    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ 端口重置成功！"
        local REVERSE_PROXY_DOMAIN
        REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
        if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
            local NGINX_CONF_PATH="/etc/nginx/sites-available/$REVERSE_PROXY_DOMAIN.conf"
            if [ -f "$NGINX_CONF_PATH" ]; then
                log_info "检测到 Nginx 反代配置，正在自动更新端口..."
                sed -i "s|proxy_pass http://127.0.0.1:.*|proxy_pass http://127.0.0.1:${NEW_FRONTEND_PORT};|g" "$NGINX_CONF_PATH"
                if nginx -t >/dev/null 2>&1; then
                    systemctl reload nginx
                    log_info "Nginx 配置已更新并重载。"
                else log_error "更新 Nginx 端口后配置测试失败！"; fi
            fi
        fi
        substore_view_access_link
    else
        log_error "服务重启失败！请检查日志。"
    fi
    press_any_key
}

# =================================================
# 函数: substore_reset_api_key
# 说明: 生成一个新的随机 API 密钥，并更新到 Sub-Store 服务配置中，使旧的访问链接失效。
# =================================================
substore_reset_api_key() {
    if ! is_substore_installed; then
        log_error "Sub-Store 尚未安装。"
        press_any_key
        return
    fi
    echo ""
    log_warn "确定要重置 API 密钥吗？旧的访问链接将立即失效。"
    read -p "请输入 Y 确认: " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_info "取消操作。"
        press_any_key
        return
    fi

    log_info "正在生成新的 API 密钥..."
    set -e
    local NEW_API_KEY
    NEW_API_KEY=$(generate_random_password)
    log_info "正在更新服务文件..."
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=.*|Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=/${NEW_API_KEY}\"|" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载并重启服务..."
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    set +e

    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ API 密钥重置成功！"
        substore_view_access_link
    else
        log_error "服务重启失败！"
    fi
    press_any_key
}

# =================================================
# 函数: substore_setup_reverse_proxy
# 说明: 为 Sub-Store 设置 Nginx 反向代理，包括自动申请 SSL 证书和生成配置文件。
# =================================================
substore_setup_reverse_proxy() {
    ensure_dependencies "nginx" "certbot" "python3-certbot-nginx"
    clear
    log_info "为保证安全和便捷，强烈建议使用域名和HTTPS访问Sub-Store。"

    if command -v nginx &>/dev/null; then
        log_info "检测到 Nginx，将为您生成配置代码和操作指南。"
        substore_handle_nginx_proxy
    else
        log_warn "未检测到 Nginx。此功能目前仅支持Nginx。"
        log_info "脚本已自动为您安装 Nginx，请重新运行此选项。"
    fi
    press_any_key
}

# =================================================
# 函数: substore_handle_nginx_proxy
# 说明: (反代辅助函数) 引导用户输入域名，申请证书，并生成 Nginx 反代配置文件。
# =================================================
substore_handle_nginx_proxy() {
    echo ""
    read -p "请输入您要用于反代的域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        log_error "域名不能为空！"
        return
    fi

    log_info "正在从服务配置中读取 Sub-Store 端口..."
    local FRONTEND_PORT
    FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    if [ -z "$FRONTEND_PORT" ]; then
        log_error "无法读取到 Sub-Store 的端口号！请检查 Sub-Store 是否已正确安装。"
        return
    fi
    log_info "读取到端口号为: $FRONTEND_PORT"

    # 申请证书
    if ! apply_ssl_certificate "$DOMAIN"; then
        log_error "证书处理失败，操作已中止。"
        return
    fi

    log_info "正在为域名 $DOMAIN 写入 Nginx 配置..."
    local NGINX_CONF_PATH="/etc/nginx/sites-available/$DOMAIN.conf"

    # 使用 setup_auto_reverse_proxy 的通用配置逻辑
    if ! _configure_nginx_proxy "$DOMAIN" "$FRONTEND_PORT"; then
        log_error "Nginx 配置失败。"
        return
    fi

    log_info "✅ Nginx 反向代理已配置成功！"
    log_info "正在更新服务文件中的域名环境变量..."

    # 使用更安全的方式更新环境变量
    if grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE"; then
        sed -i "s|^Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=.*|Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=$DOMAIN\"|" "$SUBSTORE_SERVICE_FILE"
    else
        sed -i "/\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=$DOMAIN\"" "$SUBSTORE_SERVICE_FILE"
    fi

    log_info "正在重载 systemd 并重启 Sub-Store 服务以应用新环境..."
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    substore_view_access_link
}


# =================================================================
# Nezha 哪吒监控管理
# =================================================================

# =================================================
# 函数: is_nezha_agent_installed
# 说明: 检查特定版本的哪吒探针是否已安装。
# 用法: is_nezha_agent_installed <版本ID> (e.g., v0, v1, v3)
# =================================================
is_nezha_agent_installed() {
    [ -f "/etc/systemd/system/nezha-agent-$1.service" ]
}

# =================================================
# 函数: _uninstall_nezha_agent
# 说明: (重构后) 卸载指定版本的哪吒探针的通用函数。
# 用法: _uninstall_nezha_agent <版本ID> <探针名称>
# =================================================
_uninstall_nezha_agent() {
    local ver_id="$1"
    local agent_name="$2"

    if ! is_nezha_agent_installed "$ver_id"; then
        log_warn "${agent_name} 探针未安装，无需卸载。"
        press_any_key
        return
    fi

    log_info "正在停止并禁用 nezha-agent-${ver_id} 服务..."
    systemctl stop "nezha-agent-${ver_id}.service" &>/dev/null
    systemctl disable "nezha-agent-${ver_id}.service" &>/dev/null

    log_info "正在删除相关文件..."
    rm -f "/etc/systemd/system/nezha-agent-${ver_id}.service"
    rm -rf "/opt/nezha/agent-${ver_id}"

    systemctl daemon-reload
    log_info "✅ ${agent_name} 探针已成功卸载。"
    press_any_key
}

# =================================================
# 函数: _install_nezha_agent_v0_style
# 说明: (重构后) 安装 V0/V3 这种通过参数传递密钥的哪吒探针的通用函数。
# 用法: _install_nezha_agent_v0_style <版本ID> <探针名称> <服务器地址> <服务器端口>
# =================================================
_install_nezha_agent_v0_style() {
    local ver_id="$1"
    local agent_name="$2"
    local server_addr="$3"
    local server_port="$4"

    _uninstall_nezha_agent "$ver_id" "$agent_name" &>/dev/null # 先清理旧版

    local server_key
    read -p "请输入 ${agent_name} 面板密钥: " server_key
    if [ -z "$server_key" ]; then
        log_error "面板密钥不能为空！操作中止。"
        press_any_key
        return
    fi

    local tls_option="--tls"
    [[ "$server_port" == "80" || "$server_port" == "8080" ]] && tls_option=""

    local SCRIPT_PATH_TMP="/tmp/nezha_install_orig.sh"
    log_info "正在下载官方安装脚本..."
    if ! curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/install_en.sh -o "$SCRIPT_PATH_TMP"; then
        log_error "下载官方脚本失败！"; press_any_key; return
    fi
    chmod +x "$SCRIPT_PATH_TMP"

    # 执行官方脚本
    bash "$SCRIPT_PATH_TMP" install_agent "$server_addr" "$server_port" "$server_key" $tls_option
    rm "$SCRIPT_PATH_TMP"

    # 检查标准版是否安装成功
    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
        log_error "官方脚本未能成功创建标准服务，操作中止。"
        press_any_key
        return
    fi
    log_info "标准服务安装成功，即将开始改造以实现多探针共存..."
    sleep 1

    # 改造过程
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null
    mv /etc/systemd/system/nezha-agent.service "/etc/systemd/system/nezha-agent-${ver_id}.service"
    mv /opt/nezha/agent "/opt/nezha/agent-${ver_id}"
    sed -i "s|/opt/nezha/agent/nezha-agent|/opt/nezha/agent-${ver_id}/nezha-agent|g" "/etc/systemd/system/nezha-agent-${ver_id}.service"

    log_info "正在启动改造后的 'nezha-agent-${ver_id}' 服务..."
    systemctl daemon-reload
    systemctl enable "nezha-agent-${ver_id}.service"
    systemctl start "nezha-agent-${ver_id}.service"

    sleep 2
    if systemctl is-active --quiet "nezha-agent-${ver_id}"; then
        log_info "✅ ${agent_name} 探针 (隔离版) 已成功安装并启动！"
    else
        log_error "${agent_name} 探针 (隔离版) 启动失败！"
        log_warn "显示详细状态以供诊断:"
        systemctl status "nezha-agent-${ver_id}.service" --no-pager -l
    fi
    press_any_key
}

# =================================================
# 函数: install_nezha_agent_v0
# 说明: (调用函数) 安装 San Jose V0 探针。
# =================================================
install_nezha_agent_v0() {
    _install_nezha_agent_v0_style "v0" "San Jose V0" "nz.wiitwo.eu.org" "443"
}
# =================================================
# 函数: uninstall_nezha_agent_v0
# 说明: (调用函数) 卸载 San Jose V0 探针。
# =================================================
uninstall_nezha_agent_v0() {
    _uninstall_nezha_agent "v0" "San Jose V0"
}
# =================================================
# 函数: install_nezha_agent_v3
# 说明: (调用函数) 安装 Phoenix V0 探针。
# =================================================
install_nezha_agent_v3() {
    _install_nezha_agent_v0_style "v3" "Phoenix V0" "nz.csosm.ip-ddns.com" "443"
}
# =================================================
# 函数: uninstall_nezha_agent_v3
# 说明: (调用函数) 卸载 Phoenix V0 探针。
# =================================================
uninstall_nezha_agent_v3() {
    _uninstall_nezha_agent "v3" "Phoenix V0"
}
# =================================================
# 函数: install_nezha_agent_v1
# 说明: 安装 Singapore-West V1 探针，该版本使用不同的安装脚本和环境变量。
# =================================================
install_nezha_agent_v1() {
    local user_command
    read -p "请输入安装指令以继续: " user_command
    if [ "$user_command" != "csos" ]; then
        log_error "指令错误，安装已中止。"; press_any_key; return
    fi

    _uninstall_nezha_agent "v1" "Singapore-West V1" &>/dev/null # 清理旧版

    ensure_dependencies "curl" "wget" "unzip"
    clear
    log_info "指令正确，开始全自动安装 Nezha V1 探针..."

    local SCRIPT_PATH_TMP="/tmp/agent_v1_install_orig.sh"
    if ! curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh -o "$SCRIPT_PATH_TMP"; then
        log_error "下载官方脚本失败！"; press_any_key; return
    fi
    chmod +x "$SCRIPT_PATH_TMP"

    # 执行官方V1脚本
    export NZ_SERVER="nz.ssong.eu.org:8008"
    export NZ_TLS="false"
    export NZ_CLIENT_SECRET="wdptRINwlgBB3kE0U8eDGYjqV56nAhLh"
    bash "$SCRIPT_PATH_TMP"
    unset NZ_SERVER NZ_TLS NZ_CLIENT_SECRET
    rm "$SCRIPT_PATH_TMP"

    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
        log_error "官方脚本未能成功创建标准服务，操作中止."; press_any_key; return
    fi
    log_info "标准服务安装成功，开始改造..."

    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null
    mv /etc/systemd/system/nezha-agent.service /etc/systemd/system/nezha-agent-v1.service
    mv /opt/nezha/agent /opt/nezha/agent-v1
    sed -i 's|/opt/nezha/agent|/opt/nezha/agent-v1|g' /etc/systemd/system/nezha-agent-v1.service

    systemctl daemon-reload
    systemctl enable nezha-agent-v1.service
    systemctl start nezha-agent-v1.service

    sleep 2
    if systemctl is-active --quiet nezha-agent-v1; then
        log_info "✅ Singapore-West V1 探针 (隔离版) 已成功安装并启动！"
    else
        log_error "Singapore-West V1 探针 (隔离版) 启动失败！";
        systemctl status nezha-agent-v1.service --no-pager -l
    fi
    press_any_key
}
# =================================================
# 函数: uninstall_nezha_agent_v1
# 说明: (调用函数) 卸载 Singapore-West V1 探针。
# =================================================
uninstall_nezha_agent_v1() {
    _uninstall_nezha_agent "v1" "Singapore-West V1"
}

# =================================================
# 函数: install_nezha_dashboard_v0
# 说明: 调用 fscarmen 的脚本来安装或管理 V0 版本的哪吒面板。
# =================================================
install_nezha_dashboard_v0() {
    ensure_dependencies "wget"
    log_info "即将运行 fscarmen 的 V0 面板安装/管理脚本..."
    press_any_key
    bash <(wget -qO- https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh)
    log_info "脚本执行完毕。"
    press_any_key
}

# =================================================
# 函数: install_nezha_dashboard_v1
# 说明: 调用官方脚本来安装或管理 V1 版本的哪吒面板。
# =================================================
install_nezha_dashboard_v1() {
    ensure_dependencies "curl"
    log_info "即将运行官方 V1 面板安装/管理脚本..."
    press_any_key
    curl -L https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
    log_info "脚本执行完毕。"
    press_any_key
}

# =================================================
# 函数: is_nezha_agent_v0_installed
# 说明: 检查 San Jose V0 探针是否已安装。
# =================================================
is_nezha_agent_v0_installed() { is_nezha_agent_installed "v0"; }

# =================================================
# 函数: is_nezha_agent_v3_installed
# 说明: 检查 Phoenix V0 探针是否已安装。
# =================================================
is_nezha_agent_v3_installed() { is_nezha_agent_installed "v3"; }

# =================================================
# 函数: is_nezha_agent_v1_installed
# 说明: 检查 Singapore-West V1 探针是否已安装。
# =================================================
is_nezha_agent_v1_installed() { is_nezha_agent_installed "v1"; }

# =================================================
# 函数: nezha_agent_menu
# 说明: 显示哪吒探针（Agent）的管理菜单，允许用户安装或卸载不同版本的探针。
# =================================================
nezha_agent_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE               哪吒探针 (Agent) 管理              $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

        local v0_status="${YELLOW}(未安装)$NC"
        is_nezha_agent_v0_installed && v0_status="${GREEN}(已安装)$NC"
        printf "$CYAN║$NC   1. 安装/重装 San Jose V0 探针 %-18b$CYAN║$NC\n" "$v0_status"
        echo -e "$CYAN║$NC   2. $RED卸载 San Jose V0 探针$NC                         $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

        local v1_status="${YELLOW}(未安装)$NC"
        is_nezha_agent_v1_installed && v1_status="${GREEN}(已安装)$NC"
        printf "$CYAN║$NC   3. 安装/重装 Singapore V1 探针 %-16b$CYAN║$NC\n" "$v1_status"
        echo -e "$CYAN║$NC   4. $RED卸载 Singapore V1 探针$NC                        $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

        local v3_status="${YELLOW}(未安装)$NC"
        is_nezha_agent_v3_installed && v3_status="${GREEN}(已安装)$NC"
        printf "$CYAN║$NC   5. 安装/重装 Phoenix V0 探针 %-18b$CYAN║$NC\n" "$v3_status"
        echo -e "$CYAN║$NC   6. $RED卸载 Phoenix V0 探针$NC                          $CYAN║$NC"

        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                                $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_agent_v0 ;; 2) uninstall_nezha_agent_v0 ;;
        3) install_nezha_agent_v1 ;; 4) uninstall_nezha_agent_v1 ;;
        5) install_nezha_agent_v3 ;; 6) uninstall_nezha_agent_v3 ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# =================================================
# 函数: nezha_dashboard_menu
# 说明: 显示哪吒面板（Dashboard）的管理菜单，允许用户选择安装不同版本的面板。
# =================================================
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
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        log_warn "面板安装脚本均来自第三方，其内部已集成卸载和管理功能。"
        log_warn "如需卸载或管理，请再次运行对应的安装选项即可。"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_dashboard_v0 ;;
        2) install_nezha_dashboard_v1 ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# =================================================================
# WordPress 安装与管理 (Docker)
# =================================================================

# =================================================
# 函数: _install_docker_and_compose
# 说明: (WP辅助函数) 检查并安装 Docker 和 Docker Compose V2。
# =================================================
_install_docker_and_compose() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "Docker 和 Docker Compose V2 已安装。"
        return 0
    fi
    log_warn "未检测到完整的 Docker 环境，开始执行官方标准安装流程..."
    ensure_dependencies "ca-certificates" "curl" "gnupg"
    log_info "正在添加 Docker 官方 GPG 密钥..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    log_info "正在添加 Docker 软件仓库..."
    local os_id
    os_id=$(. /etc/os-release && echo "$ID")
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$os_id \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    log_info "正在更新软件包列表以识别新的 Docker 仓库..."
    set -e
    apt-get update -y
    log_info "正在安装 Docker Engine, CLI, Containerd, 和 Docker Compose 插件..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    set +e
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "✅ Docker 和 Docker Compose V2 已成功安装！"
        return 0
    else
        log_error "Docker 环境安装失败！请检查上面的日志输出。"
        return 1
    fi
}

# =================================================
# 函数: install_wordpress
# 说明: 使用 Docker Compose 快速搭建一个全新的 WordPress 网站，包括数据库，并可选择自动配置反向代理。
# =================================================
install_wordpress() {
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建 WordPress。"
        press_any_key
        return
    fi
    clear
    log_info "开始使用 Docker Compose 搭建 WordPress..."
    echo ""
    local project_dir
    while true; do
        read -p "请输入新 WordPress 项目的安装目录 [默认: /root/wordpress]: " project_dir
        project_dir=${project_dir:-"/root/wordpress"}
        if [ -f "$project_dir/docker-compose.yml" ]; then
            log_error "错误：目录 \"$project_dir\" 下已存在一个 docker-compose.yml 文件！"
            log_warn "请为新的 WordPress 站点选择一个不同的、全新的目录。"
            echo ""
            continue
        else
            break
        fi
    done
    mkdir -p "$project_dir" || { log_error "无法创建目录 $project_dir！"; press_any_key; return; }
    cd "$project_dir" || { log_error "无法进入目录 $project_dir！"; press_any_key; return; }

    log_info "新的 WordPress 将被安装在: $(pwd)"
    echo ""
    local db_password
    read -s -p "请输入新的数据库 root 和用户密码 [默认: 123456]: " db_password
    echo ""
    db_password=${db_password:-"123456"}
    log_info "数据库密码已设置为: $db_password"
    echo ""
    local wp_port
    local used_ports_for_this_run=()
    while true; do
        read -p "请输入 WordPress 的外部访问端口 (例如 8080): " wp_port
        if [[ ! "$wp_port" =~ ^[0-9]+$ ]] || [ "$wp_port" -lt 1 ] || [ "$wp_port" -gt 65535 ]; then
            log_error "端口号必须是 1-65535 之间的数字。"
        elif ! _is_port_available "$wp_port" "used_ports_for_this_run"; then
            :
        else break; fi
    done
    echo ""
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
      MYSQL_ROOT_PASSWORD: ${db_password}
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wp_user
      MYSQL_PASSWORD: ${db_password}
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
      - "${wp_port}:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wp_user
      WORDPRESS_DB_PASSWORD: ${db_password}
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_SITEURL: ${site_url}
      WORDPRESS_HOME: ${site_url}
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
        log_error "docker-compose.yml 文件创建失败！"; press_any_key; return
    fi

    echo ""
    log_info "正在使用 Docker Compose 启动 WordPress 和数据库服务..."
    log_warn "首次启动需要下载镜像，可能需要几分钟时间，请耐心等待..."
    docker compose up -d
    echo ""
    log_info "正在检查服务状态..."
    sleep 5
    docker compose ps
    echo ""
    log_info "✅ WordPress 容器已成功启动！"
    echo ""
    read -p "是否立即为其设置反向代理 (需提前解析好域名)？(Y/n): " setup_proxy_choice
    if [[ ! "$setup_proxy_choice" =~ ^[Nn]$ ]]; then
        setup_auto_reverse_proxy "$domain" "$wp_port"
        echo ""
        log_info "WordPress 配置流程完毕！您现在应该可以通过 $site_url 访问您的网站了。"
    else
        log_info "好的，您选择不设置反向代理。"
        log_info "您可以通过以下 IP 地址完成 WordPress 的初始化安装："
        local ipv4_addr
        ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
        if [ -n "$ipv4_addr" ]; then log_info "IPv4 地址: http://${ipv4_addr}:${wp_port}"; fi
        log_warn "请注意，直接使用 IP 访问可能会导致网站样式或功能异常。"
    fi
    press_any_key
}


# =================================================================
# 脚本自身管理
# =================================================================

# =================================================
# 函数: do_update_script
# 说明: 从 GitHub 下载最新版本的脚本，并与当前版本比较。如果存在更新，则自动替换并重新加载脚本。
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

# =================================================
# 函数: _create_shortcut
# 说明: (快捷方式辅助函数) 为脚本创建一个软链接到 /usr/local/bin，使其可以作为全局命令执行。
# =================================================
_create_shortcut() {
    local shortcut_name=$1
    local full_path="/usr/local/bin/$shortcut_name"
    if [ -z "$shortcut_name" ]; then
        log_error "快捷命令名称不能为空！"
        return 1
    fi
    if ! [[ "$shortcut_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "无效的命令名称！只能包含字母、数字、下划线和连字符。"
        return 1
    fi

    echo ""
    log_info "正在为脚本创建快捷命令: $shortcut_name"
    ln -sf "$SCRIPT_PATH" "$full_path"
    chmod +x "$full_path"
    log_info "✅ 快捷命令 '$shortcut_name' 已设置！"
    log_info "现在您可以随时随地输入 '$shortcut_name' 来运行此脚本。"
}

# =================================================
# 函数: setup_shortcut
# 说明: 引导用户输入一个自定义的快捷命令名称，并调用辅助函数来创建它。
# =================================================
setup_shortcut() {
    echo ""
    local default_shortcut="sv"
    read -p "请输入您想要的快捷命令名称 [默认: $default_shortcut]: " input_name
    local shortcut_name=${input_name:-$default_shortcut}
    _create_shortcut "$shortcut_name"
    press_any_key
}


# =================================================================
# 通用反向代理与网站搭建
# =================================================================

# =================================================
# 函数: _create_self_signed_cert
# 说明: (节点生成辅助函数) 为指定的伪装域名生成一个长期有效的自签名证书，用于IP直连的场景。
# =================================================
_create_self_signed_cert() {
    local domain_name="$1"
    local cert_dir="/etc/sing-box/certs"
    cert_path="$cert_dir/$domain_name.cert.pem"
    key_path="$cert_dir/$domain_name.key.pem"

    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        echo ""
        log_info "检测到已存在的自签名证书，将直接使用。"
        return 0
    fi

    log_info "\n正在为域名 $domain_name 生成自签名证书..."
    mkdir -p "$cert_dir"
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=$domain_name"

    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        log_info "✅ 自签名证书创建成功！"
        return 0
    else
        log_error "自签名证书创建失败！"
        return 1
    fi
}

# =================================================
# 函数: _get_unique_tag
# 说明: (节点生成辅助函数) 根据基础标签检查配置文件，确保生成的节点标签是唯一的，避免冲突。
# =================================================
_get_unique_tag() {
    local base_tag="$1"
    local final_tag="$base_tag"
    local counter=2
    while jq -e --arg t "$final_tag" 'any(.inbounds[]; .tag == $t)' "$SINGBOX_CONFIG_FILE" >/dev/null; do
        final_tag="${base_tag}-${counter}"
        ((counter++))
    done
    echo "$final_tag"
}

# =================================================
# 函数: _add_protocol_inbound
# 说明: (节点生成辅助函数) 将格式化好的 JSON 配置和节点链接追加到对应的文件中。
# =================================================
_add_protocol_inbound() {
    local protocol=$1 config=$2 node_link=$3
    log_info "正在为 [$protocol] 协议添加入站配置..."

    if ! jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" >"$SINGBOX_CONFIG_FILE.tmp"; then
        log_error "[$protocol] 协议配置写入失败！请检查JSON格式。"
        rm -f "$SINGBOX_CONFIG_FILE.tmp"
        return 1
    fi

    mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
    echo "$node_link" >>"$SINGBOX_NODE_LINKS_FILE"
    log_info "✅ [$protocol] 协议配置添加成功！"
    return 0
}

# =================================================
# 函数: _configure_nginx_proxy
# 说明: (反代辅助函数) 为指定的域名和本地端口生成一个标准的 Nginx HTTPS 反向代理配置文件。
# =================================================
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
    # 将所有 HTTP 请求强制跳转到 HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    # SSL 证书配置
    ssl_certificate $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    # 反向代理配置
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
        log_error "Nginx 配置测试失败！请手动检查。"; return 1
    fi
    systemctl reload nginx
    log_info "✅ Nginx 反向代理配置成功！"
    return 0
}

# =================================================
# 函数: _configure_caddy_proxy
# 说明: (反代辅助函数) 自动将反向代理配置追加到 Caddyfile 中，并重载 Caddy 服务。
# =================================================
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

    {
        echo ""
        echo "# Auto-generated by vps-toolkit for $domain"
        echo "$domain {"
        echo "    reverse_proxy 127.0.0.1:$port"
        echo "}"
    } >> "$caddyfile"

    log_info "正在重载 Caddy 服务..."
    if ! caddy fmt --overwrite "$caddyfile"; then
        log_error "Caddyfile 格式化失败，请检查配置。"
    fi
    if ! systemctl reload caddy; then
        log_error "Caddy 服务重载失败！请手动检查。"; return 1
    fi

    log_info "✅ Caddy 反向代理配置成功！Caddy 会自动处理 HTTPS。"
    return 0
}

# =================================================
# 函数: setup_auto_reverse_proxy
# 说明: 自动检测服务器上安装的 Web 服务器 (Caddy 或 Nginx)，并为用户输入的域名和端口设置 HTTPS 反向代理。
# =================================================
setup_auto_reverse_proxy() {
    local domain_input="$1"
    local local_port="$2"
    clear
    log_info "欢迎使用通用反向代理设置向导。"
    echo ""

    if [ -z "$domain_input" ]; then
        while true; do
            read -p "请输入您要设置反代的域名: " domain_input
            if [[ -z "$domain_input" ]]; then log_error "域名不能为空！"; elif ! _is_domain_valid "$domain_input"; then log_error "域名格式不正确。"; else break; fi
        done
    else
        log_info "将为预设域名 $domain_input 进行操作。"
    fi

    if [ -z "$local_port" ]; then
        while true; do
            read -p "请输入要代理到的本地端口 (例如 8080): " local_port
            if [[ ! "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then
                log_error "端口号必须是 1-65535 之间的数字。"
            else break; fi
        done
    else
        log_info "将代理到预设的本地端口: $local_port"
    fi

    if command -v caddy &>/dev/null; then
        _configure_caddy_proxy "$domain_input" "$local_port"
    elif command -v nginx &>/dev/null; then
        if ! apply_ssl_certificate "$domain_input"; then
            log_error "证书处理失败，无法继续配置 Nginx 反代。"
        else
            _configure_nginx_proxy "$domain_input" "$local_port"
        fi
    else
        log_warn "未检测到任何 Web 服务器。将为您自动安装 Caddy..."
        ensure_dependencies "caddy"
        if command -v caddy &>/dev/null; then
            _configure_caddy_proxy "$domain_input" "$local_port"
        else
            log_error "Caddy 安装失败，无法继续。"
        fi
    fi

    if [ -z "$1" ]; then
        press_any_key
    fi
}


# =================================================================
# 主流程与菜单
# =================================================================

# =================================================
# 函数: post_add_node_menu
# 说明: 在成功添加节点后显示此菜单，为用户提供“继续添加”或“管理节点”的快捷入口。
# =================================================
post_add_node_menu() {
    while true; do
        echo ""
        echo -e "请选择接下来的操作：\n"
        echo -e "${GREEN}1. 继续新增节点$NC  ${YELLOW}2. 管理已有节点 (查看/删除/推送)${NC}    ${RED}0. 返回上一级菜单$NC\n"
        read -p "请输入选项: " next_choice
        case $next_choice in
        1) singbox_add_node_orchestrator; break ;;
        2) view_node_info; break ;;
        0) break ;;
        *) log_error "无效选项，请重新输入。" ;;
        esac
    done
}


# =================================================
# 函数: singbox_add_node_orchestrator
# 说明: 这是创建 Sing-Box 节点的核心功能，它整合了协议选择、证书处理、端口和标识输入等所有步骤，支持单个或一键批量生成节点。
# =================================================
singbox_add_node_orchestrator() {
    ensure_dependencies "jq" "uuid-runtime" "curl" "openssl"
    local protocols_to_create=()
    local is_one_click=false

    clear
    # --- 协议选择 ---
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
    echo ""
    read -p "请输入选项: " protocol_choice

    case $protocol_choice in
        1) protocols_to_create=("VLESS");;
        2) protocols_to_create=("VMess");;
        3) protocols_to_create=("Trojan");;
        4) protocols_to_create=("Hysteria2");;
        5) protocols_to_create=("TUIC");;
        6) protocols_to_create=("VLESS" "VMess" "Trojan" "Hysteria2" "TUIC"); is_one_click=true;;
        0) return;;
        *) log_error "无效选择，操作中止."; press_any_key; return;;
    esac

    clear
    log_info "您选择了 [${protocols_to_create[*]}] 协议。"

    # --- 证书与连接地址处理 ---
    local cert_path key_path connect_addr sni_domain
    local insecure_params=()
    declare -A insecure_params=( [VLESS]="" [Trojan]="" [Hysteria2]="" [TUIC]="" [VMess]="")

    echo -e "\n请选择证书类型：\n\n${GREEN}1. 使用 Let's Encrypt 域名证书 (推荐)$NC\n\n2. 使用自签名证书 (IP 直连)\n"
    read -p "请输入选项 (1-2): " cert_choice

    if [ "$cert_choice" == "1" ]; then
        read -p "请输入您已解析到本机的域名: " domain
        if ! _is_domain_valid "$domain"; then log_error "域名格式不正确。"; press_any_key; return; fi
        if ! apply_ssl_certificate "$domain"; then log_error "证书处理失败。"; press_any_key; return; fi
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"; key_path="/etc/letsencrypt/live/$domain/privkey.pem"
        connect_addr="$domain"; sni_domain="$domain"
    elif [ "$cert_choice" == "2" ]; then
        insecure_params[VLESS]="&allowInsecure=1"; insecure_params[Trojan]="&allowInsecure=1"
        insecure_params[Hysteria2]="&insecure=1"; insecure_params[TUIC]="&allow_insecure=1"
        insecure_params[VMess]=', "skip-cert-verify": true'

        ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com); ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
        if [ -n "$ipv4_addr" ]; then connect_addr="$ipv4_addr"; else connect_addr="[$ipv6_addr]"; fi

        read -p "请输入 SNI 伪装域名 [默认: www.bing.com]: " sni_input
        sni_domain=${sni_input:-"www.bing.com"}
        if ! _create_self_signed_cert "$sni_domain"; then log_error "自签名证书处理失败。"; press_any_key; return; fi
        cert_path="/etc/sing-box/certs/$sni_domain.cert.pem"; key_path="/etc/sing-box/certs/$sni_domain.key.pem"
    else
        log_error "无效证书选择."; press_any_key; return
    fi

    # --- 端口与标识输入 ---
    local used_ports_for_this_run=(); declare -A ports
    for p in "${protocols_to_create[@]}"; do
        while true; do
            local port_prompt="请输入 [$p] 的端口 [回车则随机]: "
            [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]] && port_prompt="请输入 [$p] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "
            read -p "$(echo -e "\n$port_prompt")" port_input
            port_input=${port_input:-$(generate_random_port)}
            if _is_port_available "$port_input" "used_ports_for_this_run"; then
                ports[$p]=$port_input; used_ports_for_this_run+=("$port_input"); break
            fi
        done
    done

    echo ""; read -p "请输入自定义标识 (如 Google, 回车则默认用 Jcole): " custom_id
    custom_id=${custom_id:-"Jcole"}

    # --- 节点生成循环 ---
    local geo_info_json; geo_info_json=$(curl -s ip-api.com/json)
    local country_code; country_code=$(echo "$geo_info_json" | jq -r '.countryCode // "N/A"')
    local region_name; region_name=$(echo "$geo_info_json" | jq -r '.regionName // "N/A"' | sed 's/ //g')
    local success_count=0; local final_node_link=""

    for protocol in "${protocols_to_create[@]}"; do
        local tag; tag=$(_get_unique_tag "$country_code-$region_name-$custom_id-$protocol")
        log_info "\n已为 [$protocol] 节点分配唯一 Tag: $tag"
        local uuid; uuid=$(uuidgen)
        local password; password=$(generate_random_password)
        local config; local node_link;
        local current_port=${ports[$protocol]}
        local tls_config_tcp="{\"enabled\":true,\"server_name\":\"$sni_domain\",\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\"}"
        local tls_config_udp="{\"enabled\":true,\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\",\"alpn\":[\"h3\"]}"

        case $protocol in
            "VLESS" | "VMess" | "Trojan")
                local user_json="{\"uuid\":\"$uuid\"}"; [[ "$protocol" == "Trojan" ]] && user_json="{\"password\":\"$password\"}"
                config="{\"type\":\"${protocol,,}\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[${user_json}],\"tls\":$tls_config_tcp,\"transport\":{\"type\":\"ws\",\"path\":\"/\"}}"
                case $protocol in
                    "VLESS") node_link="vless://$uuid@$connect_addr:$current_port?type=ws&security=tls&sni=$sni_domain&host=$sni_domain&path=%2F${insecure_params[VLESS]}#$tag";;
                    "VMess") vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$connect_addr\",\"port\":\"$current_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$sni_domain\",\"path\":\"/\",\"tls\":\"tls\"${insecure_params[VMess]}}"; node_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)";;
                    "Trojan") node_link="trojan://$password@$connect_addr:$current_port?security=tls&sni=$sni_domain&type=ws&host=$sni_domain&path=/${insecure_params[Trojan]}#$tag";;
                esac
                ;;
            "Hysteria2")
                config="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"password\":\"$password\"}],\"tls\":$tls_config_udp,\"up_mbps\":100,\"down_mbps\":1000}"
                node_link="hysteria2://$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3${insecure_params[Hysteria2]}#$tag"
                ;;
            "TUIC")
                config="{\"type\":\"tuic\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"uuid\":\"$uuid\",\"password\":\"$password\"}],\"tls\":$tls_config_udp}"
                node_link="tuic://$uuid:$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3&congestion_control=bbr${insecure_params[TUIC]}#$tag"
                ;;
        esac

        if _add_protocol_inbound "$protocol" "$config" "$node_link"; then
            ((success_count++)); final_node_link="$node_link"
        fi
    done

    # --- 结果处理 ---
    if [ "$success_count" -gt 0 ]; then
        log_info "\n共成功添加 $success_count 个节点，正在重启 Sing-Box..."
        systemctl restart sing-box; sleep 2
        if systemctl is-active --quiet sing-box; then
            log_info "Sing-Box 重启成功。"
            if ! $is_one_click; then
                 echo -e "\n✅ 节点添加成功！分享链接如下：\n$CYAN--------------------------------------------------------------$NC\n$YELLOW$final_node_link$NC\n$CYAN--------------------------------------------------------------$NC"
            fi
            if [ "$cert_choice" == "2" ]; then
                log_warn "\n重要提示：您使用了自签名证书，请根据客户端提示，勾选“允许不安全连接”或“跳过证书验证”选项。"
            fi
            if $is_one_click; then view_node_info; else post_add_node_menu; fi
        else
            log_error "Sing-Box 重启失败！请使用日志功能查看错误。"
            press_any_key
        fi
    else
        log_error "没有任何节点被成功添加。"
        press_any_key
    fi
}

# =================================================
# 函数: initial_setup_check
# 说明: 在脚本首次运行时执行，自动创建快捷命令并生成一个标记文件，避免后续重复执行。
# =================================================
initial_setup_check() {
    if [ ! -f "$FLAG_FILE" ]; then
        echo ""
        log_info "脚本首次运行，开始自动设置..."
        _create_shortcut "sv"
        log_info "创建标记文件以跳过下次检查。"
        touch "$FLAG_FILE"
        echo ""
        log_info "首次设置完成！正在进入主菜单..."
        sleep 2
    fi
}

# =================================================
# 函数: sys_manage_menu
# 说明: 显示系统综合管理的主菜单。
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
        echo -e "$CYAN║$NC   4. 优化 DNS                                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 设置网络优先级 (IPv4/v6)                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 设置 SSH 密钥登录                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. 设置系统时区                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE网络优化$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. BBR 拥塞控制管理                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. 安装 WARP 网络接口                          $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) show_system_info ;; 2) clean_system ;; 3) change_hostname ;; 4) optimize_dns ;;
        5) set_network_priority ;; 6) setup_ssh_key ;; 7) set_timezone ;; 8) manage_bbr ;;
        9) install_warp ;; 0) break ;; *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# =================================================
# 函数: singbox_main_menu
# 说明: 显示 Sing-Box 的主管理菜单。
# =================================================
singbox_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sing-Box 管理                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        if is_singbox_installed; then
            local STATUS_COLOR="$RED● 不活动$NC"
            systemctl is-active --quiet sing-box && STATUS_COLOR="$GREEN● 活动$NC"
            echo -e "$CYAN║$NC  当前状态: $STATUS_COLOR                                $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC   1. 新增节点                                    $CYAN║$NC"
            echo -e "$CYAN║$NC   2. 管理节点                                    $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC   3. 启动 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC   4. 停止 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC   5. 重启 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC   6. 查看日志                                    $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC   7. $RED卸载 Sing-Box$NC                               $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
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
            echo -e "$CYAN║$NC   1. 安装 Sing-Box                               $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) singbox_do_install ;; 0) break ;; *) log_error "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}


# =================================================
# 函数: substore_manage_menu
# 说明: 显示 Sub-Store 的详细管理菜单，包括启停、日志和配置修改。
# =================================================
substore_manage_menu() {
    while true; do
        clear
        local rp_menu_text="设置反向代理 (推荐)"
        grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null && rp_menu_text="更换反代域名"

        echo -e "$WHITE=============================$NC\n"
        echo -e "$WHITE      Sub-Store 管理菜单      $NC\n"
        echo -e "$WHITE=============================$NC\n"
        local STATUS_COLOR="$RED● 不活动$NC"
        systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME" && STATUS_COLOR="$GREEN● 活动$NC"
        echo -e "当前状态: $STATUS_COLOR\n"
        echo "-----------------------------"
        echo "1. 启动服务"
        echo "2. 停止服务"
        echo "3. 重启服务"
        echo "4. 查看状态"
        echo "5. 查看日志"
        echo "-----------------------------"
        echo "6. 查看访问链接"
        echo "7. 重置端口"
        echo "8. 重置 API 密钥"
        echo -e "9. $YELLOW$rp_menu_text$NC"
        echo "0. 返回主菜单"
        echo -e "$WHITE-----------------------------$NC\n"
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


# =================================================
# 函数: substore_main_menu
# 说明: 显示 Sub-Store 的主管理菜单。
# =================================================
substore_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sub-Store 管理                 $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        if is_substore_installed; then
            local STATUS_COLOR="$RED● 不活动$NC"
            systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME" && STATUS_COLOR="$GREEN● 活动$NC"
            echo -e "$CYAN║$NC  当前状态: $STATUS_COLOR                                $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC   1. 管理 Sub-Store (启停/日志/配置)             $CYAN║$NC"
            echo -e "$CYAN║$NC   2. $GREEN更新 Sub-Store 应用$NC                         $CYAN║$NC"
            echo -e "$CYAN║$NC   3. $RED卸载 Sub-Store$NC                              $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) substore_manage_menu ;; 2) update_sub_store_app ;;
            3) substore_do_uninstall ;; 0) break ;; *) log_warn "无效选项！"; sleep 1 ;;
            esac
        else
            echo -e "$CYAN║$NC  当前状态: $YELLOW● 未安装$NC                              $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC   1. 安装 Sub-Store                              $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) substore_do_install ;; 0) break ;; *) log_warn "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}


# =================================================
# 函数: main_menu
# 说明: 脚本的入口，显示所有功能模块的主菜单。
# =================================================
main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE              全功能 VPS & 应用管理脚本           $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   1. 系统综合管理                                $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Sing-Box 管理                               $CYAN║$NC"
        echo -e "$CYAN║$NC   3. Sub-Store 管理                              $CYAN║$NC"
        echo -e "$CYAN║$NC   4. $GREEN哪吒监控管理$NC                                $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE应用安装$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC   5. 安装 S-ui 面板                              $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 安装 3X-ui 面板                             $CYAN║$NC"
        echo -e "$CYAN║$NC   7. $GREEN搭建 WordPress (Docker)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC   8. $GREEN通用网站反向代理配置$NC                      $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE脚本管理$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC   9. $GREEN更新此脚本$NC                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  10. $YELLOW设置快捷命令 (默认: sv)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC   0. $RED退出脚本$NC                                    $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) sys_manage_menu ;;
        2) singbox_main_menu ;;
        3) substore_main_menu ;;
        4) nezha_agent_menu ;; # 这里暂时只链接到 agent 菜单
        5) install_sui ;;
        6) install_3xui ;;
        7) install_wordpress ;;
        8) setup_auto_reverse_proxy "" "" ;; # 传入空参数启动交互模式
        9) do_update_script ;;
        10) setup_shortcut ;;
        0) exit 0 ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


# =================================================================
# 脚本启动入口
# =================================================================

# 必须以 root 权限运行
check_root

# 首次运行时进行初始化设置
initial_setup_check

# 显示主菜单
main_menu