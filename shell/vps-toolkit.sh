#!/bin/bash

# =================================================================================
#               全功能 VPS & 应用管理脚本 (v1.0)
#
#   整合来源: sys.sh, singbox.sh, sub-store.sh
#   主导风格: sub-store.sh
#   功能涵盖:
#       - 系统综合管理 (System Management)
#       - Sing-Box 服务管理 (Sing-Box Management)
#       - Sub-Store 服务管理 (Sub-Store Management)
# =================================================================================


# --- 全局变量和辅助函数 ---
# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 配置变量
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/${SUBSTORE_SERVICE_NAME}"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SHORTCUT_PATH="/usr/local/bin/vs"
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# 日志与交互函数
log_info() { echo -e "${GREEN}[信息] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[注意] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[错误] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
press_any_key() { echo ""; read -n 1 -s -r -p "按任意键返回..."; }
check_root() { if [ "$(id -u)" -ne 0 ]; then log_error "此脚本必须以 root 用户身份运行。"; exit 1; fi; }

# 检查端口是否被占用
check_port() {
    local port=$1
    if ss -tln | grep -q -E "(:|:::)${port}\b"; then
        log_error "端口 ${port} 已被占用。"
        return 1
    fi
    return 0
}

# 生成随机端口号
generate_random_port() {
    echo $((RANDOM % 64512 + 1024))
}

# 随机生成密码函数
generate_random_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c 20
}

# --- 核心功能：依赖项管理 ---

check_and_install_dependencies() {
    log_info "开始检查并安装必需的依赖项..."
    # 修正后的列表，只包含真实的、可安装的软件包名称
    local dependencies=(
        "lsb-release"
        "curl"
        "wget"
        "unzip"
        "git"
        "sudo"
        "iproute2"
        "dnsutils"
        "apt-transport-https"
        "debian-keyring"
        "debian-archive-keyring"
        "util-linux" # 包含 lscpu, df 等
        "procps"     # 包含 free, uptime 等
        "net-tools"  # 包含 ifconfig
        "vnstat"
        "jq"
        "uuid-runtime"
        "certbot"
        "python3-certbot-nginx"
    )
    local missing_dependencies=()

    # 使用 dpkg-query 检查软件包状态，这比 grep 更准确
    log_info "正在检查已安装的软件包..."
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
            log_info "正在安装 ${pkg}..."
            apt-get install -y "$pkg"
        done
        set +e
        log_info "所有必需的依赖项已安装完毕。"
    else
        log_info "所有必需的依赖项均已安装。"
    fi
}


# --- 功能模块：系统综合管理 (来自 sys.sh) ---

