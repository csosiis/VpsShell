#!/bin/bash

# ==============================================================================
# 整合后的管理脚本
# 参考了 sub-store.sh 的风格，合并了 sys.sh 和 singbox.sh 的功能
# ==============================================================================

# --- 全局变量和颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# 系统和 Sing-Box 配置
CONFIG_FILE="/etc/sing-box/config.json"
SCRIPT_PATH=$(realpath "$0")
SERVICE_NAME="sing-box"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# --- 日志函数 ---
log_info() { echo -e "${GREEN}[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
press_any_key() { echo ""; read -n 1 -s -r -p "按任意键继续..."; }

# --- 检查 root 权限 ---
check_root() { if [ "$(id -u)" -ne 0 ]; then log_error "此脚本必须以 root 用户身份运行。"; exit 1; fi; }

# --- 主菜单 ---
show_main_menu() {
    clear
    echo "===================================="
    echo "      系统管理脚本 - 主菜单       "
    echo "===================================="
    echo "1. 安装 Sing-Box"
    echo "2. 查看系统信息"
    echo "3. 配置网络"
    echo "4. 更新脚本"
    echo "5. 设置快捷启动"
    echo "88. 退出"
    echo "===================================="
    read -p "请输入选项: " choice
    case $choice in
        1) install_sing_box ;;
        2) show_system_info ;;
        3) configure_network ;;
        4) update_script ;;
        5) setup_shortcut ;;
        88) exit 0 ;;
        *) log_error "无效的选项！"; show_main_menu ;;
    esac
}

# --- 安装 Sing-Box ---
install_sing_box() {
    log_info "正在安装 Sing-Box..."
    if ! command -v sing-box &> /dev/null; then
        bash <(curl -fsSL https://sing-box.app/deb-install.sh)
    else
        log_info "Sing-Box 已安装，跳过安装过程。"
    fi
    systemctl enable sing-box.service
    log_info "Sing-Box 安装完成！"
    press_any_key
    show_main_menu
}

# --- 查看系统信息 ---
show_system_info() {
    log_info "显示系统信息..."
    hostname_info=$(hostname)
    os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^ *//')
    kernel_info=$(uname -r)
    memory_info=$(free -h | grep Mem | awk '{print $3 "/" $2 " (" $3/$2*100 "%)"}')
    disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')
    log_info "主机名: $hostname_info"
    log_info "操作系统: $os_info"
    log_info "内存使用: $memory_info"
    log_info "硬盘占用: $disk_info"
    press_any_key
    show_main_menu
}

# --- 配置网络 ---
configure_network() {
    log_info "设置网络配置..."
    echo "请输入新的时区配置："
    read -p "时区 (e.g., Asia/Shanghai): " timezone
    sudo timedatectl set-timezone "$timezone"
    log_info "时区已设置为 $timezone"
    press_any_key
    show_main_menu
}

# --- 更新脚本 ---
update_script() {
    log_info "正在更新脚本..."
    curl -fsSL https://raw.githubusercontent.com/csosiis/VpsShell/main/shell/sys.sh -o sys.sh
    chmod +x sys.sh
    ./sys.sh
    log_info "脚本更新完成！"
    press_any_key
    show_main_menu
}

# --- 设置快捷启动 ---
setup_shortcut() {
    log_info "设置快捷启动命令..."
    ln -sf "$SCRIPT_PATH" /usr/local/bin/sb
    chmod +x /usr/local/bin/sb
    log_info "快捷命令 sb 已设置，使用 sb 运行脚本。"
    press_any_key
    show_main_menu
}

# 启动脚本
check_root
show_main_menu
