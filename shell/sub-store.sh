#!/bin/bash

# ==============================================================================
# Sub-Store 管理脚本 (v6.1)
#
# 基于 v6.0 版本修改：
# 1. [优化] 将“更新脚本”和“更新Sub-Store”功能提升至主菜单，方便访问。
# 2. [BUG修复] 修正菜单项颜色代码无法正确显示的问题。
# ==============================================================================

# --- 全局变量和辅助函数 ---
# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# 配置变量
SERVICE_NAME="sub-store.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
INSTALL_DIR="/root/sub-store"
SCRIPT_PATH=$(realpath "$0")
SHORTCUT_PATH="/usr/local/bin/sub"
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/singbox.sh"

# 日志函数
log_info() { echo -e "${GREEN}[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
press_any_key() { echo ""; read -n 1 -s -r -p "按任意键返回..."; }

# 检查是否以 root 身份运行
check_root() { if [ "$(id -u)" -ne 0 ]; then log_error "此脚本必须以 root 用户身份运行。"; exit 1; fi; }
is_installed() { if [ -f "$SERVICE_FILE" ]; then return 0; else return 1; fi; }

check_port() {
    local port=$1
    if ss -tln | grep -q -E "(:|:::)${port}\b"; then log_error "端口 ${port} 已被占用。"; return 1; fi
    log_info "端口 ${port} 可用。"; return 0;
}

# --- 主要功能函数 ---

setup_shortcut() {
    log_info "正在设置 'sub' 快捷命令..."; ln -sf "$SCRIPT_PATH" "$SHORTCUT_PATH"; chmod +x "$SHORTCUT_PATH"
    log_info "快捷命令设置成功！现在您可以随时随地输入 'sub' 来运行此脚本。"
}

do_install() {
    log_info "开始执行 Sub-Store 安装流程..."; set -e
    log_info "更新系统并安装基础组件..."; apt update -y > /dev/null; apt install unzip curl wget git sudo iproute2 apt-transport-https dnsutils -y > /dev/null
    log_info "正在安装 FNM, Node.js 和 PNPM..."; curl -fsSL https://fnm.vercel.app/install | bash
    export PATH="/root/.local/share/fnm:$PATH"; eval "$(fnm env)"; fnm install v20.18.0; fnm use v20.18.0
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    export PNPM_HOME="/root/.local/share/pnpm"; export PATH="$PNPM_HOME:$PATH"
    log_info "正在下载并设置 Sub-Store 项目文件..."; mkdir -p "$INSTALL_DIR"; cd "$INSTALL_DIR"
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -q dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"
    log_info "开始配置系统服务..."; echo ""; while true; do read -p "请输入前端访问端口 [默认: 3000]: " FRONTEND_PORT; FRONTEND_PORT=${FRONTEND_PORT:-3000}; check_port "$FRONTEND_PORT" && break; done
    echo ""; read -p "请输入后端 API 端口 [默认: 3001]: " BACKEND_PORT; BACKEND_PORT=${BACKEND_PORT:-3001}
    API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1); log_info "生成的 API 密钥为: ${API_KEY}"
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Sub-Store Service
After=network-online.target
Wants=network-online.target
[Service]
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/${API_KEY}"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=${INSTALL_DIR}/frontend"
Environment="SUB_STORE_FRONTEND_HOST=::"
Environment="SUB_STORE_FRONTEND_PORT=${FRONTEND_PORT}"
Environment="SUB_STORE_DATA_BASE_PATH=${INSTALL_DIR}"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=${BACKEND_PORT}"
ExecStart=/root/.local/share/fnm/fnm exec --using v20.18.0 node ${INSTALL_DIR}/sub-store.bundle.js
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
    log_info "正在启动并启用 sub-store 服务..."; systemctl daemon-reload; systemctl enable "$SERVICE_NAME" > /dev/null; systemctl start "$SERVICE_NAME"; setup_shortcut
    log_info "正在检测服务状态 (等待 5 秒)..."; sleep 5; set +e
    if systemctl is-active --quiet "$SERVICE_NAME"; then log_info "服务状态正常 (active)。"; view_access_link; else log_error "服务启动失败！"; fi
    echo ""; read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then setup_reverse_proxy; else press_any_key; fi
}