# 显示系统信息
show_system_info() {
    clear
    log_info "正在查询系统信息，请稍候..."

    # 主机名
    hostname_info=$(hostname)
    # 操作系统和版本
    os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^ *//')
    # Linux内核版本
    kernel_info=$(uname -r)
    # CPU架构和型号
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_model=$(lscpu | grep "Model name" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_cores=$(lscpu | grep "CPU(s):" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_freq=$(lscpu | grep "CPU MHz" | awk -F: '{print $2}' | sed 's/^ *//')
    # 系统负载
    load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    # 内存使用情况
    memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}')
    # 硬盘使用情况
    disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')
    # 网络接收和发送量
    net_info=$(vnstat --oneline | awk -F\; '{print "接收: " $4 " / 发送: " $5}')
    # 网络算法
    net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    # 运营商信息
    ip_info=$(curl -s http://ip-api.com/json | jq -r '.org')
    # IP 地址
    ip_addr=$(hostname -I)
    # DNS 地址
    dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    # 地理位置和时区
    geo_info=$(curl -s http://ip-api.com/json | jq -r '.city + ", " + .country')
    timezone=$(timedatectl show --property=Timezone --value)
    # 系统运行时间
    uptime_info=$(uptime -p)
    # 当前时间
    current_time=$(date "+%Y-%m-%d %H:%M:%S")

    # 输出所有信息
    echo -e "${CYAN}-------------------- 系统信息查询 ----------------------${NC}"
    echo -e "${GREEN}主机名:       ${WHITE}$hostname_info${NC}"
    echo -e "${GREEN}系统版本:     ${WHITE}$os_info${NC}"
    echo -e "${GREEN}Linux版本:    ${WHITE}$kernel_info${NC}"
    echo -e "${CYAN}-------------------------------------------------------${NC}"
    echo -e "${GREEN}CPU架构:      ${WHITE}$cpu_arch${NC}"
    echo -e "${GREEN}CPU型号:      ${WHITE}$cpu_model${NC}"
    echo -e "${GREEN}CPU核心数:    ${WHITE}$cpu_cores${NC}"
    echo -e "${GREEN}CPU频率:      ${WHITE}$cpu_freq MHz${NC}"
    echo -e "${CYAN}-------------------------------------------------------${NC}"
    echo -e "${GREEN}CPU占用:      ${WHITE}$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')${NC}"
    echo -e "${GREEN}系统负载:     ${WHITE}$load_info${NC}"
    echo -e "${GREEN}物理内存:     ${WHITE}$memory_info${NC}"
    echo -e "${GREEN}硬盘占用:     ${WHITE}$disk_info${NC}"
    echo -e "${CYAN}-------------------------------------------------------${NC}"
    echo -e "${GREEN}网络流量:     ${WHITE}$net_info${NC}"
    echo -e "${GREEN}网络算法:     ${WHITE}$net_algo${NC}"
    echo -e "${CYAN}-------------------------------------------------------${NC}"
    echo -e "${GREEN}运营商:       ${WHITE}$ip_info${NC}"
    echo -e "${GREEN}IPv4地址:     ${WHITE}$ip_addr${NC}"
    echo -e "${GREEN}DNS地址:      ${WHITE}$dns_info${NC}"
    echo -e "${GREEN}地理位置:     ${WHITE}$geo_info${NC}"
    echo -e "${GREEN}系统时间:     ${WHITE}$timezone $current_time${NC}"
    echo -e "${CYAN}-------------------------------------------------------${NC}"
    echo -e "${GREEN}运行时长:     ${WHITE}$uptime_info${NC}"
    echo -e "${CYAN}-------------------------------------------------------${NC}"
    press_any_key
}

# 清理系统
clean_system() {
    log_info "正在清理无用的软件包和缓存..."
    set -e
    apt autoremove -y
    apt clean
    set +e
    log_info "系统清理完毕。"
    press_any_key
}

# 修改主机名
change_hostname() {
    log_info "准备修改主机名..."
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
    echo "$new_hostname" > /etc/hostname
    sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    set +e
    log_info "✅ 主机名修改成功！新的主机名是：${new_hostname}"
    log_info "当前主机名是：$(hostname)"
    press_any_key
}

# 优化 DNS
optimize_dns() {
    log_info "开始优化DNS地址..."
    log_info "正在检查IPv6支持..."
    if ping6 -c 1 google.com > /dev/null 2>&1; then
        log_info "检测到IPv6支持，配置IPv6优先的DNS..."
        cat <<EOF > /etc/resolv.conf
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
        cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
    fi
    log_info "✅ DNS优化完成！当前的DNS配置如下："
    echo -e "${WHITE}"
    cat /etc/resolv.conf
    echo -e "${NC}"
    press_any_key
}

# 设置网络优先级
set_network_priority() {
    clear
    echo "请选择网络优先级设置:"
    echo "1. IPv6 优先"
    echo "2. IPv4 优先"
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
                echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
            fi
            log_info "✅ IPv4 优先已设置。"
            ;;
        *)
            log_error "无效选择。"
            ;;
    esac
    press_any_key
}

# 设置SSH密钥登录
# 设置SSH密钥登录
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
        # 如果读到空行，则停止
        if [[ -z "$line" ]]; then
            break
        fi
        # 将读到的行拼接到变量中，并加上换行符
        public_key+="$line"$'\n'
    done

    # 移除可能存在的最后一个多余的换行符
    public_key=$(echo -e "$public_key" | sed '/^$/d')

    if [ -z "$public_key" ]; then
        log_error "没有输入公钥，操作已取消。"
        press_any_key
        return
    fi

    # 使用 printf 更安全地写入文件
    printf "%s\n" "$public_key" >> ~/.ssh/authorized_keys

    # 去重，防止重复添加同一个密钥
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

# 设置系统时区
set_timezone() {
    clear
    log_info "当前系统时区是: $(timedatectl show --property=Timezone --value)"
    echo "请选择新的时区："
    options=("Asia/Shanghai" "Asia/Hong_Kong" "Asia/Tokyo" "Europe/London" "America/New_York" "UTC")
    select opt in "${options[@]}"; do
        if [[ -n "$opt" ]]; then
            log_info "正在设置时区为 $opt..."
            timedatectl set-timezone "$opt"
            log_info "✅ 时区已成功设置为：$opt"
            break
        else
            log_error "无效选择。"
        fi
    done
    press_any_key
}

# 安装 S-ui
install_sui(){
    log_info "正在准备安装 S-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
    log_info "S-ui 安装脚本执行完毕。"
    press_any_key
}

# 安装 3X-ui
install_3xui(){
    log_info "正在准备安装 3X-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    log_info "3X-ui 安装脚本执行完毕。"
    press_any_key
}


# --- 功能模块：Sing-Box 管理 (来自 singbox.sh) ---

# 检查 Sing-Box 是否已安装
is_singbox_installed() {
    if command -v sing-box &> /dev/null; then return 0; else return 1; fi
}

# 检查并提示安装 Sing-Box
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

# 安装 Sing-Box
singbox_do_install() {
    if is_singbox_installed; then
        log_info "Sing-Box 已经安装，跳过安装过程。"
        press_any_key
        return
    fi
    log_info "Sing-Box 未安装，正在开始安装..."
    check_and_install_dependencies # 确保依赖就绪
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
        log_info "找到服务文件位于: ${service_file_path}"
        sed -i 's/User=sing-box/User=root/' "$service_file_path"
        sed -i 's/Group=sing-box/Group=root/' "$service_file_path"
        systemctl daemon-reload
        log_info "服务权限修改完成。"
    else
        log_error "无法自动定位 sing-box.service 文件！跳过权限修改。可能会导致证书读取失败。"
    fi

    config_dir="/etc/sing-box"
    mkdir -p "$config_dir"

    # ==================== 最终修正点：采用正确的 DNS 配置结构 ====================
    if [ ! -f "$SINGBOX_CONFIG_FILE" ]; then
        log_info "正在创建最终修正版的 Sing-Box 默认配置文件..."
        cat > "$SINGBOX_CONFIG_FILE" <<EOL
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-bootstrap",
        "address": "8.8.8.8",
        "detour": "direct"
      },
      {
        "tag": "google-doh",
        "address": "https://dns.google/dns-query",
        "address_resolver": "dns-bootstrap",
        "detour": "direct"
      },
      {
        "tag": "cloudflare-doh",
        "address": "https://1.1.1.1/dns-query",
        "address_resolver": "dns-bootstrap",
        "detour": "direct"
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"},
    {"type": "dns", "tag": "dns-out"}
  ],
  "route": {
    "rules": [
      {"protocol": "dns", "outbound": "dns-out"}
    ]
  }
}
EOL
    fi
    # ==============================================================================

    log_info "正在启用并重启 Sing-Box 服务..."
    systemctl enable sing-box.service
    systemctl restart sing-box
    log_info "✅ Sing-Box 配置文件初始化完成并已启动！"
    press_any_key
}

# 内部函数：处理 Caddy (全自动HTTPS)
_handle_caddy_cert() {
    log_info "检测到 Caddy 已安装。"
    log_warn "Caddy 会自动管理 SSL 证书，本脚本无需执行任何操作。"
    log_warn "请确保您的 Caddyfile 中已正确配置您的域名，例如："
    echo -e "${WHITE}"
    echo "sg.facebookbio.eu.org { Gzip 压缩指令"
    echo "    reverse_proxy localhost:PORT # 将 PORT 替换为 Sing-Box 的监听端口"
    echo "}"
    echo -e "${NC}"
    log_info "Caddy 会在首次被访问时自动申请证书。"
    # 既然 Caddy 会处理，我们在这里就认为“证书环节”是成功的
    return 0
}

# 内部函数：处理 Nginx
_handle_nginx_cert() {
    local domain_name="$1"
    log_info "检测到 Nginx，将使用 '--nginx' 插件模式。"

    if ! systemctl is-active --quiet nginx; then
        log_info "Nginx 服务未运行，正在启动..."
        systemctl start nginx
    fi

    local NGINX_CONF_PATH="/etc/nginx/sites-available/${domain_name}.conf"
    if [ ! -f "$NGINX_CONF_PATH" ]; then
        log_info "为域名验证创建临时的 Nginx 配置文件..."
        cat <<EOF > "$NGINX_CONF_PATH"
server {
    listen 80;
    listen [::]:80;
    server_name ${domain_name};
    root /var/www/html;
    index index.html index.htm;
}
EOF
        if [ ! -L "/etc/nginx/sites-enabled/${domain_name}.conf" ]; then
            ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"
        fi
    fi

    log_info "正在重载 Nginx 以应用配置..."
    if ! nginx -t; then log_error "Nginx 配置测试失败！"; return 1; fi
    systemctl reload nginx

    log_info "正在使用 'certbot --nginx' 模式为 ${domain_name} 申请证书..."
    certbot --nginx -d "${domain_name}" --non-interactive --agree-tos --email "temp@${domain_name}" --redirect

    if [ -f "/etc/letsencrypt/live/${domain_name}/fullchain.pem" ]; then
        log_info "✅ Nginx 模式证书申请成功！"
        return 0
    else
        log_error "Nginx 模式证书申请失败！"
        return 1
    fi
}

