#!/bin/bash
clear
# 设置颜色
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[1;31m'
CYAN='\033[1;36m'
RESET='\033[0m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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
        echo -e "${GREEN} 7. 设置系统时区${RESET}"
        echo -e "${GREEN} 8. 设置快捷键${RESET}"
        echo -e "${GREEN}----------------------------------------${RESET}"
        echo -e "${GREEN} 9. Sing-Box管理${RESET}"
        echo -e "${GREEN} 10. 安装 S-ui${RESET}"
        echo -e "${GREEN} 11. 安装 3X-ui${RESET}"
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
                set_timezone
                ;;
            8)
                set_shortcut
                ;;
            9)
                show_menu
                ;;
            10)
                install_sui
                ;;
            11)
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
    echo -e "${CYAN}-------------------- 系统信息查询 ----------------------${RESET}"
    echo -e "${GREEN}主机名:       $hostname_info${RESET}"
    echo -e "${GREEN}系统版本:     $os_info${RESET}"
    echo -e "${GREEN}Linux版本:    $kernel_info${RESET}"
    echo -e "${CYAN}-------------------------------------------------------${RESET}"
    echo -e "${GREEN}CPU架构:      $cpu_arch${RESET}"
    echo -e "${GREEN}CPU型号:      $cpu_model${RESET}"
    echo -e "${GREEN}CPU核心数:    $cpu_cores${RESET}"
    echo -e "${GREEN}CPU频率:      $cpu_freq GHz${RESET}"
    echo -e "${CYAN}-------------------------------------------------------${RESET}"
    echo -e "${GREEN}CPU占用:      $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')${RESET}"
    echo -e "${GREEN}系统负载:     $load_info${RESET}"
    echo -e "${GREEN}物理内存:     $memory_info${RESET}"
    echo -e "${GREEN}硬盘占用:     $disk_info${RESET}"
    echo -e "${CYAN}-------------------------------------------------------${RESET}"
    echo -e "${GREEN}总接收:       $(echo $net_info | awk '{print $2}')${RESET}"
    echo -e "${GREEN}总发送:       $(echo $net_info | awk '{print $4}')${RESET}"
    echo -e "${CYAN}-------------------------------------------------------${RESET}"
    echo -e "${GREEN}网络算法:     $net_algo${RESET}"
    echo -e "${CYAN}-------------------------------------------------------${RESET}"
    echo -e "${GREEN}运营商:       $ip_info${RESET}"
    echo -e "${GREEN}IPv4地址:     $ip_addr${RESET}"
    echo -e "${GREEN}DNS地址:      $dns_info${RESET}"
    echo -e "${GREEN}地理位置:     $geo_info${RESET}"
    echo -e "${GREEN}系统时间:     $timezone $current_time${RESET}"
    echo -e "${CYAN}--------------------------------------------------${RESET}"
    echo -e "${GREEN}运行时长:     $uptime_info${RESET}"
    echo -e "${CYAN}--------------------------------------------------${RESET}"
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
    echo -e "${CYAN}修改主机名...${RESET}"
    # 输入新主机名
    read -p "请输入新的主机名: " new_hostname
    # 获取当前的主机名
    current_hostname=$(hostname)
    # 检查新的主机名是否与当前主机名相同
    if [ "$new_hostname" == "$current_hostname" ]; then
        echo -e "${YELLOW}新主机名与当前主机名相同，无需修改。${RESET}"
        return
    fi
    # 修改当前的主机名
    sudo hostnamectl set-hostname "$new_hostname"
    # 更新 /etc/hostname 文件
    echo "$new_hostname" | sudo tee /etc/hostname > /dev/null
    # 更新 /etc/hosts 文件
    sudo sed -i "s/^127.0.1.1[[:space:]]\+${current_hostname}/127.0.1.1\t$new_hostname/" /etc/hosts
    # 输出修改后的主机名
    echo -e "${CYAN}主机名修改完成！新的主机名是：${RESET} $new_hostname"
    # 显示当前的主机名
    echo -e "${CYAN}当前的主机名是：${RESET} $(hostname)"
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

    # 检查IPv6支持
    ipv6_support=$(ping6 -c 1 google.com > /dev/null 2>&1; echo $?)

    # 清空当前的 DNS 配置文件
    sudo bash -c 'echo "" > /etc/resolv.conf'

    # 如果支持IPv6，配置IPv6 DNS 地址（优先）
    if [ $ipv6_support -eq 0 ]; then
        echo -e "${CYAN}检测到IPv6支持，配置IPv6优先的DNS...${RESET}"
        # 配置IPv6 DNS 地址
        sudo bash -c 'echo "nameserver 2a00:1098:2b::1" >> /etc/resolv.conf'
        sudo bash -c 'echo "nameserver 2a00:1098:2c::1" >> /etc/resolv.conf'
        sudo bash -c 'echo "nameserver 2a01:4f8:c2c:123f::1" >> /etc/resolv.conf'
        sudo bash -c 'echo "nameserver 2606:4700:4700::1111" >> /etc/resolv.conf'
        sudo bash -c 'echo "nameserver 2001:4860:4860::8888" >> /etc/resolv.conf'

        # 配置IPv4 DNS 地址（备用）
        sudo bash -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'
        sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'

    else
        # 如果不支持IPv6，则只配置IPv4 DNS 地址
        echo -e "${CYAN}未检测到IPv6支持，配置IPv4 DNS...${RESET}"
        # 配置IPv4 DNS 地址
        sudo bash -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'
        sudo bash -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
    fi

    # 输出当前的DNS配置
    echo -e "${CYAN}当前的DNS配置如下：${RESET}"
    cat /etc/resolv.conf

    # 提示DNS优化完成
    echo -e "${GREEN}DNS优化完成！${RESET}"
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

