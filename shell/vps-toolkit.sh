#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/$SUBSTORE_SERVICE_NAME"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"
log_info() { echo -e "$GREEN[信息] - $1$NC"; }
log_warn() { echo -e "$YELLOW[注意] - $1$NC"; }
log_error() { echo -e "$RED[错误] - $1$NC"; }
press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键返回..."
}
check_root() { if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本必须以 root 用户身份运行。"
    exit 1
fi; }
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
    ip_info=$(curl -s http://ip-api.com/json | jq -r '.org')
    dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    geo_info=$(curl -s http://ip-api.com/json | jq -r '.city + ", " + .country')
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
    0) return 1 ;;
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
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
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
# ================= Nezha Management Start =================
# 检查隔离的v0探针是否安装
is_nezha_agent_v0_installed() {
    [ -f "/etc/systemd/system/nezha-agent-v0.service" ]
}
# 检查隔离的v1探针是否安装
is_nezha_agent_v1_installed() {
    [ -f "/etc/systemd/system/nezha-agent-v1.service" ]
}
# 检查标准探针是否安装
is_nezha_agent_standard_installed() {
    [ -f "/etc/systemd/system/nezha-agent.service" ]
}
# 静默卸载隔离的v0探针
uninstall_nezha_agent_v0_silent() {
    if ! is_nezha_agent_v0_installed; then return; fi
    systemctl stop nezha-agent-v0.service &>/dev/null
    systemctl disable nezha-agent-v0.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent-v0.service
    rm -rf /opt/nezha/agent-v0
}
# 静默卸载隔离的v1探针
uninstall_nezha_agent_v1_silent() {
    if ! is_nezha_agent_v1_installed; then return; fi
    systemctl stop nezha-agent-v1.service &>/dev/null
    systemctl disable nezha-agent-v1.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent-v1.service
    rm -rf /opt/nezha/agent-v1
}
# 静默卸载标准探针
uninstall_nezha_agent_standard_silent() {
    if ! is_nezha_agent_standard_installed; then return; fi
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent.service
    rm -rf /opt/nezha/agent
}
# 完整卸载隔离的v0探针
uninstall_nezha_agent_v0() {
    if ! is_nezha_agent_v0_installed; then
        log_warn "Nezha V0 探针未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用 nezha-agent-v0 服务..."
    uninstall_nezha_agent_v0_silent
    systemctl daemon-reload
    log_info "✅ Nezha V0 探针已成功卸载。"
    press_any_key
}
# 完整卸载隔离的v1探针
uninstall_nezha_agent_v1() {
    if ! is_nezha_agent_v1_installed; then
        log_warn "Nezha V1 探针未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用 nezha-agent-v1 服务..."
    uninstall_nezha_agent_v1_silent
    systemctl daemon-reload
    log_info "✅ Nezha V1 探针已成功卸载。"
    press_any_key
}
# 一键清理所有探针
cleanup_all_nezha_agents() {
    log_warn "此操作将尝试停止并删除本机上所有版本的哪吒探针！"
    log_warn "包括: 标准版, V0版, V1版。此操作不可逆！"
    read -p "请输入 Y 确认执行: " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi

    log_info "正在清理标准版 nezha-agent..."
    uninstall_nezha_agent_standard_silent

    log_info "正在清理 V0 版 nezha-agent-v0..."
    uninstall_nezha_agent_v0_silent

    log_info "正在清理 V1 版 nezha-agent-v1..."
    uninstall_nezha_agent_v1_silent

    log_info "正在重载 systemd 配置..."
    systemctl daemon-reload

    log_info "✅ 所有可识别的哪吒探针均已清理完毕。"
    press_any_key
}
# [核心重构] 采用“先安装标准版，再改造”的逻辑安装V0探针
install_nezha_agent_v0() {
    log_info "为确保全新安装，将首先清理所有旧的探针安装..."
    cleanup_all_nezha_agents &>/dev/null
    systemctl daemon-reload

    ensure_dependencies "curl" "wget" "unzip"
    clear
    log_info "开始安装 Nezha V0 探针 (安装后改造模式)..."

    read -p "请输入面板服务器地址 [默认: nz.wiitwo.eu.org]: " server_addr
    server_addr=${server_addr:-"nz.wiitwo.eu.org"}
    read -p "请输入面板服务器端口 [默认: 443]: " server_port
    server_port=${server_port:-"443"}
    read -p "请输入面板密钥: " server_key
    if [ -z "$server_key" ]; then
        log_error "面板密钥不能为空！"; press_any_key; return
    fi

    local tls_option="--tls"
    if [[ "$server_port" == "80" || "$server_port" == "8080" ]]; then
        tls_option="";
    fi

    local SCRIPT_PATH_TMP="/tmp/nezha_install_orig.sh"

    log_info "正在下载官方安装脚本..."
    if ! curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/install_en.sh -o "$SCRIPT_PATH_TMP"; then
        log_error "下载官方脚本失败！"; press_any_key; return
    fi

    chmod +x "$SCRIPT_PATH_TMP"

    log_info "第1步：执行官方原版脚本进行标准安装..."
    bash "$SCRIPT_PATH_TMP" install_agent "$server_addr" "$server_port" "$server_key" $tls_option
    rm "$SCRIPT_PATH_TMP"

    if ! is_nezha_agent_standard_installed; then
        log_error "官方脚本未能成功创建标准服务，操作中止。"
        press_any_key
        return
    fi
    log_info "标准服务安装成功，即将开始改造..."
    sleep 1

    log_info "第2步：停止标准服务并重命名文件以实现隔离..."
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null

    mv /etc/systemd/system/nezha-agent.service /etc/systemd/system/nezha-agent-v0.service
    mv /opt/nezha/agent /opt/nezha/agent-v0

    log_info "第3步：修改新的服务文件，使其指向正确的路径..."
    sed -i 's|/opt/nezha/agent/nezha-agent|/opt/nezha/agent-v0/nezha-agent|g' /etc/systemd/system/nezha-agent-v0.service

    log_info "第4步：重载并启动改造后的 'nezha-agent-v0' 服务..."
    systemctl daemon-reload
    systemctl enable nezha-agent-v0.service
    systemctl start nezha-agent-v0.service

    log_info "检查最终服务状态..."
    sleep 2
    if systemctl is-active --quiet nezha-agent-v0; then
        log_info "✅ Nezha V0 探针 (隔离版) 已成功安装并启动！"
    else
        log_error "Nezha V0 探针 (隔离版) 最终启动失败！"
        log_warn "显示详细状态以供诊断:"
        systemctl status nezha-agent-v0.service --no-pager -l
    fi
    press_any_key
}
# [核心重构] 采用“先安装标准版，再改造”的逻辑安装V1探针
install_nezha_agent_v1() {
    log_info "为确保全新安装，将首先清理所有旧的探针安装..."
    cleanup_all_nezha_agents &>/dev/null
    systemctl daemon-reload

    ensure_dependencies "curl" "wget" "unzip"
    clear
    log_info "开始安装 Nezha V1 探针 (安装后改造模式)..."

    read -p "请输入面板服务器地址和端口 (格式: domain:port) [默认: nz.ssong.eu.org:8008]: " server_info
    server_info=${server_info:-"nz.ssong.eu.org:8008"}
    read -p "请输入面板密钥 [默认: wdptRINwlgBB3kE0U8eDGYjqV56nAhLh]: " server_secret
    server_secret=${server_secret:-"wdptRINwlgBB3kE0U8eDGYjqV56nAhLh"}
    read -p "是否为gRPC连接启用TLS? (y/N): " use_tls
    if [[ "$use_tls" =~ ^[Yy]$ ]]; then NZ_TLS="true"; else NZ_TLS="false"; fi

    local SCRIPT_PATH_TMP="/tmp/agent_v1_install_orig.sh"

    log_info "正在下载官方V1安装脚本..."
    if ! curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh -o "$SCRIPT_PATH_TMP"; then
        log_error "下载官方脚本失败！"; press_any_key; return
    fi

    chmod +x "$SCRIPT_PATH_TMP"

    log_info "第1步：执行官方原版脚本进行标准安装..."
    export NZ_SERVER="$server_info"
    export NZ_TLS="$NZ_TLS"
    export NZ_CLIENT_SECRET="$server_secret"
    bash "$SCRIPT_PATH_TMP"
    unset NZ_SERVER NZ_TLS NZ_CLIENT_SECRET
    rm "$SCRIPT_PATH_TMP"

    if ! is_nezha_agent_standard_installed; then
        log_error "官方脚本未能成功创建标准服务，操作中止。"
        press_any_key
        return
    fi
    log_info "标准服务安装成功，即将开始改造..."
    sleep 1

    log_info "第2步：停止标准服务并重命名文件以实现隔离..."
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null

    mv /etc/systemd/system/nezha-agent.service /etc/systemd/system/nezha-agent-v1.service
    mv /opt/nezha/agent /opt/nezha/agent-v1

    log_info "第3步：修改新的服务文件，使其指向正确的路径..."
    sed -i 's|/opt/nezha/agent|/opt/nezha/agent-v1|g' /etc/systemd/system/nezha-agent-v1.service

    log_info "第4步：重载并启动改造后的 'nezha-agent-v1' 服务..."
    systemctl daemon-reload
    systemctl enable nezha-agent-v1.service
    systemctl start nezha-agent-v1.service

    log_info "检查最终服务状态..."
    sleep 2
    if systemctl is-active --quiet nezha-agent-v1; then
        log_info "✅ Nezha V1 探针 (隔离版) 已成功安装并启动！"
    else
        log_error "Nezha V1 探针 (隔离版) 最终启动失败！"
        log_warn "显示详细状态以供诊断:"
        systemctl status nezha-agent-v1.service --no-pager -l
    fi
    press_any_key
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
        echo -e "$CYAN║$WHITE                 哪吒探针 (Agent) 管理            $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        if is_nezha_agent_v0_installed; then
            echo -e "$CYAN║$NC   1. 安装/重装 V0 探针 ${GREEN}(已安装)$NC                   $CYAN║$NC"
        else
            echo -e "$CYAN║$NC   1. 安装/重装 V0 探针 ${YELLOW}(未安装)$NC                   $CYAN║$NC"
        fi
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. $RED卸载 V0 探针$NC                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        if is_nezha_agent_v1_installed; then
            echo -e "$CYAN║$NC   3. 安装/重装 V1 探针 ${GREEN}(已安装)$NC                   $CYAN║$NC"
        else
            echo -e "$CYAN║$NC   3. 安装/重装 V1 探针 ${YELLOW}(未安装)$NC                   $CYAN║$NC"
        fi
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. $RED卸载 V1 探针$NC                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   5. $YELLOW清理所有哪吒探针 (强制重置)$NC                $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_agent_v0 ;;
        2) uninstall_nezha_agent_v0 ;;
        3) install_nezha_agent_v1 ;;
        4) uninstall_nezha_agent_v1 ;;
        5) cleanup_all_nezha_agents ;;
        0) break ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
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
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}
nezha_manage_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   哪吒监控管理                   $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 探针 (Agent) 管理                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 面板 (Dashboard) 管理                       $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) nezha_agent_menu ;;
        2) nezha_dashboard_menu ;;
        0) break ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}
# ================= Nezha Management End ===================
# ================= App Management Start =================
app_management_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                  应用安装与管理                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. $GREEN哪吒监控管理$NC                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Sing-Box 管理                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. Sub-Store 管理                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE面板与应用$CYAN ───────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 安装 S-ui 面板                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 安装 3X-ui 面板                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. $GREEN搭建 WordPress (Docker)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) nezha_manage_menu ;;
        2) singbox_main_menu ;;
        3) substore_main_menu ;;
        4) install_sui ;;
        5) install_3xui ;;
        6) install_wordpress ;;
        0) break ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}
# ================= App Management End ===================
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
setup_shortcut() {
    echo ""
    local default_shortcut="sv"
    read -p "请输入您想要的快捷命令名称 [默认: $default_shortcut]: " input_name
    local shortcut_name=${input_name:-$default_shortcut}
    _create_shortcut "$shortcut_name"
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
main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE              全功能 VPS & 应用管理脚本           $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 系统综合管理                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. $GREEN应用安装与管理$NC                             $CYAN║$NC"
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
        2) app_management_menu ;;
        8) do_update_script ;;
        9) setup_shortcut ;;
        0) exit 0 ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}
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
check_root
initial_setup_check
main_menu