do_uninstall() {
    log_warn "你确定要卸载 Sub-Store 吗？此操作不可逆！"; echo ""; read -p "请输入 Y 确认: " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "取消卸载。"; press_any_key; return; fi
    log_info "正在停止并禁用服务..."; systemctl stop "$SERVICE_NAME" || true; systemctl disable "$SERVICE_NAME" || true
    log_info "正在删除服务文件..."; rm -f "$SERVICE_FILE"; systemctl daemon-reload
    log_info "正在删除项目文件和 Node.js 环境..."; rm -rf "$INSTALL_DIR"; rm -rf "/root/.local"; rm -rf "/root/.pnpm-state.json"
    log_info "正在移除快捷命令..."; rm -f "$SHORTCUT_PATH"
    if [ -f "/etc/caddy/Caddyfile" ] && grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
        echo ""; read -p "检测到 Caddy 反代配置，是否移除? (y/N): " rm_caddy_choice
        if [[ "$rm_caddy_choice" == "y" || "$rm_caddy_choice" == "Y" ]]; then
            log_info "正在移除 Caddy 配置..."; sed -i '/# Sub-Store config start/,/# Sub-Store config end/d' /etc/caddy/Caddyfile; systemctl reload caddy
        fi
    fi
    log_info "✅ Sub-Store 已成功卸载。"; press_any_key
}

# --- 管理功能 ---
save_reverse_proxy_domain() {
    local domain_to_save=$1
    log_info "正在保存域名配置: ${domain_to_save}"; sed -i '/SUB_STORE_REVERSE_PROXY_DOMAIN/d' "$SERVICE_FILE"
    sed -i "/\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=${domain_to_save}\"" "$SERVICE_FILE"
    systemctl daemon-reload; log_info "域名配置已保存！"
}

view_access_link() {
    log_info "正在读取配置并生成访问链接..."; if ! is_installed; then log_error "Sub-Store尚未安装。"; return; fi
    REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    API_KEY=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"/')
    echo -e "\n===================================================================="
    if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
        ACCESS_URL="https://${REVERSE_PROXY_DOMAIN}/subs?api=https://${REVERSE_PROXY_DOMAIN}/${API_KEY}"
        echo -e "\n您的 Sub-Store 反代访问链接如下：\n\n${YELLOW}${ACCESS_URL}${NC}\n"
    else
        FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
        SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com); if [ -n "$SERVER_IP_V4" ]; then
            ACCESS_URL_V4="http://${SERVER_IP_V4}:${FRONTEND_PORT}/subs?api=http://${SERVER_IP_V4}:${FRONTEND_PORT}/${API_KEY}"
            echo -e "\n您的 Sub-Store IPv4 访问链接如下：\n\n${YELLOW}${ACCESS_URL_V4}${NC}\n"
        fi
        SERVER_IP_V6=$(curl -s --max-time 2 http://ipv6.icanhazip.com); if [[ "$SERVER_IP_V6" =~ .*:.* && -n "$SERVER_IP_V6" ]]; then
            ACCESS_URL_IPV6="http://[${SERVER_IP_V6}]:${FRONTEND_PORT}/subs?api=http://[${SERVER_IP_V6}]:${FRONTEND_PORT}/${API_KEY}"
            echo -e "--------------------------------------------------------------------"
            echo -e "\n您的 Sub-Store IPv6 访问链接如下：\n\n${YELLOW}${ACCESS_URL_IPV6}${NC}\n"
        fi
    fi
    echo -e "===================================================================="
}