# 设置系统时区
function set_timezone() {
    echo -e "${CYAN}设置系统时区...${RESET}"

    # 显示当前时区
    current_timezone=$(timedatectl show --property=Timezone --value)
    echo -e "${CYAN}当前系统时区是: ${RESET}$current_timezone"

    # 提供时区选择列表
    echo -e "${CYAN}请选择新的时区：${RESET}"
    echo -e "1. Asia/Shanghai (上海)"
    echo -e "2. Europe/London (伦敦)"
    echo -e "3. America/New_York (纽约)"
    echo -e "4. Australia/Sydney (悉尼)"
    echo -e "5. Asia/Tokyo (东京)"
    echo -e "6. UTC (协调世界时)"
    echo -e "7. Europe/Berlin (柏林)"
    echo -e "8. Africa/Nairobi (内罗毕)"
    echo -e "9. America/Los_Angeles (洛杉矶)"
    echo -e "10. Asia/Kolkata (加尔各答)"
    echo -e "11. Europe/Paris (巴黎)"
    echo -e "12. America/Chicago (芝加哥)"

    # 获取用户输入的选项
    read -p "请输入对应的数字选择时区: " timezone_choice

    # 设置对应的时区
    case $timezone_choice in
        1)
            timezone="Asia/Shanghai"
            ;;
        2)
            timezone="Europe/London"
            ;;
        3)
            timezone="America/New_York"
            ;;
        4)
            timezone="Australia/Sydney"
            ;;
        5)
            timezone="Asia/Tokyo"
            ;;
        6)
            timezone="UTC"
            ;;
        7)
            timezone="Europe/Berlin"
            ;;
        8)
            timezone="Africa/Nairobi"
            ;;
        9)
            timezone="America/Los_Angeles"
            ;;
        10)
            timezone="Asia/Kolkata"
            ;;
        11)
            timezone="Europe/Paris"
            ;;
        12)
            timezone="America/Chicago"
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择。${RESET}"
            return
            ;;
    esac

    # 设置新的时区
    sudo timedatectl set-timezone "$timezone"

    # 确认设置成功
    echo -e "${GREEN}时区已成功设置为：${RESET}$timezone"

    # 输出新的时区
    new_timezone=$(timedatectl show --property=Timezone --value)
    echo -e "${CYAN}当前系统时区已更新为: ${RESET}$new_timezone"
}
#!/bin/bash

# 设置快捷键执行脚本的方法
function set_shortcut() {
    # 获取用户输入的快捷键和脚本路径
    local shortcut_key=$1
    local script_path=$2

    # 检查脚本是否存在
    if [[ ! -f "$script_path" ]]; then
        echo "脚本文件不存在: $script_path"
        return 1
    fi

    # 获取用户的bashrc文件路径
    local bashrc_file="$HOME/.bashrc"

    # 检查 .bashrc 文件是否存在
    if [[ ! -f "$bashrc_file" ]]; then
        echo "未找到 .bashrc 文件"
        return 1
    fi

    # 创建 bind 命令
    local bind_command="bind '\"\\C-$shortcut_key\":\"$script_path\\n\"'"

    # 将 bind 命令添加到 .bashrc 文件
    echo "$bind_command" >> "$bashrc_file"

    # 使修改生效
    source "$bashrc_file"

    echo "快捷键 Ctrl + $shortcut_key 已设置为执行脚本: $script_path"
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
import json
import base64
# 全局变量定义配置文件路径
config_file="/etc/sing-box/config.json"

# 输出函数
function echo_color() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    WHITE='\033[1;37m'
    NC='\033[0m' # 无色
    local color=$1
    local message=$2
    case $color in
        red)
            echo -e "\n${RED}* $message ${NC}"
            ;;
        green)
            echo -e "\n${GREEN}$message${NC}"
            ;;
        yellow)
            echo -e "\n${YELLOW}* $message ${NC}"
            ;;
        white)
            echo -e "\n${WHITE}$message${NC}"
            ;;
        *)
            echo -e "\n${WHITE}$message${NC}"  # 默认白色
            ;;
    esac
}
# 主菜单
function show_menu() {
    clear
    echo "==============================="
    echo -e "\n           Sing-Box"
    echo -e "\n==============================="
    echo -e "\n1. 安装Sing-Box"
    echo -e "\n2. 新增节点信息"
    echo -e "\n3. 管理节点信息"
    echo -e "\n==============================="
    echo -e "\n88. 卸载Sing-Box"
    echo -e "\n00. 退出脚本"
    echo -e "\n==============================="
    echo
    read -p "请选择操作 (1-5): " choice
    case $choice in
        1) install_sing_box ;;
        2)
            check_and_install_sing_box  # 检查是否安装 Sing-Box
            add_node
            ;;
        3)
            check_and_install_sing_box  # 检查是否安装 Sing-Box
            view_node_info
            ;;
        88)
            check_and_install_sing_box  # 检查是否安装 Sing-Box
            uninstall_sing_box
            ;;
        00) exit 0 ;;
        *) echo "无效的选择，请重新选择！" && read -p "按 Enter 键返回..." && show_menu ;;
    esac
}
# 检查 Sing-Box 是否已安装
function check_and_install_sing_box() {
    if ! command -v sing-box &> /dev/null; then
        echo_color yellow "Sing-Box 尚未安装。"
        echo
        read -p "您是否希望先安装 Sing-Box？(y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            install_sing_box
        else
            echo_color white "按任意键返回主菜单..."
            read -n 1 -s -r
            show_menu
        fi
    fi
}
# 安装 Sing-Box
function install_sing_box() {

    # 检查 Sing-Box 是否已安装
    if command -v sing-box &> /dev/null; then
        echo_color green "Sing-Box 已经安装，跳过安装过程。"
        echo
        read -n 1 -s -r -p "按任意键返回主菜单..."
        show_menu  # 返回主菜单
    fi

    echo_color green "Sing-Box 未安装，正在安装..."

    # 检查 curl 是否已安装，如果没有则安装
    if ! command -v curl &> /dev/null; then
        echo_color green "curl 未安装，正在安装..."
        apt update && apt install -y curl
        if ! command -v curl &> /dev/null; then
            echo_red "curl 安装失败，请检查网络或包管理器设置。"
            exit 1
        fi
    fi

    # 安装 Sing-Box
    if ! bash <(curl -fsSL https://sing-box.app/deb-install.sh) > install_log.txt 2>&1; then
        echo_red "Sing-Box 安装失败，请检查 install_log.txt 文件。"
        exit 1
    fi

    # 检查安装是否成功
    if ! command -v sing-box &> /dev/null; then
        echo_red "Sing-Box 安装失败，无法找到 sing-box 命令。"
        exit 1
    fi

    echo_color green "Sing-Box 安装成功！"

    # 配置文件目录和文件路径
    config_dir="/etc/sing-box"
    config_file="$config_dir/config.json"

    # 创建配置目录
    if [ ! -d "$config_dir" ]; then
        echo_color green "Sing-Box 配置目录不存在，正在创建..."
        mkdir -p "$config_dir" || { echo_red "创建目录失败！"; exit 1; }
    fi

    # 创建 config.json 文件
    if [ ! -f "$config_file" ]; then
        #echo_color green "config.json 文件不存在，正在创建..."
        touch "$config_file" || { echo_red "创建文件失败！"; exit 1; }
    fi

    # 写入配置内容到 config.json
    #echo_color green "正在创建 Sing-Box 配置文件..."
    cat > "$config_file" <<EOL
{
  "log": {
    "level": "info"
  },
  "dns": {},
  "ntp": null,
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      }
    ]
  }
}
EOL

    if [ $? -ne 0 ]; then
        echo_red "写入配置文件失败！"
        exit 1
    fi

    #echo_color green "config.json 文件已创建并写入内容：$config_file"

    # 安装完成后返回主菜单
    echo_color green "Sing-Box配置文件初始化完成！"
    echo
    read -p "按 Enter 键返回主菜单..." && show_menu
}
# 安装缺失的依赖
function install_dependencies() {
    # 检查并安装 uuidgen
    if ! command -v uuidgen &>/dev/null; then
        echo "uuidgen 未找到，正在安装..."
        apt-get update
        apt-get install -y uuid-runtime
    fi

    # 检查并安装 jq
    if ! command -v jq &>/dev/null; then
        echo "jq 未找到，正在安装..."
        apt-get update
        apt-get install -y jq
    fi
}
# 生成随机端口号
function generate_random_port() {
    # 生成一个 1024 到 65535 之间的随机端口
    echo $((RANDOM % 64512 + 1024))
}
# 随机生成密码函数
function generate_random_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c 20
}

