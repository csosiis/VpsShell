#!/bin/bash

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

# 检查 sing-box 是否已安装，如果没有安装，则进行安装
if ! command -v sing-box &> /dev/null; then
    echo -e "${GREEN}sing-box 没有安装，正在安装...${RESET}"
    bash <(curl -fsSL https://sing-box.app/deb-install.sh)
else
    echo -e "${GREEN}sing-box 已安装，继续执行脚本...${RESET}"
fi

# 检查 certbot 是否已安装，如果没有安装，则进行安装
if ! command -v certbot &> /dev/null; then
    echo -e "${GREEN}certbot 没有安装，正在安装...${RESET}"
    sudo apt update
    sudo apt install -y certbot
else
    echo -e "${GREEN}certbot 已安装，继续执行脚本...${RESET}"
fi

# 获取用户输入的域名
read -p "请输入 VLess 域名 (已解析在Cloudflare，注意：如果开启了DNS代理（小黄云）需端口回源): " VLESS_DOMAIN
read -p "请输入 Hysteria2 域名 (已解析在CF并且没有开启DNS代理（小黄云): " HYSTERIA2_DOMAIN

# 获取端口，如果没有输入则使用默认值
read -p "请输入 VLess 端口 (默认 2053): " PORT2
PORT2=${PORT2:-2053}  # 默认值为 2053

read -p "请输入 Hysteria 端口 (默认 23460): " PORT3
PORT3=${PORT3:-23460}  # 默认值为 23460

# 获取自定义节点名称
read -p "请输入自定义节点名称(例如：US1，后面会自动加上协议名：US1-Vless): " NODE_NAME

# 生成 UUID 和 Hysteria2 随机密码
UUID=$(cat /proc/sys/kernel/random/uuid)
HYSTERIA_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9')  # 生成16字节的随机密码

# 生成 obfs 随机密码
OBFS_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9')  # 生成16字节的随机密码

# 配置文件路径
CONFIG_PATH="/etc/sing-box/config.json"

# 检查配置文件是否存在，如果存在则删除
if [ -f "$CONFIG_PATH" ]; then
    echo -e "${GREEN}配置文件已存在，正在删除旧的配置文件...${RESET}"
    rm -f "$CONFIG_PATH"
fi

# 检查域名证书是否存在
VLESS_CERT_PATH="/etc/letsencrypt/live/$VLESS_DOMAIN/fullchain.pem"
VLESS_KEY_PATH="/etc/letsencrypt/live/$VLESS_DOMAIN/privkey.pem"
HYSTERIA2_CERT_PATH="/etc/letsencrypt/live/$HYSTERIA2_DOMAIN/fullchain.pem"
HYSTERIA2_KEY_PATH="/etc/letsencrypt/live/$HYSTERIA2_DOMAIN/privkey.pem"

# 如果证书文件不存在，使用 certbot 申请证书
if [[ ! -f "$VLESS_CERT_PATH" || ! -f "$VLESS_KEY_PATH" ]]; then
    echo -e "${GREEN}VLess 域名证书不存在，正在申请证书...${RESET}"
    # 申请证书
    sudo certbot certonly --standalone -d $VLESS_DOMAIN

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}VLess 域名证书申请成功${RESET}"
    else
        echo -e "${GREEN}VLess 域名证书申请失败，请检查问题并手动申请证书${RESET}"
        exit 1
    fi
fi

if [[ ! -f "$HYSTERIA2_CERT_PATH" || ! -f "$HYSTERIA2_KEY_PATH" ]]; then
    echo -e "${GREEN}Hysteria2 域名证书不存在，正在申请证书...${RESET}"
    # 申请证书
    sudo certbot certonly --standalone -d $HYSTERIA2_DOMAIN

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Hysteria2 域名证书申请成功${RESET}"
    else
        echo -e "${GREEN}Hysteria2 域名证书申请失败，请检查问题并手动申请证书${RESET}"
        exit 1
    fi
fi

echo -e "${GREEN}写入 sing-box 配置文件...$CONFIG_PATH${RESET}"

