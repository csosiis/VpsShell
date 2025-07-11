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
SHORTCUT_PATH="/usr/local/bin/sv"
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
is_singbox_installed() {
    if command -v sing-box &>/dev/null; then return 0; else return 1; fi
}
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
singbox_do_install() {
    ensure_dependencies "curl"
    if is_singbox_installed; then
        echo ""
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
    config_dir="/etc/sing-box"
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
    echo ""
    log_info "正在启用并重启 Sing-Box 服务..."
    echo ""
    systemctl enable sing-box.service
    systemctl restart sing-box
    echo ""
    log_info "✅ Sing-Box 配置文件初始化完成并已启动！"
    echo ""
    press_any_key
}
_handle_caddy_cert() {
    log_info "检测到 Caddy 已安装。"
    log_error "脚本的自动证书功能与 Caddy 冲突。"
    log_error "请先卸载 Caddy，或手动配置 Caddyfile 并创建无TLS的 Sing-Box 节点。"
    log_error "操作已中止，以防止生成错误的配置。"
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
    root /var/www/html; # 指向一个存在的目录
    index index.html index.htm;
}
EOF
        if [ ! -L "/etc/nginx/sites-enabled/$domain_name.conf" ]; then
            ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"
        fi
        log_info "正在重载 Nginx 以应用临时配置..."
        if ! nginx -t; then
            log_error "Nginx 临时配置测试失败！请检查 Nginx 状态。"
            rm -f "$NGINX_CONF_PATH"
            rm -f "/etc/nginx/sites-enabled/$domain_name.conf"
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
_handle_apache_cert() {
    local domain_name="$1"
    log_info "检测到 Apache，将使用 '--apache' 插件模式。"
    log_error "Apache 模式暂未完全实现，请先安装 Nginx 或使用独立模式。"
    return 1
}
_handle_standalone_cert() {
    local domain_name="$1"
    log_info "未检测到支持的 Web 服务器，回退到 '--standalone' 独立模式。"
    log_warn "此模式需要临时占用 80 端口，可能会暂停其他服务。"
    if systemctl is-active --quiet nginx; then
        log_info "临时停止 Nginx..."
        systemctl stop nginx
        local stopped_service="nginx"
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
    elif command -v apache2 &>/dev/null; then
        ensure_dependencies "python3-certbot-apache"
        _handle_apache_cert "$domain_name"
    else
        log_info "未检测到 Caddy 或 Apache，将默认使用 Nginx 模式。"
        ensure_dependencies "nginx" "python3-certbot-nginx"
        _handle_nginx_cert "$domain_name"
    fi
    return $?
}
get_domain_and_common_config() {
    ensure_dependencies "jq" "uuid-runtime"
    local type_flag=$1
    echo
    while true; do
        echo ""
        read -p "请输入您已解析到本机的域名 (用于TLS): " domain_name
        if [[ -z "$domain_name" ]]; then
            log_error "\n域名不能为空"
            continue
        fi
        if ! echo "$domain_name" | grep -Pq "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; then
            log_error "\n无效的域名格式"
            continue
        fi
        break
    done
    if [[ $type_flag -eq 2 ]]; then
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
            echo ""
            port=$(generate_random_port)
            log_info "已生成随机端口: $port"
            break
        fi
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            echo ""
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
            return 1
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
    tag="$location-$custom_id-$protocol_name"
    return 0
}
add_protocol_node() {
    local protocol=$1
    local config=$2
    local node_link=""
    log_info "正在将新的入站配置添加到 config.json..."
    if ! jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" >"$SINGBOX_CONFIG_FILE.tmp"; then
        log_error "更新配置文件失败！请检查JSON格式和文件权限。"
        rm -f "$SINGBOX_CONFIG_FILE.tmp"
        return 1
    fi
    mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
    case $protocol in
    VLESS)
        node_link="vless://$uuid@$domain_name:$port?type=ws&security=tls&sni=$domain_name&host=$domain_name&path=%2F#$tag"
        ;;
    Hysteria2)
        node_link="hysteria2://$password@$domain_name:$port?upmbps=100&downmbps=1000&sni=$domain_name&obfs=salamander&obfs-password=$obfs_password#$tag"
        ;;
    VMess)
        vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$domain_name\",\"port\":\"$port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain_name\",\"path\":\"/\",\"tls\":\"tls\"}"
        base64_vmess_link=$(echo -n "$vmess_json" | base64 -w 0)
        node_link="vmess://$base64_vmess_link"
        ;;
    Trojan)
        node_link="trojan://$password@$domain_name:$port?security=tls&sni=$domain_name&type=ws&host=$domain_name&path=/#$tag"
        ;;
    *)
        log_error "未知的协议类型！"
        return 1
        ;;
    esac
    echo "$node_link" >>"$SINGBOX_NODE_LINKS_FILE"
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
    log_info "✅ 节点添加成功！正在显示所有节点信息..."
    sleep 1
    view_node_info
}
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
        echo ""
        log_info "已选择推送所有节点。"
        for line in "${node_lines[@]}"; do
            selected_links+=("$line")
        done
        ;;
    2)
        echo ""
        log_info "请选择要推送的节点 (可多选，用空格分隔):"
        echo ""
        for i in "${!node_lines[@]}"; do
            line="${node_lines[$i]}"
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
    0)
        return 1
        ;;
    *)
        log_error "无效选项！"
        return 1
        ;;
    esac
    if [ ${#selected_links[@]} -eq 0 ]; then
        log_warn "未选择任何有效节点。"
        return 1
    fi
    return 0
}
push_to_sub_store() {
    ensure_dependencies "curl" "jq"
    if ! select_nodes_for_push; then
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
push_to_telegram() {
    if ! select_nodes_for_push; then
        press_any_key
        return
    fi
    local tg_config_file="/etc/sing-box/telegram-bot-config.txt"
    local tg_api_token
    local tg_chat_id
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
    *)
        log_error "无效选项！"
        press_any_key
        ;;
    esac
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
    local sub_filename=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 16)
    local sub_filepath="$sub_dir/$sub_filename"
    mapfile -t node_lines <"$SINGBOX_NODE_LINKS_FILE"
    local all_links_str
    all_links_str=$(printf "%s\n" "${node_lines[@]}")
    local base64_content
    base64_content=$(echo -n "$all_links_str" | base64 -w0)
    echo "$base64_content" >"$sub_filepath"
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
            line="${node_lines[$i]}"
            tag=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            node_tags_map[$i]=$tag
        done
        echo ""
        log_info "请选择要删除的节点 (可多选，用空格分隔, 输入 'all' 删除所有):"
        echo ""
        for i in "${!node_lines[@]}"; do
            line="${node_lines[$i]}"
            node_name=${node_tags_map[$i]}
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC"
            echo ""
        done
        read -p "请输入编号 (输入 0 返回上一级菜单): " -a nodes_to_delete
        is_cancel=false
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
                jq '.inbounds = []' "$SINGBOX_CONFIG_FILE" >"$SINGBOX_CONFIG_FILE.tmp" && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
                rm -f "$SINGBOX_NODE_LINKS_FILE"
                log_info "✅ 所有节点已删除。"
            else
                log_info "操作已取消。"
            fi
            systemctl restart sing-box
            break
        else
            indices_to_delete=()
            tags_to_delete=()
            has_invalid_input=false
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
            cp "$SINGBOX_CONFIG_FILE" "$SINGBOX_CONFIG_FILE.tmp"
            for tag in "${tags_to_delete[@]}"; do
                jq --arg t "$tag" 'del(.inbounds[] | select(.tag == $t))' "$SINGBOX_CONFIG_FILE.tmp" >"$SINGBOX_CONFIG_FILE.tmp.2" && mv "$SINGBOX_CONFIG_FILE.tmp.2" "$SINGBOX_CONFIG_FILE.tmp"
            done
            mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
            remaining_lines=()
            for i in "${!node_lines[@]}"; do
                should_keep=true
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
    log_info "正在删除 Sing-Box 服务文件..."
    rm -f /etc/systemd/system/sing-box.service
    rm /etc/sing-box/config.json
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
is_substore_installed() {
    if [ -f "$SUBSTORE_SERVICE_FILE" ]; then return 0; else return 1; fi
}
# 安装 Sub-Store
substore_do_install() {
    ensure_dependencies "curl" "unzip" "git"

    echo ""
    log_info "开始执行 Sub-Store 安装流程..."
    set -e

    # ==================== 核心修正：使用 FNM 官方安装脚本 ====================
    log_info "正在安装 FNM (Node.js 版本管理器)..."
    # 使用官方推荐的安装方式，它能自动处理架构和下载，比手动下载更稳定
    # 通过 --install-dir 直接指定路径，避免权限问题
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /root/.fnm --skip-shell

    # 将 fnm 的路径加入到当前脚本会话的 PATH 中，这是最关键的一步
    export PATH="/root/.fnm:$PATH"
    # 立即评估 fnm 的环境变量，使其在当前会话中生效
    eval "$(fnm env)"
    log_info "FNM 安装完成。"
    # =========================================================================

    log_info "正在使用 FNM 安装 Node.js (lts/iron)..."
    # 使用 lts/iron 来确保安装一个稳定的长期支持版本
    fnm install lts/iron
    fnm use lts/iron

    log_info "正在安装 pnpm..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    log_info "Node.js 和 PNPM 环境准备就绪。"

    # (后续的 Sub-Store 下载和配置代码保持不变)
    log_info "正在下载并设置 Sub-Store 项目文件..."
    mkdir -p "$SUBSTORE_INSTALL_DIR"
    cd "$SUBSTORE_INSTALL_DIR"
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"
    log_info "开始配置系统服务..."
    echo ""
    local API_KEY
    local random_api_key
    random_api_key=$(generate_random_password)
    read -p "请输入 Sub-Store 的 API 密钥 [回车则随机生成]: " user_api_key
    API_KEY=${user_api_key:-$random_api_key}
    if [ -z "$API_KEY" ]; then API_KEY=$(generate_random_password); fi
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
        if [ "$BACKEND_PORT" == "$FRONTEND_PORT" ]; then log_error "后端端口不能与前端端口相同!"; else
            if check_port "$BACKEND_PORT"; then break; fi
        fi
    done

    # ExecStart 使用 fnm exec 可以确保 systemd 服务能找到正确的 node 版本
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
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then substore_setup_reverse_proxy; else press_any_key; fi
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
            log_error "错误：目录 \"$project_dir\" 下已存在一个 WordPress 站点！"
            log_warn "请为新的 WordPress 站点选择一个不同的、全新的目录。"
            echo ""
            continue
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
    echo ""
    echo ""
    local db_password
    local db_password_default="123456"
    read -s -p "请输入新的数据库 root 和用户密码 [默认: 123456]: " db_password
    echo ""
    db_password=${db_password:-$db_password_default}
    log_info "数据库密码已设置为: $db_password"
    echo ""
    local wp_port
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
    if [[ "$setup_proxy_choice" != "n" && "$setup_proxy_choice" != "N" ]]; then
        setup_auto_reverse_proxy "$domain" "$wp_port"
        echo ""
        log_info "WordPress 配置流程完毕！您现在应该可以通过 $site_url 访问您的网站了。"
    else
        log_info "好的，您选择不设置反向代理。"
        log_info "您可以通过以下 IP 地址完成 WordPress 的初始化安装："
        local ipv4_addr
        ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
        local ipv6_addr
        ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
        if [ -n "$ipv4_addr" ]; then log_info "IPv4 地址: http://$ipv4_addr:$wp_port"; fi
        if [ -n "$ipv6_addr" ]; then log_info "IPv6 地址: http://[$ipv6_addr]:$wp_port"; fi
        log_warn "请注意，直接使用 IP 访问可能会导致网站样式或功能异常。"
    fi
    press_any_key
}
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
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        log_info "取消卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用服务..."
    systemctl stop "$SUBSTORE_SERVICE_NAME" || true
    systemctl disable "$SUBSTORE_SERVICE_NAME" || true
    log_info "正在删除服务文件..."
    rm -f "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    log_info "正在删除项目文件和 Node.js 环境..."
    rm -rf "$SUBSTORE_INSTALL_DIR"
    rm -rf "/root/.local"
    rm -rf "/root/.pnpm-state.json"
    log_info "✅ Sub-Store 已成功卸载。"
    press_any_key
}
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
    cd "$SUBSTORE_INSTALL_DIR"
    log_info "正在下载最新的后端文件 (sub-store.bundle.js)..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    log_info "正在下载最新的前端文件 (dist.zip)..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    log_info "正在部署新版前端..."
    rm -rf frontend
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "正在重启 Sub-Store 服务以应用更新..."
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "✅ Sub-Store 更新成功并已重启！"; else log_error "Sub-Store 更新后重启失败！请使用 '查看日志' 功能进行排查。"; fi
    press_any_key
}
substore_view_access_link() {
    echo ""
    log_info "正在读取配置并生成访问链接..."
    if ! is_substore_installed; then
        echo ""
        log_error "Sub-Store尚未安装。"
        press_any_key
        return
    fi
    REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    API_KEY=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    echo -e "\n===================================================================="
    if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
        ACCESS_URL="https://$REVERSE_PROXY_DOMAIN/subs?api=https://$REVERSE_PROXY_DOMAIN$API_KEY"
        echo -e "\n您的 Sub-Store 反代访问链接如下：\n\n$YELLOW$ACCESS_URL$NC\n"
    else
        SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com)
        if [ -n "$SERVER_IP_V4" ]; then
            ACCESS_URL_V4="http://$SERVER_IP_V4:$FRONTEND_PORT/subs?api=http://$SERVER_IP_V4:$FRONTEND_PORT$API_KEY"
            echo -e "\n您的 Sub-Store IPv4 访问链接如下：\n\n$YELLOW$ACCESS_URL_V4$NC\n"
        fi
    fi
    echo -e "===================================================================="
}
substore_reset_ports() {
    log_info "开始重置 Sub-Store 端口..."
    if ! is_substore_installed; then
        log_error "Sub-Store 尚未安装，无法重置端口。"
        press_any_key
        return
    fi
    CURRENT_FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    CURRENT_BACKEND_PORT=$(grep 'SUB_STORE_BACKEND_API_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
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
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_PORT=.*|Environment=\"SUB_STORE_FRONTEND_PORT=$NEW_FRONTEND_PORT\"|" "$SUBSTORE_SERVICE_FILE"
    sed -i "s|^Environment=\"SUB_STORE_BACKEND_API_PORT=.*|Environment=\"SUB_STORE_BACKEND_API_PORT=$NEW_BACKEND_PORT\"|" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载并重启服务..."
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ 端口重置成功！"
        REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
        if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
            NGINX_CONF_PATH="/etc/nginx/sites-available/$REVERSE_PROXY_DOMAIN.conf"
            if [ -f "$NGINX_CONF_PATH" ]; then
                log_info "检测到 Nginx 反代配置，正在自动更新端口..."
                sed -i "s|proxy_pass http://127.0.0.1:.*|proxy_pass http://127.0.0.1:$NEW_FRONTEND_PORT;|g" "$NGINX_CONF_PATH"
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
substore_reset_api_key() {
    if ! is_substore_installed; then
        log_error "Sub-Store 尚未安装。"
        press_any_key
        return
    fi
    echo ""
    log_warn "确定要重置 API 密钥吗？旧的访问链接将立即失效。"
    echo ""
    read -p "请输入 Y 确认: " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        log_info "取消操作。"
        press_any_key
        return
    fi
    log_info "正在生成新的 API 密钥..."
    set -e
    NEW_API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
    log_info "正在更新服务文件..."
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=.*|Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=/$NEW_API_KEY\"|" "$SUBSTORE_SERVICE_FILE"
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
substore_setup_reverse_proxy() {
    ensure_dependencies "nginx"
    clear
    log_info "为保证安全和便捷，强烈建议使用域名和HTTPS访问Sub-Store。"
    if command -v nginx &>/dev/null; then
        log_info "检测到 Nginx，将为您生成配置代码和操作指南。"
        substore_handle_nginx_proxy
    else
        log_warn "未检测到 Nginx。此功能目前仅支持Nginx。"
    fi
    press_any_key
}
substore_handle_nginx_proxy() {
    echo ""
    read -p "请输入您要使用的新域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        log_error "域名不能为空！"
        return
    fi
    log_info "正在从服务配置中读取 Sub-Store 端口..."
    local FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    if [ -z "$FRONTEND_PORT" ]; then
        log_error "无法读取到 Sub-Store 的端口号！请检查 Sub-Store 是否已正确安装。"
        return
    fi
    log_info "读取到端口号为: $FRONTEND_PORT"
    local OLD_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null | awk -F'=' '{print $3}' | tr -d '"')
    if [ -n "$OLD_DOMAIN" ] && [ "$OLD_DOMAIN" != "$DOMAIN" ]; then
        log_warn "正在清理旧域名 $OLD_DOMAIN 的 Nginx 配置..."
        rm -f "/etc/nginx/sites-available/$OLD_DOMAIN.conf"
        rm -f "/etc/nginx/sites-enabled/$OLD_DOMAIN.conf"
    fi
    if ! apply_ssl_certificate "$DOMAIN"; then
        log_error "证书处理失败，操作已中止。"
        return
    fi
    log_info "正在为新域名 $DOMAIN 写入 Nginx 配置..."
    NGINX_CONF_PATH="/etc/nginx/sites-available/$DOMAIN.conf"
    cat <<EOF >"$NGINX_CONF_PATH"
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    location / {
        proxy_pass http://127.0.0.1:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    if [ ! -L "/etc/nginx/sites-enabled/$DOMAIN.conf" ]; then
        ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"
    fi
    log_info "正在重载 Nginx 以应用新域名配置..."
    if ! nginx -t; then
        log_error "Nginx 新配置测试失败！请检查。"
        return
    fi
    systemctl reload nginx
    log_info "✅ Nginx 反向代理已更新为新域名！"
    log_info "正在更新服务文件中的域名环境变量..."
    sed -i '/SUB_STORE_REVERSE_PROXY_DOMAIN/d' "$SUBSTORE_SERVICE_FILE"
    sed -i "/\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=$DOMAIN\"" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载 systemd 并重启 Sub-Store 服务以应用新环境..."
    systemctl daemon-reload
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 2
    substore_view_access_link
    press_any_key
}
substore_manage_menu() {
    while true; do
        clear
        local rp_menu_text="设置反向代理 (推荐)"
        if grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null; then
            rp_menu_text="更换反代域名"
        fi
        echo -e "$WHITE=============================$NC\n"
        echo -e "$WHITE      Sub-Store 管理菜单      $NC\n"
        echo -e "$WHITE=============================$NC\n"
        if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then STATUS_COLOR="$GREEN● 活动$NC"; else STATUS_COLOR="$RED● 不活动$NC"; fi
        echo -e "当前状态: $STATUS_COLOR\n"
        echo "-----------------------------"
        echo ""
        echo "1. 启动服务"
        echo ""
        echo "2. 停止服务"
        echo ""
        echo "3. 重启服务"
        echo ""
        echo "4. 查看状态"
        echo ""
        echo "5. 查看日志"
        echo ""
        echo "-----------------------------"
        echo ""
        echo "6. 查看访问链接"
        echo ""
        echo "7. 重置端口"
        echo ""
        echo "8. 重置 API 密钥"
        echo ""
        echo -e "9. $YELLOW$rp_menu_text$NC"
        echo ""
        echo "0. 返回主菜单"
        echo ""
        echo -e "$WHITE-----------------------------$NC\n"
        read -p "请输入选项: " choice
        case $choice in
        1)
            systemctl start "$SUBSTORE_SERVICE_NAME"
            log_info "命令已发送"
            sleep 1
            ;;
        2)
            systemctl stop "$SUBSTORE_SERVICE_NAME"
            log_info "命令已发送"
            sleep 1
            ;;
        3)
            systemctl restart "$SUBSTORE_SERVICE_NAME"
            log_info "命令已发送"
            sleep 1
            ;;
        4)
            clear
            systemctl status "$SUBSTORE_SERVICE_NAME" -l --no-pager
            press_any_key
            ;;
        5)
            clear
            journalctl -u "$SUBSTORE_SERVICE_NAME" -f --no-pager
            ;;
        6)
            substore_view_access_link
            press_any_key
            ;;
        7) substore_reset_ports ;;
        8) substore_reset_api_key ;;
        9) substore_setup_reverse_proxy ;;
        0) break ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}
