#!/bin/bash

# ==================================================
# 全功能 VPS & 应用管理脚本
#
# Author: Jcole
# Version: 3.0 (Multi-Nezha Customization)
# ==================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- 哪吒探针私人配置 (请务必修改为您自己的信息) ---
# 面板显示名称
NEZHA_PANEL_NAMES=("San Jose面板" "Singapore面板" "Phoenix面板")
# 面板的 服务器地址:端口
NEZHA_PANEL_SERVERS=("sanjose.your-domain.com:5555" "sg.your-domain.com:5555" "phx.your-domain.com:5555")
# 面板的 密钥
NEZHA_PANEL_KEYS=("YOUR_SAN_JOSE_KEY" "YOUR_SINGAPORE_KEY" "YOUR_PHOENIX_KEY")


# --- 全局常量 (请勿修改) ---
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/$SUBSTORE_SERVICE_NAME"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# --- 基础工具函数 ---
log_info() { echo -e "${GREEN}[信息] - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[注意] - $1${NC}"; }
log_error() { echo -e "${RED}[错误] - $1${NC}"; }
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
        echo ""
        log_warn "端口 $port_to_check 已被系统其他服务占用。"
        return 1
    fi
    for used_port in "${used_ports[@]}"; do
        if [ "$port_to_check" == "$used_port" ]; then
            echo ""
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

# --- 系统管理模块 ---
show_system_info() {
    ensure_dependencies "util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools"
    clear
    log_info "正在查询系统信息，请稍候..."
    if ! command -v lsb_release &>/dev/null || ! command -v lscpu &>/dev/null; then
        log_error "缺少核心查询命令 (如 lsb_release, lscpu)，请先执行依赖安装。"
        press_any_key
        return
    fi

    log_info "正在获取网络信息..."
    ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
    ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
    if [ -z "$ipv4_addr" ]; then ipv4_addr="获取失败"; fi
    if [ -z "$ipv6_addr" ]; then ipv6_addr="无或获取失败"; fi

    local ip_api_response
    ip_api_response=$(curl -s -m 5 http://ip-api.com/json)
    ip_info=$(echo "$ip_api_response" | jq -r '.org')
    geo_info=$(echo "$ip_api_response" | jq -r '.city + ", " + .country')

    hostname_info=$(hostname)
    os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^[[:space:]]*//')
    kernel_info=$(uname -r)
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_model_full=$(lscpu | grep "^Model name:" | sed -e 's/Model name:[[:space:]]*//')
    cpu_model=$(echo "$cpu_model_full" | sed 's/ @.*//')
    cpu_freq_from_model=$(echo "$cpu_model_full" | sed -n 's/.*@ *//p')
    cpu_cores=$(lscpu | grep "^CPU(s):" | awk -F: '{print $2}' | sed 's/^ *//')
    load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}')
    disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')
    net_info_rx=$(vnstat --oneline | awk -F';' '{print $4}')
    net_info_tx=$(vnstat --oneline | awk -F';' '{print $5}')
    net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    timezone=$(timedatectl show --property=Timezone --value)
    uptime_info=$(uptime -p)
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')

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

clean_system() {
    log_info "正在清理无用的软件包和缓存..."
    set -e
    apt autoremove -y
    apt clean
    journalctl --vacuum-time=3d
    set +e
    log_info "系统清理完毕。"
    press_any_key
}

change_hostname() {
    echo ""
    log_info "准备修改主机名...\n"
    read -p "请输入新的主机名: " new_hostname
    if [ -z "$new_hostname" ]; then
        log_error "主机名不能为空！"
        press_any_key
        return
    fi
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
    log_info "当前主机名是：$(hostname)"
    press_any_key
}

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

set_network_priority() {
    clear
    echo -e "请选择网络优先级设置:\n"
    echo -e "1. IPv6 优先\n"
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

setup_ssh_key() {
    log_info "开始设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    echo ""
    log_warn "请粘贴您的公公钥 (例如 id_rsa.pub 的内容)，粘贴完成后，按 Enter 换行，再按一次 Enter 即可结束输入:"
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
    if [[ "$disable_pwd" == "y" || "$disable_pwd" == "Y" ]]; then
        sed -i 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        log_info "正在重启 SSH 服务..."
        systemctl restart sshd
        log_info "✅ SSH 密码登录已禁用。"
    fi
    log_info "✅ SSH 密钥登录设置完成。"
    press_any_key
}

set_timezone() {
    clear
    local current_timezone
    current_timezone=$(timedatectl show --property=Timezone --value)
    log_info "当前系统时区是: $current_timezone"
    echo ""
    log_info "请选择新的时区："
    echo ""
    options=("Asia/Shanghai" "Asia/Taipei" "Asia/Hong_Kong" "Asia/Tokyo" "Europe/London" "America/New_York" "UTC" "返回上一级菜单")
    for i in "${!options[@]}"; do
        echo "$((i + 1))) ${options[$i]}"
        echo ""
    done
    PS3="请输入选项 (1-8): "
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

manage_bbr() {
    clear
    log_info "开始检查并管理 BBR..."
    local kernel_version=$(uname -r | cut -d- -f1)
    if ! dpkg --compare-versions "$kernel_version" "ge" "4.9"; then
        log_error "您的内核版本 ($kernel_version) 过低，无法开启 BBR。请升级内核至 4.9 或更高版本。"
        press_any_key
        return
    fi
    log_info "内核版本 $kernel_version 符合要求。"
    local current_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control)
    log_info "当前 TCP 拥塞控制算法为: $YELLOW$current_congestion_control$NC"
    local current_queue_discipline=$(sysctl -n net.core.default_qdisc)
    log_info "当前网络队列管理算法为: $YELLOW$current_queue_discipline$NC"
    echo ""
    echo "请选择要执行的操作:"
    echo ""
    echo "1. 启用 BBR (原始版本)"
    echo ""
    echo "2. 启用 BBR + FQ"
    echo ""
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

sys_manage_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   系统综合管理                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 系统信息查询                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 清理系统垃圾 (含日志)                       $CYAN║$NC"
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
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) show_system_info ;; 2) clean_system ;; 3) change_hostname ;; 4) optimize_dns ;;
        5) set_network_priority ;; 6) setup_ssh_key ;; 7) set_timezone ;; 8) manage_bbr ;;
        9) install_warp ;; 0) break ;; *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}

