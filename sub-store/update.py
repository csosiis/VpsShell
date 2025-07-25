#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# 为了让脚本能无需密码重启服务，可能需要配置sudo
# sudo visudo
# 在文件末尾添加 (请将 'ubuntu' 替换为你的实际用户名):
# ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl restart sub-store.service
#
import os
import subprocess
import requests
import logging

# --- 配置区 ---
# 【必填】替换为你的 Telegram Bot Token
TELEGRAM_TOKEN = "7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE"
# 【必填】替换为你的 Telegram Chat ID
TELEGRAM_CHAT_ID = "7457253104"
# 【必填】Sub-Store 的工作目录
WORKING_DIR = "/root/sub-store/"


# --- 日志配置 ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def send_telegram_notification(message):
    """向 Telegram 发送通知"""
    # 只有在提供了 TOKEN 和 CHAT_ID 时才发送
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        logging.warning("Telegram Token 或 Chat ID 未配置，跳过发送通知。")
        return

    api_url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {'chat_id': TELEGRAM_CHAT_ID, 'text': message, 'parse_mode': 'Markdown'}
    try:
        response = requests.post(api_url, json=payload, timeout=10)
        if response.status_code == 200:
            logging.info("Telegram 通知发送成功！")
        else:
            logging.error(f"发送 Telegram 通知失败: {response.text}")
    except Exception as e:
        logging.error(f"发送 Telegram 通知时出现网络错误: {e}")

def run_command(command):
    """在 shell 中执行命令并检查是否成功"""
    logging.info(f"正在执行: {command}")
    # 使用 subprocess.run 来执行命令
    result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
    logging.info(f"命令成功: {command}")
    # 如果有标准输出，则记录
    if result.stdout:
        logging.info(f"输出:\n{result.stdout}")
    # 如果有标准错误输出，也记录（有些程序会把正常信息输出到 stderr）
    if result.stderr:
        logging.warning(f"标准错误输出:\n{result.stderr}")

def main():
    """主执行函数"""
    try:
        # 切换到工作目录
        os.chdir(WORKING_DIR)
        logging.info(f"已切换到工作目录: {os.getcwd()}")
    except FileNotFoundError:
        error_message = f"❌ **处理失败**\n\n目录不存在: `{WORKING_DIR}`"
        logging.error(error_message)
        send_telegram_notification(error_message)
        return

    try:
        # 步骤 1: 更新本地文件
        update_commands = [
            "rm -rf frontend sub-store.bundle.js",
            "curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js",
            "curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip",
            "unzip -o dist.zip && mv dist frontend && rm dist.zip"
        ]
        logging.info("--- 步骤 1/2: 开始更新 Sub-Store 文件 ---")
        for cmd in update_commands:
            run_command(cmd)
        logging.info("--- 文件更新完成 ---")

        # 步骤 2: 重启本地服务
        logging.info("--- 步骤 2/2: 正在重启本地 sub-store 服务 ---")
        # 注意：这里需要sudo权限且可能需要免密配置
        run_command("sudo /bin/systemctl restart sub-store.service")
        logging.info("--- 本地服务重启成功 ---")

        # 发送最终成功通知
        success_message = (
            "✅ **Sub-Store 自动化任务全部完成！**\n\n"
            "1️⃣ 文件已更新到最新版本。\n"
            "2️⃣ **本地Sub-Store服务**已成功重启。"
        )
        send_telegram_notification(success_message)

    except subprocess.CalledProcessError as e:
        # 捕获命令执行失败的错误
        error_details = f"命令 `{e.cmd}` 执行失败。\n\n**错误信息**:\n```\n{e.stderr}\n```"
        error_message = f"❌ **自动化任务失败**\n\n{error_details}"
        logging.error(error_message)
        send_telegram_notification(error_message)
    except Exception as e:
        # 捕获其他未知错误
        error_message = f"❌ **发生未知错误**\n\n**错误详情**:\n```\n{str(e)}\n```"
        logging.error(error_message)
        send_telegram_notification(error_message)

if __name__ == "__main__":
    main()