# 申请域名证书并处理 80 端口被占用的情况
function apply_ssl_certificate() {
    local domain_name="$1"
    local stopped_services=()  # 用来记录停止的服务

    # 检测 Nginx 和 Apache 服务是否正在运行，如果在运行则停止
    if systemctl is-active --quiet nginx; then
        echo -e "\nNginx 正在运行，停止 Nginx 服务...\n"
        systemctl stop nginx
        stopped_services+=("nginx")
    fi

    if systemctl is-active --quiet apache2; then
        echo "\nApache2 正在运行，停止 Apache2 服务...\n"
        systemctl stop apache2
        stopped_services+=("apache2")
    fi

    # 确保 80 端口开放，释放 80 端口
    if command -v ufw &> /dev/null; then
        echo_color green "正在释放 80 端口，确保域名验证通过..."
        ufw allow 80/tcp
    fi

    # 使用 Certbot 申请证书
    echo_color green "正在申请证书...\n"
    certbot certonly --standalone --preferred-challenges http -d "$domain_name"

    # 检查证书是否成功申请
    cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"

    if [[ -f "$cert_path" && -f "$key_path" ]]; then
        echo_color green "证书申请成功！"
        echo_color green "证书路径：$cert_path"
        echo_color green "密钥路径：$key_path"
        # 配置证书的自动续期
        echo_color white "配置证书自动续期..."
        # 通过 cron 配置自动续期，每 12 小时检查证书是否需要续期
        (crontab -l ; echo "0 */12 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
        # 完成证书申请并配置自动续期，返回
        echo_color green "证书配置和自动续期设置完成！"
        # 重启之前停止的服务
        if [[ ${#stopped_services[@]} -gt 0 ]]; then
            for service in "${stopped_services[@]}"; do
                echo "正在重启 $service 服务..."
                systemctl start "$service"
            done
        fi
    else
        echo_color red "证书申请失败，请检查日志。"
        # 证书申请失败，重启停止的服务
        if [[ ${#stopped_services[@]} -gt 0 ]]; then
            for service in "${stopped_services[@]}"; do
                #echo "正在重启 $service 服务..."
                systemctl start "$service"
            done
        fi
        echo
        read -n 1 -s -r -p "按任意键返回新增节点菜单..."
        add_node  # 返回新增节点菜单
        return 1
    fi
}

# Cloudflare 域名和配置的方法
function get_cloudflare_domain_and_config() {
    echo
    # 获取输入的域名并验证格式
    while true; do
        read -p "请输入解析在Cloudflare域名（用于 TLS 加密认证）：" domain_name
        # 检查域名是否为空
        if [[ -z "$domain_name" ]]; then
            echo "域名不能为空，请重新输入。"
            continue
        fi

        # 验证域名格式是否正确
        if ! echo "$domain_name" | grep -P "^[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9-]{1,63})*\.[A-Za-z]{2,}$" > /dev/null; then
            echo "无效的域名格式，请重新输入。"
            continue
        fi

        break
    done

    # 根据传入的 type_flag 值判断是否需要显示 Cloudflare 提示
    if [[ $1 -eq 2 ]]; then
        echo_color yellow "注意：如果你的域名开启DNS代理（小黄云）请关闭，否则节点不通。"
         echo_color yellow "开启了防火墙需要手动放行端口！"
    else
        echo_color yellow "注意：如果你的域名开启DNS代理（小黄云），那么你需要在Cloudflare回源端口。"
        echo_color yellow "443  2053    2083    2087    2096    8443 不需要回源"
        echo_color yellow "开启了防火墙需要手动放行端口！"
    fi

    echo

    # 根据传入的 type_flag 值设置端口类型和提示信息
    while true; do
        if [[ $1 -eq 2 ]]; then
            read -p "请输入一个 UDP 端口（回车默认自动生成一个随机端口）：" port  # 当传入2时，提示输入 UDP 端口
        else
            read -p "请输入一个 TCP 端口（回车默认自动生成一个随机端口）：" port  # 其他情况，提示输入 TCP 端口
        fi

        # 如果端口为空，生成随机端口
        if [[ -z "$port" ]]; then
            if [[ $1 -eq 2 ]]; then
                port=$(generate_random_port)  # 如果是 UDP 类型，生成 UDP 随机端口
                echo -e "\n生成的随机 UDP 端口是：$port"
            else
                port=$(generate_random_port)  # 否则生成 TCP 随机端口
                echo -e "\n生成的随机 TCP 端口是：$port"
            fi
            break
        fi

        # 验证端口是否合法
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            echo "无效的端口号，请输入一个 1 到 65535 之间的端口。"
        else
            break
        fi
    done

    echo

    # 询问自定义节点名称
    read -p "请输入自定义节点名称（例如：香港-Huawei）： " custom_tag

    echo

    # 检查证书是否存在，如果不存在则申请
    cert_dir="/etc/letsencrypt/live/$domain_name"
    if [[ ! -d "$cert_dir" ]]; then
        echo_color green "证书不存在，正在申请证书..."
        apply_ssl_certificate "$domain_name"
    else
        echo_color green "证书已存在，跳过证书申请。"
    fi

    echo

    # 生成 UUID
    uuid=$(uuidgen)

    # 获取证书路径
    cert_path="$cert_dir/fullchain.pem"
    key_path="$cert_dir/privkey.pem"

    echo

    # 根据传入的 type_flag 值设置 tag 和协议
    case $1 in
        1)
            tag="${custom_tag}-Vless"
            ;;
        2)
            tag="${custom_tag}-Hysteria2"
            ;;
        3)
            tag="${custom_tag}-Vmess"
            ;;
        4)
            tag="${custom_tag}-Trojan"
            ;;
        *)
            # 根据参数的值选择默认协议
            case $1 in
                1)
                    default_protocol="Vless"
                    ;;
                2)
                    default_protocol="Hysteria2"
                    ;;
                3)
                    default_protocol="Vmess"
                    ;;
                4)
                    default_protocol="Trojan"
                    ;;
                *)
                    default_protocol="Vless"  # 默认值是Vless
                    ;;
            esac
            echo "无效的类型，使用默认的标签：$domain_name-$default_protocol"
            tag="${domain_name}-$default_protocol"
            ;;
    esac
}
# 新增节点
function add_node() {
    install_dependencies
    clear
    echo "==============================="
    echo -e "\n       请选择协议类型"
    echo -e "\n==============================="
    echo -e "\n1. Vless"
    echo -e "\n2. Hysteria2"
    echo -e "\n3. Vmess"
    echo -e "\n4. Trojan"
    #echo -e "\n5. SOCKS5"
    echo -e "\n==============================="
    echo -e "\n11. 查看节点"
    echo -e "\n12. 推送节点"
    echo -e "\n13. 删除节点"
    echo -e "\n==============================="
    echo -e "\n00. 返回主菜单"
    echo -e "\n88. 退出脚本"
    echo -e "\n==============================="
    echo
    read -p "请选择操作编号： " choice
    case $choice in
        1) add_vless_node ;;
        2) add_hysteria2_node ;;
        3) add_vmess_node ;;
        4) add_trojan_node ;;
        11) view_node_info ;;
        12) push_nodes ;;
        13) delete_nodes ;;
        #5) add_socks5_node ;;
        00) show_menu ;;
        88) exit ;;
        *) echo "无效的选择，请重新选择！" && read -p "按 Enter 键返回..." && add_node ;;
    esac
}