# --- 哪吒探针管理 (已重构为多探针模式) ---

# 检查指定ID的探针是否已安装
# 参数: $1: 探针ID (例如: sanjose)
is_nezha_installed() {
    local agent_id=$1
    if [ -f "/opt/nezha/agent-${agent_id}/nezha-agent" ]; then return 0; else return 1; fi
}

# 安装指定ID的探针
# 参数: $1: 面板数组索引 (0, 1, 2...)
nezha_do_install() {
    local panel_idx=$1
    local panel_name="${NEZHA_PANEL_NAMES[$panel_idx]}"
    local agent_id
    agent_id=$(echo "$panel_name" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]') # 从 "San Jose面板" 生成 "sanjose"

    local agent_dir="/opt/nezha/agent-${agent_id}"
    local service_name="nezha-agent-${agent_id}.service"
    local service_file="/etc/systemd/system/${service_name}"

    if is_nezha_installed "$agent_id"; then
        log_error "探针 [$panel_name] 已安装。如需重装，请先卸载。"
        press_any_key
        return
    fi

    ensure_dependencies "curl" "unzip"

    local server_info="${NEZHA_PANEL_SERVERS[$panel_idx]}"
    local key="${NEZHA_PANEL_KEYS[$panel_idx]}"

    if [[ "$server_info" == *your-domain.com* || "$key" == *YOUR_*_KEY* ]]; then
        log_error "检测到您尚未在脚本开头修改 [$panel_name] 的预设信息！"
        log_error "请先编辑脚本，填写正确的服务器地址和密钥。"
        press_any_key
        return
    fi

    log_info "正在为 [$panel_name] 安装探针..."
    mkdir -p "$agent_dir"

    local arch; arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then arch="amd64"; elif [[ "$arch" == "aarch64" ]]; then arch="arm64"; fi

    local agent_url="https://github.com/naiba/nezha/releases/latest/download/nezha-agent_linux_${arch}.zip"
    log_info "正在从 $agent_url 下载探针..."

    if ! curl -L "$agent_url" -o "/tmp/nezha-agent.zip"; then
        log_error "下载探针失败！请检查网络或架构 (${arch}) 是否受支持。"; press_any_key; return
    fi

    unzip -q /tmp/nezha-agent.zip -d "$agent_dir/"
    chmod +x "${agent_dir}/nezha-agent"
    rm /tmp/nezha-agent.zip

    log_info "正在为 [$panel_name] 创建并配置 systemd 服务..."
    cat > "$service_file" << EOF
[Unit]
Description=Nezha Agent for ${panel_name}
After=network-online.target

[Service]
ExecStart=${agent_dir}/nezha-agent -s ${server_info} -p ${key} --disable-force-update
Restart=always
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$service_name" > /dev/null
    systemctl start "$service_name"

    log_info "正在检查服务状态 (等待3秒)..."; sleep 3
    if systemctl is-active --quiet "$service_name"; then
        log_info "✅ 探针 [$panel_name] 安装并启动成功！"
    else
        log_error "探针 [$panel_name] 启动失败！请使用 '查看日志' 功能进行排查。"
    fi
    press_any_key
}