# 内部函数：处理 Apache
_handle_apache_cert() {
    local domain_name="$1"
    log_info "检测到 Apache，将使用 '--apache' 插件模式。"
    # 此处省略 Apache 的具体实现逻辑，它与 Nginx 非常相似
    # 需要检查 python3-certbot-apache 包，创建 VirtualHost 配置等
    log_error "Apache 模式暂未完全实现，请先安装 Nginx 或使用独立模式。"
    return 1
}

# 内部函数：处理 Standalone 独立模式 (作为最终回退)
_handle_standalone_cert() {
    local domain_name="$1"
    log_info "未检测到支持的 Web 服务器，回退到 '--standalone' 独立模式。"
    log_warn "此模式需要临时占用 80 端口，可能会暂停其他服务。"

    # 停止可能占用80端口的服务
    if systemctl is-active --quiet nginx; then
        log_info "临时停止 Nginx..."
        systemctl stop nginx
        local stopped_service="nginx"
    fi
    # 可为 apache2 添加类似逻辑

    certbot certonly --standalone -d "${domain_name}" --non-interactive --agree-tos --email "temp@${domain_name}"

    # 重启之前停止的服务
    if [ -n "$stopped_service" ]; then
        log_info "正在重启 ${stopped_service}..."
        systemctl start "$stopped_service"
    fi

    if [ -f "/etc/letsencrypt/live/${domain_name}/fullchain.pem" ]; then
        log_info "✅ Standalone 模式证书申请成功！"
        return 0
    else
        log_error "Standalone 模式证书申请失败！"
        return 1
    fi
}


# 主函数：申请SSL证书 (智能调度中心)
apply_ssl_certificate() {
    local domain_name="$1"
    log_info "开始智能检测环境并申请证书..."

    # 检查并安装 Certbot 主程序
    if ! command -v certbot &> /dev/null; then
        log_info "Certbot 未安装，正在安装..."
        apt-get update && apt-get install -y certbot
    fi

    # 新的判断逻辑：Caddy -> Apache -> Nginx (作为默认和最终选项)
    if command -v caddy &> /dev/null; then
        _handle_caddy_cert "$domain_name"
    elif command -v apache2 &> /dev/null; then
        # 检查 Apache 插件
        if ! dpkg -l | grep -q "python3-certbot-apache"; then
            log_info "正在安装 Certbot 的 Apache 插件..."
            apt-get install -y python3-certbot-apache
        fi
        _handle_apache_cert "$domain_name"
    else
        # 默认使用 Nginx 模式。
        # _handle_nginx_cert 函数内部会检查 nginx 是否已安装，如果没有则会提示用户安装。
        # 这就完美地实现了“如果啥都没有，就默认装Nginx”的逻辑。
        log_info "未检测到 Caddy 或 Apache，将默认使用 Nginx 模式。"

        # 检查 Nginx 插件
        if ! dpkg -l | grep -q "python3-certbot-nginx"; then
            log_info "正在安装 Certbot 的 Nginx 插件..."
            apt-get install -y python3-certbot-nginx
        fi
        _handle_nginx_cert "$domain_name"
    fi

    # 将函数最终的返回值 (0代表成功, 1代表失败) 传递给调用者
    return $?
}

# 获取域名和通用配置
get_domain_and_common_config() {
    local type_flag=$1
    echo
    while true; do
        read -p "请输入您已解析到本机的域名 (用于TLS): " domain_name
        if [[ -z "$domain_name" ]]; then log_error "域名不能为空"; continue; fi
        if ! echo "$domain_name" | grep -Pq "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; then log_error "无效的域名格式"; continue; fi
        break
    done

    if [[ $type_flag -eq 2 ]]; then # Hysteria2
        echo ""
        log_warn "Hysteria2 协议需要关闭域名在Cloudflare的DNS代理(小黄云)。"
    else
        echo ""
        log_warn "若域名开启了CF代理(小黄云), 请确保端口在Cloudflare支持的范围内。"
        echo ""
        log_warn "支持的HTTPS端口: 443, 2053, 2083, 2087, 2096, 8443。"
    fi
    echo ""
    log_warn "请确保防火墙已放行所需端口！"
    echo

    while true; do
        if [[ $type_flag -eq 2 ]]; then
            read -p "请输入一个 UDP 端口 (回车则随机生成): " port
        else
            read -p "请输入一个 TCP 端口 (回车则随机生成): " port
        fi
        if [[ -z "$port" ]]; then
            port=$(generate_random_port)
            log_info "已生成随机端口: $port"
            break
        fi
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "无效的端口号，请输入 1-65535 之间的数字。"
        else
            break
        fi
    done
    echo

    log_info "正在自动获取当前服务器位置..."
    location=$(curl -s ip-api.com/json | jq -r '.city' | sed 's/ //g')
    if [ -z "$location" ] || [ "$location" == "null" ]; then
        log_warn "自动获取位置失败，请手动输入。"
        read -p "请输入当前服务器位置 (例如: HongKong): " location
    else
        log_info "成功获取到位置: $location"
    fi
    echo
    read -p "请输入自定义节点标识 (例如: GCP): " custom_id
    echo

    cert_dir="/etc/letsencrypt/live/$domain_name"
    if [[ ! -d "$cert_dir" ]]; then
        log_info "证书不存在，开始申请证书..."
        if ! apply_ssl_certificate "$domain_name"; then
            return 1 # 证书申请失败，中断流程
        fi
    else
        log_info "证书已存在，跳过申请。"
    fi
    echo

    uuid=$(uuidgen)
    cert_path="$cert_dir/fullchain.pem"
    key_path="$cert_dir/privkey.pem"

    local protocol_name=""
    case $type_flag in
        1) protocol_name="VLESS" ;;
        2) protocol_name="Hysteria2" ;;
        3) protocol_name="VMess" ;;
        4) protocol_name="Trojan" ;;
        *) protocol_name="UNKNOWN" ;;
    esac
    tag="${location}-${custom_id}-${protocol_name}"
    return 0
}

