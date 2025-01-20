#!/bin/bash

# 定义全局变量
SUB_STORE_FRONTEND_BACKEND_PATH=""
PROXY_DOMAIN=""
EXTERNAL_IP=""
OPENSSL_CMD=$(command -v openssl)

# 安装依赖项
install_dependencies() {
    echo_green "检查并安装所需组件..."
    apt update -y
    apt install unzip curl wget git sudo openssl nginx certbot -y
}

# 生成随机密码
generate_random_password() {
    if [ -z "$OPENSSL_CMD" ]; then
        echo_green "未安装 openssl，正在安装..."
        apt install openssl -y
    fi
    echo "/$(openssl rand -base64 15 | tr -d '/+')"
}

# 安装并配置 FNM 版本管理器
install_fnm() {
    echo_green "安装 FNM 版本管理器..."
    curl -fsSL https://fnm.vercel.app/install | bash
    source /root/.bashrc
}

# 安装 Node.js
install_node() {
    echo_green "安装 Node.js v20.18.0..."
    fnm install v20.18.0
}

# 安装 PNPM
install_pnpm() {
    echo_green "安装 PNPM 软件包管理器..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    source /root/.bashrc
}

# 安装 Sub-Store
install_sub_store() {
    echo_green "安装 Sub-Store..."
    mkdir -p /root/sub-store && cd /root/sub-store
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip dist.zip && mv dist frontend && rm dist.zip
}

# 创建 systemd 服务
create_service() {
    echo_green "创建 systemd 服务..."
    SERVICE_FILE="/etc/systemd/system/sub-store.service"
    touch $SERVICE_FILE

    SUB_STORE_FRONTEND_BACKEND_PATH=$(generate_random_password)

    cat <<EOL > $SERVICE_FILE
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=$SUB_STORE_FRONTEND_BACKEND_PATH"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3001"
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
EOL
    systemctl daemon-reload
    systemctl start sub-store.service
    systemctl status sub-store.service
    systemctl enable sub-store.service
}

# 获取外部 IP
get_external_ip() {
    EXTERNAL_IP=$(curl -s http://whatismyip.akamai.com/)
}

# 检查是否已存在证书
check_existing_certificate() {
    if [ -d "/etc/letsencrypt/live/$PROXY_DOMAIN" ]; then
        echo_green "域名 $PROXY_DOMAIN 的 SSL 证书已存在。"
        read -p "$(echo_green "是否覆盖现有证书? (Yes/No) 默认是 No: ")" OVERWRITE_CERT
        OVERWRITE_CERT=${OVERWRITE_CERT:-No}

        if [ "$OVERWRITE_CERT" == "No" ]; then
            echo_green "跳过证书申请步骤，继续后续操作。"
            return 0
        else
            echo_green "正在覆盖现有证书..."
            certbot renew --cert-name "$PROXY_DOMAIN"
            if [ $? -ne 0 ]; then
                echo_green "证书覆盖失败，请检查错误日志。"
                exit 1
            fi
            echo_green "证书已更新！"
        fi
    else
        echo_green "域名 $PROXY_DOMAIN 未找到现有证书，开始申请新的证书..."
        certbot certonly --standalone -d "$PROXY_DOMAIN"
        if [ $? -ne 0 ]; then
            echo_green "证书申请失败，请检查域名配置或选择 No。"
            exit 1
        fi
        echo_green "证书申请成功！"
    fi
}

# 更新 Nginx 配置
update_nginx_config() {
    NGINX_CONFIG_FILE="/etc/nginx/sites-enabled/sub-store.conf"
    touch $NGINX_CONFIG_FILE
    chmod 644 $NGINX_CONFIG_FILE

    cat <<EOL > $NGINX_CONFIG_FILE
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name $PROXY_DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$PROXY_DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$PROXY_DOMAIN/privkey.pem;

  location / {
    proxy_pass http://localhost:3001;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOL

    nginx -s reload
    nginx -t
    if [ $? -ne 0 ]; then
        echo_green "Nginx 配置有误，请检查错误日志。"
        exit 1
    fi
}

# 配置反向代理（包含证书检查和申请）
configure_reverse_proxy() {
    get_external_ip
    read -p "$(echo_green "是否为服务设置反向代理 (Yes/No)? 默认是 No: ")" SET_PROXY
    SET_PROXY=${SET_PROXY:-No}

    if [ "$SET_PROXY" == "No" ]; then
        echo_green "请访问链接: http://$EXTERNAL_IP:3001/?api=http://$EXTERNAL_IP:3001$SUB_STORE_FRONTEND_BACKEND_PATH"
    else
        read -p "$(echo_green "请输入反向代理的域名 (确保已在 Cloudflare 中解析): ")" PROXY_DOMAIN
        check_existing_certificate
        install_nginx
        update_nginx_config
    fi
}

# 打印绿色字体
echo_green() {
    echo -e "\033[32m$1\033[0m"
}

# 主程序
main() {
    install_dependencies
    install_fnm
    install_node
    install_pnpm
    install_sub_store
    create_service
    configure_reverse_proxy
}

main