# 处理节点配置生成链接
function add_protocol_node() {
    # 获取协议名称作为参数
    protocol=$1

    # 如果配置文件不存在，创建文件
    if [[ ! -f "$config_file" ]]; then
        echo "配置文件不存在，创建新文件：$config_file"
        touch "$config_file"
    fi

    jq --argjson new_config "$config" '.inbounds += [$new_config]' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    # 根据传入的协议选择不同的配置
    case $protocol in
        Vless)
            node_link="vless://$uuid@$domain_name:$port?type=ws&security=tls&sni=$domain_name&host=$domain_name&path=%2Fcsos#${tag}"
            ;;
        Hysteria2)
            node_link="hysteria2://$password@$domain_name:$port?upmbps=100&downmbps=1000&sni=$domain_name&obfs=salamander&obfs-password=$obfs_password#${tag}"
            ;;
        Vmess)
            vmess_link="{
              \"v\": \"2\",
              \"ps\": \"$tag\",
              \"add\": \"$domain_name\",
              \"port\": $port,
              \"id\": \"$uuid\",
              \"aid\": \"0\",
              \"net\": \"ws\",
              \"type\": \"none\",
              \"host\": \"$domain_name\",
              \"path\": \"/csos\",
              \"tls\": \"tls\"
            }"
            base64_vmess_link=$(echo -n "$vmess_link" | base64 | tr -d '\n')
            node_link="vmess://$base64_vmess_link"
            ;;
        Trojan)
            node_link="trojan://$password@$domain_name:$port?type=ws&security=tls&sni=$domain_name&host=$domain_name&path=%2Fcsos#${tag}"
            ;;
        *)
            echo "无效的协议类型！"
            return 1
            ;;
    esac

    # 输出节点链接，并且前后添加空行
    echo "------------------------------------------------------------------------------------------------------"
    echo -e "\n\n\e[32m$node_link\e[0m\n\n"
    echo "------------------------------------------------------------------------------------------------------"

    # 保存节点链接到文件
    echo "$node_link" >> /etc/sing-box/nodes_links.txt

    # 重启 sing-box 使配置生效
    systemctl restart sing-box
    echo
    echo "配置成功并重启 sing-box。"
    echo "sing-box 运行状态"
    systemctl status sing-box
    echo
    read -p "按 Enter 键返回菜单..." && add_node
}

