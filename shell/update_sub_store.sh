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

# 错误处理函数，发送消息并退出
handle_error() {
  local message=$1
  send_telegram_message "$message"
  echo "$message"
  exit 1
}

# 删除文件或目录并检查是否删除成功
delete_file() {
  local file=$1
  if [ -e "$file" ]; then
    if [ -d "$file" ]; then
      # 如果是目录，使用 rm -rf 删除
      rm -rf "$file" || handle_error "$(date) - San Jose - 删除目录失败: $file"
      echo "$(date) - San Jose - 成功删除目录 $file"
    else
      # 如果是文件，使用 rm -f 删除
      rm -f "$file" || handle_error "$(date) - San Jose - 删除文件失败: $file"
      echo "$(date) - San Jose - 成功删除文件 $file"
    fi
  else
    echo "$(date) - San Jose - 文件或目录 $file 不存在，跳过删除"
  fi
}

# 进入工作目录
cd "$WORK_DIR" || handle_error "$(date) - San Jose - 无法进入目录 $WORK_DIR"

# 输出并发送开始更新日志
message="$(date) - San Jose - 开始更新 Sub-Store"
echo "$message"
send_telegram_message "$message"

# 下载文件的通用函数
download_file() {
  local url=$1
  local output=$2
  curl -fsSL --max-time 300 "$url" -o "$output" || handle_error "$(date) - San Jose - 下载文件失败: $url"
}

# 下载最新的 sub-store.bundle.js
download_file "https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js" "sub-store.bundle.js"

# 下载最新的 dist.zip
download_file "https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip" "dist.zip"

# 解压 dist.zip
unzip dist.zip || handle_error "$(date) - San Jose - 解压 dist.zip 失败"

# 检查 dist 目录是否存在
if [ ! -d "dist" ]; then
  handle_error "$(date) - San Jose - dist 目录不存在，无法移动"
fi

# 如果 frontend 目录已存在，先删除它
rm -rf frontend

# 创建 frontend 目录
mkdir -p frontend

# 打印调试信息，查看 dist 目录
echo "$(date) - San Jose - 开始移动 dist 文件夹到 frontend"
ls -l dist  # 查看 dist 目录的内容

# 使用 rsync 将 dist 内容移动到 frontend
rsync -av dist/ frontend/ || handle_error "$(date) - San Jose - 使用 rsync 移动 dist 文件夹失败"

# 删除临时文件
delete_file "dist.zip"
delete_file "dist"

# 重启 sub-store 服务
systemctl restart sub-store.service || handle_error "$(date) - San Jose - 重启 sub-store 服务失败"

# 输出并发送更新完成日志
message="$(date) - San Jose - Sub-Store 更新完成"
echo "$message"
send_telegram_message "$message"