reset_ports() {
    log_info "开始重置端口..."; if ! is_installed; then log_error "Sub-Store尚未安装。"; return; fi
    CURRENT_FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    CURRENT_BACKEND_PORT=$(grep 'SUB_STORE_BACKEND_API_PORT=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    log_info "当前前端端口: ${CURRENT_FRONTEND_PORT}"; log_info "当前后端端口: ${CURRENT_BACKEND_PORT}"; echo ""
    while true; do read -p "请输入新的前端访问端口 [默认: ${CURRENT_FRONTEND_PORT}]: " NEW_FRONTEND_PORT; NEW_FRONTEND_PORT=${NEW_FRONTEND_PORT:-$CURRENT_FRONTEND_PORT}; if [ "$NEW_FRONTEND_PORT" == "$CURRENT_FRONTEND_PORT" ] || check_port "$NEW_FRONTEND_PORT"; then break; fi; done
    echo ""; read -p "请输入新的后端 API 端口 [默认: ${CURRENT_BACKEND_PORT}]: " NEW_BACKEND_PORT; NEW_BACKEND_PORT=${NEW_BACKEND_PORT:-$CURRENT_BACKEND_PORT}
    log_info "正在更新服务文件..."; set -e
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_PORT=.*|Environment=\"SUB_STORE_FRONTEND_PORT=${NEW_FRONTEND_PORT}\"|" "$SERVICE_FILE"
    sed -i "s|^Environment=\"SUB_STORE_BACKEND_API_PORT=.*|Environment=\"SUB_STORE_BACKEND_API_PORT=${NEW_BACKEND_PORT}\"|" "$SERVICE_FILE"
    log_info "正在重载并重启服务..."; systemctl daemon-reload; systemctl restart "$SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "✅ 端口重置成功！"; REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
        if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
            NGINX_CONF_PATH="/etc/nginx/sites-available/${REVERSE_PROXY_DOMAIN}.conf"
            if [ -f "$NGINX_CONF_PATH" ]; then
                log_info "检测到 Nginx 反代配置，正在自动更新端口..."; sed -i "s|proxy_pass http://localhost:.*|proxy_pass http://localhost:${NEW_FRONTEND_PORT};|g" "$NGINX_CONF_PATH"
                if nginx -t >/dev/null 2>&1; then systemctl reload nginx; log_info "Nginx 配置已更新并重载。"; else log_error "更新 Nginx 端口后配置测试失败！"; fi
            fi
            if [ -f "/etc/caddy/Caddyfile" ] && grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
                log_info "检测到 Caddy 反代配置，正在自动更新端口..."; sed -i "/# Sub-Store config start/,/# Sub-Store config end/ s|reverse_proxy localhost:.*|reverse_proxy localhost:${NEW_FRONTEND_PORT}|" /etc/caddy/Caddyfile
                systemctl reload caddy; log_info "Caddy 配置已更新并重载。";
            fi
        fi
        view_access_link
    else log_error "服务重启失败！"; fi
}

reset_api_key() {
    log_warn "确定要重置 API 密钥吗？旧的访问链接将立即失效。"; echo ""; read -p "请输入 Y 确认: " choice; if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "取消操作。"; return; fi
    log_info "正在生成新的 API 密钥..."; set -e; NEW_API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
    log_info "正在更新服务文件..."; sed -i "s|^Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=.*|Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=/${NEW_API_KEY}\"|" "$SERVICE_FILE"
    log_info "正在重载并重启服务..."; systemctl daemon-reload; systemctl restart "$SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SERVICE_NAME"; then log_info "✅ API 密钥重置成功！"; view_access_link; else log_error "服务重启失败！"; fi
}

install_caddy() {
    log_info "正在安装 Caddy..."; if ! command -v caddy &> /dev/null; then
    set -e; apt-get install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
    apt-get update -y > /dev/null; apt-get install caddy -y; set +e
    log_info "Caddy 安装成功！"; else log_info "Caddy 已安装。"; fi
}

handle_caddy_proxy() {
    if ! command -v dig &> /dev/null; then log_info "'dig' 命令未找到，安装 'dnsutils'..."; set -e; apt-get update >/dev/null; apt-get install -y dnsutils >/dev/null; set +e; fi
    echo ""; read -p "请输入您已解析到本服务器的域名: " DOMAIN; if [ -z "$DOMAIN" ]; then log_error "域名不能为空！"; return; fi
    log_info "正在验证域名解析..."; SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com); DOMAIN_IP_V4=$(dig +short "$DOMAIN" A)
    if [ "$SERVER_IP_V4" != "$DOMAIN_IP_V4" ]; then
        log_warn "域名 A 记录 (${DOMAIN_IP_V4}) 与本机 IPv4 (${SERVER_IP_V4}) 不符。"; echo ""; read -p "是否仍然继续? (y/N): " continue_choice; if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then log_info "操作中止。"; return; fi
    else log_info "域名 IPv4 解析验证成功！"; fi
    local FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    log_info "正在生成 Caddy 配置文件..."; CADDY_CONFIG="\n# Sub-Store config start\n$DOMAIN {\n    reverse_proxy localhost:$FRONTEND_PORT\n}\n# Sub-Store config end\n"
    if grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
        log_warn "检测到已存在的配置，将进行覆盖。"; awk -v new_config="$CADDY_CONFIG" 'BEGIN {p=1} /# Sub-Store config start/ {p=0} p==1 {print} /# Sub-Store config end/ {p=1; printf "%s", new_config}' /etc/caddy/Caddyfile > /tmp/Caddyfile.tmp && mv /tmp/Caddyfile.tmp /etc/caddy/Caddyfile
    else echo -e "$CADDY_CONFIG" >> /etc/caddy/Caddyfile; fi
    log_info "正在重载 Caddy 服务..."; systemctl reload caddy
    if systemctl is-active --quiet caddy; then log_info "✅ 反向代理设置成功！"; save_reverse_proxy_domain "$DOMAIN"; view_access_link; else log_error "Caddy 服务重载失败！"; fi
}

