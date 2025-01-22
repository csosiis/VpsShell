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

function show_main_menu() {
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
                exit
                ;;
            *)
                echo "无效选项，请重新输入。"
                ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}
# 检查并安装缺失的依赖
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
function wait_for_key_to_main_menu() {
    echo -n "按任意键返回主菜单..."
    read -n 1 -s
    clear
    show_main_menu
}
# 查询系统信息
function show_system_info() {
    # 主机名
    hostname_info=$(hostname)

    # 操作系统和版本
    os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^ *//')

    # Linux内核版本
    kernel_info=$(uname -r)

    # CPU架构和型号
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_model=$(lscpu | grep "Model name" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_cores=$(lscpu | grep "CPU(s)" | awk -F: '{print $2}' | sed 's/^ *//')
    cpu_freq=$(lscpu | grep "CPU MHz" | awk -F: '{print $2}' | sed 's/^ *//')

    # 系统负载
    load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')

    # 内存使用情况
    memory_info=$(free -h | grep Mem | awk '{print $3 "/" $2 " (" $3/$2*100 "%)"}')

    # 硬盘使用情况
    disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')

    # 网络接收和发送量
    net_info=$(vnstat --oneline | awk -F\; '{print "接收: " $2 " 发送: " $3}')

    # 网络算法
    net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)

    # 运营商信息
    ip_info=$(curl -s http://ip-api.com/json | jq -r '.org')

    # IP 地址
    ip_addr=$(hostname -I)

    # DNS 地址
    dns_info=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')

    # 地理位置和时区
    geo_info=$(curl -s http://ip-api.com/json | jq -r '.city', '.country')
    timezone=$(timedatectl show --property=Timezone --value)

    # 系统运行时间
    uptime_info=$(uptime -p)

    # 当前时间
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    clear
    # 输出所有信息
    echo "------------- 系统信息查询 -------------"
    echo "主机名:       $hostname_info"
    echo "系统版本:     $os_info"
    echo "Linux版本:    $kernel_info"
    echo "------------------------------------"
    echo "CPU架构:      $cpu_arch"
    echo "CPU型号:      $cpu_model"
    echo "CPU核心数:    $cpu_cores"
    echo "CPU频率:      $cpu_freq GHz"
    echo "------------------------------------"
    echo "CPU占用:      $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')"
    echo "系统负载:     $load_info"
    echo "物理内存:     $memory_info"
    echo "硬盘占用:     $disk_info"
    echo "------------------------------------"
    echo "总接收:       $(echo $net_info | awk '{print $2}')"
    echo "总发送:       $(echo $net_info | awk '{print $4}')"
    echo "------------------------------------"
    echo "网络算法:     $net_algo"
    echo "------------------------------------"
    echo "运营商:       $ip_info"
    echo "IPv4地址:     $ip_addr"
    echo "DNS地址:      $dns_info"
    echo "地理位置:     $geo_info"
    echo "系统时间:     $timezone $current_time"
    echo "------------------------------------"
    echo "运行时长:     $uptime_info"
    echo "------------------------------------"
    wait_for_key_to_main_menu
}


# 清理系统
function clean_system() {
    echo "正在清理无用文件..."
    sudo apt autoremove -y
    sudo apt clean
    echo "系统已清理完毕。"
}

# 修改服务器名字
function change_hostname() {
    read -p "请输入新的主机名: " new_hostname
    sudo hostnamectl set-hostname $new_hostname
    echo "主机名已修改为 $new_hostname。"
}

# 更新脚本
function update_script() {
    echo "正在更新脚本..."

    # 检查 wget 是否存在
    if ! command -v wget &> /dev/null; then
        echo "wget 未安装，尝试使用 curl 下载文件..."
        if ! command -v curl &> /dev/null; then
            echo "curl 也未安装，请手动安装 wget 或 curl。"
            return 1
        fi
        DOWNLOAD_CMD="curl -L -o sys.sh"
    else
        DOWNLOAD_CMD="wget -O sys.sh"
    fi

    # 确认删除文件
    if [ -f sys.sh ]; then
        echo "正在删除旧的 sys.sh 文件..."
        rm sys.sh
    else
        echo "未找到 sys.sh 文件，跳过删除步骤。"
    fi

    # 下载新的 sys.sh
    $DOWNLOAD_CMD https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sys.sh
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络连接或下载源。"
        return 1
    fi

    # 添加执行权限
    chmod +x sys.sh

    # 执行更新后的脚本
    ./sys.sh
    if [ $? -ne 0 ]; then
        echo "脚本执行失败，请检查 sys.sh 内容。"
        return 1
    fi

    echo "脚本更新完成。"
}

# 优化 DNS
function optimize_dns() {
   echo -e "${CYAN}优化DNS地址...${RESET}"
    # 设置优化后的 DNS 地址
    sudo bash -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2a00:1098:2b::1" > /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2a00:1098:2c::1" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2a01:4f8:c2c:123f::1" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2606:4700:4700::1111" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2001:4860:4860::8888" >> /etc/resolv.conf'
    echo -e "${GREEN}DNS优化完成！${RESET}
    "
}

# 设置网络优先级
function set_network_priority() {
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

# 设置SSH密钥登录
function setup_ssh_key() {
    echo "
    开始设置 SSH 密钥登录..."

    # 确保 SSH 密钥目录存在
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

    # 将用户提供的公钥添加到 authorized_keys
    SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnHMbvtoTAZQD8WQttlpIKaD6/RPiY1EMuxXYcDT74b7ZDOZlQ6SYrZZqUuPZKGlSBgY7h5c/OWmgeCWe6huPDUMqIJZVqTSvnJZREuP4VYYgHn96WNDG5Z2YN1di3Nh79DMADCFd7W8xk2yA7o97x4L6asWbSkcIzpB6GiNag2eBb506cWmGlBjQvu4zC4zm2GepLqGO/90hIphtckqaHgM5p/ceKGAJek2d5oBEcvXhFxZG7mDhv2CUwfbp8P9HVM0nNkBTy8QJMCUN2zBc3NhV3WrzwtgCLRgYJPv9kbe9pbXrPSoZOHiv1vWzVDqsY5/0gK8tgmTj1LjBHutNVR1qdtZ7zUQcPIf3jC60/csNFNSxcSV1ouhAuW5YYdeeQKIyAMz2LdAkAgn7jux15XywK/yeIO378uy0P9rAx5dA/S94VCjbtnDoMvyvARJV+RTy9t2YDAZUNb+m28hj38TWO2c1oxpSkj/ecx7GJDkDJ79ldzzs1EyIlyGm51ZHr3FBvjv1EDv6GQIykcHcG84BYMjG4RpGGEWnSNwFbtaeQcOwv7goDM6bQPnPrzkLfbwRHmwhN7fQaHzjiJlbdlKRCTpSTTOd1+Y44bXUa7opmuGw/QZR5T7fsrvmhIVRChf2Yy+9qW+kzhg9zc00nq9WWqvJqAIoBED9es/74Qw== csos@vip.qq.com"
    echo "$SSH_PUBLIC_KEY" >> ~/.ssh/authorized_keys
    echo "公钥已添加到 authorized_keys 文件中。"

    # 配置 SSH 服务，允许密钥登录并禁用密码登录
    echo "确保 SSH 配置文件允许密钥登录..."
    sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd  # 重启 SSH 服务

    echo "SSH 密钥登录设置完成。"
}

# 搭建 Sing-Box 节点
function setup_singbox() {
    echo "开始搭建 sing-sox 节点... "
    wget https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sing-box-install.sh
    chmod +x sing-box-install.sh
    ./sing-box-install.sh
    rm sing-box-install.sh
    echo "sing-box 节点搭完成。
    "
}

# 安装S-ui
function install_sui() {
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
    rm install.sh
}

# 安装3X-ui
function install_3xui() {
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    rm install.sh
}

show_main_menu