# 创建配置文件并写入内容
cat <<EOF > $CONFIG_PATH
{
  "log": {
    "level": "info"
  },
  "dns": {},
  "inbounds": [
    {
      "type": "vless",
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "$VLESS_CERT_PATH",
        "key_path": "$VLESS_KEY_PATH",
        "server_name": "$VLESS_DOMAIN"
      },
      "multiplex": {},
      "transport": {
        "type": "ws",
        "early_data_header_name": "Sec-WebSocket-Protocol",
        "path": "/csos",
        "headers": {
          "Host": "$VLESS_DOMAIN"
        }
      },
      "tag": "$NODE_NAME-Vless",  # 自定义节点名称和协议名称组成的 tag
      "listen": "::",
      "listen_port": $PORT2
    },
    {
      "type": "hysteria2",
      "users": [
        {
          "password": "$HYSTERIA_PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "key_path": "$HYSTERIA2_KEY_PATH",
        "server_name": "$HYSTERIA2_DOMAIN",
        "certificate_path": "$HYSTERIA2_CERT_PATH"
      },
      "tag": "$NODE_NAME-Hysteria2",  # 自定义节点名称和协议名称组成的 tag
      "listen": "::",
      "listen_port": $PORT3,
      "up_mbps": 100,
      "down_mbps": 1000,
      "obfs": {
        "type": "salamander",
        "password": "$OBFS_PASSWORD"  # 使用随机生成的 obfs 密码
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
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
EOF

echo -e "${GREEN}配置文件已创建: $CONFIG_PATH${RESET}"

# 重启 sing-box 服务
echo -e "${GREEN}正在重启 sing-box 服务...${RESET}"
sudo systemctl restart sing-box

# 检查服务状态
if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}sing-box 服务已成功重启${RESET}"
else
    echo -e "${GREEN}sing-box 服务重启失败${RESET}"
fi

# 询问是否推送到服务器，默认不推送
read -p "节点搭建完成，是否推送到 sub-store 服务器? (y/n, 默认 n): " PUSH_TO_SERVER
PUSH_TO_SERVER=${PUSH_TO_SERVER:-n}  # 如果没有输入，默认选择 n

if [[ "$PUSH_TO_SERVER" == "y" || "$PUSH_TO_SERVER" == "Y" ]]; then
    # 获取 Token 和修改名称
    read -p "请输入Sub-Store验证 Token: " TOKEN
    read -p "请输入Sub-Store订阅名称: " NAME

    # 节点信息
    NODE_INFO="{
      \"token\": \"$TOKEN\",
      \"name\": \"$NAME\",
      \"vless_link\": \"vless://$UUID@$VLESS_DOMAIN:$PORT2?type=ws&security=tls&sni=$VLESS_DOMAIN&host=$VLESS_DOMAIN&path=%2Fcsos#${NODE_NAME}-Vless\",
      \"hysteria2_link\": \"hysteria2://$HYSTERIA_PASSWORD@$HYSTERIA2_DOMAIN:$PORT3?peer=$HYSTERIA2_DOMAIN&obfs=salamander&obfs-password=$OBFS_PASSWORD&upmbps=100&downmbps=1000#${NODE_NAME}-Hysteria2\"
    }"

    # 目标服务器 URL
    SERVER_URL="https://oregen.wiitwo.eu.org/data"

    # 发送 POST 请求到指定服务器，并带上 Token 进行验证
    echo -e "${GREEN}将节点信息推送到服务器: $SERVER_URL${RESET}"
    response=$(curl -X POST "$SERVER_URL" \
      -H "Content-Type: application/json" \
      -d "$NODE_INFO")

    # 打印服务器响应
    echo -e "${GREEN}服务器响应: $response${RESET}"
    echo ""
    echo -e "${GREEN}节点信息：${RESET}"
    echo -e "${GREEN}---------------------------------------------------------------------------------------------------------------------${RESET}"
    echo ""
    # 输出黄色节点链接
    VLESS_LINK="vless://$UUID@$VLESS_DOMAIN:$PORT2?type=ws&security=tls&sni=$VLESS_DOMAIN&host=$VLESS_DOMAIN&path=%2Fcsos#${NODE_NAME}-Vless"
    echo -e "${YELLOW}$VLESS_LINK${RESET}"

    # 生成 hysteria2 链接
    HYSTERIA2_LINK="hysteria2://$HYSTERIA_PASSWORD@$HYSTERIA2_DOMAIN:$PORT3?peer=$HYSTERIA2_DOMAIN&obfs=salamander&obfs-password=$OBFS_PASSWORD&upmbps=100&downmbps=1000#${NODE_NAME}-Hysteria2"
    echo -e "${YELLOW}$HYSTERIA2_LINK${RESET}"
    echo ""
    echo -e "${GREEN}---------------------------------------------------------------------------------------------------------------------${RESET}"
else
    echo -e "${GREEN}节点信息：${RESET}"
    echo -e "${GREEN}---------------------------------------------------------------------------------------------------------------------${RESET}"
    echo ""
    # 输出黄色节点链接
    VLESS_LINK="vless://$UUID@$VLESS_DOMAIN:$PORT2?type=ws&security=tls&sni=$VLESS_DOMAIN&host=$VLESS_DOMAIN&path=%2Fcsos#${NODE_NAME}-Vless"
    echo -e "${YELLOW}$VLESS_LINK${RESET}"

    # 生成 hysteria2 链接
    HYSTERIA2_LINK="hysteria2://$HYSTERIA_PASSWORD@$HYSTERIA2_DOMAIN:$PORT3?peer=$HYSTERIA2_DOMAIN&obfs=salamander&obfs-password=$OBFS_PASSWORD&upmbps=100&downmbps=1000#${NODE_NAME}-Hysteria2"
    echo -e "${YELLOW}$HYSTERIA2_LINK${RESET}"
    echo ""
    echo -e "${GREEN}---------------------------------------------------------------------------------------------------------------------${RESET}"
fi

# 设置 sing-box 开机启动
echo -e "${GREEN}设置 sing-box 开机启动: systemctl enable sing-box${RESET}"
systemctl enable sing-box

# 查看 sing-box 运行状态
echo -e "${GREEN}查看 sing-box 运行状态: systemctl status sing-box${RESET}"
systemctl status sing-box