# 新增 Vless 节点
function add_vless_node() {
    get_cloudflare_domain_and_config 1
    # 配置 Vless 节点的 JSON
    echo -e "\n生成 Vless 节点配置..."

    # 生成节点配置
    config="{
      \"type\": \"vless\",
      \"users\": [
        {
          \"uuid\": \"$uuid\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"key_path\": \"$key_path\",
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\"
      },
      \"multiplex\": {},
      \"transport\": {
        \"type\": \"ws\",
        \"early_data_header_name\": \"Sec-WebSocket-Protocol\",
        \"path\": \"/csos\",
        \"headers\": {
          \"Host\": \"$domain_name\"
        }
      },
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port
    }"

    add_protocol_node Vless
}
# 新增 Hysteria2 节点
function add_hysteria2_node() {
    get_cloudflare_domain_and_config 2

    # 生成随机密码
    password=$(generate_random_password)
    obfs_password=$(generate_random_password)

    # 配置 Hysteria2 节点的 JSON
    echo "配置 Hysteria2 节点..."

    # 生成节点配置
    config="{
      \"type\": \"hysteria2\",
      \"users\": [
        {
          \"password\": \"$password\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"key_path\": \"$key_path\",
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\"
      },
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port,
      \"up_mbps\": 100,
      \"down_mbps\": 1000,
      \"obfs\": {
        \"type\": \"salamander\",
        \"password\": \"$obfs_password\"
      }
    }"

    add_protocol_node Hysteria2
}
# 新增 Vmess 节点
function add_vmess_node() {
    get_cloudflare_domain_and_config 3
    # 配置 Vmess 入站节点的 JSON 格式
    echo "配置 Vmess 入站节点..."

    # 生成 vmess 入站节点配置
    config="{
      \"type\": \"vmess\",
      \"users\": [
        {
          \"name\": \"$custom_name\",
          \"uuid\": \"$uuid\",
          \"alterId\": 0
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"key_path\": \"$key_path\",
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\"
      },
      \"multiplex\": {},
      \"transport\": {
        \"type\": \"ws\",
        \"early_data_header_name\": \"Sec-WebSocket-Protocol\",
        \"path\": \"/csos\",
        \"headers\": {
          \"Host\": \"$domain_name\"
        }
      },
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port
    }"

    add_protocol_node Vmess
}
# 添加 Trojan 节点
function add_trojan_node() {
    get_cloudflare_domain_and_config 4

    password=$(generate_random_password)
    echo "生成的密码是：$password"

    # 配置 Trojan 入站节点的 JSON 格式
    echo "配置 Trojan 入站节点..."

    # 生成 trojan 入站节点配置
    config="{
      \"type\": \"trojan\",
      \"users\": [
        {
          \"name\": \"$custom_name\",
          \"password\": \"$password\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"key_path\": \"$key_path\",
        \"server_name\": \"$domain_name\",
        \"certificate_path\": \"$cert_path\"
      },
      \"multiplex\": {},
      \"transport\": {
        \"type\": \"ws\",
        \"early_data_header_name\": \"Sec-WebSocket-Protocol\",
        \"path\": \"/csos\",
        \"headers\": {
          \"Host\": \"$domain_name\"
        }
      },
      \"tag\": \"$tag\",
      \"listen\": \"::\",
      \"listen_port\": $port
    }"
    add_protocol_node Trojan
}

# 添加 SOCKS5 节点
function add_socks5_node() {
    echo "请输入 SOCKS5 节点配置文件路径（如：/path/to/socks5-node-config.json）："
    read -p "配置文件路径: " node_config

    # 检查配置文件是否存在
    if [ ! -f "$node_config" ]; then
        echo "配置文件不存在，请检查路径并重试。"
        read -p "按 Enter 键返回..." && add_node
        return
    fi

    # 将配置文件复制到 Sing-Box 配置目录
    echo "正在将 SOCKS5 配置文件复制到 /etc/sing-box/..."
    cp "$node_config" /etc/sing-box/

    # 重启 Sing-Box 服务以加载新配置
    echo "正在重启 Sing-Box 服务..."
    systemctl restart sing-box

    # 检查 Sing-Box 服务是否正常启动
    if systemctl is-active --quiet sing-box; then
        echo "SOCKS5 节点配置已成功添加，并且 Sing-Box 服务已重启！"
    else
        echo "Sing-Box 服务启动失败，请检查日志并重试。"
    fi

    # 返回主菜单
    read -p "按 Enter 键返回主菜单..." && show_menu
}

