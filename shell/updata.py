#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#sudo visudo
#ubuntu ALL=(ALL) NOPASSWD: /usr/bin/rsync
#ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl restart sub-store.service
import os
import subprocess
import requests
import logging

# --- 配置区 ---
TELEGRAM_TOKEN = "7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE"
TELEGRAM_CHAT_ID = "7457253104"
WORKING_DIR = "/root/sub-store/"

# 【修改】将单个服务器配置改为服务器列表
# 在这里添加您所有需要同步的服务器信息
SERVERS = [
    {
        "name": "Oracle-London(伦敦)",  # 服务器的友好名称，用于日志和通知
        "user": "ubuntu",
        "host": "79.72.72.95",
        "port": "22",
        "ssh_key_path": "/root/.ssh/server",
        "dest_dir": "/root/sub-store/"
    },
    {
        "name": "Oracle-Phoenix(凤凰城)", # 比如 "服务器B"
        "user": "ubuntu",
        "host": "137.131.41.2",
        "port": "22",
        "ssh_key_path": "/root/.ssh/id_ed25519_phoenix",
        "dest_dir": "/root/sub-store/"
    }
    # 如果还有更多服务器，继续在这里添加
]


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
        logging.info("--- 步骤 1/3: 开始更新 Sub-Store 文件 ---")
        for cmd in update_commands:
            run_command(cmd)
        logging.info("--- 文件更新完成 ---")

        # 2. 重启本地服务
        logging.info("--- 步骤 2/3: 正在重启本地 sub-store 服务 ---")
        run_command("systemctl restart sub-store.service")
        logging.info("--- 本地服务重启成功 ---")

        # 【修改】循环处理所有远程服务器
        logging.info("--- 步骤 3/3: 开始同步文件并重启远程服务 ---")

        synced_servers_details = [] # 用于在通知中显示处理详情

        for server in SERVERS:
            server_name = server["name"]
            logging.info(f"--- 正在处理服务器: {server_name} ---")

            # 3a. 镜像同步到服务器
            logging.info(f"开始镜像同步文件到 {server_name}...")
            rsync_command = (
                f'rsync -avzP --delete -e "ssh -p {server["port"]} -i {server["ssh_key_path"]}" '
                f'--rsync-path="sudo rsync" {WORKING_DIR} '
                f'{server["user"]}@{server["host"]}:{server["dest_dir"]}'
            )
            run_command(rsync_command)
            logging.info(f"文件到 {server_name} 的镜像同步成功。")

            # 3b. 重启远程服务器上的服务
            logging.info(f"正在重启 {server_name} 上的 sub-store 服务...")
            remote_restart_command = (
                f'ssh -p {server["port"]} -i {server["ssh_key_path"]} {server["user"]}@{server["host"]} '
                f'"sudo /bin/systemctl restart sub-store.service"'
            )
            run_command(remote_restart_command)
            logging.info(f"{server_name} 上的远程服务重启成功。")

            synced_servers_details.append(f"✅ **{server_name}**: 同步并重启成功")

        logging.info("--- 所有远程服务器处理完毕 ---")

        # 【修改】更新成功消息，动态显示所有处理过的服务器
        remote_servers_status = "\n".join(synced_servers_details)
        success_message = (
            "✅ **Oracle-San Jose Sub-Store 自动化任务全部完成！**\n\n"
            "1️⃣ 文件已更新到最新版本。\n"
            "2️⃣ **本地Sub-Store服务**已成功重启。\n"
            "3️⃣ **远程服务器**同步和重启状态如下:\n"
            f"{remote_servers_status}"
        )
        send_telegram_notification(success_message)

    except subprocess.CalledProcessError as e:
        # 【修改】错误消息中包含服务器信息
        # 注意：这里的错误处理会在第一个失败的服务器处停止。
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