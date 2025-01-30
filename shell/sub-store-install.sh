#!/bin/bash

# 用绿色输出信息
print_green() {
    echo -e "\033[32m$1\033[0m"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 安装所需组件
install_required_components() {
    print_green "检查并安装所需组件..."
    apt update -y
    for pkg in unzip curl wget git sudo; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            print_green "安装 $pkg..."
            apt install "$pkg" -y
        else
            print_green "$pkg 已安装，跳过。"
        fi
    done
}

# 安装 FNM 版本管理器
install_fnm() {
    if command_exists fnm; then
        print_green "FNM 已安装，跳过安装。"
    else
        print_green "安装 FNM 版本管理器..."
        curl -fsSL https://fnm.vercel.app/install | bash
        export PATH="$HOME/.fnm:$PATH"
        eval "$(fnm env)"
    fi
}

# 安装 Node.js
install_node() {
    local NODE_VERSION="v20.18.0"
    if command_exists node && [[ "$(node -v)" == "$NODE_VERSION" ]]; then
        print_green "Node.js $NODE_VERSION 已安装，跳过安装。"
    else
        print_green "安装 Node.js $NODE_VERSION..."
        fnm install "$NODE_VERSION"
        fnm use "$NODE_VERSION"
    fi
}

# 安装 PNPM 软件包管理器
install_pnpm() {
    if command_exists pnpm; then
        print_green "PNPM 已安装，跳过安装。"
    else
        print_green "安装 PNPM 软件包管理器..."
        curl -fsSL https://get.pnpm.io/install.sh | sh -
        export PATH="$HOME/.local/share/pnpm:$PATH"
    fi
}

# 安装 Sub-Store
install_sub_store() {
    local INSTALL_DIR="/root/sub-store"

    if [ -d "$INSTALL_DIR" ]; then
        print_green "Sub-Store 已安装，跳过下载。"
    else
        print_green "安装 Sub-Store..."
        mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"
        curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
        curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
        unzip dist.zip && mv dist frontend && rm dist.zip
    fi
}

# 生成随机密码
generate_random_password() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 26
}

# 创建 Sub-Store 系统服务
create_system_service() {
    local RANDOM_PASSWORD=$(generate_random_password)
    print_green "生成的随机密码：$RANDOM_PASSWORD"

    if [ -f "/etc/systemd/system/sub-store.service" ]; then
        print_green "Sub-Store 服务已存在，跳过创建。"
    else
        print_green "创建 Sub-Store 系统服务..."
        cat > /etc/systemd/system/sub-store.service <<EOF
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/$RANDOM_PASSWORD"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3000"
ExecStart=/root/.local/share/fnm/fnm exec --using v20.18.0 node /root/sub-store/sub-store.bundle.js
User=root
Group=root
Restart=on-failure
RestartSec=5s
ExecStartPre=/bin/sh -c ulimit -n 51200
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable --now sub-store.service
    fi
}

# 安装 Nginx
install_nginx() {
    if command_exists nginx; then
        print_green "Nginx 已安装，跳过安装。"
    else
        print_green "安装 Nginx..."
        apt update -y
        apt install nginx -y
        systemctl stop nginx
    fi
}

# 获取外网 IP
get_external_ip() {
    curl -s http://whatismyip.akamai.com/
}

# 获取外网 IP 并判断 IPv4/IPv6
get_ip_with_brackets() {
    local IP=$(get_external_ip)
    if [[ $IP =~ : ]]; then
        echo "[$IP]"
    else
        echo "$IP"
    fi
}

# 申请证书
request_certificate() {
    local DOMAIN_NAME=$1
    local CERT_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"

    print_green "检查证书..."

    if [ -f "$CERT_PATH" ]; then
        print_green "证书已存在，跳过申请。"
    else
        print_green "申请 SSL 证书..."
        certbot certonly --standalone -d "$DOMAIN_NAME" --agree-tos --non-interactive --email your-email@example.com
        systemctl start nginx
    fi
}

# 配置 Nginx 反向代理
configure_nginx_reverse_proxy() {
    local DOMAIN_NAME=$1
    local NGINX_CONFIG="/etc/nginx/sites-available/sub-store"

    print_green "配置 Nginx 反向代理..."

    if [ -f "$NGINX_CONFIG" ]; then
        print_green "Nginx 反向代理已配置，跳过。"
    else
        cat > "$NGINX_CONFIG" <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
server {
    listen 80;
    server_name $DOMAIN_NAME;
    return 301 https://$DOMAIN_NAME\$request_uri;
}
EOF
        ln -s "$NGINX_CONFIG" /etc/nginx/sites-enabled/
        nginx -t && systemctl restart nginx
    fi
}

# 提示用户是否配置反向代理
prompt_reverse_proxy() {
    read -p "是否进行反向代理配置？(y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        read -p "请输入反向代理的域名: " DOMAIN_NAME
        install_nginx
        request_certificate "$DOMAIN_NAME"
        configure_nginx_reverse_proxy "$DOMAIN_NAME"
        print_green "反向代理配置完成！访问链接：https://$DOMAIN_NAME"
    else
        EXTERNAL_IP=$(get_ip_with_brackets)
        print_green "访问链接：http://$EXTERNAL_IP:3000"
    fi
}

# 主安装流程
main_installation() {
    install_required_components
    install_fnm
    install_node
    install_pnpm
    install_sub_store
    create_system_service
    prompt_reverse_proxy
}

main_installation