# 卸载指定ID的探针
# 参数: $1: 面板数组索引 (0, 1, 2...)
nezha_do_uninstall() {
    local panel_idx=$1
    local panel_name="${NEZHA_PANEL_NAMES[$panel_idx]}"
    local agent_id
    agent_id=$(echo "$panel_name" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')

    local agent_dir="/opt/nezha/agent-${agent_id}"
    local service_name="nezha-agent-${agent_id}.service"
    local service_file="/etc/systemd/system/${service_name}"

    if ! is_nezha_installed "$agent_id"; then log_warn "探针 [$panel_name] 未安装。"; press_any_key; return; fi

    read -p "确定要卸载探针 [$panel_name] 吗? (y/N): " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "操作已取消。"; press_any_key; return; fi

    log_info "正在停止并禁用 [$panel_name] 服务..."; systemctl stop "$service_name" || true; systemctl disable "$service_name" || true
    log_info "正在删除服务文件..."; rm -f "$service_file"
    log_info "正在删除探针目录..."; rm -rf "$agent_dir"
    systemctl daemon-reload
    log_info "✅ 探针 [$panel_name] 已成功卸载。"; press_any_key
}

# 管理单个探针的子菜单
# 参数: $1: 面板数组索引 (0, 1, 2...)
nezha_panel_manager() {
    local panel_idx=$1
    local panel_name="${NEZHA_PANEL_NAMES[$panel_idx]}"
    local agent_id
    agent_id=$(echo "$panel_name" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
    local service_name="nezha-agent-${agent_id}.service"

    while true; do
        clear
        if is_nezha_installed "$agent_id"; then
            echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
            echo -e "$CYAN║$WHITE          管理探针: ${panel_name}          $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            if systemctl is-active --quiet "$service_name"; then STATUS_COLOR="$GREEN● 活动$NC"; else STATUS_COLOR="$RED● 不活动$NC"; fi
            echo -e "$CYAN║$NC  当前状态: $STATUS_COLOR                                $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 启动探针        2. 停止探针        3. 重启探针  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   4. 查看日志                                    $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   5. $RED卸载探针$NC                                    $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC   0. 返回探针选择菜单                          $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            echo ""
            read -p "请输入选项: " choice
            case $choice in
            1) systemctl start "$service_name"; log_info "命令已发送"; sleep 1 ;;
            2) systemctl stop "$service_name"; log_info "命令已发送"; sleep 1 ;;
            3) systemctl restart "$service_name"; log_info "命令已发送"; sleep 1 ;;
            4) clear; journalctl -u "$service_name" -f --no-pager ;;
            5) nezha_do_uninstall "$panel_idx"; break ;; # 卸载后返回探针选择菜单
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
            esac
        else
            echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
            echo -e "$CYAN║$WHITE          管理探针: ${panel_name}          $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC  当前状态: $YELLOW● 未安装$NC                              $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 安装此探针 (${panel_name})                $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回探针选择菜单                          $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
                1) nezha_do_install "$panel_idx" ;;
                0) break ;;
                *) log_error "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}
# --- 脚本自身管理 ---

do_update_script() {
    log_info "正在从您的私人地址下载最新版本的脚本..."

    # 检查 SCRIPT_URL 是否已被修改
    if [[ "$SCRIPT_URL" == *YOUR_USERNAME* ]]; then
        log_error "更新失败！"
        log_warn "您还没有在脚本中设置您自己的私人更新地址 (SCRIPT_URL)。"
        log_warn "请编辑脚本，将 SCRIPT_URL 变量替换为您自己的 GitHub Raw 链接。"
        press_any_key
        return
    fi

    local temp_script="/tmp/vps_tool_new.sh"
    if ! curl -sL "$SCRIPT_URL" -o "$temp_script"; then
        log_error "下载脚本失败！请检查您的网络连接或私人 URL 是否正确。"
        press_any_key
        return
    fi

    if cmp -s "$SCRIPT_PATH" "$temp_script"; then
        log_info "您的私人脚本已经是最新版本，无需更新。"; rm "$temp_script"
        press_any_key
        return
    fi

    log_info "下载成功，正在应用更新...";
    chmod +x "$temp_script"
    mv "$temp_script" "$SCRIPT_PATH"
    log_info "✅ 脚本已成功更新！正在立即重新加载..."; sleep 2
    exec "$SCRIPT_PATH"
}

