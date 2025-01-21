#!/bin/bash

# 设置可配置的变量
NODE_VERSION="v20.18.0"
FNM_INSTALL_DIR="/root/.local/share/fnm"
SUB_STORE_PATH="/root/sub-store"
SUB_STORE_FRONTEND_PATH="$SUB_STORE_PATH/frontend"
FRONTEND_PORT=3000
BACKEND_PORT=3001
BACKEND_API_HOST="127.0.0.1"
BACKEND_API_PORT=3001
SUB_STORE_BACKEND_PATH="/9vUgbmi2oP5v0FevHvuW"

# 输出日志的函数
log() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

# 错误处理函数
error_exit() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
    exit 1
}

# 更新系统并安装依赖
install_dependencies() {
    log "更新系统并安装依赖组件..."
    apt update -y || error_exit "更新系统失败"
    apt install unzip curl wget git sudo -y || error_exit "安装依赖失败"
}

# 安装 FNM 版本管理器
install_fnm() {
    log "安装 FNM 版本管理器..."
    curl -fsSL https://fnm.vercel.app/install | bash || error_exit "安装 FNM 失败"
    source /root/.bashrc || error_exit "加载 FNM 配置失败"
}

# 使用 FNM 安装指定版本的 Node.js
install_node() {
    log "安装 Node.js ${NODE_VERSION}..."
    fnm install $NODE_VERSION || error_exit "安装 Node.js 失败"
}

# 安装 PNPM 软件包管理器
install_pnpm() {
    log "安装 PNPM 软件包管理器..."
    curl -fsSL https://get.pnpm.io/install.sh | sh - || error_exit "安装 PNPM 失败"
    source /root/.bashrc || error_exit "加载 PNPM 配置失败"
}

# 安装 Sub-Store
install_sub_store() {
    log "创建 Sub-Store 文件夹并下载必要文件..."
    mkdir -p $SUB_STORE_PATH || error_exit "创建文件夹失败"
    cd $SUB_STORE_PATH

    log "拉取 Sub-Store 和 Front-End 项目..."
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js || error_exit "下载 Sub-Store 后端文件失败"
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip || error_exit "下载 Front-End 文件失败"

    log "解压并移动 Front-End 文件..."
    unzip dist.zip && mv dist frontend && rm dist.zip || error_exit "解压 Front-End 文件失败"
}

# 创建并配置 systemd 服务
create_systemd_service() {
    log "创建 systemd 服务配置文件..."
    cat > /etc/systemd/system/sub-store.service <<EOL
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=$SUB_STORE_BACKEND_PATH"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=$SUB_STORE_FRONTEND_PATH"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=$FRONTEND_PORT"
Environment="SUB_STORE_DATA_BASE_PATH=$SUB_STORE_PATH"
Environment="SUB_STORE_BACKEND_API_HOST=$BACKEND_API_HOST"
Environment="SUB_STORE_BACKEND_API_PORT=$BACKEND_API_PORT"
ExecStart=$FNM_INSTALL_DIR/fnm exec --using $NODE_VERSION node $SUB_STORE_PATH/sub-store.bundle.js
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
    if [ $? -ne 0 ]; then
        error_exit "创建 systemd 服务失败"
    fi
}

# 启动并设置 Sub-Store 服务开机自启
start_sub_store_service() {
    log "启动 Sub-Store 服务..."
    systemctl start sub-store.service || error_exit "启动服务失败"
    systemctl status sub-store.service || error_exit "查看服务状态失败"
    systemctl enable sub-store.service || error_exit "设置服务开机自启失败"
}

# 获取外网 IP 地址
get_external_ip() {
    EXTERNAL_IP=$(curl -s ifconfig.me)
    if [ -z "$EXTERNAL_IP" ]; then
        error_exit "无法获取外网 IP 地址"
    fi
    echo $EXTERNAL_IP
}

# 输出访问链接
output_access_link() {
    local ip=$(get_external_ip)
    log "访问 Sub-Store 通过以下链接："
    echo "http://$ip/?api=http://$ip$SUB_STORE_BACKEND_PATH"
}

# 主安装函数
install_sub_store_stack() {
    install_dependencies
    install_fnm
    install_node
    install_pnpm
    install_sub_store
    create_systemd_service
    start_sub_store_service
    output_access_link
}

# 执行安装
install_sub_store_stack
