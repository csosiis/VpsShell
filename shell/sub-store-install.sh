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
    print_green "安装所需组件..."
    apt update -y
    apt install unzip curl wget git sudo -y
}

# 安装 FNM 版本管理器
install_fnm() {
    print_green "安装 FNM 版本管理器..."
    curl -fsSL https://fnm.vercel.app/install | bash
    source /root/.bashrc
}

# 安装 Node.js
install_node() {
    print_green "安装 Node.js..."
    fnm install v20.18.0
}

# 安装 PNPM 软件包管理器
install_pnpm() {
    print_green "安装 PNPM 软件包管理器..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    source /root/.bashrc
}

# 安装 Sub-Store
install_sub_store() {
    print_green "安装 Sub-Store..."

    # 创建目录并进入
    mkdir -p /root/sub-store && cd /root/sub-store

    # 拉取项目并解压
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip dist.zip && mv dist frontend && rm dist.zip
}

# 创建随机密码
generate_random_password() {
    # 生成一个26位的随机密码
    echo $(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 26)
}

# 创建 Sub-Store 系统服务
create_system_service() {
    # 生成随机密码
    RANDOM_PASSWORD=$(generate_random_password)
    print_green "生成的随机密码：$RANDOM_PASSWORD"

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
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3000"
Environment="SUB_STORE_DATA_BASE_PATH=/root/sub-store"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=3001"
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
    systemctl start sub-store.service
    systemctl enable sub-store.service
}

# 申请证书
request_certificate() {
    local DOMAIN_NAME=$1
    local CERT_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
    local KEY_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"

    print_green "检查证书..."

    if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
        print_green "证书不存在，正在申请证书..."
        # 检查 80 端口是否被占用
        # 申请证书
        certbot certonly --standalone -d "$DOMAIN_NAME" --agree-tos --non-interactive --email your-email@example.com

        # 检查证书申请是否成功
        if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
            print_green "证书申请成功！"
            systemctl start nginx
        else
            print_green "证书申请失败，请检查 Certbot 配置和 DNS 设置。"
            EXTERNAL_IP=$(get_ip_with_brackets)
            print_green "访问链接：http://$EXTERNAL_IP:3000/?api=http://$EXTERNAL_IP:3000/$RANDOM_PASSWORD"
            systemctl start nginx
            exit 1
        fi

        # 如果 Nginx 已安装，则重新启动 Nginx 服务
        if command_exists nginx; then
            systemctl start nginx
            print_green "Nginx 服务已重新启动。"
        fi
    else
        print_green "证书已存在，路径：$CERT_PATH 和 $KEY_PATH"
    fi
}

# 配置 Nginx 反向代理
configure_nginx_reverse_proxy() {
    local DOMAIN_NAME=$1
    local CERT_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
    local KEY_PATH="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"

    print_green "配置 Nginx 反向代理..."

    cat > /etc/nginx/sites-available/sub-store <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $DOMAIN_NAME;

    # SSL 配置
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;

    # 强制使用 TLS 1.2 或 1.3（提高安全性）
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # 设置 HTTP Strict Transport Security (HSTS)，防止中间人攻击
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # 配置代理到 127.0.0.1:23458 的请求
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;  # 传递原始协议 (HTTP/HTTPS)
        proxy_set_header X-Forwarded-Port $server_port;  # 传递原始端口
    }
}
server {
    if ($host = $DOMAIN_NAME) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80 ;
    listen [::]:80 ;
    server_name $DOMAIN_NAME;
    return 404; # managed by Certbot

}
EOF

    # 启用站点配置并重启 Nginx
    ln -s /etc/nginx/sites-available/sub-store /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx

    print_green "Nginx 反向代理配置完成！"
}

# 安装 Nginx
install_nginx() {
    if ! command_exists nginx; then
        print_green "Nginx 未安装，正在安装 Nginx..."
        apt update -y
        apt install nginx -y
        systemctl stop nginx
    else
        print_green "Nginx 已安装，跳过安装。"
        systemctl stop nginx
    fi
}

# 获取本机外网IP
get_external_ip() {
    IP=$(curl -s http://whatismyip.akamai.com/)
    echo $IP
}

# 获取外网IP并判断IPv4/IPv6
get_ip_with_brackets() {
    local IP=$(get_external_ip)
    if [[ $IP =~ : ]]; then
        echo "[$IP]"
    else
        echo "$IP"
    fi
}

# 提示用户选择是否配置反代
prompt_reverse_proxy() {
    read -p "是否进行反向代理配置？(y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        # 获取用户输入的域名
        read -p "请输入反向代理的域名: " DOMAIN_NAME

        # 安装 Nginx
        install_nginx

        # 申请证书
        request_certificate "$DOMAIN_NAME"

        # 配置 Nginx 反向代理
        configure_nginx_reverse_proxy "$DOMAIN_NAME"

        # 输出反向代理访问链接
        print_green "反向代理配置成功！"
        print_green "访问链接：https://$DOMAIN_NAME/?api=https://$DOMAIN_NAME/$RANDOM_PASSWORD"
    else
        print_green "跳过反向代理配置。"
        # 输出访问链接
        EXTERNAL_IP=$(get_ip_with_brackets)
        print_green "访问链接：http://$EXTERNAL_IP:3000/?api=http://$EXTERNAL_IP:3000/$RANDOM_PASSWORD"
    fi
}

# 主安装流程
main_installation() {
    # 安装所需组件
    install_required_components

    # 安装 FNM 和 Node.js
    install_fnm
    install_node

    # 安装 PNPM
    install_pnpm

    # 安装 Sub-Store
    install_sub_store
    create_system_service

    # 提示是否进行反代设置
    prompt_reverse_proxy
}

# 执行主安装流程
main_installation
