#!/bin/bash

# 绿色文本输出函数
echo_green() {
  echo -e "\033[32m$1\033[0m"
}

# 步骤 1: 安装所需组件
echo_green "正在静默安装所需组件（unzip curl wget git）..."
sudo apt update -y
sudo apt install unzip curl wget git sudo -y --quiet --show-progress
echo_green "所需组件已成功安装！"

# 步骤 2: 安装 FNM 版本管理器
echo_green "正在安装 FNM 版本管理器..."
curl -fsSL https://fnm.vercel.app/install | bash
source /root/.bashrc
echo_green "FNM 版本管理器已成功安装！"

# 步骤 3: 安装 Node.js v20.18.0
echo_green "正在使用 FNM 安装 Node.js v20.18.0..."
fnm install v20.18.0
fnm use v20.18.0
echo_green "Node.js v20.18.0 已成功安装！"

# 步骤 4: 安装 PNPM 软件包管理器
echo_green "正在安装 PNPM 软件包管理器..."
curl -fsSL https://get.pnpm.io/install.sh | sh -
source /root/.bashrc
echo_green "PNPM 软件包管理器已成功安装！"

# 步骤 5: 安装 Sub-Store
echo_green "正在安装 Sub-Store..."
mkdir -p /root/sub-store && cd /root/sub-store
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip dist.zip
mv dist frontend
rm dist.zip
echo_green "Sub-Store 已成功安装！"

# 步骤 6: 随机生成 SUB_STORE_FRONTEND_BACKEND_PATH
RANDOM_PATH=$(openssl rand -base64 26 | tr -d '/+=')  # 生成长度为26的随机字符串
echo_green "随机生成的 SUB_STORE_FRONTEND_BACKEND_PATH: $RANDOM_PATH"

# 步骤 7: 创建系统服务
echo_green "正在创建 Sub-Store 系统服务..."
cat <<EOF | sudo tee /etc/systemd/system/sub-store.service > /dev/null
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=$RANDOM_PATH"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3001"
Environment="SUB_STORE_DATA_BASE_PATH=/root/sub-store"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=3000"
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

# 重新加载 systemd 服务并启动服务
sudo systemctl daemon-reload
sudo systemctl enable sub-store.service
sudo systemctl start sub-store.service
echo_green "Sub-Store 系统服务已创建并启动！"

# 步骤 8: 配置 Nginx 反向代理并申请 SSL 证书
read -p "是否需要配置 Nginx 反向代理？(y/n): " SET_NGINX

if [[ "$SET_NGINX" == "y" ]]; then
  # 配置 Nginx 反向代理
  read -p "请输入你的反代域名: " DOMAIN

  # 检测域名证书是否存在
  if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo_green "域名证书不存在，正在申请证书..."

    # 安装 certbot 和 Nginx 插件
    sudo apt update -y
    sudo apt install certbot python3-certbot-nginx -y

    # 申请证书
    sudo certbot --nginx -d $DOMAIN --agree-tos --non-interactive --email your-email@example.com

    echo_green "证书申请完成！"
  else
    echo_green "域名证书已存在，无需重新申请。"
  fi

  # 检测 Nginx 是否已安装
  if ! command -v nginx &> /dev/null
  then
    echo_green "Nginx 未安装，正在安装 Nginx..."
    sudo apt install nginx -y
    echo_green "Nginx 安装完成！"
  else
    echo_green "Nginx 已安装，继续配置反向代理..."
  fi

  # 配置 Nginx 反向代理
  echo_green "正在配置 Nginx 反向代理..."

  # 生成 Nginx 配置文件
  cat <<EOF | sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  location / {
    proxy_pass http://127.0.0.1:3001;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

  # 启用 Nginx 配置并重新加载服务
  sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
  sudo nginx -t  # 检查配置是否正确
  sudo systemctl restart nginx  # 重启 Nginx 服务

  echo_green "Nginx 反向代理配置完成，$DOMAIN 已成功设置为反代域名！"

  # 输出 Sub-Store 访问地址
  ACCESS_URL="https://$DOMAIN/?api=https://$DOMAIN/$RANDOM_PATH"
  echo_green "Sub-Store 访问地址: $ACCESS_URL"

else
  # 如果不配置 Nginx 反向代理
  LOCAL_IP=$(hostname -I | awk '{print $1}')  # 获取本机 IP 地址
  ACCESS_URL="http://$LOCAL_IP/?api=http://$LOCAL_IP/$RANDOM_PATH"
  echo_green "Sub-Store 访问地址: $ACCESS_URL"
fi