substore_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sub-Store 管理                 $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
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
            3) substore_do_uninstall ;; 0) break ;; *)
                log_warn "无效选项！"
                sleep 1
                ;;
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
            1) substore_do_install ;; 0) break ;; *)
                log_warn "无效选项！"
                sleep 1
                ;;
            esac
        fi
    done
}
# ================= Nezha Management Start =================
is_nezha_agent_installed() {
    [ -f "/etc/systemd/system/nezha-agent.service" ]
}
uninstall_nezha_agent_v0() {
    if ! is_nezha_agent_v0_installed; then
        log_warn "Nezha V0 探针未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用 nezha-agent-v0 服务..."
    systemctl stop nezha-agent-v0.service &>/dev/null
    systemctl disable nezha-agent-v0.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent-v0.service
    rm -rf /opt/nezha/agent-v0
    systemctl daemon-reload
    log_info "✅ Nezha V0 探针已成功卸载。"
    press_any_key
}
uninstall_nezha_agent_v3() {
    if ! is_nezha_agent_v0_installed; then
        log_warn "Nezha V0 探针未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用 nezha-agent-v0 服务..."
    systemctl stop nezha-agent-v3.service &>/dev/null
    systemctl disable nezha-agent-v3.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent-v0.service
    rm -rf /opt/nezha/agent-v0
    systemctl daemon-reload
    log_info "✅ Nezha V0 探针已成功卸载。"
    press_any_key
}
uninstall_nezha_agent_v1() {
    if ! is_nezha_agent_v1_installed; then
        log_warn "Nezha V1 探针未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用 nezha-agent-v1 服务..."
    systemctl stop nezha-agent-v1.service &>/dev/null
    systemctl disable nezha-agent-v1.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent-v1.service
    rm -rf /opt/nezha/agent-v1
    systemctl daemon-reload
    log_info "✅ Nezha V1 探针已成功卸载。"
    press_any_key
}

