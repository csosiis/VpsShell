#!/bin/bash

# =================================================================================
#               全功能 VPS & 应用管理脚本 (v3.2 - 最终稳定版)
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
SHORTCUT_PATH="/usr/local/bin/sv"
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# 日志与交互函数
log_info() { echo -e "${GREEN}[信息] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[注意] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[错误] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
press_any_key() { echo ""; read -n 1 -s -r -p "按任意键返回..."; }
check_root() { if [ "$(id -u)" -ne 0 ]; then log_error "此脚本必须以 root 用户身份运行。"; exit 1; fi; }
check_port() { local port=$1; if ss -tln | grep -q -E "(:|:::)${port}\b"; then log_error "端口 ${port} 已被占用。"; return 1; fi; return 0; }
generate_random_port() { echo $((RANDOM % 64512 + 1024)); }
generate_random_password() { < /dev/urandom tr -dc 'A-Za-z0-9' | head -c 20; }
_is_port_available() {
    local port_to_check=$1
    local used_ports_array_name=$2
    eval "local used_ports=(\"\${${used_ports_array_name}[@]}\")"
    if ss -tlnu | grep -q -E ":${port_to_check}\s"; then
        log_warn "端口 ${port_to_check} 已被系统其他服务占用。"
        return 1
    fi
    for used_port in "${used_ports[@]}"; do
        if [ "$port_to_check" == "$used_port" ]; then
            log_warn "端口 ${port_to_check} 即将被本次操作中的其他协议使用。"
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

# --- 核心功能：依赖项管理 ---
ensure_dependencies() {
    local dependencies=("$@"); local missing_dependencies=()
    if [ ${#dependencies[@]} -eq 0 ]; then return 0; fi
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
        for pkg in "${missing_dependencies[@]}"; do log_info "正在安装 ${pkg}..."; apt-get install -y "$pkg"; done
        set +e
        log_info "按需依赖已安装完毕。"
    else
        log_info "所需依赖均已安装。"
    fi; echo ""
}

# --- 功能模块：系统综合管理 ---
show_system_info() {
    ensure_dependencies "util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools"
    clear; log_info "正在查询系统信息，请稍候..."
    log_info "正在获取网络信息..."; ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com); ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
    if [ -z "$ipv4_addr" ]; then ipv4_addr="获取失败"; fi
    if [ -z "$ipv6_addr" ]; then ipv6_addr="无或获取失败"; fi
    hostname_info=$(hostname); os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^[[:space:]]*//'); kernel_info=$(uname -r)
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_model_full=$(lscpu | grep "^Model name:" | sed -e 's/Model name:[[:space:]]*//')
    cpu_model=$(echo "$cpu_model_full" | sed 's/ @.*//'); cpu_freq_from_model=$(echo "$cpu_model_full" | sed -n 's/.*@ *//p')
    cpu_cores=$(lscpu | grep "^CPU(s):" | awk -F: '{print $2}' | sed 's/^ *//'); load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}'); disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')
    net_info_rx=$(vnstat --oneline | awk -F';' '{print $4}'); net_info_tx=$(vnstat --oneline | awk -F';' '{print $5}'); net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    ip_info=$(curl -s http://ip-api.com/json | jq -r '.org'); dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    geo_info=$(curl -s http://ip-api.com/json | jq -r '.city + ", " + .country'); timezone=$(timedatectl show --property=Timezone --value); uptime_info=$(uptime -p)
    current_time=$(date "+%Y-%m-%d %H:%M:%S"); cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    clear; echo ""; echo -e "${CYAN}-------------------- 系统信息查询 ---------------------${NC}"
    printf "${GREEN}主机名　　　  : ${WHITE}%s${NC}\n" "$hostname_info"; printf "${GREEN}系统版本　　  : ${WHITE}%s${NC}\n" "$os_info"; printf "${GREEN}Linux版本　 　: ${WHITE}%s${NC}\n" "$kernel_info"
    echo -e "${CYAN}-------------------------------------------------------${NC}"; printf "${GREEN}CPU架构　　 　: ${WHITE}%s${NC}\n" "$cpu_arch"; printf "${GREEN}CPU型号　　 　: ${WHITE}%s${NC}\n" "$cpu_model"; printf "${GREEN}CPU频率　　 　: ${WHITE}%s${NC}\n" "$cpu_freq_from_model"; printf "${GREEN}CPU核心数　 　: ${WHITE}%s${NC}\n" "$cpu_cores"
    echo -e "${CYAN}-------------------------------------------------------${NC}"; printf "${GREEN}CPU占用　　 　: ${WHITE}%s${NC}\n" "$cpu_usage"; printf "${GREEN}系统负载　　  : ${WHITE}%s${NC}\n" "$load_info"; printf "${GREEN}物理内存　　  : ${WHITE}%s${NC}\n" "$memory_info"; printf "${GREEN}硬盘占用　　  : ${WHITE}%s${NC}\n" "$disk_info"
    echo -e "${CYAN}-------------------------------------------------------${NC}"; printf "${GREEN}总接收　　　  : ${WHITE}%s${NC}\n" "$net_info_rx"; printf "${GREEN}总发送　　　  : ${WHITE}%s${NC}\n" "$net_info_tx"; printf "${GREEN}网络算法　　  : ${WHITE}%s${NC}\n" "$net_algo"
    echo -e "${CYAN}-------------------------------------------------------${NC}"; printf "${GREEN}运营商　　　  : ${WHITE}%s${NC}\n" "$ip_info"; printf "${GREEN}公网IPv4地址　: ${WHITE}%s${NC}\n" "$ipv4_addr"; printf "${GREEN}公网IPv6地址　: ${WHITE}%s${NC}\n" "$ipv6_addr"; printf "${GREEN}DNS地址　　 　: ${WHITE}%s${NC}\n" "$dns_info"; printf "${GREEN}地理位置　　  : ${WHITE}%s${NC}\n" "$geo_info"; printf "${GREEN}系统时间　　  : ${WHITE}%s${NC}\n" "$timezone $current_time"
    echo -e "${CYAN}-------------------------------------------------------${NC}"; printf "${GREEN}运行时长　　  : ${WHITE}%s${NC}\n" "$uptime_info"; echo -e "${CYAN}-------------------------------------------------------${NC}"; press_any_key
}
clean_system() { log_info "正在清理无用的软件包和缓存..."; set -e; apt autoremove -y > /dev/null; apt clean > /dev/null; set +e; log_info "系统清理完毕。"; press_any_key; }
change_hostname() { log_info "准备修改主机名..."; read -p "请输入新的主机名: " new_hostname; if [ -z "$new_hostname" ]; then log_error "主机名不能为空！"; press_any_key; return; fi; current_hostname=$(hostname); if [ "$new_hostname" == "$current_hostname" ]; then log_warn "新主机名与当前主机名相同，无需修改。"; press_any_key; return; fi; set -e; hostnamectl set-hostname "$new_hostname"; echo "$new_hostname" > /etc/hostname; sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts; set +e; log_info "✅ 主机名修改成功！新的主机名是：${new_hostname}"; log_info "当前主机名是：$(hostname)"; press_any_key; }
optimize_dns() { ensure_dependencies "iputils-ping"; log_info "开始优化DNS地址..."; if ping6 -c 1 google.com > /dev/null 2>&1; then log_info "检测到IPv6支持，配置IPv6优先..."; cat <<EOF > /etc/resolv.conf
nameserver 2606:4700:4700::1111
nameserver 8.8.8.8
EOF
else log_info "未检测到IPv6支持，仅配置IPv4 DNS..."; cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi; log_info "✅ DNS优化完成！"; press_any_key; }
set_network_priority() { clear; echo -e "请选择网络优先级设置:\n1. IPv6 优先\n2. IPv4 优先"; read -p "请输入选择: " choice; case $choice in 1) log_info "设置 IPv6 优先..."; sed -i '/^precedence ::ffff:0:0\/96/s/^/#/' /etc/gai.conf;; 2) log_info "设置 IPv4 优先..."; if ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf; fi;; *) log_error "无效选择。";; esac; press_any_key; }
setup_ssh_key() { log_info "开始设置 SSH 密钥登录..."; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; echo ""; log_warn "请粘贴您的公钥，粘贴完成后，按 Enter 换行，再按一次 Enter 即可结束输入:"; local public_key=""; local line; while IFS= read -r line; do if [[ -z "$line" ]]; then break; fi; public_key+="$line"$'\n'; done; public_key=$(echo -e "$public_key" | sed '/^$/d'); if [ -z "$public_key" ]; then log_error "没有输入公钥，操作已取消。"; press_any_key; return; fi; printf "%s\n" "$public_key" >> ~/.ssh/authorized_keys; sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys; log_info "公钥已成功添加。"; echo ""; read -p "是否要禁用密码登录 (强烈推荐)? (y/N): " disable_pwd; if [[ "$disable_pwd" == "y" || "$disable_pwd" == "Y" ]]; then sed -i 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd; log_info "✅ SSH 密码登录已禁用。"; fi; log_info "✅ SSH 密钥登录设置完成。"; press_any_key; }
set_timezone() {
    clear; local current_timezone; current_timezone=$(timedatectl show --property=Timezone --value); log_info "当前系统时区是: ${current_timezone}"
    while true; do
        echo ""; log_info "请选择新的时区："
        local options=("Asia/Shanghai" "Asia/Taipei" "Asia/Hong_Kong" "Asia/Tokyo" "Europe/London" "America/New_York" "UTC" "返回上一级菜单")
        for i in "${!options[@]}"; do echo -e "\n$((i+1))) ${options[$i]}"; done
        echo ""; read -p "请输入选项 (1-8): " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then log_error "无效输入，请输入数字。"; sleep 2; clear; continue; fi
        if [ "$choice" -ge 1 ] && [ "$choice" -le ${#options[@]} ]; then
            local selected_opt=${options[$((choice-1))]}
            if [[ "$selected_opt" == "返回上一级菜单" ]]; then log_info "操作已取消。"; break
            else timedatectl set-timezone "$selected_opt"; log_info "✅ 时区已成功设置为：$selected_opt"; break; fi
        else
            log_error "无效选项，请输入列表中的数字 (1-8)。"; sleep 2; clear
        fi
    done; press_any_key
}
manage_bbr() { clear; log_info "开始检查并管理 BBR..."; local kernel_version; kernel_version=$(uname -r | cut -d- -f1); if ! dpkg --compare-versions "$kernel_version" "ge" "4.9"; then log_error "内核版本 (${kernel_version}) 过低。"; press_any_key; return; fi; log_info "内核版本 ${kernel_version} 符合要求。"; local current_congestion_control; current_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control); log_info "当前 TCP 拥塞控制算法为: ${YELLOW}${current_congestion_control}${NC}"; local current_queue_discipline; current_queue_discipline=$(sysctl -n net.core.default_qdisc); log_info "当前网络队列管理算法为: ${YELLOW}${current_queue_discipline}${NC}"; echo -e "\n请选择要执行的操作:\n\n1. 启用 BBR\n\n2. 启用 BBR + FQ\n\n0. 返回\n"; read -p "请输入选项: " choice; local sysctl_conf="/etc/sysctl.conf"; sed -i -e '/net.core.default_qdisc/d' -e '/net.ipv4.tcp_congestion_control/d' "$sysctl_conf"; case $choice in 1) echo "net.ipv4.tcp_congestion_control = bbr" >> "$sysctl_conf";; 2) echo "net.core.default_qdisc = fq" >> "$sysctl_conf"; echo "net.ipv4.tcp_congestion_control = bbr" >> "$sysctl_conf";; 0) return ;; *) log_error "无效选项！"; press_any_key; return ;; esac; sysctl -p >/dev/null; log_info "✅ 配置已应用！"; press_any_key; }
install_warp() { ensure_dependencies "curl"; clear; log_info "开始安装 WARP..."; log_warn "将使用 fscarmen 的多功能 WARP 脚本。"; press_any_key; bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh); log_info "WARP 脚本执行完毕。"; press_any_key; }
sys_manage_menu() { while true; do clear; echo -e "${WHITE}===========================${NC}\n\n${WHITE}       系统综合管理      ${NC}\n\n${WHITE}===========================${NC}\n"; echo -e "1. 系统信息查询\n\n2. 清理系统垃圾\n\n3. 修改主机名\n\n4. 优化 DNS\n\n5. 设置网络优先级\n\n6. 设置 SSH 密钥登录\n\n7. 设置系统时区\n\n8. BBR 拥塞控制管理\n\n9. 安装 WARP 网络接口\n\n---------------------------\n\n0. 返回主菜单\n\n---------------------------\n"; read -p "请输入选项: " choice; case $choice in 1) show_system_info;; 2) clean_system;; 3) change_hostname;; 4) optimize_dns;; 5) set_network_priority;; 6) setup_ssh_key;; 7) set_timezone;; 8) manage_bbr;; 9) install_warp;; 0) break;; *) log_error "无效选项！"; sleep 1;; esac; done; }

