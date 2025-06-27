#!/bin/bash
set -e  # 出错立即退出

# 工作目录
cd /root/sub-store/ || exit 1

# Telegram 配置
BOT_TOKEN="7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE"
CHAT_ID="7457253104"

SEND_TELEGRAM_MSG() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$1" \
        -d parse_mode="Markdown"
}

SEND_TELEGRAM_MSG "🚀 *Oracle-Singapore-West* 开始更新 Sub-Store..."

# 删除旧文件
rm -rf frontend
rm -f sub-store.bundle.js

# 下载 sub-store.bundle.js
if curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js; then
    echo "✅ 成功下载 sub-store.bundle.js"
else
    SEND_TELEGRAM_MSG "❌ 下载 sub-store.bundle.js 失败，请检查网络或 GitHub 地址是否可用。"
    exit 1
fi

# 下载并解压 dist.zip
if curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip; then
    unzip -o dist.zip
    mv dist frontend
    rm -f dist.zip
    echo "✅ 成功更新前端文件"
else
    SEND_TELEGRAM_MSG "❌ 下载 dist.zip 失败，请检查网络或 GitHub 地址是否可用。"
    exit 1
fi

# 重启服务
if systemctl restart sub-store.service; then
    echo "✅ 成功重启 sub-store.service"
else
    SEND_TELEGRAM_MSG "❌ 重启 sub-store.service 失败，请手动检查服务状态。"
    exit 1
fi

# 通知完成
SEND_TELEGRAM_MSG "✅ *Oracle-Singapore-West* Sub-Store 已成功更新并重启服务！"