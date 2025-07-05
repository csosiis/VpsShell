#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import subprocess
import requests
import logging

# --- 配置区 ---
TELEGRAM_TOKEN = "7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE"
TELEGRAM_CHAT_ID = "7457253104"
WORKING_DIR = "/root/sub-store/"

# 备份服务器配置
REMOTE_USER = "ubuntu"
REMOTE_HOST = "140.245.36.228"
REMOTE_PORT = "22"
SSH_KEY_PATH = "/root/.ssh/server"
REMOTE_DEST_DIR = "/root/sub-store/"

# --- 日志配置 ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def send_telegram_notification(message):
    """向 Telegram 发送通知"""
    api_url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {'chat_id': TELEGRAM_CHAT_ID, 'text': message, 'parse_mode': 'Markdown'}
    try:
        response = requests.post(api_url, json=payload, timeout=10)
        if response.status_code == 200: logging.info("Telegram 通知发送成功！")
        else: logging.error(f"发送 Telegram 通知失败: {response.text}")
    except Exception as e: logging.error(f"发送 Telegram 通知时出现网络错误: {e}")

def run_command(command):
    """在 shell 中执行命令并检查是否成功"""
    logging.info(f"正在执行: {command}")
    result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
    logging.info(f"命令成功: {command}")
    if result.stdout: logging.info(f"输出:\n{result.stdout}")
    if result.stderr: logging.warning(f"标准错误输出:\n{result.stderr}")

def main():
    """主执行函数"""
    try:
        os.chdir(WORKING_DIR)
        logging.info(f"已切换到工作目录: {os.getcwd()}")
    except FileNotFoundError:
        error_message = f"❌ **处理失败**\n\n目录不存在: `{WORKING_DIR}`"
        logging.error(error_message)
        send_telegram_notification(error_message)
        return

    try:
        # 1. 更新文件
        update_commands = [
            "rm -rf frontend sub-store.bundle.js",
            "curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js",
            "curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip",
            "unzip -o dist.zip && mv dist frontend && rm dist.zip"
        ]
        logging.info("--- 步骤 1/4: 开始更新 Sub-Store 文件 ---")
        for cmd in update_commands:
            run_command(cmd)
        logging.info("--- 文件更新完成 ---")

        # 2. 重启本地服务
        logging.info("--- 步骤 2/4: 正在重启本地 sub-store 服务 ---")
        run_command("systemctl restart sub-store.service")
        logging.info("--- 本地服务重启成功 ---")

        # 3. 镜像同步到另一台服务器
        logging.info("--- 步骤 3/4: 开始镜像同步文件到备份服务器 ---")
        # ✨ 新增 --delete 选项，实现镜像同步
        rsync_command = (
            f'rsync -avzP --delete -e "ssh -p {REMOTE_PORT} -i {SSH_KEY_PATH}" '
            f'--rsync-path="sudo rsync" {WORKING_DIR} '
            f'{REMOTE_USER}@{REMOTE_HOST}:{REMOTE_DEST_DIR}'
        )
        run_command(rsync_command)
        logging.info("--- 文件镜像同步成功 ---")

        # 4. ✨ 新增功能：重启远程服务器上的服务
        logging.info("--- 步骤 4/4: 正在重启远程服务器上的 sub-store 服务 ---")
        remote_restart_command = (
            f'ssh -p {REMOTE_PORT} -i {SSH_KEY_PATH} {REMOTE_USER}@{REMOTE_HOST} '
            f'"sudo /bin/systemctl restart sub-store.service"'
        )
        run_command(remote_restart_command)
        logging.info("--- 远程服务重启成功 ---")

        # 5. 发送最终成功通知
        # ✨ 更新了成功消息
        success_message = (
            "✅ **Oracle-San Jose Sub-Store 自动化任务全部完成！**\n\n"
            "1️⃣ 文件已更新到最新版本。\n"
            "2️⃣ **本地Sub-Store服务**已成功重启。\n"
            f"3️⃣ 文件已**镜像同步**到Oralce-Singapore West。\n"
            "4️⃣ **远程Sub-Store服务**已成功重启。"
        )
        send_telegram_notification(success_message)

    except subprocess.CalledProcessError as e:
        error_details = f"命令 `{e.cmd}` 执行失败。\n\n**错误信息**:\n```\n{e.stderr}\n```"
        error_message = f"❌ **自动化任务失败**\n\n{error_details}"
        logging.error(error_message)
        send_telegram_notification(error_message)
    except Exception as e:
        error_message = f"❌ **发生未知错误**\n\n**错误详情**:\n```\n{str(e)}\n```"
        logging.error(error_message)
        send_telegram_notification(error_message)

if __name__ == "__main__":
    main()