# --- 功能模块：Sing-Box 管理 ---
is_singbox_installed() { if command -v sing-box &> /dev/null; then return 0; else return 1; fi; }
_get_unique_tag() { local base_tag="$1"; local final_tag="$base_tag"; local counter=2; while jq -e --arg t "$final_tag" 'any(.inbounds[]; .tag == $t)' "$SINGBOX_CONFIG_FILE" > /dev/null; do final_tag="${base_tag}-${counter}"; ((counter++)); done; echo "$final_tag"; }
_create_self_signed_cert() { local domain_name="$1"; local cert_dir="/etc/sing-box/certs"; cert_path="${cert_dir}/${domain_name}.cert.pem"; key_path="${cert_dir}/${domain_name}.key.pem"; if [ -f "$cert_path" ] && [ -f "$key_path" ]; then log_info "检测到已存在的自签名证书。"; return 0; fi; log_info "为 ${domain_name} 生成自签名证书..."; mkdir -p "$cert_dir"; openssl ecparam -genkey -name prime256v1 -out "$key_path"; openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=${domain_name}"; if [ -f "$cert_path" ] && [ -f "$key_path" ]; then log_info "✅ 自签名证书创建成功！"; return 0; else log_error "自签名证书创建失败！"; return 1; fi; }
_add_protocol_inbound() { local protocol=$1 config=$2 node_link=$3; log_info "正在为 [${protocol}] 协议添加入站配置..."; if ! jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp"; then log_error "[${protocol}] 协议配置写入失败！"; rm -f "$SINGBOX_CONFIG_FILE.tmp"; return 1; fi; mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"; echo "$node_link" >> "$SINGBOX_NODE_LINKS_FILE"; log_info "✅ [${protocol}] 协议配置添加成功！"; return 0; }
apply_ssl_certificate() { local domain_name="$1"; local cert_dir="/etc/letsencrypt/live/${domain_name}"; if [ -d "$cert_dir" ]; then log_info "域名 ${domain_name} 的证书已存在。"; return 0; fi; log_info "为 ${domain_name} 申请新证书..."; ensure_dependencies "certbot"; if command -v nginx &> /dev/null; then ensure_dependencies "nginx" "python3-certbot-nginx"; _handle_nginx_cert "$domain_name"; else log_error "Nginx 未安装，无法使用 Let's Encrypt。"; return 1; fi; return $?; }
_handle_nginx_cert() { local domain_name="$1"; log_info "检测到 Nginx，将使用 '--nginx' 插件模式。"; if ! systemctl is-active --quiet nginx; then log_info "Nginx 服务未运行，正在启动..."; systemctl start nginx; fi; local NGINX_CONF_PATH="/etc/nginx/sites-available/${domain_name}.conf"; if [ ! -f "$NGINX_CONF_PATH" ]; then log_info "为域名验证创建临时的 HTTP Nginx 配置文件..."; cat <<EOF > "$NGINX_CONF_PATH"
server { listen 80; listen [::]:80; server_name ${domain_name}; root /var/www/html; index index.html index.htm; }
EOF
if [ ! -L "/etc/nginx/sites-enabled/${domain_name}.conf" ]; then ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"; fi; log_info "正在重载 Nginx 以应用临时配置..."; if ! nginx -t; then log_error "Nginx 临时配置测试失败！"; rm -f "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/${domain_name}.conf"; return 1; fi; systemctl reload nginx; else log_warn "检测到已存在的 Nginx 配置文件，将直接在此基础上尝试申请证书。"; fi; log_info "正在使用 'certbot --nginx' 模式为 ${domain_name} 申请证书..."; certbot --nginx -d "${domain_name}" --non-interactive --agree-tos --email "temp@${domain_name}" --redirect; if [ -f "/etc/letsencrypt/live/${domain_name}/fullchain.pem" ]; then log_info "✅ Nginx 模式证书申请成功！"; return 0; else log_error "Nginx 模式证书申请失败！"; return 1; fi; }
_handle_apache_cert() { log_error "Apache 模式暂未完全实现。"; return 1; }
singbox_do_install() { ensure_dependencies "curl"; if is_singbox_installed; then echo ""; log_info "Sing-Box 已经安装。"; press_any_key; return; fi; log_info "正在安装Sing-Box ..."; set -e; bash <(curl -fsSL https://sing-box.app/deb-install.sh); set +e; if ! is_singbox_installed; then log_error "Sing-Box 安装失败！"; exit 1; fi; echo ""; log_info "✅ Sing-Box 安装成功！"; log_info "正在自动定位服务文件并修改运行权限..."; local service_file_path; service_file_path=$(systemctl status sing-box | grep -oP 'Loaded: loaded \(\K[^;]+'); if [ -n "$service_file_path" ] && [ -f "$service_file_path" ]; then log_info "找到服务文件位于: ${service_file_path}"; sed -i 's/User=sing-box/User=root/' "$service_file_path"; sed -i 's/Group=sing-box/Group=root/' "$service_file_path"; systemctl daemon-reload; log_info "服务权限修改完成。"; else log_error "无法自动定位 sing-box.service 文件！"; fi; config_dir="/etc/sing-box"; mkdir -p "$config_dir"; if [ ! -f "$SINGBOX_CONFIG_FILE" ]; then log_info "正在创建兼容性更强的 Sing-Box 默认配置文件..."; cat > "$SINGBOX_CONFIG_FILE" <<EOL
{ "log": { "level": "info", "timestamp": true }, "dns": {}, "inbounds": [], "outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" }, { "type": "dns", "tag": "dns-out" } ], "route": { "rules": [ { "protocol": "dns", "outbound": "dns-out" } ] } }
EOL
fi; echo ""; log_info "正在启用并重启 Sing-Box 服务..."; systemctl enable --now sing-box.service >/dev/null 2>&1; echo ""; log_info "✅ Sing-Box 配置文件初始化完成并已启动！"; echo ""; press_any_key; }
singbox_add_node_orchestrator() { ensure_dependencies "jq" "uuid-runtime" "curl" "openssl"; local cert_choice custom_id location connect_addr sni_domain final_node_link; local cert_path key_path; declare -A ports; local protocols_to_create=(); local is_one_click=false; clear; log_info "欢迎使用 Sing-Box 节点创建向导 v3.7"; echo -e "\n请选择您要搭建的节点类型：\n"; echo -e "1. VLESS\n2. VMess\n3. Trojan\n4. Hysteria2\n\n${CYAN}-------------------------------------${NC}\n"; echo -e "5. 一键生成以上全部 4 种协议节点\n\n${CYAN}-------------------------------------${NC}\n\n0. 返回上一级菜单\n"; read -p "请输入选项: " protocol_choice; case $protocol_choice in 1) protocols_to_create=("VLESS");; 2) protocols_to_create=("VMess");; 3) protocols_to_create=("Trojan");; 4) protocols_to_create=("Hysteria2");; 5) protocols_to_create=("VLESS" "VMess" "Trojan" "Hysteria2"); is_one_click=true;; 0) return;; *) log_error "无效选择，操作中止。"; press_any_key; return;; esac; clear; log_info "您选择了 [${protocols_to_create[*]}] 协议。"; echo -e "\n请选择证书类型：\n1. 使用 Let's Encrypt 域名证书 (推荐)\n2. 使用自签名证书 (IP 直连)\n"; read -p "请输入选项 (1-2): " cert_choice; if [ "$cert_choice" == "1" ]; then while true; do read -p "请输入您已解析到本机的域名: " domain; if [[ -z "$domain" ]]; then log_error "域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确。"; else break; fi; done; if ! apply_ssl_certificate "$domain"; then log_error "证书处理失败。"; press_any_key; return; fi; cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"; key_path="/etc/letsencrypt/live/${domain}/privkey.pem"; connect_addr="$domain"; sni_domain="$domain"; elif [ "$cert_choice" == "2" ]; then ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com); ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com); if [ -n "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then echo -e "\n请选择用于节点链接的地址：\n1. IPv4: ${ipv4_addr}\n2. IPv6: ${ipv6_addr}\n"; read -p "请输入选项 (1-2): " ip_choice; if [ "$ip_choice" == "2" ]; then connect_addr="[${ipv6_addr}]"; else connect_addr="$ipv4_addr"; fi; elif [ -n "$ipv4_addr" ]; then log_info "将自动使用 IPv4 地址。"; connect_addr="$ipv4_addr"; elif [ -n "$ipv6_addr" ]; then log_info "将自动使用 IPv6 地址。"; connect_addr="[${ipv6_addr}]"; else log_error "无法获取任何公网 IP 地址！"; press_any_key; return; fi; read -p "请输入 SNI 伪装域名 [默认: www.bing.com]: " sni_input; sni_domain=${sni_input:-"www.bing.com"}; if ! _create_self_signed_cert "$sni_domain"; then log_error "自签名证书处理失败。"; press_any_key; return; fi; cert_path="/etc/sing-box/certs/${sni_domain}.cert.pem"; key_path="/etc/sing-box/certs/${sni_domain}.key.pem"; else log_error "无效证书选择。"; press_any_key; return; fi; local used_ports_for_this_run=(); if $is_one_click; then echo ""; log_info "您已选择一键模式，请为每个协议指定端口。"; for p in "${protocols_to_create[@]}"; do while true; do local port_prompt="请输入 [${p}] 的端口 [回车则随机]: "; if [[ "$p" == "Hysteria2" ]]; then port_prompt="请输入 [${p}] 的 ${YELLOW}UDP${NC} 端口 [回车则随机]: "; fi; read -p "$(echo -e "${port_prompt}")" port_input; if [ -z "$port_input" ]; then port_input=$(generate_random_port); log_info "已为 [${p}] 生成随机端口: ${port_input}"; fi; if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then log_error "端口号需为 1-65535。"; elif _is_port_available "$port_input" "used_ports_for_this_run"; then ports[$p]=$port_input; used_ports_for_this_run+=("$port_input"); break; fi; done; done; if [ "$cert_choice" == "1" ]; then read -p "请输入自定义标识 (如 GCP, 回车则默认): " custom_id; else custom_id=""; fi; else local protocol_name=${protocols_to_create[0]}; while true; do local port_prompt="请输入 [${protocol_name}] 的端口 [回车则随机]: "; if [[ "$protocol_name" == "Hysteria2" ]]; then port_prompt="请输入 [${protocol_name}] 的 ${YELLOW}UDP${NC} 端口 [回车则随机]: "; fi; read -p "$(echo -e "${port_prompt}")" port_input; if [ -z "$port_input" ]; then port_input=$(generate_random_port); log_info "已生成随机端口: ${port_input}"; fi; if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then log_error "端口号需为 1-65535。"; elif _is_port_available "$port_input" "used_ports_for_this_run"; then ports[$protocol_name]=$port_input; used_ports_for_this_run+=("$port_input"); break; fi; done; read -p "请输入自定义标识 (如 GCP, 回车则默认): " custom_id; fi; read -p "请输入自定义 Tag 前缀 (如 SG-Google, 回车则使用默认地区名): " custom_id; local location=$(curl -s ip-api.com/json | jq -r '.city' | sed 's/ //g' | sed 's/\(.\)/\u\1/'); if [ -z "$location" ]; then location="N/A"; fi; local success_count=0; for protocol in "${protocols_to_create[@]}"; do echo ""; local tag_prefix; if [ -n "$custom_id" ]; then tag_prefix="$custom_id"; else tag_prefix="$location"; fi; local base_tag_for_protocol="${tag_prefix}-${protocol}"; local tag; tag=$(_get_unique_tag "$base_tag_for_protocol"); log_info "已为此节点分配唯一 Tag: ${tag}"; local uuid=$(uuidgen); local password=$(generate_random_password); local config=""; local node_link=""; local current_port=${ports[$protocol]}; local tls_config_tcp="{\"enabled\":true,\"server_name\":\"$sni_domain\",\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\"}"; local tls_config_udp="{\"enabled\":true,\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\",\"alpn\":[\"h3\"]}"; case $protocol in "VLESS"|"VMess"|"Trojan") config="..."; node_link="...";; "Hysteria2") config="..."; node_link="...";; esac; if _add_protocol_inbound "$protocol" "$config" "$node_link"; then ((success_count++)); final_node_link="$node_link"; fi; done; if [ "$success_count" -gt 0 ]; then log_info "共成功添加 ${success_count} 个节点..."; systemctl restart sing-box; sleep 2; if systemctl is-active --quiet sing-box; then log_info "Sing-Box 重启成功。"; if [ "$success_count" -eq 1 ] && ! $is_one_click; then echo ""; log_info "✅ 节点添加成功！..."; press_any_key; else log_info "正在显示所有节点信息..."; sleep 1; view_node_info; fi; else log_error "Sing-Box 重启失败！"; press_any_key; fi; else log_error "没有任何节点被成功添加。"; press_any_key; fi; }

# --- 主菜单 ---
# ...
# --- 脚本入口 ---
check_root
initial_setup_check
main_menu