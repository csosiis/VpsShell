#!/bin/bash

# 设置工作目录
WORK_DIR="/root/sub-store"
# Telegram Bot 信息
BOT_TOKEN="7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE"
CHAT_ID="7457253104"

# 发送 Telegram 消息函数
send_telegram_message() {
  local message=$1
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
       -d chat_id=$CHAT_ID \
       -d text="$message"
}

# 进入工作目录
cd "$WORK_DIR" || { send_telegram_message "$(date) - Oregen - 无法进入目录 $WORK_DIR"; exit 1; }

# 输出开始更新日志
echo "$(date) - Oregen - 开始更新 Sub-Store"
send_telegram_message "$(date) - Oregen - 开始更新 Sub-Store"

# 下载最新的 sub-store.bundle.js
curl -fsSL --max-time 300 https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 下载 sub-store.bundle.js 失败"
  exit 1
fi

# 下载最新的 dist.zip
curl -fsSL --max-time 300 https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 下载 dist.zip 失败"
  exit 1
fi

# 解压 dist.zip
unzip dist.zip
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 解压 dist.zip 失败"
  exit 1
fi

# 检查 dist 目录是否存在
if [ ! -d "dist" ]; then
  send_telegram_message "$(date) - Oregen - dist 目录不存在，无法移动"
  exit 1
fi

# 如果 frontend 目录已存在，先删除它
if [ -d "frontend" ]; then
  rm -rf frontend
fi

# 创建 frontend 目录
mkdir -p frontend

# 打印调试信息，查看 dist 目录
echo "$(date) - Oregen - 开始移动 dist 文件夹到 frontend"
ls -l dist  # 查看 dist 目录的内容

# 使用 rsync 将 dist 内容移动到 frontend
rsync -av dist/ frontend/
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 使用 rsync 移动 dist 文件夹失败"
  exit 1
fi

# 删除 dist.zip 文件
rm dist.zip
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 删除 dist.zip 文件失败"
  exit 1
fi

# 删除 dist 目录
rm -rf dist
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 删除 dist 目录失败"
  exit 1
fi

# 重启 sub-store 服务
systemctl restart sub-store.service
if [ $? -ne 0 ]; then
  send_telegram_message "$(date) - Oregen - 重启 sub-store 服务失败"
  exit 1
fi

# 输出更新完成日志
echo "$(date) - Oregen - Sub-Store 更新完成"
send_telegram_message "$(date) - Oregen - Sub-Store 更新完成"