uninstall_nezha_agent() {
    # 这是一个辅助函数，确保清理标准版时不会报错
    if [ -f "/etc/systemd/system/nezha-agent.service" ]; then
        systemctl stop nezha-agent.service &>/dev/null
        systemctl disable nezha-agent.service &>/dev/null
        rm -f /etc/systemd/system/nezha-agent.service
        rm -rf /opt/nezha/agent
    fi
}

install_nezha_agent_v0() {
    # --- 从函数第一个参数获取密钥 ---
    local server_key="$1"

    # --- 固定的服务器信息 ---
    # 您可以在这里修改为您自己的服务器地址和端口
    local server_addr="nz.wiitwo.eu.org"
    local server_port="443"

    # --- 基础准备 ---
    log_info "为确保全新安装，将首先清理所有旧的探针安装..."
    uninstall_nezha_agent_v0 &>/dev/null
    uninstall_nezha_agent &>/dev/null # 清理标准版，以防万一
    systemctl daemon-reload

    ensure_dependencies "curl" "wget" "unzip"
    clear
    log_info "开始安装 Nezha V0 探针 (San Jose)..."
    log_info "服务器地址: $server_addr"
    log_info "服务器端口: $server_port"

    # --- 获取密钥 ---
    # 如果没有通过参数传入密钥，则提示用户输入
    if [ -z "$server_key" ]; then
        read -p "请输入面板密钥: " server_key
    fi

    # 最终检查密钥是否为空
    if [ -z "$server_key" ]; then
        log_error "面板密钥不能为空！操作中止。"; press_any_key; return
    fi

    # --- 安装过程 ---
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
    # 执行脚本，传入固定的服务器信息和获取到的密钥
    bash "$SCRIPT_PATH_TMP" install_agent "$server_addr" "$server_port" "$server_key" $tls_option
    rm "$SCRIPT_PATH_TMP"

    # 检查标准版是否安装成功
    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
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
install_nezha_agent_v0() {
    # --- 从函数第一个参数获取密钥 ---
    local server_key="$1"

    # --- 固定的服务器信息 ---
    # 您可以在这里修改为您自己的服务器地址和端口
    local server_addr="nz.csosm.ip-ddns.com"
    local server_port="443"

    # --- 基础准备 ---
    log_info "为确保全新安装，将首先清理所有旧的探针安装..."
    uninstall_nezha_agent_v3 &>/dev/null
    uninstall_nezha_agent &>/dev/null # 清理标准版，以防万一
    systemctl daemon-reload

    ensure_dependencies "curl" "wget" "unzip"
    clear
    log_info "开始安装 Nezha V0 探针 (Phoenix)..."
    log_info "服务器地址: $server_addr"
    log_info "服务器端口: $server_port"

    # --- 获取密钥 ---
    # 如果没有通过参数传入密钥，则提示用户输入
    if [ -z "$server_key" ]; then
        read -p "请输入面板密钥: " server_key
    fi

    # 最终检查密钥是否为空
    if [ -z "$server_key" ]; then
        log_error "面板密钥不能为空！操作中止。"; press_any_key; return
    fi

    # --- 安装过程 ---
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
    # 执行脚本，传入固定的服务器信息和获取到的密钥
    bash "$SCRIPT_PATH_TMP" install_agent "$server_addr" "$server_port" "$server_key" $tls_option
    rm "$SCRIPT_PATH_TMP"

    # 检查标准版是否安装成功
    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
        log_error "官方脚本未能成功创建标准服务，操作中止。"
        press_any_key
        return
    fi
    log_info "标准服务安装成功，即将开始改造..."
    sleep 1

    log_info "第2步：停止标准服务并重命名文件以实现隔离..."
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null

    mv /etc/systemd/system/nezha-agent.service /etc/systemd/system/nezha-agent-v3.service
    mv /opt/nezha/agent /opt/nezha/agent-v3

    log_info "第3步：修改新的服务文件，使其指向正确的路径..."
    sed -i 's|/opt/nezha/agent/nezha-agent|/opt/nezha/agent-v3/nezha-agent|g' /etc/systemd/system/nezha-agent-v3.service

    log_info "第4步：重载并启动改造后的 'nezha-agent-v3' 服务..."
    systemctl daemon-reload
    systemctl enable nezha-agent-v3.service
    systemctl start nezha-agent-v3.service

    log_info "检查最终服务状态..."
    sleep 2
    if systemctl is-active --quiet nezha-agent-v3; then
        log_info "✅ Nezha V0 探针 (隔离版) 已成功安装并启动！"
    else
        log_error "Nezha V0 探针 (隔离版) 最终启动失败！"
        log_warn "显示详细状态以供诊断:"
        systemctl status nezha-agent-v3.service --no-pager -l
    fi
    press_any_key
}

uninstall_nezha_agent_v1() {
    if ! is_nezha_agent_v1_installed; then
        log_warn "Nezha V1 探针未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在停止并禁用 nezha-agent-v1 服务..."
    systemctl stop nezha-agent-v1.service &>/dev/null
    systemctl disable nezha-agent-v1.service &>/dev/null
    rm -f /etc/systemd/system/nezha-agent-v1.service
    rm -rf /opt/nezha/agent-v1
    systemctl daemon-reload
    log_info "✅ Nezha V1 探针已成功卸载。"
    press_any_key
}

install_nezha_agent_v0() {
    log_info "为确保全新安装，将首先清理所有旧的探针安装..."
    uninstall_nezha_agent_v0 &>/dev/null
    uninstall_nezha_agent &>/dev/null # 清理标准版，以防万一
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

    # 检查标准版是否安装成功
    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
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
# 全自动安装函数：
# - 新增交互式指令验证
# - 用户输入正确的指令 "csos" 后，才会继续全自动安装
install_nezha_agent_v1() {
    # --- 新增：交互式指令输入 ---
    local user_command
    read -p "请输入安装指令以继续: " user_command

    # 检查输入的指令是否为 "csos"
    if [ "$user_command" != "csos" ]; then
        log_error "指令错误，安装已中止。"
        press_any_key
        return 1
    fi

    # --- 全自动安装配置 ---
    # (指令正确后，后续流程与之前完全相同)
    # 所有参数已在此处硬编码，无需手动输入。
    # 如果需要修改，请直接编辑下面的值。
    local server_info="nz.ssong.eu.org:8008"
    local server_secret="wdptRINwlgBB3kE0U8eDGYjqV56nAhLh"
    local NZ_TLS="false" # 是否为gRPC连接启用TLS? ("true" 或 "false")

    # --- 基础准备 ---
    log_info "为确保全新安装，将首先清理所有旧的探针安装..."
    uninstall_nezha_agent_v1 &>/dev/null
    uninstall_nezha_agent &>/dev/null # 清理标准版，以防万一
    systemctl daemon-reload

    ensure_dependencies "curl" "wget" "unzip"
    clear
    log_info "指令正确，开始全自动安装 Nezha V1 探针 (安装后改造模式)..."
    log_info "服务器信息: $server_info"
    log_info "连接密钥: $server_secret"
    log_info "启用TLS: $NZ_TLS"

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

    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
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
is_nezha_agent_v0_installed() {
    [ -f "/etc/systemd/system/nezha-agent-v0.service" ]
}
is_nezha_agent_v3_installed() {
    [ -f "/etc/systemd/system/nezha-agent-v3.service" ]
}
is_nezha_agent_v1_installed() {
    [ -f "/etc/systemd/system/nezha-agent-v1.service" ]
}
nezha_agent_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE               哪吒探针 (Agent) 管理              $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        if is_nezha_agent_v0_installed; then
            echo -e "$CYAN║$NC   1. 安装/重装 San Jose V0 探针 ${GREEN}(已安装)$NC         $CYAN║$NC"
        else
            echo -e "$CYAN║$NC   1. 安装/重装 San Jose V0 探针 ${YELLOW}(未安装)$NC         $CYAN║$NC"
        fi
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. $RED卸载 San Jose V0 探针$NC                       $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        if is_nezha_agent_v1_installed; then
            echo -e "$CYAN║$NC   3. 安装/重装 Singpore V1 探针 ${GREEN}(已安装)$NC         $CYAN║$NC"
        else
            echo -e "$CYAN║$NC   3. 安装/重装 Singpore V1 探针 ${YELLOW}(未安装)$N          $CYAN║$NC"
        fi
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. $RED卸载 Singpore V1 探针$NC                      $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        if is_nezha_agent_v3_installed; then
            echo -e "$CYAN║$NC   5. 安装/重装 Phoenix V0 探针 ${GREEN}(已安装)$NC           $CYAN║$NC"
        else
            echo -e "$CYAN║$NC   5. 安装/重装 Phoenix V0 探针 ${YELLOW}(未安装)$NC          $CYAN║$NC"
        fi
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. $RED卸载 Phoenix V0 探针$NC                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
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
        5) install_nezha_agent_v0 ;;
        6) uninstall_nezha_agent_v3 ;;
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
        log_info "证书路径: $cert_path"
        log_info "密钥路径: $key_path"
        return 0
    else
        log_error "自签名证书创建失败！"
        return 1
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
    echo -e "\n# Auto-generated by vps-toolkit for $domain" >>"$caddyfile"
    echo "$domain {" >>"$caddyfile"
    echo "    reverse_proxy 127.0.0.1:$port" >>"$caddyfile"
    echo "}" >>"$caddyfile"
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
    log_info "欢迎使用通用反向代理设置向导。"
    echo ""
    if [ -z "$domain_input" ]; then
        while true; do
            read -p "请输入您要设置反代的域名: " domain_input
            if [[ -z "$domain_input" ]]; then
                log_error "域名不能为空！"
            elif ! _is_domain_valid "$domain_input"; then
                log_error "域名格式不正确。"
            else break; fi
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
            press_any_key
            return
        fi
        _configure_nginx_proxy "$domain_input" "$local_port"
    elif command -v apache2 &>/dev/null; then
        log_error "Apache 自动配置暂未实现。"
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
        echo -e "$CYAN║$NC   4. $GREEN哪吒监控管理$NC                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE面板安装$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 安装 S-ui 面板                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 安装 3X-ui 面板                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. $GREEN搭建 WordPress (Docker)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. $GREEN自动配置网站反向代理$NC                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. $GREEN更新此脚本$NC                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  10. $YELLOW设置快捷命令 (默认: sv)$NC                     $CYAN║$NC"
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
        4) nezha_manage_menu ;;
        5) install_sui ;;
        6) install_3xui ;;
        7) install_wordpress ;;
        8) setup_auto_reverse_proxy ;;
        9) do_update_script ;;
        10) setup_shortcut ;;
        0) exit 0 ;;
        *)
            log_error "无效选项！"
            sleep 1
            ;;
        esac
    done
}
post_add_node_menu() {
    while true; do
        echo ""
        echo -e "请选择接下来的操作：\n"
        echo -e "${GREEN}1. 继续新增节点$NC  ${YELLOW}2. 管理已有节点 (查看/删除/推送)$NC    ${RED}0. 返回上一级菜单$NC\n"
        read -p "请输入选项: " next_choice
        case $next_choice in
        1)
            singbox_add_node_orchestrator
            break
            ;;
        2)
            view_node_info
            break
            ;;
        0)
            break
            ;;
        *)
            log_error "无效选项，请重新输入。"
            sleep 1
            ;;
        esac
    done
}
singbox_add_node_orchestrator() {
    ensure_dependencies "jq" "uuid-runtime" "curl" "openssl"
    local cert_choice custom_id location connect_addr sni_domain final_node_link
    local cert_path key_path
    declare -A ports
    local protocols_to_create=()
    local protocols_with_self_signed=()
    local is_one_click=false

    clear
    echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
    echo -e "$CYAN║$WHITE              Sing-Box 节点协议选择               $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   1. VLESS + WSS                                 $CYAN║$NC"
     echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   2. VMess + WSS                                 $CYAN║$NC"
     echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   3. Trojan + WSS                                $CYAN║$NC"
     echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   4. Hysteria2 (UDP)                             $CYAN║$NC"
     echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   5. TUIC v5 (UDP)                               $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
     echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   6. $GREEN一键生成以上全部 5 种协议节点$NC               $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
    echo ""
    read -p "请输入选项: " protocol_choice

    case $protocol_choice in
    1) protocols_to_create=("VLESS") ;;
    2) protocols_to_create=("VMess") ;;
    3) protocols_to_create=("Trojan") ;;
    4) protocols_to_create=("Hysteria2") ;;
    5) protocols_to_create=("TUIC") ;;
    6)
        protocols_to_create=("VLESS" "VMess" "Trojan" "Hysteria2" "TUIC")
        is_one_click=true
        ;;
    0) return ;;
    *)
        log_error "无效选择，操作中止。"
        press_any_key
        return
        ;;
    esac
    clear
    echo -e "$GREEN您选择了 [${protocols_to_create[*]}] 协议。$NC"
    echo -e "\n请选择证书类型：\n\n${GREEN}1. 使用 Let's Encrypt 域名证书 (推荐)$NC\n\n2. 使用自签名证书 (IP 直连)\n"
    read -p "请输入选项 (1-2): " cert_choice

    local insecure_param=""
    local vmess_insecure_json_part=""
    local hy2_insecure_param=""
    local tuic_insecure_param=""

    if [ "$cert_choice" == "1" ]; then
        echo ""
        while true; do
            read -p "请输入您已解析到本机的域名: " domain
            if [[ -z "$domain" ]]; then
                echo ""
                log_error "域名不能为空！"
            elif ! _is_domain_valid "$domain"; then
                echo ""
                log_error "域名格式不正确。"
            else break; fi
        done
        if ! apply_ssl_certificate "$domain"; then
            echo ""
            log_error "证书处理失败。"
            press_any_key
            return
        fi
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_path="/etc/letsencrypt/live/$domain/privkey.pem"
        connect_addr="$domain"
        sni_domain="$domain"
    elif [ "$cert_choice" == "2" ]; then
        protocols_with_self_signed=("${protocols_to_create[@]}")
        insecure_param="&allowInsecure=1"
        vmess_insecure_json_part=", \"skip-cert-verify\": true"
        hy2_insecure_param="&insecure=1"
        tuic_insecure_param="&allow_insecure=1"

        ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
        ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
        if [ -n "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
            echo -e "\n请选择用于节点链接的地址：\n\n1. IPv4: $ipv4_addr\n\n2. IPv6: $ipv6_addr\n"
            read -p "请输入选项 (1-2): " ip_choice
            if [ "$ip_choice" == "2" ]; then connect_addr="[$ipv6_addr]"; else connect_addr="$ipv4_addr"; fi
        elif [ -n "$ipv4_addr" ]; then
            echo ""
            log_info "将自动使用 IPv4 地址。"
            connect_addr="$ipv4_addr"
        elif [ -n "$ipv6_addr" ]; then
            echo ""
            log_info "将自动使用 IPv6 地址。"
            connect_addr="[$ipv6_addr]"
        else
            echo ""
            log_error "无法获取任何公网 IP 地址！"
            press_any_key
            return
        fi
        echo ""
        read -p "请输入 SNI 伪装域名 [默认: www.bing.com]: " sni_input
        sni_domain=${sni_input:-"www.bing.com"}
        if ! _create_self_signed_cert "$sni_domain"; then
            echo ""
            log_error "自签名证书处理失败。"
            press_any_key
            return
        fi
        cert_path="/etc/sing-box/certs/$sni_domain.cert.pem"
        key_path="/etc/sing-box/certs/$sni_domain.key.pem"
    else
        log_error "无效证书选择。"
        press_any_key
        return
    fi
    local used_ports_for_this_run=()
    if $is_one_click; then
        echo ""
        log_info "您已选择一键模式，请为每个协议指定端口。"
        for p in "${protocols_to_create[@]}"; do
            while true; do
                echo ""
                local port_prompt="请输入 [$p] 的端口 [回车则随机]: "
                if [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]]; then port_prompt="请输入 [$p] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
                read -p "$(echo -e "$port_prompt")" port_input
                if [ -z "$port_input" ]; then
                    port_input=$(generate_random_port)
                    echo ""
                    log_info "已为 [$p] 生成随机端口: $port_input"
                fi
                if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then
                    echo ""
                    log_error "端口号需为 1-65535。"
                elif _is_port_available "$port_input" "used_ports_for_this_run"; then
                    ports[$p]=$port_input
                    used_ports_for_this_run+=("$port_input")
                    break
                fi
            done
        done
    else
        local protocol_name=${protocols_to_create[0]}
        while true; do
            local port_prompt="请输入 [$protocol_name] 的端口 [回车则随机]: "
            if [[ "$protocol_name" == "Hysteria2" || "$protocol_name" == "TUIC" ]]; then port_prompt="请输入 [$protocol_name] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
            echo ""
            read -p "$(echo -e "$port_prompt")" port_input
            if [ -z "$port_input" ]; then
                port_input=$(generate_random_port)
                echo ""
                log_info "已生成随机端口: $port_input"
            fi
            if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then
                echo ""
                log_error "端口号需为 1-65535。"
            elif _is_port_available "$port_input" "used_ports_for_this_run"; then
                ports[$protocol_name]=$port_input
                used_ports_for_this_run+=("$port_input")
                break
            fi
        done
    fi
    echo ""
    read -p "请输入自定义标识 (如 Google, 回车则默认用 Jcole): " custom_id
    custom_id=${custom_id:-"Jcole"}
    local geo_info_json
    geo_info_json=$(curl -s ip-api.com/json)
    local country_code
    country_code=$(echo "$geo_info_json" | jq -r '.countryCode')
    local region_name
    region_name=$(echo "$geo_info_json" | jq -r '.regionName' | sed 's/ //g')
    if [ -z "$country_code" ]; then country_code="N/A"; fi
    if [ -z "$region_name" ]; then region_name="N/A"; fi
    local success_count=0
    for protocol in "${protocols_to_create[@]}"; do
        echo ""
        local tag_base="$country_code-$region_name-$custom_id"
        local base_tag_for_protocol="$tag_base-$protocol"
        local tag
        tag=$(_get_unique_tag "$base_tag_for_protocol")
        log_info "已为此节点分配唯一 Tag: $tag"
        local uuid=$(uuidgen)
        local password=$(generate_random_password)
        local config=""
        local node_link=""
        local current_port=${ports[$protocol]}
        local tls_config_tcp="{\"enabled\":true,\"server_name\":\"$sni_domain\",\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\"}"
        local tls_config_udp="{\"enabled\":true,\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\",\"alpn\":[\"h3\"]}"
        case $protocol in
        "VLESS" | "VMess" | "Trojan")
            config="{\"type\":\"${protocol,,}\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[$(if
                [[ "$protocol" == "VLESS" || "$protocol" == "VMess" ]]
            then echo "{\"uuid\":\"$uuid\"}"; else echo "{\"password\":\"$password\"}"; fi)],\"tls\":$tls_config_tcp,\"transport\":{\"type\":\"ws\",\"path\":\"/\"}}"
            if [[ "$protocol" == "VLESS" ]]; then
                node_link="vless://$uuid@$connect_addr:$current_port?type=ws&security=tls&sni=$sni_domain&host=$sni_domain&path=%2F${insecure_param}#$tag"
            elif [[ "$protocol" == "VMess" ]]; then
                local vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$connect_addr\",\"port\":\"$current_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$sni_domain\",\"path\":\"/\",\"tls\":\"tls\"${vmess_insecure_json_part}}"
                node_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
            else
                node_link="trojan://$password@$connect_addr:$current_port?security=tls&sni=$sni_domain&type=ws&host=$sni_domain&path=/${insecure_param}#$tag"
            fi
            ;;
        "Hysteria2")
            config="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"password\":\"$password\"}],\"tls\":$tls_config_udp,\"up_mbps\":100,\"down_mbps\":1000}"
            node_link="hysteria2://$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3${hy2_insecure_param}#$tag"
            ;;
        "TUIC")
            config="{\"type\":\"tuic\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"uuid\":\"$uuid\",\"password\":\"$password\"}],\"tls\":$tls_config_udp}"
            node_link="tuic://$uuid:$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3&congestion_control=bbr${tuic_insecure_param}#$tag"
            ;;
        esac
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
                echo ""
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

            if [ "$success_count" -gt 1 ] || $is_one_click; then
                view_node_info
            else
                press_any_key
            fi

        else
            log_error "Sing-Box 重启失败！请使用 'journalctl -u sing-box -f' 查看详细日志。"
            press_any_key
        fi
    else
        log_error "没有任何节点被成功添加。"
        press_any_key
    fi
}
singbox_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sing-Box 管理                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        if is_singbox_installed; then
            if systemctl is-active --quiet sing-box; then
                STATUS_COLOR="$GREEN● 活动$NC"
            else
                STATUS_COLOR="$RED● 不活动$NC"
            fi
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
            echo ""
            read -p "请输入选项: " choice
            case $choice in
            1) singbox_add_node_orchestrator ;; 2) view_node_info ;;
            3)
                systemctl start sing-box
                log_info "命令已发送"
                sleep 1
                ;;
            4)
                systemctl stop sing-box
                log_info "命令已发送"
                sleep 1
                ;;
            5)
                systemctl restart sing-box
                log_info "命令已发送"
                sleep 1
                ;;
            6)
                clear
                journalctl -u sing-box -f --no-pager
                ;;
            7) singbox_do_uninstall ;; 0) break ;; *)
                log_error "无效选项！"
                sleep 1
                ;;
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
            echo ""
            read -p "请输入选项: " choice
            case $choice in
            1) singbox_do_install ;; 0) break ;; *)
                log_error "无效选项！"
                sleep 1
                ;;
            esac
        fi
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