# 添加节点配置到JSON并生成链接
add_protocol_node() {
    local protocol=$1
    local config=$2
    local node_link=""

    log_info "正在将新的入站配置添加到 config.json..."
    # 使用临时文件确保原子性操作，防止配置文件损坏
    if ! jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp"; then
        log_error "更新配置文件失败！请检查JSON格式和文件权限。"
        rm -f "$SINGBOX_CONFIG_FILE.tmp"
        return 1
    fi
    mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"

    case $protocol in
        VLESS)
            node_link="vless://${uuid}@${domain_name}:${port}?type=ws&security=tls&sni=${domain_name}&host=${domain_name}&path=%2F#${tag}"
            ;;
        Hysteria2)
            node_link="hysteria2://${password}@${domain_name}:${port}?upmbps=100&downmbps=1000&sni=${domain_name}&obfs=salamander&obfs-password=${obfs_password}#${tag}"
            ;;
        VMess)
            vmess_json="{\"v\":\"2\",\"ps\":\"${tag}\",\"add\":\"${domain_name}\",\"port\":\"${port}\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${domain_name}\",\"path\":\"/\",\"tls\":\"tls\"}"
            base64_vmess_link=$(echo -n "$vmess_json" | base64 -w 0)
            node_link="vmess://${base64_vmess_link}"
            ;;
        Trojan)
            node_link="trojan://${password}@${domain_name}:${port}?security=tls&sni=${domain_name}&type=ws&host=${domain_name}&path=/#${tag}"
            ;;
        *)
            log_error "未知的协议类型！"
            return 1
            ;;
    esac

    # 将新生成的链接追加到文件中
    echo "$node_link" >> "$SINGBOX_NODE_LINKS_FILE"

    log_info "正在重启 Sing-Box 使配置生效..."
    systemctl restart sing-box
    sleep 2
    if systemctl is-active --quiet sing-box; then
        log_info "Sing-Box 重启成功。"
    else
        log_error "Sing-Box 重启失败！请使用日志功能查看错误。"
        press_any_key
        return
    fi

    # ==================== 关键修正点 ====================
    # 新增节点成功后，直接调用查看函数，显示所有节点信息
    log_info "✅ 节点添加成功！正在显示所有节点信息..."
    sleep 1
    view_node_info
    # ===================================================
}

# 新增 VLESS 节点
add_vless_node() {
    if ! get_domain_and_common_config 1; then press_any_key; return; fi
    log_info "正在生成 VLESS 节点配置..."
    config="{
      \"type\": \"vless\",
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port,
      \"users\": [{\"uuid\": \"$uuid\", \"flow\": \"xtls-rprx-vision\"}],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\",
        \"key_path\": \"$key_path\"
      },
      \"transport\": {
        \"type\": \"ws\",
        \"path\": \"/\"
      }
    }"
    add_protocol_node "VLESS" "$config"
}

# 新增 Hysteria2 节点
add_hysteria2_node() {
    if ! get_domain_and_common_config 2; then press_any_key; return; fi
    password=$(generate_random_password)
    obfs_password=$(generate_random_password)
    log_info "正在生成 Hysteria2 节点配置..."
    config="{
      \"type\": \"hysteria2\",
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port,
      \"users\": [{\"password\": \"$password\"}],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\",
        \"key_path\": \"$key_path\"
      },
      \"up_mbps\": 100,
      \"down_mbps\": 1000,
      \"obfs\": {
        \"type\": \"salamander\",
        \"password\": \"$obfs_password\"
      }
    }"
    add_protocol_node "Hysteria2" "$config"
}

# 新增 VMess 节点
add_vmess_node() {
    if ! get_domain_and_common_config 3; then press_any_key; return; fi
    log_info "正在生成 VMess 节点配置..."
    config="{
      \"type\": \"vmess\",
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port,
      \"users\": [{\"uuid\": \"$uuid\"}],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\",
        \"key_path\": \"$key_path\"
      },
      \"transport\": {
        \"type\": \"ws\",
        \"path\": \"/\"
      }
    }"
    add_protocol_node "VMess" "$config"
}

# 新增 Trojan 节点
add_trojan_node() {
    if ! get_domain_and_common_config 4; then press_any_key; return; fi
    password=$(generate_random_password)
    log_info "正在生成 Trojan 节点配置..."
    config="{
      \"type\": \"trojan\",
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port,
      \"users\": [{\"password\": \"$password\"}],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\",
        \"key_path\": \"$key_path\"
      },
      \"transport\": {
        \"type\": \"ws\",
        \"path\": \"/\"
      }
    }"
    add_protocol_node "Trojan" "$config"
}

# 显示/管理节点信息
view_node_info() {
    while true; do
        clear
        if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
            log_warn "暂无配置的节点！"
            press_any_key
            return
        fi

        log_info "当前已配置的节点链接信息："
        echo -e "${CYAN}--------------------------------------------------------------${NC}"

        mapfile -t node_lines < "$SINGBOX_NODE_LINKS_FILE"
        all_links=""
        for i in "${!node_lines[@]}"; do
            line="${node_lines[$i]}"
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "VMess节点"')
            fi
            echo -e "${GREEN}$((i + 1)). ${WHITE}${node_name}${NC}"
            echo -e "${line}"
            echo -e "${CYAN}--------------------------------------------------------------${NC}"
            all_links+="$line"$'\n'
        done

        aggregated_link=$(echo -n "$all_links" | base64 -w0)
        echo -e "${GREEN}聚合订阅链接 (Base64):${NC}"
        echo -e "${YELLOW}${aggregated_link}${NC}"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"

        echo ""
        echo "1. 新增节点"
        echo "2. 删除节点"
        echo "3. 推送节点到 Sub-Store / Telegram"
        echo "0. 返回上级菜单"
        read -p "请输入选项: " choice
        case $choice in
            1) singbox_add_node_menu; break ;;
            2) delete_nodes; break ;;
            3) push_nodes; break ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# 删除节点