function uninstall_telegram_config() {
    # 删除 Telegram 配置信息
    rm -f /etc/sing-box/telegram-bot-config.txt
    echo -e "\nTelegram 配置信息已删除。"
}
# 选择节点的函数
function select_nodes() {
    node_file="/etc/sing-box/nodes_links.txt"
    if [[ ! -f "$node_file" ]]; then
        echo -e "\n\e[31m节点文件不存在！\e[0m"
        return 1
    fi
    mapfile -t node_lines < "$node_file"

    # 提示选择推送方式（单个节点或所有节点）
    echo -e "\n请选择推送的节点："
    echo -e "\n\e[32m1. 推送单个/多个节点  2. 推送所有节点  00.返回主菜单  88.退出脚本\e[0m\n"
    read -p "请输入选择：" push_choice

    # 处理推送方式
    case $push_choice in
        1)
            # 提示选择要推送的单个节点
            echo -e "\n请选择要推送的节点（用空格分隔多个节点）："
            for i in "${!node_lines[@]}"; do
                line="${node_lines[$i]}"
                node_protocol=$(echo "$line" | awk -F' ' '{print $1}')  # 假设协议在节点信息的第一部分
                node_name=""
                tag=""

                if [[ "$node_protocol" =~ ^vmess:// ]]; then
                    # 清理回车和换行符
                    clean_line=$(echo "$line" | tr -d '\r\n')

                    # 对 Vmess 链接进行解码
                    decoded_vmess=$(echo "$clean_line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null)

                    if [[ $? -ne 0 ]]; then
                        echo -e "\e[31mVmess 链接解码失败：$line\e[0m"
                        return 1
                    fi

                    # 提取节点名称和 tag
                    node_name=$(echo "$decoded_vmess" | jq -r '.ps // "默认名称"')
                    tag=$(echo "$decoded_vmess" | jq -r '.tag // ""')  # 如果没有 tag，使用默认值

                    # 如果没有 tag，则使用节点名称作为默认 tag
                    if [[ -z "$tag" ]]; then
                        tag="$node_name"
                    fi
                else
                    # 非 Vmess 协议，直接使用行内容
                    # 其他类型的节点直接使用 # 后面的内容
                    node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
                    tag=$node_name
                fi
                echo -e "\n\e[32m$((i + 1)). $node_name\e[0m"
            done
            echo
            echo -n "请输入节点编号："
            read -a selected_nodes
            ;;

        2)
            # 推送所有节点
            selected_nodes=()  # 初始化空数组
            for i in "${!node_lines[@]}"; do
                selected_nodes+=($((i + 1)))  # 添加所有节点的索引
            done

            # 打印 selected_nodes 的内容
            #echo "选中的节点编号：${selected_nodes[@]}"

            ;;
        00)
            push_nodes
            ;;
        88)
            exit
            ;;
        *)
            echo -e "\e[31m无效的选择，返回主菜单\e[0m"
            show_menu  # 返回主菜单
            ;;
    esac
}
# 推送到 Telegram 的函数
function push_to_telegram() {
    select_nodes  # 调用选择节点的函数

    # 打印选中的节点编号，确保选中的节点编号正确
    #echo "选中的节点编号：${selected_nodes[@]}"

    # 检查是否是第一次推送到 Telegram Bot
    if [[ ! -f "/etc/sing-box/telegram-bot-config.txt" ]]; then
        echo -e "\n第一次推送到 Telegram Bot，请输入 Telegram Bot 信息："
        echo -n "请输入 Telegram Bot API Token: "
        read tg_api_token
        echo -n "请输入 Telegram Chat ID: "
        read tg_chat_id
        # 保存 Telegram Bot 配置信息
        echo "tg_api_token=$tg_api_token" > /etc/sing-box/telegram-bot-config.txt
        echo "tg_chat_id=$tg_chat_id" >> /etc/sing-box/telegram-bot-config.txt
        echo -e "\nTelegram Bot 配置信息已保存。"
    else
        # 读取已保存的 Telegram Bot 配置信息
        source /etc/sing-box/telegram-bot-config.txt
    fi

    # 调试输出，确保读取的 chat_id 正确
    echo -e "\n将使用以下 chat_id 进行推送：$tg_chat_id"

    # 如果选中推送所有节点，则确保选中的节点包含全部节点
    if [[ "$push_choice" == "2" ]]; then
        selected_nodes=($(seq 1 ${#node_lines[@]}))  # 推送所有节点
    fi

    # 打印选中的节点编号（调试用）
    #echo "选中的所有节点编号：${selected_nodes[@]}"

    # 推送选中的节点到 Telegram Bot
    for node_index in "${selected_nodes[@]}"; do
        node_index=$((node_index - 1))  # 调整为从0开始的索引
        if [[ $node_index -ge 0 && $node_index -lt ${#node_lines[@]} ]]; then
            node_info="${node_lines[$node_index]}"

            # 判断是否是 Vmess 节点
            if [[ "$node_info" =~ ^vmess:// ]]; then
                clean_node=$(echo "$node_info" | sed 's/^vmess:\/\///')  # 移除前缀
                decoded_node=$(echo "$clean_node" | base64 --decode)  # 解码 Base64

                # 提取节点名称（ps字段）
                node_name=$(echo "$decoded_node" | jq -r '.ps // "默认名称"')
            else
                # 处理其他类型节点
                node_name=$(echo "$node_info" | sed 's/.*#\(.*\)/\1/')  # 假设节点名称在#后面
            fi

            echo -e "\n推送节点：$node_name 到 Telegram Bot"
            # 使用 curl 命令将节点推送到 Telegram Bot
            response=$(curl -s -X POST "https://api.telegram.org/bot$tg_api_token/sendMessage" \
                 -d chat_id="$tg_chat_id" \
                 -d text="节点推送：$node_name - ${node_lines[$node_index]}")

            # 判断推送是否成功
            if [[ $(echo "$response" | jq -r '.ok') == "false" ]]; then
                echo -e "\e[31m推送失败：${response}\e[0m"
                echo -e "推送失败，是否需要重新配置 Telegram Bot 信息？（y/n）"
                read user_response
                if [[ "$user_response" == "y" || "$user_response" == "Y" ]]; then
                    uninstall_telegram_config  # 删除旧的 Telegram 配置
                    echo -e "已删除旧的配置，请重新输入 Telegram Bot 信息。"
                    push_to_telegram  # 重新配置并执行推送
                else
                    echo "返回主菜单。"
                    show_menu  # 返回主菜单
                fi
            else
                echo -e "\n\e[32m节点推送成功！\e[0m"
            fi
        else
            echo -e "\e[31m无效的节点编号：$node_index\e[0m"
        fi
    done

    show_action_menu
}
# 推送到Sub-Store
function push_to_sub_store() {
    select_nodes  # 调用选择节点的函数

    if [[ ! -f "/etc/sing-box/sub-store-config.txt" ]]; then
        echo "第一次推送到 Sub-Store，请输入 Sub-Store 信息："
        read -p "Sub-Store 地址: " sub_store_url
        read -p "Sub-Store API 密钥: " sub_store_api_key
        read -p "Sub-Store Subs: " sub_store_subs

        # 保存 Sub-Store 配置信息
        echo "sub_store_url=$sub_store_url" > /etc/sing-box/sub-store-config.txt
        echo "sub_store_api_key=$sub_store_api_key" >> /etc/sing-box/sub-store-config.txt
        echo "sub_store_subs=$sub_store_subs" >> /etc/sing-box/sub-store-config.txt
    else
        # 读取已保存的 Sub-Store 配置信息
        source /etc/sing-box/sub-store-config.txt
    fi

    # 遍历选中的节点
    #echo "选中的节点编号：${selected_nodes[@]}"
    links=()  # 初始化一个空数组，用于存储所有节点的链接
    for node_index in "${selected_nodes[@]}"; do
        node_index=$((node_index - 1))
        if [[ $node_index -ge 0 && $node_index -lt ${#node_lines[@]} ]]; then
            node_info="${node_lines[$node_index]}"
            node_name=$(echo "$node_info" | sed 's/.*#\(.*\)/\1/')
            # 将节点的链接部分提取出来，并按换行符分割成数组
            mapfile -t node_links <<< "$(echo "$node_info" | sed 's/^.*# //')"
            # 将当前节点的链接添加到总的链接数组中
            links+=("${node_links[@]}")
        fi
    done

    # 将 links 数组中的元素用逗号分隔，并用双引号包裹
    links_str=""
    for link in "${links[@]}"; do
      links_str="$links_str$link\n"
    done

    node_json="{
        \"token\": \"$sub_store_api_key\",
        \"name\": \"$sub_store_subs\",
        \"link\": \"$links_str\"
    }"
    #echo "$links_str"

    # 打印调试信息
    #echo -e "${GREEN}将节点信息推送到 Sub-Store: $sub_store_url${RESET}"

    # 推送到 Sub-Store
    response=$(curl -s -X POST "$sub_store_url" \
        -H "Content-Type: application/json" \
        -d "$node_json")

    # 检查推送结果
    if [[ $(echo "$response") == "节点更新成功!" ]]; then
        echo -e "\e[32m\n节点信息推送成功！\e[0m\n"
    else
        echo -e "\e[31m推送失败，服务器响应: $response\e[0m"
    fi

    show_action_menu
}

# 推送节点方法
function push_nodes() {
    # 获取节点名称数组和节点链接数组
    node_names=("$@")  # 假设传入节点名称作为参数
    node_lines=("${node_names[@]}")  # 根据实际需求填充节点链接

    # 提示选择推送方式
    echo -e "\n请选择推送方式："
    echo -e "\n\e[32m1. 推送到 Sub-Store   2. 推送到 Telegram Bot     00. 返回主菜单   88.退出脚本\e[0m\n"
    echo -n "请输入选择："
    read push_choice

    # 处理推送方式
    case $push_choice in
        1)
            push_to_sub_store  # 调用推送到 Sub-Store 的方法
            ;;

        2)
            push_to_telegram  # 调用推送到 Telegram Bot 的方法
            ;;

        00)
            show_menu  # 返回主菜单
            ;;
        88)
            exit  # 返回主菜单
            ;;
        *)
            echo -e "\e[31m无效的选择，返回主菜单\e[0m"
            show_menu
            ;;
    esac
}
# 菜单选择方法
function show_action_menu() {
    echo -e "\n请选择操作："
    echo -e "\n\e[32m1.查看节点     2.新增节点     3. 推送节点     5. 删除节点     00. 返回主菜单   88. 退出脚本\e[0m\n"
    read -p "请输入操作编号: " action

    case $action in
        1)
            view_node_info
            ;;
        2)
            add_node
            ;;
        3)
            push_nodes
            ;;
        4)
            delete_nodes
            ;;
        00)
            show_menu
            ;;
        88)
            exit
            ;;
        *)
            echo -e "\n\e[31m无效选择，请重新选择！\e[0m"
            show_action_menu  # 重新显示菜单
            ;;
    esac
}