handle_nginx_proxy() {
    echo ""; read -p "请输入您要使用的域名: " DOMAIN; if [ -z "$DOMAIN" ]; then log_error "域名不能为空！"; return; fi
    local FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SERVICE_FILE" | awk -F'=' '{print $3}' | tr -d '"')
    local NGINX_CONFIG_BLOCK="server {\n    listen 80;\n    listen [::]:80;\n    server_name ${DOMAIN};\n\n    location / {\n        proxy_pass http://localhost:${FRONTEND_PORT};\n        proxy_http_version 1.1;\n        proxy_set_header Upgrade \$http_upgrade;\n        proxy_set_header Connection \"upgrade\";\n        proxy_set_header Host \$host;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto \$scheme;\n    }\n}";
    clear; echo -e "${YELLOW}--- Nginx 配置指南 ---${NC}"; echo "请手动完成以下步骤，或选择让脚本自动执行。"; echo "1. 创建或编辑 Nginx 配置文件:"; echo -e "   ${GREEN}sudo vim /etc/nginx/sites-available/${DOMAIN}.conf${NC}"
    echo "2. 将以下代码块完整复制并粘贴到文件中："; echo -e "${WHITE}--------------------------------------------------${NC}"
    echo -e "${NGINX_CONFIG_BLOCK}"; echo -e "${WHITE}--------------------------------------------------${NC}"
    echo "3. 启用该站点:"; echo -e "   ${GREEN}sudo ln -s /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/${NC}"; echo "4. 测试 Nginx 配置是否有语法错误:"; echo -e "   ${GREEN}sudo nginx -t${NC}"; echo "5. 重载 Nginx 服务以应用配置:"; echo -e "   ${GREEN}sudo systemctl reload nginx${NC}"; echo "6. (推荐) 申请 HTTPS 证书 (需提前安装 certbot):"; echo -e "   ${GREEN}sudo certbot --nginx -d ${DOMAIN}${NC}"
    echo ""; read -p "是否要让脚本尝试自动执行以上所有步骤? (Y/n): " auto_choice
    if [[ "$auto_choice" == "y" || "$auto_choice" == "Y" ]]; then
        log_info "开始为 Nginx 自动配置..."; log_info "正在检查并安装 Certbot 及其 Nginx 插件..."
        set -e; apt-get update -y >/dev/null; apt-get install -y certbot python3-certbot-nginx >/dev/null; set +e
        log_info "Certbot 依赖检查/安装完毕。"
        NGINX_CONF_PATH="/etc/nginx/sites-available/${DOMAIN}.conf"; log_info "正在写入 Nginx 配置文件: ${NGINX_CONF_PATH}"; echo -e "${NGINX_CONFIG_BLOCK}" > "$NGINX_CONF_PATH"
        if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]; then log_info "正在启用站点..."; ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"; else log_warn "站点似乎已被启用，跳过创建软链接。"; fi
        log_info "正在测试 Nginx 配置..."; if ! nginx -t; then log_error "Nginx 配置测试失败！请检查您的 Nginx 配置。"; return; fi
        log_info "正在重载 Nginx..."; systemctl reload nginx; RANDOM_EMAIL=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)@gmail.com
        log_warn "将使用随机生成的邮箱 ${RANDOM_EMAIL} 为 Certbot 注册。"; log_warn "为保证续期通知，建议之后手动执行 'sudo certbot register --update-registration --email 您的真实邮箱' 来更新邮箱。"
        log_info "正在为 ${DOMAIN} 申请 HTTPS 证书..."; certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --email "${RANDOM_EMAIL}" --no-eff-email --redirect
        if [ $? -eq 0 ]; then log_info "✅ Nginx 反向代理和 HTTPS 证书已自动配置成功！"; save_reverse_proxy_domain "$DOMAIN"; view_access_link; else log_error "Certbot 证书申请失败！请检查域名解析和防火墙设置。"; fi
    fi
}

do_update_script() {
    log_info "正在从 GitHub 下载最新版本的脚本..."
    local temp_script="/tmp/sub_manager_new.sh"
    if ! curl -sL "$SCRIPT_URL" -o "$temp_script"; then
        log_error "下载脚本失败！请检查您的网络连接或 URL 是否正确。"; press_any_key; return
    fi
    if cmp -s "$SCRIPT_PATH" "$temp_script"; then
        log_info "脚本已经是最新版本，无需更新。"; rm "$temp_script"; press_any_key; return
    fi
    log_info "下载成功，正在应用更新..."; chmod +x "$temp_script"; mv "$temp_script" "$SCRIPT_PATH"
    log_info "✅ 脚本已成功更新！"; log_warn "请重新运行脚本以使新版本生效 (例如，再次输入 'sub')..."; exit 0
}