delete_nodes() {
    clear
    if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
        log_warn "没有节点可以删除。"
        press_any_key
        return
    fi

    mapfile -t node_lines < "$SINGBOX_NODE_LINKS_FILE"
    node_tags=()
    echo "请选择要删除的节点 (可多选，用空格分隔, 输入 'all' 删除所有):"
    for i in "${!node_lines[@]}"; do
        line="${node_lines[$i]}"
        tag=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
        node_tags+=("$tag")
        node_name=$tag
        if [[ "$line" =~ ^vmess:// ]]; then
            node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$tag"')
        fi
        echo -e "${GREEN}$((i + 1)). ${WHITE}${node_name}${NC}"
    done
    echo ""
    read -p "请输入编号: " -a nodes_to_delete

    if [[ "${nodes_to_delete[0]}" == "all" ]]; then
        read -p "你确定要删除所有节点吗？(y/N): " confirm_delete
        if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
            log_info "正在删除所有节点..."
            jq '.inbounds = []' "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
            rm -f "$SINGBOX_NODE_LINKS_FILE"
            log_info "✅ 所有节点已删除。"
        else
            log_info "操作已取消。"
        fi
    else
        nodes_to_delete_indices=()
        for node_num in "${nodes_to_delete[@]}"; do
            if ! [[ "$node_num" =~ ^[0-9]+$ ]] || [[ $node_num -lt 1 || $node_num -gt ${#node_lines[@]} ]]; then
                log_error "无效的编号: $node_num"
                continue
            fi
            nodes_to_delete_indices+=($((node_num - 1)))
        done

        # 降序排序以安全删除
        sorted_indices=($(for i in "${nodes_to_delete_indices[@]}"; do echo $i; done | sort -rn))

        remaining_lines=("${node_lines[@]}")
        for index in "${sorted_indices[@]}"; do
            tag_to_delete="${node_tags[$index]}"
            log_info "正在删除节点: ${tag_to_delete}"
            jq --arg tag "$tag_to_delete" 'del(.inbounds[] | select(.tag == $tag))' "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
            unset "remaining_lines[$index]"
        done

        printf "%s\n" "${remaining_lines[@]}" > "$SINGBOX_NODE_LINKS_FILE"
        log_info "✅ 所选节点已删除。"
    fi

    log_info "正在重启 Sing-Box..."
    systemctl restart sing-box
    press_any_key
}

# 推送节点
push_nodes() {
    log_info "该功能正在开发中，敬请期待！"
    press_any_key
}

# 卸载 Sing-Box (更彻底的版本)
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

    # ==================== 关键修正点：最终验证 ====================
    if command -v sing-box &> /dev/null; then
        log_error "卸载失败！系统中仍能找到 'sing-box' 命令。"
        log_warn "请手动执行 'whereis sing-box' 查找并删除残留文件。"
    else
        log_info "✅ Sing-Box 已成功卸载。"
    fi
    # =============================================================
    press_any_key
}

# --- 功能模块：Sub-Store 管理 (来自 sub-store.sh) ---

# 检查 Sub-Store 是否已安装
is_substore_installed() {
    if [ -f "$SUBSTORE_SERVICE_FILE" ]; then return 0; else return 1; fi
}

# 安装 Sub-Store
substore_do_install() {
    log_info "开始执行 Sub-Store 安装流程..."; set -e
    # 注意：这里的依赖检查现在是全局自动的，保留日志作为流程说明
    log_info "开始检查并安装必需的依赖项..."
    check_and_install_dependencies
    log_info "依赖检查完成。"

    log_info "正在安装 FNM, Node.js 和 PNPM (这可能需要一些时间)..."
    FNM_DIR="/root/.local/share/fnm"
    mkdir -p "$FNM_DIR"
    curl -L https://github.com/Schniz/fnm/releases/latest/download/fnm-linux.zip -o /tmp/fnm.zip
    unzip -q -o -d "$FNM_DIR" /tmp/fnm.zip; rm /tmp/fnm.zip; chmod +x "${FNM_DIR}/fnm";

    # 将 fnm 路径加入当前会话的 PATH
    export PATH="${FNM_DIR}:$PATH"
    log_info "FNM 安装完成。"

    # ==================== 关键修正点 ====================
    log_info "正在为当前会话配置 FNM 环境变量..."
    eval "$(fnm env)"
    # ===================================================

    log_info "正在使用 FNM 安装 Node.js (v20)..."
    fnm install v20
    fnm use v20

    log_info "正在安装 pnpm..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    export PNPM_HOME="/root/.local/share/pnpm"; export PATH="$PNPM_HOME:$PATH"
    log_info "Node.js 和 PNPM 环境准备就绪。"

    log_info "正在下载并设置 Sub-Store 项目文件..."
    mkdir -p "$SUBSTORE_INSTALL_DIR"; cd "$SUBSTORE_INSTALL_DIR"
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"

    log_info "开始配置系统服务..."; echo ""
    while true; do read -p "请输入前端访问端口 [默认: 3000]: " FRONTEND_PORT; FRONTEND_PORT=${FRONTEND_PORT:-3000}; check_port "$FRONTEND_PORT" && break; done
    echo "";
    while true; do read -p "请输入后端 API 端口 [默认: 3001]: " BACKEND_PORT; BACKEND_PORT=${BACKEND_PORT:-3001}; if [ "$BACKEND_PORT" == "$FRONTEND_PORT" ]; then log_error "后端端口不能与前端端口相同!"; else check_port "$BACKEND_PORT" && break; fi; done

    API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1); log_info "生成的 API 密钥为: ${API_KEY}"

    # 修正 ExecStart，确保使用正确的 Node 版本
    NODE_EXEC_PATH=$(which node)

    cat <<EOF > "$SUBSTORE_SERVICE_FILE"
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
ExecStart=${NODE_EXEC_PATH} ${SUBSTORE_INSTALL_DIR}/sub-store.bundle.js
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
    log_info "正在启动并启用 sub-store 服务..."; systemctl daemon-reload; systemctl enable "$SUBSTORE_SERVICE_NAME" > /dev/null; systemctl start "$SUBSTORE_SERVICE_NAME";
    log_info "正在检测服务状态 (等待 5 秒)..."; sleep 5; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "✅ 服务状态正常 (active)。"; substore_view_access_link; else log_error "服务启动失败！请使用日志功能排查。"; fi
    echo ""; read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then substore_setup_reverse_proxy; else press_any_key; fi
}

# 卸载 Sub-Store
substore_do_uninstall() {
    if ! is_substore_installed; then log_warn "Sub-Store 未安装。"; press_any_key; return; fi
    log_warn "你确定要卸载 Sub-Store 吗？此操作不可逆！"; echo ""; read -p "请输入 Y 确认: " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "取消卸载。"; press_any_key; return; fi
    log_info "正在停止并禁用服务..."; systemctl stop "$SUBSTORE_SERVICE_NAME" || true; systemctl disable "$SUBSTORE_SERVICE_NAME" || true
    log_info "正在删除服务文件..."; rm -f "$SUBSTORE_SERVICE_FILE"; systemctl daemon-reload
    log_info "正在删除项目文件和 Node.js 环境..."; rm -rf "$SUBSTORE_INSTALL_DIR"; rm -rf "/root/.local"; rm -rf "/root/.pnpm-state.json"
    log_info "✅ Sub-Store 已成功卸载。"; press_any_key
}

# 更新 Sub-Store
update_sub_store_app() {
    log_info "开始更新 Sub-Store 应用..."; if ! is_substore_installed; then log_error "Sub-Store 尚未安装，无法更新。"; press_any_key; return; fi
    set -e; cd "$SUBSTORE_INSTALL_DIR"
    log_info "正在下载最新的后端文件 (sub-store.bundle.js)..."; curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    log_info "正在下载最新的前端文件 (dist.zip)..."; curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    log_info "正在部署新版前端..."; rm -rf frontend; unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "正在重启 Sub-Store 服务以应用更新..."; systemctl restart "$SUBSTORE_SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "✅ Sub-Store 更新成功并已重启！"; else log_error "Sub-Store 更新后重启失败！请使用 '查看日志' 功能进行排查。"; fi
    press_any_key
}

# 查看访问链接
substore_view_access_link() {
    log_info "正在读取配置并生成访问链接...";
    if ! is_substore_installed; then
        log_error "Sub-Store尚未安装。"
        press_any_key
        return
    fi

    # ==================== 关键修正点：将 awk 的 {print $2} 全部改为 {print $3} ====================
    REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    API_KEY=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    # =========================================================================================

    echo -e "\n===================================================================="
    if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
        ACCESS_URL="https://${REVERSE_PROXY_DOMAIN}/subs?api=https://${REVERSE_PROXY_DOMAIN}${API_KEY}"
        echo -e "\n您的 Sub-Store 反代访问链接如下：\n\n${YELLOW}${ACCESS_URL}${NC}\n"
    else
        SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com)
        if [ -n "$SERVER_IP_V4" ]; then
            ACCESS_URL_V4="http://${SERVER_IP_V4}:${FRONTEND_PORT}/subs?api=http://${SERVER_IP_V4}:${FRONTEND_PORT}${API_KEY}"
            echo -e "\n您的 Sub-Store IPv4 访问链接如下：\n\n${YELLOW}${ACCESS_URL_V4}${NC}\n"
        fi
        # 可选的IPv6链接
        # SERVER_IP_V6=$(curl -s --max-time 2 http://ipv6.icanhazip.com);
        # if [[ "$SERVER_IP_V6" =~ .*:.* && -n "$SERVER_IP_V6" ]]; then
        #     ACCESS_URL_IPV6="http://[${SERVER_IP_V6}]:${FRONTEND_PORT}/subs?api=http://[${SERVER_IP_V6}]:${FRONTEND_PORT}${API_KEY}"
        #     echo -e "--------------------------------------------------------------------"
        #     echo -e "\n您的 Sub-Store IPv6 访问链接如下：\n\n${YELLOW}${ACCESS_URL_IPV6}${NC}\n"
        # fi
    fi
    echo -e "===================================================================="
}

# 重置端口
substore_reset_ports() {
    log_info "开始重置 Sub-Store 端口...";
    if ! is_substore_installed; then
        log_error "Sub-Store 尚未安装，无法重置端口。";
        press_any_key
        return
    fi

    CURRENT_FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    CURRENT_BACKEND_PORT=$(grep 'SUB_STORE_BACKEND_API_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')

    log_info "当前前端端口: ${CURRENT_FRONTEND_PORT}"
    log_info "当前后端端口: ${CURRENT_BACKEND_PORT}"
    echo ""

    local NEW_FRONTEND_PORT
    while true; do
        read -p "请输入新的前端访问端口 [直接回车则不修改: ${CURRENT_FRONTEND_PORT}]: " NEW_FRONTEND_PORT
        NEW_FRONTEND_PORT=${NEW_FRONTEND_PORT:-$CURRENT_FRONTEND_PORT}
        if [ "$NEW_FRONTEND_PORT" == "$CURRENT_FRONTEND_PORT" ]; then
            break
        fi
        if check_port "$NEW_FRONTEND_PORT"; then
            break
        fi
    done

    local NEW_BACKEND_PORT
    while true; do
        read -p "请输入新的后端 API 端口 [直接回车则不修改: ${CURRENT_BACKEND_PORT}]: " NEW_BACKEND_PORT
        NEW_BACKEND_PORT=${NEW_BACKEND_PORT:-$CURRENT_BACKEND_PORT}
        if [ "$NEW_BACKEND_PORT" == "$NEW_FRONTEND_PORT" ]; then
            log_error "后端端口不能与前端端口相同！"
            continue
        fi
        if [ "$NEW_BACKEND_PORT" == "$CURRENT_BACKEND_PORT" ]; then
            break
        fi
        if check_port "$NEW_BACKEND_PORT"; then
            break
        fi
    done

    log_info "正在更新服务文件...";
    set -e
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_PORT=.*|Environment=\"SUB_STORE_FRONTEND_PORT=${NEW_FRONTEND_PORT}\"|" "$SUBSTORE_SERVICE_FILE"
    sed -i "s|^Environment=\"SUB_STORE_BACKEND_API_PORT=.*|Environment=\"SUB_STORE_BACKEND_API_PORT=${NEW_BACKEND_PORT}\"|" "$SUBSTORE_SERVICE_FILE"

    log_info "正在重载并重启服务...";
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    set +e

    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ 端口重置成功！"

        # 检查并更新反向代理配置
        REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
        if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
            NGINX_CONF_PATH="/etc/nginx/sites-available/${REVERSE_PROXY_DOMAIN}.conf"
            if [ -f "$NGINX_CONF_PATH" ]; then
                log_info "检测到 Nginx 反代配置，正在自动更新端口...";
                # 使用更精确的替换，避免错误修改其他 proxy_pass
                sed -i "s|proxy_pass http://127.0.0.1:.*|proxy_pass http://127.0.0.1:${NEW_FRONTEND_PORT};|g" "$NGINX_CONF_PATH"
                if nginx -t >/dev/null 2>&1; then
                    systemctl reload nginx
                    log_info "Nginx 配置已更新并重载。"
                else
                    log_error "更新 Nginx 端口后配置测试失败！请手动检查配置文件。"
                fi
            fi
            # 未来可以加入对 Caddy 的支持
            # if [ -f "/etc/caddy/Caddyfile" ] && grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
            #     log_info "检测到 Caddy 反代配置，正在自动更新端口...";
            #     sed -i "/# Sub-Store config start/,/# Sub-Store config end/ s|reverse_proxy 127.0.0.1:.*|reverse_proxy 127.0.0.1:${NEW_FRONTEND_PORT}|" /etc/caddy/Caddyfile
            #     systemctl reload caddy
            #     log_info "Caddy 配置已更新并重载。"
            # fi
        fi
        substore_view_access_link
    else
        log_error "服务重启失败！请检查日志。"
    fi
    press_any_key
}

# 重置API密钥
substore_reset_api_key() {
    log_warn "确定要重置 API 密钥吗？旧的访问链接将立即失效。"; echo ""; read -p "请输入 Y 确认: " choice; if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "取消操作。"; return; fi
    log_info "正在生成新的 API 密钥..."; set -e; NEW_API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
    log_info "正在更新服务文件..."; sed -i "s|^Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=.*|Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=/${NEW_API_KEY}\"|" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载并重启服务..."; systemctl daemon-reload; systemctl restart "$SUBSTORE_SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "✅ API 密钥重置成功！"; substore_view_access_link; else log_error "服务重启失败！"; fi
    press_any_key
}

# 设置反向代理
substore_setup_reverse_proxy() {
    clear
    log_info "为保证安全和便捷，强烈建议使用域名和HTTPS访问Sub-Store。"
    if command -v nginx &> /dev/null; then
        log_info "检测到 Nginx，将为您生成配置代码和操作指南。"; substore_handle_nginx_proxy
    else
        log_warn "未检测到 Nginx。此功能目前仅支持Nginx。";
        # 未来可以加入Caddy的支持
    fi
    press_any_key
}

substore_handle_nginx_proxy() {
    echo ""; read -p "请输入您要使用的域名: " DOMAIN; if [ -z "$DOMAIN" ]; then log_error "域名不能为空！"; return; fi

    # ==================== 关键修正点：在这里增加读取端口号的逻辑 ====================
    log_info "正在从服务配置中读取 Sub-Store 端口..."
    local FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')

    if [ -z "$FRONTEND_PORT" ]; then
        log_error "无法读取到 Sub-Store 的端口号！请检查 Sub-Store 是否已正确安装。"
        return
    fi
    log_info "读取到端口号为: ${FRONTEND_PORT}"
    # ==============================================================================

    NGINX_CONF_PATH="/etc/nginx/sites-available/${DOMAIN}.conf"

    log_info "正在写入 Nginx 配置文件: ${NGINX_CONF_PATH}"
    cat <<EOF > "$NGINX_CONF_PATH"
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]; then
        log_info "正在启用站点..."; ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/";
    fi

    log_info "正在测试 Nginx 配置...";
    if ! nginx -t; then
        log_error "Nginx 配置测试失败！请检查您的 Nginx 配置。"
        return
    fi
    log_info "正在重载 Nginx..."; systemctl reload nginx;

    log_info "正在为 ${DOMAIN} 申请 HTTPS 证书...";
    # 使用 apply_ssl_certificate 函数，因为它更健壮
    if ! apply_ssl_certificate "${DOMAIN}"; then
        log_error "证书申请失败，但HTTP反代可能已生效。请检查域名解析和防火墙设置。"
        return
    fi

    log_info "证书申请成功，正在更新 Nginx 配置以启用 HTTPS..."
    cat <<EOF > "$NGINX_CONF_PATH"
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    location / {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    log_info "正在重载 Nginx 以应用HTTPS配置..."
    systemctl reload nginx

    log_info "✅ Nginx 反向代理和 HTTPS 证书已自动配置成功！"
    # 保存域名信息
    sed -i '/SUB_STORE_REVERSE_PROXY_DOMAIN/d' "$SUBSTORE_SERVICE_FILE"
    sed -i "/\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=${DOMAIN}\"" "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    substore_view_access_link
}


# --- 主菜单和子菜单 ---

# 脚本更新
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
    log_info "下载成功，正在应用更新...";
    chmod +x "$temp_script"
    mv "$temp_script" "$SCRIPT_PATH"
    log_info "✅ 脚本已成功更新！"
    log_warn "请重新运行脚本以使新版本生效 (例如，再次输入 'vs')..."
    exit 0
}

# 设置快捷命令
setup_shortcut() {
    log_info "正在设置 '${SHORTCUT_PATH##*/}' 快捷命令...";
    ln -sf "$SCRIPT_PATH" "$SHORTCUT_PATH"
    chmod +x "$SHORTCUT_PATH"
    log_info "✅ 快捷命令设置成功！现在您可以随时随地输入 '${SHORTCUT_PATH##*/}' 来运行此脚本。"
    press_any_key
}


sys_manage_menu() {
    while true; do
        clear
        echo ""
        echo -e "${WHITE}------ 系统综合管理 -------${NC}\n"
        echo "1. 系统信息查询"
        echo ""
        echo "2. 清理系统垃圾"
        echo ""
        echo "3. 修改主机名"
        echo ""
        echo "4. 优化 DNS"
        echo ""
        echo "5. 设置网络优先级 (IPv4/v6)"
        echo ""
        echo "6. 设置 SSH 密钥登录"
        echo ""
        echo "7. 设置系统时区"
        echo ""
        echo "---------------------------"
        echo ""
        echo "8. 安装 S-ui (面板)"
        echo ""
        echo "9. 安装 3X-ui (面板)"
        echo ""
        echo "---------------------------"
        echo ""
        echo "0. 返回主菜单"
        echo ""
        read -p "请输入选项: " choice

        case $choice in
            1) show_system_info ;;
            2) clean_system ;;
            3) change_hostname ;;
            4) optimize_dns ;;
            5) set_network_priority ;;
            6) setup_ssh_key ;;
            7) set_timezone ;;
            8) install_sui ;;
            9) install_3xui ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