# 显示节点信息
function view_node_info() {
    # 文件路径
    node_file="/etc/sing-box/nodes_links.txt"

    # 检查文件是否存在
    if [[ ! -f "$node_file" ]]; then
        echo_color yellow "暂无配置的节点！"
        echo
        read -n 1 -s -r -p "按任意键返回主菜单..."
        show_menu  # 返回主菜单
        return 1
    fi

    # 打印文件内容，显示所有的节点链接，每个节点之间加分隔符
    clear
    echo -e "\n节点链接信息：\n"
    echo "------------------------------------------------------------------------------------------------------"
    echo

    # 读取文件并逐行处理，给每个节点加上序号
    node_list=()
    index=1
    all_links=""

    while IFS= read -r line; do
        # 判断链接是否是 Vmess 链接（包含 'vmess://'）
        if [[ "$line" =~ ^vmess:// ]]; then
            # 解码 base64 链接
            decoded_vmess=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null)

            # 提取节点名称
            node_name=$(echo "$decoded_vmess" | jq -r '.ps')

            # 如果没有成功提取节点名称，默认显示为 "Vmess节点"
            if [[ -z "$node_name" ]]; then
                node_name="Vmess节点"
            fi
        else
            # 如果是其他类型的链接，直接使用 # 后的节点名称
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
        fi

        # 保存节点信息到列表，并显示节点序号
        node_list+=("$line")
        echo -e "\e[32m$index.$node_name\e[0m\n"
        echo -e "$line"
        echo
        echo "------------------------------------------------------------------------------------------------------"
        echo
        index=$((index+1))

        # 聚合所有链接
        all_links+="$line"$'\n'
    done < "$node_file"
    aggregated_link=$(echo -n "$all_links" | base64)
    # 输出聚合链接
    echo -e "\e[32m聚合链接（Base64 编码)\e[0m\n"
    echo -e "$aggregated_link\n"
    echo "------------------------------------------------------------------------------------------------------"

    show_action_menu
}

# 删除节点
function delete_nodes() {
    # 节点文件路径
    node_file="/etc/sing-box/nodes_links.txt"
    config_file="/etc/sing-box/config.json"

    # 统一的错误提示函数
    function error_exit {
        echo -e "\e[31m$1\e[0m"
        read -n 1 -s -r -p "按任意键返回查看节点信息..."
        view_node_info  # 返回查看节点信息
        return 1
    }

    # 统一的成功提示函数
    function success_msg {
        echo -e "\e[32m$1\e[0m"
    }

    # 检查节点文件和配置文件是否存在
    if [[ ! -f "$node_file" ]]; then
        error_exit "节点文件不存在！"
    fi

    if [[ ! -f "$config_file" ]]; then
        error_exit "配置文件不存在！"
    fi

    # 读取文件中的节点链接
    mapfile -t node_lines < "$node_file"

    # 提取节点名称和唯一标识符（假设每个节点都有一个 tag 或 uuid）
    node_names=()
    node_tags=()
    for line in "${node_lines[@]}"; do
        # 如果节点是 Vmess 类型，尝试提取名称和 tag
        if [[ "$line" =~ ^vmess:// ]]; then
            decoded_vmess=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null)

            if [[ $? -ne 0 ]]; then
                error_exit "Vmess 链接解码失败！"
            fi

            # 提取 node_name 和 tag
            node_name=$(echo "$decoded_vmess" | jq -r '.ps // "默认名称"')
            tag=$(echo "$decoded_vmess" | jq -r '.tag // ""')  # 返回空字符串作为默认

            if [[ -z "$tag" ]]; then
                tag="$node_name"  # 使用 node_name 作为默认的 tag
            fi
        else
            # 如果是其他类型的链接，直接使用 # 后的节点名称，并假设 tag 在 # 后面
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            tag=$node_name
        fi
        node_names+=("$node_name")
        node_tags+=("$tag")
    done

    # 提示选择要删除的节点
    echo -e "\n请选择操作："
    echo -e "\n\e[32m1. 删除单个/多个节点    2. 删除所有节点    00. 返回主菜单    88.退出脚本\e[0m\n"
    echo -n "请输入操作编号："
    read choice

    case $choice in
        1)
            # 删除单个或多个节点
            echo -e "\n请选择要删除的节点（用空格分隔多个节点）：\n"
            for i in "${!node_names[@]}"; do
                echo -e "\e[32m$((i + 1)). ${node_names[$i]}\e[0m\n"
            done
            echo -n "请输入节点编号："
            read -a nodes_to_delete
            echo
            # 删除选中的节点
            for node_index in "${nodes_to_delete[@]}"; do
                node_index=$((node_index - 1))  # 调整为从0开始的索引
                if [[ $node_index -ge 0 && $node_index -lt ${#node_names[@]} ]]; then
                    #success_msg "删除节点：${node_names[$node_index]}"

                    # 从 config.json 中删除对应的节点配置，假设通过 tag 删除
                    ##echo "正在删除 config.json 中的节点：${node_tags[$node_index]}"

                    # 检查 config.json 是否有效
                    jq empty "$config_file" 2>/dev/null
                    if [[ $? -ne 0 ]]; then
                        error_exit "config.json 格式无效，无法继续删除操作。"
                    fi

                    # 删除 config.json 中的节点
                    jq --arg tag "${node_tags[$node_index]}" 'del(.inbounds[] | select(.tag == $tag))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

                    # 检查是否成功删除
                    grep -q "${node_tags[$node_index]}" "$config_file"
                    if [[ $? -eq 0 ]]; then
                        error_exit "删除失败，未能删除 config.json 中的节点。"
                    else
                        success_msg "${node_tags[$node_index]}节点成功删除！"
                    fi
                else
                    error_exit "无效的节点编号：$node_index"
                fi
            done
            ;;
        2)
            # 删除所有节点
            echo "正在删除所有节点..."
            rm -f "$node_file"
            success_msg "已成功删除所有节点！"
            ;;
        00)
            # 返回主菜单
            show_menu
            ;;
        88)
            # 返回主菜单
            exit
            ;;
        *)
            error_exit "无效的选项！"
            ;;
    esac

    # 删除节点文件中的节点
    #echo "正在删除节点文件中的节点..."
    if [[ ${#node_lines[@]} -eq 1 ]]; then
        # 如果文件中只有一个节点，直接删除文件
        rm -f "$node_file"
        #success_msg "已从 $node_file 中删除所有节点，文件已被删除。"
    else
        # 多个节点时，排除掉要删除的节点
        for node_index in "${nodes_to_delete[@]}"; do
            node_index=$((node_index - 1))  # 调整为从0开始的索引
            # 从 nodes_links.txt 中删除节点
            grep -vF "${node_lines[$node_index]}" "$node_file" > "$node_file.tmp" && mv "$node_file.tmp" "$node_file"
            #success_msg "从 $node_file 中删除了节点：${node_names[$node_index]}"
        done
    fi

    # 删除成功后，显示节点信息并询问是否查看信息或返回主菜单
    ##echo -e "\n\e[32m节点删除完成！\e[0m\n"
    echo -e "\n请继续选择操作："
    echo -e "\n\e[32m1. 查看节点信息    00. 返回主菜单  88.退出脚本   \e[0m\n"

    # 获取用户输入
    read -p "请输入选项（1 或 2）: " choice

    case $choice in
        1)
            view_node_info  # 调用查看节点信息的函数
            ;;
        00)
            show_menu  # 返回主菜单
            ;;
        88)
            exit
            ;;
        *)
            echo "无效的选项，返回主菜单"
            show_menu
            ;;
    esac
}


