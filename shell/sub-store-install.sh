#!/bin/bash

# 设置绿色字体输出函数
print_green() {
    echo -e "\033[32m$1\033[0m"
}

# 更新系统并安装所需组件
install_dependencies() {
    print_green "更新系统并安装所需组件..."
    apt update -y
    apt install unzip curl wget git sudo -y
}

# 安装 FNM 版本管理器
install_fnm() {
    print_green "安装 FNM 版本管理器..."
    curl -fsSL https://fnm.vercel.app/install | bash
    source /root/.bashrc
}

# 安装 Node.js v20.18.0
install_node() {
    print_green "安装 Node.js v20.18.0..."
    fnm install v20.18.0
}

# 安装 PNPM 软件包管理器
install_pnpm() {
    print_green "安装 PNPM 软件包管理器..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    source /root/.bashrc
}

# 安装 Sub-Store
install_substore() {
    print_green "安装 Sub-Store..."

    # 创建文件夹
    mkdir -p /root/sub-store && cd /root/sub-store

    # 拉取 Sub-Store 项目并解压
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip dist.zip && mv dist frontend && rm dist.zip
}

# 创建并配置系统服务
create_service() {
    print_green "创建并配置 Sub-Store 系统服务..."

    # 创建 sub-store.service 文件
    touch /etc/systemd/system/sub-store.service

    # 写入服务配置
    cat > /etc/systemd/system/sub-store.service <<EOF
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/9vUgbmi2oP5v0FevHvuW"
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
}

# 重载服务并启动
start_service() {
    print_green "重载系统服务并启动 Sub-Store 服务..."

    # 重载系统服务
    systemctl daemon-reload

    # 启动服务
    systemctl start sub-store.service

    # 查看服务状态
    systemctl status sub-store.service

    # 设置开机启动
    systemctl enable sub-store.service
}

# 获取外网 IP 地址
get_external_ip() {
    EXTERNAL_IP=$(curl -s https://api.ipify.org)

    # 判断是否是 IPv6
    if [[ $EXTERNAL_IP =~ ":" ]]; then
        # 如果是 IPv6，使用 [] 包裹
        echo "[$EXTERNAL_IP]"
    else
        # 如果是 IPv4，直接返回
        echo "$EXTERNAL_IP"
    fi
}

# 获取 SUB_STORE_FRONTEND_PORT 值（用来构建访问链接）
get_frontend_port() {
    FRONTEND_PORT=$(grep -oP 'Environment="SUB_STORE_FRONTEND_PORT=\K[0-9]+' /etc/systemd/system/sub-store.service)
    echo "$FRONTEND_PORT"
}

# 输出访问链接
output_link() {
    print_green "Sub-Store 已成功安装并启动！"
    EXTERNAL_IP=$(get_external_ip)

    # 获取前端端口号
    FRONTEND_PORT=$(get_frontend_port)

    print_green "请访问以下链接进行使用："
    print_green "http://$EXTERNAL_IP:$FRONTEND_PORT/?api=http://$EXTERNAL_IP:$FRONTEND_PORT/9vUgbmi2oP5v0FevHvuW"
}

# 主执行逻辑
main() {
    install_dependencies
    install_fnm
    install_node
    install_pnpm
    install_substore
    create_service
    start_service
    output_link
}

# 执行主程序
main