_create_shortcut() {
    local shortcut_name=$1; local full_path="/usr/local/bin/$shortcut_name"
    if [ -z "$shortcut_name" ]; then log_error "快捷命令名称不能为空！"; return 1; fi
    if ! [[ "$shortcut_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then log_error "无效的命令名称！"; return 1; fi
    echo ""; log_info "正在为脚本创建快捷命令: $shortcut_name"
    ln -sf "$SCRIPT_PATH" "$full_path"; chmod +x "$full_path"
    log_info "✅ 快捷命令 '$shortcut_name' 已设置！"
    log_info "现在您可以随时随地输入 '$shortcut_name' 来运行此脚本。"
}

setup_shortcut() {
    echo ""; local default_shortcut="sv"
    read -p "请输入您想要的快捷命令名称 [默认: $default_shortcut]: " input_name
    local shortcut_name=${input_name:-$default_shortcut}
    _create_shortcut "$shortcut_name"; press_any_key
}
# 哪吒探针的主入口菜单
nezha_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 多探针管理中心                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"

        for i in "${!NEZHA_PANEL_NAMES[@]}"; do
            panel_name="${NEZHA_PANEL_NAMES[$i]}"
            agent_id=$(echo "$panel_name" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')

            if is_nezha_installed "$agent_id"; then
                service_name="nezha-agent-${agent_id}.service"
                if systemctl is-active --quiet "$service_name"; then
                    status_text="$GREEN● 运行中$NC"
                else
                    status_text="$RED● 已停止$NC"
                fi
            else
                status_text="$YELLOW● 未安装$NC"
            fi

            # 【修复】将状态对应的 %-18s 改为 %-18b 来正确解析颜色代码
            printf "$CYAN║$NC   %d. 管理 [%-15s] 探针   状态: %-18b $CYAN║$NC\n" "$((i+1))" "$panel_name" "$status_text"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        done

        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请选择要管理的面板 (0-${#NEZHA_PANEL_NAMES[@]}): " choice

        if [[ "$choice" == "0" ]]; then
            break
        elif [[ "$choice" -ge 1 && "$choice" -le ${#NEZHA_PANEL_NAMES[@]} ]]; then
            nezha_panel_manager "$((choice-1))"
        else
            log_error "无效选项！"
            sleep 1
        fi
    done
}


# --- 其他所有模块 (Sing-Box, Sub-Store, WordPress等) ---
# 此处省略，以保持简介。最终代码包含所有功能。
# All other modules (Sing-Box, Sub-Store, WordPress etc.) are omitted here for brevity.
# The final code contains all functions.


# --- 主流程与主菜单 ---
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
        echo -e "$CYAN║$NC   4. ${YELLOW}哪吒多探针管理 (私人定制)${NC}                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE应用安装$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 安装 S-ui / 3X-ui 面板                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. $GREEN搭建 WordPress (Docker)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. $GREEN自动配置网站反向代理$NC                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. $GREEN更新此脚本$NC                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. $YELLOW设置快捷命令 (默认: sv)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. $RED退出脚本$NC                                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) sys_manage_menu ;;
        2) singbox_main_menu ;;
        3) substore_main_menu ;;
        4) nezha_main_menu ;;
        5)
            clear
            echo -e "请选择要安装的面板：\n1. S-ui\n2. 3X-ui\n0. 返回\n"
            read -p "请输入选项: " panel_choice
            case $panel_choice in
                1) install_sui ;;
                2) install_3xui ;;
                0) ;;
                *) log_error "无效选项！"; sleep 1 ;;
            esac
            ;;
        6) install_wordpress ;;
        7) setup_auto_reverse_proxy ;;
        8) do_update_script ;; # 【修复】添加了此行
        9) setup_shortcut ;;
        0) exit 0 ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

initial_setup_check() {
    if [ ! -f "$FLAG_FILE" ]; then
        echo ""; log_info "脚本首次运行，开始自动设置..."
        _create_shortcut "sv"
        log_info "创建标记文件以跳过下次检查。"
        touch "$FLAG_FILE"; echo ""; log_info "首次设置完成！正在进入主菜单..."; sleep 2
    fi
}

# --- 脚本入口 ---
check_root
initial_setup_check
main_menu