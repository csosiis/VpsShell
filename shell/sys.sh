#!/bin/bash
clear
# 设置颜色
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[1;31m'
CYAN='\033[1;36m'
RESET='\033[0m'

# 定义所需的依赖项
required_dependencies=("lsb-release" "curl" "hostname" "lscpu" "free" "df" "vnstat" "uptime" "ifconfig" "jq")

function install_dependencies() {
    for dep in "${required_dependencies[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep"; then
            echo "$dep 未安装，正在安装..."
            sudo apt update && sudo apt install -y "$dep"
        else
            echo "$dep 已经安装"
        fi
    done
}

# 显示主菜单
function main_menu() {
    while true; do
        clear
        echo -e "${CYAN}========================================${RESET}"
        echo -e "${CYAN}         Jcole 的 VPS 管理工具       ${RESET}"
        echo -e "${CYAN}========================================${RESET}"
        echo -e "${GREEN} 1. 系统信息查询${RESET}"
        echo -e "${GREEN} 2. 系统清理${RESET}"
        echo -e "${GREEN} 3. 修改主机名${RESET}"
        echo -e "${GREEN} 4. 优化 DNS${RESET}"
        echo -e "${GREEN} 5. 设置网络优先级${RESET}"
        echo -e "${GREEN} 6. 设置 SSH 密钥登录${RESET}"
        echo -e "${GREEN}----------------------------------------${RESET}"
        echo -e "${GREEN} 7. 搭建 Sing-Box 节点${RESET}"
        echo -e "${GREEN} 8. 安装 S-ui${RESET}"
        echo -e "${GREEN} 9. 安装 3X-ui${RESET}"
        echo -e "${GREEN}----------------------------------------${RESET}"
        echo -e "${GREEN} 88. 退出${RESET}"
        echo -e "${GREEN} 00. 更新脚本${RESET}"
        echo -e "${CYAN}========================================${RESET}"
        read -p "请输入选项: " option
        case $option in
            1)
                show_system_info
                ;;
            2)
                clean_system
                ;;
            3)
                change_hostname
                ;;
            4)
                optimize_dns
                ;;
            5)
                set_network_priority
                ;;
            6)
                setup_ssh_key
                ;;
            7)
                setup_singbox
                ;;
            8)
                install_sui
                ;;
            9)
                install_3xui
                ;;
            00)
                update_script
                ;;
            88)
                echo "退出脚本..."
                exit 0
                ;;
            *)
                echo "无效选项，请重新输入。"
                ;;
        esac
    done
}

# 查询系统信息
show_system_info() {
    # [此处省略已有代码]
    echo -e "${CYAN}------------- 系统信息查询 -------------${RESET}"
    # [此处省略已有代码]
}

# 清理系统
clean_system() {
    echo "正在清理无用文件..."
    sudo apt autoremove -y
    sudo apt clean
    echo "系统已清理完毕。"
}

# 修改主机名
change_hostname() {
    read -p "请输入新的主机名: " new_hostname
    sudo hostnamectl set-hostname $new_hostname
    echo "主机名已修改为 $new_hostname。"
}

# 优化 DNS
optimize_dns() {
    echo -e "${CYAN}优化DNS地址...${RESET}"
    sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2a00:1098:2b::1" >> /etc/resolv.conf'
    echo -e "${GREEN}DNS优化完成！${RESET}"
}

# 设置网络优先级
set_network_priority() {
    echo "请选择网络优先级设置:"
    echo "1. IPv6 优先"
    echo "2. IPv4 优先"
    read -p "请输入选择: " choice
    case $choice in
        1)
            echo "正在设置 IPv6 优先..."
            sudo sysctl -w net.ipv6.conf.all.autoconf=1
            sudo sysctl -w net.ipv6.conf.default.autoconf=1
            echo "IPv6 优先已设置。"
            ;;
        2)
            echo "正在设置 IPv4 优先..."
            sudo sysctl -w net.ipv4.conf.all.disable_ipv6=1
            sudo sysctl -w net.ipv4.conf.default.disable_ipv6=1
            echo "IPv4 优先已设置。"
            ;;
        *)
            echo "无效选择。"
            ;;
    esac
}

# 设置 SSH 密钥登录
setup_ssh_key() {
    echo "开始设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnHMbvtoTAZQD8WQttlpIKaD6/RPiY1EMuxXYcDT74b7ZDOZlQ6SYrZZqUuPZKGlSBgY7h5c/OWmgeCWe6huPDUMqIJZVqTSvnJZREuP4VYYgHn96WNDG5Z2YN1di3Nh79DMADCFd7W8xk2yA7o97x4L6asWbSkcIzpB6GiNag2eBb506cWmGlBjQvu4zC4zm2GepLqGO/90hIphtckqaHgM5p/ceKGAJek2d5oBEcvXhFxZG7mDhv2CUwfbp8P9HVM0nNkBTy8QJMCUN2zBc3NhV3WrzwtgCLRgYJPv9kbe9pbXrPSoZOHiv1vWzVDqsY5/0gK8tgmTj1LjBHutNVR1qdtZ7zUQcPIf3jC60/csNFNSxcSV1ouhAuW5YYdeeQKIyAMz2LdAkAgn7jux15XywK/yeIO378uy0P9rAx5dA/S94VCjbtnDoMvyvARJV+RTy9t2YDAZUNb+m28hj38TWO2c1oxpSkj/ecx7GJDkDJ79ldzzs1EyIlyGm51ZHr3FBvjv1EDv6GQIykcHcG84BYMjG4RpGGEWnSNwFbtaeQcOwv7goDM6bQPnPrzkLfbwRHmwhN7fQaHzjiJlbdlKRCTpSTTOd1+Y44bXUa7opmuGw/QZR5T7fsrvmhIVRChf2Yy+9qW+kzhg9zc00nq9WWqvJqAIoBED9es/74Qw== user@hostname"
    echo "$SSH_PUBLIC_KEY" >> ~/.ssh/authorized_keys
    echo "SSH 密钥登录设置完毕。"
}

# 启动依赖安装
install_dependencies

# 启动主菜单
main_menu