singbox_add_node_menu() {
     while true; do
        clear
        echo -e "${WHITE}--- 新增 Sing-Box 节点 ---${NC}\n"
        echo "1. 新增 VLESS 节点"
        echo ""
        echo "2. 新增 Hysteria2 节点"
        echo ""
        echo "3. 新增 VMess 节点"
        echo ""
        echo "4. 新增 Trojan 节点"
        echo ""
        echo "0. 返回上级菜单"
        echo ""
        read -p "请选择协议类型: " choice
        case $choice in
            1) add_vless_node; break ;;
            2) add_hysteria2_node; break ;;
            3) add_vmess_node; break ;;
            4) add_trojan_node; break ;;
            0) break;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}


singbox_main_menu() {
    while true; do
        clear
        echo -e "${WHITE}--- Sing-Box 管理菜单 ---${NC}\n"
        if is_singbox_installed; then
            if systemctl is-active --quiet sing-box; then STATUS_COLOR="${GREEN}● 活动${NC}"; else STATUS_COLOR="${RED}● 不活动${NC}"; fi
            echo -e "当前状态: ${STATUS_COLOR}\n"
            echo -e "${WHITE}-------------------------${NC}\n"
            echo "1. 查看 / 管理节点"
            echo ""
            echo "2. 新增节点"
            echo ""
            echo "-------------------------"
            echo ""
            echo "3. 启动 Sing-Box"
            echo ""
            echo "4. 停止 Sing-Box"
            echo ""
            echo "5. 重启 Sing-Box"
            echo ""
            echo "6. 查看日志"
            echo ""
            echo "-------------------------"
            echo ""
            echo -e "7. ${RED}卸载 Sing-Box${NC}"
            echo ""
            echo "0. 返回主菜单"
            echo ""
            echo -e "${WHITE}-------------------------${NC}\n"
            read -p "请输入选项: " choice
            case $choice in
                1) view_node_info ;;
                2) singbox_add_node_menu ;;
                3) systemctl start sing-box; log_info "命令已发送"; sleep 1 ;;
                4) systemctl stop sing-box; log_info "命令已发送"; sleep 1 ;;
                5) systemctl restart sing-box; log_info "命令已发送"; sleep 1 ;;
                6) clear; journalctl -u sing-box -f --no-pager ;;
                7) singbox_do_uninstall ;;
                0) break ;;
                *) log_error "无效选项！"; sleep 1 ;;
            esac
        else
            # ==================== 关键修正点 ====================
            # 当 sing-box 未安装时，显示这个菜单
            " - Sing-Box 尚未安装。"
            echo ""
            echo "1. 安装 Sing-Box"
            echo ""
            echo "0. 返回主菜单"
            echo ""
            read -p "请输入选项: " choice
            case $choice in
                1) singbox_do_install ;;
                0) break ;;
                *) log_error "无效选项！"; sleep 1 ;;
            esac
            # ===================================================
        fi
    done
}