# 检查是否成功卸载 Sing-Box
function check_sing_box() {
    # 检查 sing-box 命令是否仍然存在
    if command -v sing-box &> /dev/null; then
        echo "Sing-Box 卸载失败，仍然可以找到 sing-box 命令。"
        echo "查找 sing-box 所有相关文件..."
        whereis sing-box

        # 删除所有路径下的 sing-box 文件
        echo "删除 sing-box 相关文件..."
        rm -rf $(whereis sing-box | awk '{print $2}')
        rm -f $(whereis sing-box | awk '{print $3}')
        rm -f $(whereis sing-box | awk '{print $4}')  # 如果仍未卸载完全，尝试手动查找并删除所有相关文件
        return 1
    else
        echo "Sing-Box 已完全卸载。"
        return 0
    fi
}

function uninstall_sing_box() {
    # 停止 Sing-Box 服务
    echo "停止 Sing-Box 服务..."
    systemctl stop sing-box

    # 禁用 Sing-Box 服务
    echo "禁用 Sing-Box 服务..."
    systemctl disable sing-box

    # 删除 Sing-Box 服务文件
    echo "删除 Sing-Box 服务文件..."
    rm -f /etc/systemd/system/sing-box.service

    # 删除 Sing-Box 可执行文件
    echo "删除 Sing-Box 可执行文件..."
    rm -f /usr/local/bin/sing-box
    rm -f /usr/bin/sing-box
    rm -f /bin/sing-box
    rm -f /usr/local/sbin/sing-box
    rm -f /sbin/sing-box

    # 删除 Sing-Box 配置文件和日志文件
    echo "删除 Sing-Box 配置文件和日志文件..."
    rm -rf /etc/sing-box
    rm -rf /var/log/sing-box

    # 删除可能存在的缓存和库文件
    echo "删除 Sing-Box 缓存和库文件..."
    rm -rf /usr/local/lib/sing-box
    rm -rf /var/cache/sing-box

    # 重新加载 systemd 配置
    echo "重新加载 systemd 配置..."
    systemctl daemon-reload

    # 清理残留的链接
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/systemd/system/sing-box*

    # 检查是否卸载成功
    check_sing_box

    # 提示卸载完成并返回主菜单
    #echo "Sing-Box 卸载成功！"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    show_menu  # 返回主菜单
}

show_main_menu