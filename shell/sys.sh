#!/bin/bash
clear

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 定义所需的依赖项
required_dependencies=("lsb-release" "curl" "hostname" "lscpu" "free" "df" "vnstat" "uptime" "ifconfig" "jq")

# 检查并安装缺失的依赖
function install_dependencies() {
    for dep in "${required_dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}$dep 未安装，正在安装...${RESET}"
            sudo apt update && sudo apt install -y "$dep"
        else
            echo -e "${GREEN}$dep 已经安装${RESET}"
        fi
    done
}

# 主菜单
function main_menu() {
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

    case $choice in
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
            update_script
            ;;
        5)
            optimize_dns
            ;;
        6)
            set_network_priority
            ;;
        7)
            setup_ssh_key
            ;;
        88)
            echo -e "${RED}退出脚本...${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入。${RESET}"
            main_menu
            ;;
    esac
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
    echo -e "${CYAN}------------- 系统信息查询 -------------${RESET}"
    echo -e "${GREEN}主机名:       ${YELLOW}$hostname_info${RESET}"
    echo -e "${GREEN}系统版本:     ${YELLOW}$os_info${RESET}"
    echo -e "${GREEN}Linux版本:    ${YELLOW}$kernel_info${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    echo -e "${GREEN}CPU架构:      ${YELLOW}$cpu_arch${RESET}"
    echo -e "${GREEN}CPU型号:      ${YELLOW}$cpu_model${RESET}"
    echo -e "${GREEN}CPU核心数:    ${YELLOW}$cpu_cores${RESET}"
    echo -e "${GREEN}CPU频率:      ${YELLOW}$cpu_freq GHz${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    echo -e "${GREEN}CPU占用:      ${YELLOW}$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')${RESET}"
    echo -e "${GREEN}系统负载:     ${YELLOW}$load_info${RESET}"
    echo -e "${GREEN}物理内存:     ${YELLOW}$memory_info${RESET}"
    echo -e "${GREEN}硬盘占用:     ${YELLOW}$disk_info${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    echo -e "${GREEN}总接收:       ${YELLOW}$(echo $net_info | awk '{print $2}')${RESET}"
    echo -e "${GREEN}总发送:       ${YELLOW}$(echo $net_info | awk '{print $4}')${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    echo -e "${GREEN}网络算法:     ${YELLOW}$net_algo${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    echo -e "${GREEN}运营商:       ${YELLOW}$ip_info${RESET}"
    echo -e "${GREEN}IPv4地址:     ${YELLOW}$ip_addr${RESET}"
    echo -e "${GREEN}DNS地址:      ${YELLOW}$dns_info${RESET}"
    echo -e "${GREEN}地理位置:     ${YELLOW}$geo_info${RESET}"
    echo -e "${GREEN}系统时间:     ${YELLOW}$timezone $current_time${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    echo -e "${GREEN}运行时长:     ${YELLOW}$uptime_info${RESET}"
    echo -e "${CYAN}------------------------------------${RESET}"
    wait_for_key_to_main_menu
}

# 等待用户输入回到主菜单
function wait_for_key_to_main_menu() {
    echo -e "${CYAN}按任意键返回主菜单...${RESET}"
    read -n 1
    main_menu
}

# 清理系统
function clean_system() {
    echo "正在清理无用文件..."
    sudo apt autoremove -y
    sudo apt clean
    echo "系统已清理完毕。"
    wait_for_key_to_main_menu
}

# 修改服务器名字
function change_hostname() {
    read -p "请输入新的主机名: " new_hostname
    sudo hostnamectl set-hostname "$new_hostname"
    echo "主机名已修改为 $new_hostname。"
    wait_for_key_to_main_menu
}

# 更新脚本
function update_script() {
    echo "正在更新脚本..."
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
    if [ -f sys.sh ]; then
        echo "正在删除旧的 sys.sh 文件..."
        rm sys.sh
    fi
    $DOWNLOAD_CMD https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sys.sh
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络连接或下载源。"
        return 1
    fi
    chmod +x sys.sh
    ./sys.sh
    if [ $? -ne 0 ]; then
        echo "脚本执行失败，请检查 sys.sh 内容。"
        return 1
    fi
    echo "脚本更新完成。"
    wait_for_key_to_main_menu
}

# 优化 DNS
function optimize_dns() {
    echo -e "${CYAN}优化DNS地址...${RESET}"
    sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2a00:1098:2b::1" >> /etc/resolv.conf'
    sudo bash -c 'echo "nameserver 2a00:1098:2c::1" >> /etc/resolv.conf'
    echo -e "${GREEN}DNS优化完成！${RESET}"
    wait_for_key_to_main_menu
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
    wait_for_key_to_main_menu
}

# 设置SSH密钥登录
function setup_ssh_key() {
    echo "开始设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDfUz2lUMpPR1xe6X6W6OZGUM9HY6ATUtzw9FfzO2Ah4trMjtkqrZnFdodA3BdIpZfu5JqYIcZZ4Ru8pqqXZZFpu0nsPq0IzdCktaxwIpWvBqjZ9XB0EvAHlxToFxRxHm6hKGAx0By7m1mrrijG9vjfGpVgElrtnu9J7Sg05AbllLMR0mjy63dHzp1ZjzJ_J8STtD1LBhxyZZaQQ5aeAVUl3ZfnK1cCHTjTm1c05zHsbSY= user@hostname"
    echo "$SSH_PUBLIC_KEY" >> ~/.ssh/authorized_keys
    echo "SSH 密钥登录设置完毕。"
    wait_for_key_to_main_menu
}

# 安装依赖项
install_dependencies

# 启动主菜单
main_menu