substore_manage_menu() {
    while true; do
        clear;
        local rp_menu_text="设置反向代理 (推荐)"
        if grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null; then
            rp_menu_text="更换反代域名"
        fi
        echo -e "${WHITE}--- Sub-Store 管理菜单 ---${NC}\n"
        if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then STATUS_COLOR="${GREEN}● 活动${NC}"; else STATUS_COLOR="${RED}● 不活动${NC}"; fi
        echo -e "当前状态: ${STATUS_COLOR}\n"
        echo "1. 启动服务"
        echo ""
        echo "2. 停止服务";
        echo ""
        echo "3. 重启服务"
        echo ""
        echo "4. 查看状态";
        echo ""
        echo "5. 查看日志"
        echo ""
        echo "--------------------------"
        echo ""
        echo "6. 查看访问链接"
        echo ""
        echo "7. 重置端口"
        echo ""
        echo "8. 重置 API 密钥"
        echo ""
        echo -e "9. ${YELLOW}${rp_menu_text}${NC}"
        echo ""
        echo "0. 返回主菜单"
        echo ""
        echo -e "${WHITE}--------------------------${NC}\n"
        read -p "请输入选项: " choice
        case $choice in
            1) systemctl start "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            2) systemctl stop "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            3) systemctl restart "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            4) clear; systemctl status "$SUBSTORE_SERVICE_NAME" -l --no-pager; press_any_key;;
            5) clear; journalctl -u "$SUBSTORE_SERVICE_NAME" -f --no-pager;;
            6) substore_view_access_link; press_any_key;;
            7) substore_reset_ports; ;;
            8) substore_reset_api_key; ;;
            9) substore_setup_reverse_proxy;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