update_sub_store() {
    log_info "开始更新 Sub-Store 应用..."; if ! is_installed; then log_error "Sub-Store 尚未安装，无法更新。"; press_any_key; return; fi
    set -e; cd "$INSTALL_DIR"
    log_info "正在下载最新的后端文件 (sub-store.bundle.js)..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    log_info "正在下载最新的前端文件 (dist.zip)..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    log_info "正在部署新版前端..."; rm -rf frontend
    unzip -q dist.zip && mv dist frontend && rm dist.zip
    log_info "正在重启 Sub-Store 服务以应用更新..."; systemctl restart "$SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SERVICE_NAME"; then log_info "✅ Sub-Store 更新成功并已重启！"; else log_error "Sub-Store 更新后重启失败！请使用 '查看日志' 功能进行排查。"; fi
    press_any_key
}

setup_reverse_proxy() {
    clear
    if command -v caddy &> /dev/null; then log_info "检测到 Caddy，将为您进行全自动配置。"; handle_caddy_proxy
    elif command -v nginx &> /dev/null; then log_info "检测到 Nginx，将为您生成配置代码和操作指南。"; handle_nginx_proxy
    elif command -v apache2 &> /dev/null || command -v httpd &> /dev/null; then log_warn "检测到 Apache，但本脚本暂未支持自动生成其配置。";
    else
        log_warn "未检测到任何 Web 服务器 (Caddy, Nginx, Apache)。"; echo ""; read -p "是否要自动安装 Caddy 以进行全自动配置? (y/N): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then install_caddy; handle_caddy_proxy; else log_info "操作中止。"; fi
    fi
    press_any_key
}

manage_menu() {
    while true; do
        clear; echo -e "${WHITE}--- Sub-Store 管理菜单 (v6.1) ---${NC}\n"
        if systemctl is-active --quiet "$SERVICE_NAME"; then STATUS_COLOR="${GREEN}● 活动${NC}"; else STATUS_COLOR="${RED}● 不活动${NC}"; fi
        echo -e "当前状态: ${STATUS_COLOR}\n"; echo "1. 启动服务"; echo ""; echo "2. 停止服务"; echo ""; echo "3. 重启服务"; echo ""; echo "4. 查看状态"; echo ""; echo "5. 查看日志"
        echo -e "\n---------------------------------\n"; echo "6. 查看访问链接"; echo ""; echo "7. 重置端口"; echo ""; echo "8. 重置 API 密钥"
        echo -e "\n9. ${YELLOW}设置/更新反向代理${NC}"; echo ""; echo -e "0. ${RED}退出脚本${NC}"; echo ""; read -p "请输入选项: " choice
        case $choice in
            1) systemctl start "$SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;; 2) systemctl stop "$SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            3) systemctl restart "$SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;; 4) clear; systemctl status "$SERVICE_NAME"; press_any_key;;
            5) clear; journalctl -u "$SERVICE_NAME" -f --no-pager;; 6) view_access_link; press_any_key;;
            7) reset_ports; press_any_key;; 8) reset_api_key; press_any_key;; 9) setup_reverse_proxy;; 0) break ;;
            *) log_warn "无效选项！"; sleep 1 ;;
        esac
    done
}

main_menu() {
    while true; do
        clear; echo -e "${WHITE}=====================================${NC}"; echo -e "${WHITE}     Sub-Store 管理脚本 (v6.1)       ${NC}"; echo -e "${WHITE}=====================================${NC}\n"
        if is_installed; then
            echo "1. 管理 Sub-Store"; echo ""; echo -e "2. ${GREEN}更新 Sub-Store${NC}"; echo""; echo -e "3. ${GREEN}更新脚本${NC}"
            echo ""; echo -e "4. ${RED}卸载 Sub-Store${NC}"; echo ""; echo -e "0. ${RED}退出脚本${NC}"; echo ""; read -p "请输入选项: " choice
            case $choice in 1) manage_menu ;; 2) update_sub_store ;; 3) do_update_script ;; 4) do_uninstall ;; 0) exit 0 ;; *) log_warn "无效选项！"; sleep 1 ;; esac
        else
            echo "1. 安装 Sub-Store"; echo ""; echo -e "0. ${RED}退出脚本${NC}"; echo ""; read -p "请输入选项: " choice
            case $choice in 1) do_install ;; 0) exit 0 ;; *) log_warn "无效选项！"; sleep 1 ;; esac
        fi
    done
}

# --- 脚本入口 ---
check_root
main_menu