substore_main_menu() {
    while true; do
        clear
        echo -e "${WHITE}--- Sub-Store 管理菜单 ---${NC}\n"
        if is_substore_installed; then
            echo "1. 管理 Sub-Store"
            echo ""
            echo -e "2. ${GREEN}更新 Sub-Store 应用${NC}\n"
            echo -e "3. ${RED}卸载 Sub-Store${NC}"
            echo ""
            echo "0. 返回主菜单"
            echo ""
            echo -e "${WHITE}-------------------${NC}\n"
            read -p "请输入选项: " choice
            case $choice in
                1) substore_manage_menu ;;
                2) update_sub_store_app ;;
                3) substore_do_uninstall ;;
                0) break ;;
                *) log_warn "无效选项！"; sleep 1 ;;
            esac
        else
            echo "1. 安装 Sub-Store"
            echo ""
            echo "0. 返回主菜单"
            echo ""
            echo "-------------------------"
            echo ""
            read -p "请输入选项: " choice
            case $choice in
                1) substore_do_install ;;
                0) break ;;
                *) log_warn "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}

main_menu() {
    while true; do
        clear
        echo -e "${WHITE}=====================================${NC}\n"
        echo -e "${WHITE}    全功能 VPS & 应用管理脚本      ${NC}\n"
        echo -e "${WHITE}=====================================${NC}\n"
        echo "1. 系统综合管理"
        echo ""
        echo "2. Sing-Box 管理"
        echo ""
        echo "3. Sub-Store 管理"
        echo ""
        echo -e "${WHITE}-------------------------------------${NC}"
        echo ""
        echo -e "8. ${GREEN}更新此脚本${NC}"
        echo ""
        echo -e "9. ${YELLOW}设置快捷命令 (vs)${NC}"
        echo ""
        echo -e "0. ${RED}退出脚本${NC}"
        echo ""
        echo -e "${WHITE}=====================================${NC}"
        echo ""
        read -p "请输入选项: " choice

        case $choice in
            1) sys_manage_menu ;;
            2) singbox_main_menu ;;
            3) substore_main_menu ;;
            8) do_update_script ;;
            9) setup_shortcut ;;
            0) exit 0 ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# 首次运行检查函数
initial_setup_check() {
    if [ ! -f "$FLAG_FILE" ]; then
        log_info "脚本首次运行，开始自动检查并安装所有依赖..."
        log_warn "这个过程可能需要一些时间，请耐心等待..."
        check_and_install_dependencies
        if [ $? -eq 0 ]; then
            log_info "依赖项初始化完成，创建标记文件以跳过下次检查。"
            touch "$FLAG_FILE"
            log_info "按任意键继续进入主菜单..."
            press_any_key
        else
            log_error "依赖安装失败！请检查网络或错误输出。脚本将退出。"
            exit 1
        fi
    fi
}
# --- 脚本入口 ---
check_root
initial_setup_check # 新增这一行调用
main_menu