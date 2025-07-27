#!/bin/bash
# =================================================================
#               全功能 VPS & 应用管理脚本
#
#   Author: Jcole & 编码助手
#   Version: 5.0 (Added Portability, Docker Mgmt, More Tools & Refactoring)
#   Created: 2024
#
# =================================================================

# --- 颜色和样式定义 ---
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
WHITE=$'\033[1;37m'
NC=$'\033[0m'

# --- 全局常量和路径定义 ---
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/$SUBSTORE_SERVICE_NAME"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# --- 全局 IP 缓存变量 ---
GLOBAL_IPV4=""
GLOBAL_IPV6=""

# --- 全局系统环境检测变量 ---
PKG_MANAGER=""
OS_ID=""
OS_VERSION_CODENAME=""


# =================================================
#           错误处理 & 脚本退出清理
# =================================================
# 定义一个数组来追踪所有临时文件
TEMP_FILES=()

cleanup_on_exit() {
    # 只有当 TEMP_FILES 数组不为空时才执行
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        log_info "脚本退出，正在清理临时文件..."
        for temp_file in "${TEMP_FILES[@]}"; do
            if [ -f "$temp_file" ]; then
                rm -f "$temp_file"
            fi
        done
    fi
}

# 注册 trap，无论脚本如何退出（正常退出、Ctrl+C、错误），都会执行 cleanup_on_exit 函数
trap cleanup_on_exit EXIT INT TERM

# 创建临时文件时，使用此函数来注册它们以便自动清理
# 用法: register_temp_file "/path/to/temp/file"
register_temp_file() {
    TEMP_FILES+=("$1")
}


# =================================================
#                核心 & 辅助函数
# =================================================

log_info() { echo -e "\n$GREEN[信息] - $1$NC"; }
log_warn() { echo -e "\n$YELLOW[注意] - $1$NC"; }
log_error() { echo -e "\n$RED[错误] - $1$NC"; }

press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键返回..."
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本必须以 root 用户身份运行。"
        exit 1
    fi
}

check_port() {
    local port=$1
    if ss -tln | grep -q -E "(:|:::)$port\b"; then
        log_error "端口 $port 已被占用。"
        return 1
    fi
    return 0
}

get_public_ip() {
    local type=$1
    if [[ "$type" == "v4" ]]; then
        if [ -z "$GLOBAL_IPV4" ]; then
            GLOBAL_IPV4=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
        fi
        echo "$GLOBAL_IPV4"
    elif [[ "$type" == "v6" ]]; then
        if [ -z "$GLOBAL_IPV6" ]; then
            GLOBAL_IPV6=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
        fi
        echo "$GLOBAL_IPV6"
    fi
}

generate_random_port() {
    echo $((RANDOM % 64512 + 1024))
}

generate_random_password() {
    tr </dev/urandom -dc 'A-Za-z0-9' | head -c 20
}

_is_port_available() {
    local port_to_check=$1
    local used_ports_array_name=$2
    eval "local used_ports=(\"\${$used_ports_array_name[@]}\")"
    if ss -tlnu | grep -q -E ":$port_to_check\s"; then
        log_warn "端口 $port_to_check 已被系统其他服务占用。"
        return 1
    fi
    for used_port in "${used_ports[@]}"; do
        if [ "$port_to_check" == "$used_port" ]; then
            log_warn "端口 $port_to_check 即将被本次操作中的其他协议使用。"
            return 1
        fi
    done
    return 0
}

_is_domain_valid() {
    local domain_to_check=$1
    if [[ $domain_to_check =~ ^([a-zA-Z0-9][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}
# =================================================
#      检测操作系统和包管理器 (detect_os_and_package_manager) - 修正版
# =================================================
detect_os_and_package_manager() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION_CODENAME=$VERSION_CODENAME
    else
        log_error "无法检测到操作系统类型。"
        exit 1
    fi

    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        log_error "无法检测到支持的包管理器 (apt, yum, dnf)。"
        exit 1
    fi
    # log_info "检测到系统: $OS_ID, 包管理器: $PKG_MANAGER"
}
# 统一的包安装函数
install_packages() {
    local packages_to_install=("$@")
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        return 0
    fi
    log_info "正在安装包: ${packages_to_install[*]}"
    case "$PKG_MANAGER" in
        apt)
            apt-get install -y "${packages_to_install[@]}"
            ;;
        yum|dnf)
            "$PKG_MANAGER" install -y "${packages_to_install[@]}"
            ;;
        *)
            log_error "未知的包管理器: $PKG_MANAGER"
            return 1
            ;;
    esac
}

# 确保依赖包已安装（已适配多发行版）
ensure_dependencies() {
    local dependencies=("$@")
    local missing_dependencies=()
    if [ ${#dependencies[@]} -eq 0 ]; then
        return 0
    fi

    for pkg in "${dependencies[@]}"; do
        local is_installed=false
        case "$PKG_MANAGER" in
            apt)
                if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                    is_installed=true
                fi
                ;;
            yum|dnf)
                if rpm -q "$pkg" &>/dev/null; then
                    is_installed=true
                fi
                # 特殊处理 policycoreutils-python-utils 在 CentOS/RHEL 上的包名
                if [ "$pkg" == "policycoreutils-python-utils" ] && [ "$PKG_MANAGER" == "dnf" ]; then
                     if rpm -q "policycoreutils-python-utils" &>/dev/null || rpm -q "python3-policycoreutils" &>/dev/null; then
                        is_installed=true
                     fi
                fi
                ;;
        esac
        if ! $is_installed; then
             missing_dependencies+=("$pkg")
        fi
    done

    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        log_warn "检测到以下缺失的依赖包: ${missing_dependencies[*]}"
        if [ "$PKG_MANAGER" == "apt" ]; then
            log_info "正在更新软件包列表 (apt)..."
            if ! apt-get update -y; then
                log_error "软件包列表更新失败，请检查网络或源配置！"
                return 1
            fi
        fi

        if ! install_packages "${missing_dependencies[@]}"; then
            log_error "部分依赖包安装失败，请手动检查。"
            return 1
        fi
    else
        log_info "所需依赖均已安装。"
    fi
    return 0
}
# =================================================
#           新增：通用菜单绘制函数 (V13 - awk兼容性终极修正版)
# =================================================
# 函数: 绘制一个标准的、完美对齐的菜单
#
# @param $1: 菜单标题 (字符串，可包含\n换行符)
# @param $2: 用于接收用户选择的变量名 (引用)
# @param $3+: 菜单选项数组
_draw_menu() {
    local title_block="$1"
    local -n choice_ref=$2
    shift 2
    local -a options=("$@")

    # --- 核心参数 ---
    local menu_width=50
    local right_border_col=$((menu_width + 2))
    local border_char="║"

    # --- 辅助函数：使用 awk -v 的安全方式计算视觉宽度 ---
    _get_visual_width() {
        # 核心改动：使用 awk -v var="$1" 的方式传递变量，
        # 这种方式能确保字符串内容不会干扰 awk 的源代码。
        awk -v text="$1" 'BEGIN {
            w=0;
            for(i=1; i<=length(text); i++) {
                char = substr(text, i, 1);
                if (char ~ /^[ -~]$/) { w += 1; } else { w += 2; }
            }
            print w;
        }'
    }

    clear

    # 1. 打印上边框和智能对齐的标题
    echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"

    local title_line_num=0
    while IFS= read -r title_line; do
        if [ $title_line_num -eq 0 ]; then
            # --- 主标题：居中对齐 ---
            local clean_title
            clean_title=$(echo -e "$title_line" | sed 's/\x1b\[[0-9;]*m//g')
            local title_width
            title_width=$(_get_visual_width "$clean_title")
            local padding_left=$(((menu_width - title_width) / 2))
            local padding_right=$((menu_width - title_width - padding_left))
            printf "$CYAN%s%*s%b%*s%s$NC\n" "$border_char" "$padding_left" "" "$title_line" "$padding_right" "" "$border_char"
        else
            # --- 状态行/副标题：左对齐 ---
            printf "$CYAN%s$NC  %b" "$border_char" "$title_line"
            printf "\033[%sG$CYAN%s$NC\n" "$right_border_col" "$border_char"
        fi
        title_line_num=$((title_line_num + 1))
    done <<< "$(echo -e "$title_block")"

    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

    # 2. 打印菜单选项
    for i in "${!options[@]}"; do
        local option_text="${options[$i]}"
        local rendered_option
        rendered_option=$(echo -e "$option_text")
        local prefix_text
        printf -v prefix_text "  %2d. " "$((i + 1))"
        # 增加垂直间距
        printf "$CYAN%s" "$border_char"
        printf "\033[%sG$CYAN%s$NC\n" "$right_border_col" "$border_char"
        # 打印内容行
        printf "$CYAN%s$NC%s%b" "$border_char" "$prefix_text" "$rendered_option"
        printf "\033[%sG$CYAN%s$NC\n" "$right_border_col" "$border_char"
    done

    # 3. 打印结尾和 "返回" 选项
    printf "$CYAN%s" "$border_char"
    printf "\033[%sG$CYAN%s$NC\n" "$right_border_col" "$border_char"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    printf "$CYAN%s$NC   0. 返回" "$border_char"
    printf "\033[%sG$CYAN%s$NC\n" "$right_border_col" "$border_char"
    echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

    # 4. 读取用户输入
    read -p "请输入选项: " choice_ref
}
# =================================================
#           新增：系统健康巡检辅助函数
# =================================================
_check_service_status() {
    local service_name="$1"
    local display_name="$2"
    local status_text
    if systemctl is-active --quiet "$service_name"; then
        status_text="${GREEN}● 运行中${NC}"
    else
        # 如果服务文件存在但未运行，则为不活动；如果文件不存在，则为未安装
        if systemctl list-unit-files | grep -q "^${service_name}.service"; then
            status_text="${RED}● 不活动${NC}"
        else
            status_text="${YELLOW}○ 未安装${NC}"
        fi
    fi
    # 使用printf进行格式化对齐
    printf "$CYAN║$NC  %-16s: %-29s $CYAN║$NC\n" "$display_name" "$status_text"
}
# =================================================
#           修正版：系统健康巡检辅助函数
# =================================================。
_get_service_status() {
    local service_name="$1"
    # 使用-n声明，可以直接修改外部同名变量的值
    local -n status_text_ref=$2
    local -n status_color_ref=$3

    if systemctl is-active --quiet "$service_name"; then
        status_text_ref="● 运行中"
        status_color_ref=$GREEN
    else
        if systemctl list-unit-files | grep -q "^${service_name}.service"; then
            status_text_ref="● 不活动"
            status_color_ref=$RED
        else
            status_text_ref="○ 未安装"
            status_color_ref=$YELLOW
        fi
    fi
}
# =================================================
#     最终版：系统健康巡检主函数 (V6 - 系统信息查询风格)
# =================================================
system_health_check() {
    clear
    # 辅助函数：用于获取服务状态，但不打印 (此函数保持不变)
    _get_service_status() {
        local service_name="$1"
        local -n status_text_ref=$2
        local -n status_color_ref=$3
        if systemctl is-active --quiet "$service_name"; then
            status_text_ref="● 运行中"
            status_color_ref=$GREEN
        elif systemctl list-unit-files | grep -q "^${service_name}.service"; then
            status_text_ref="● 不活动"
            status_color_ref=$RED
        else
            status_text_ref="○ 未安装"
            status_color_ref=$YELLOW
        fi
    }

    echo -e "\n$CYAN-------------------- 系统健康巡检报告 ---------------------$NC"

    # --- 核心服务状态 ---
    local status_text status_color
    _get_service_status "docker" status_text status_color
    printf "$GREEN%-20s: ${status_color}%s${NC}\n" "Docker 服务" "$status_text"

    _get_service_status "nginx" status_text status_color
    printf "$GREEN%-20s: ${status_color}%s${NC}\n" "Nginx 服务" "$status_text"

    _get_service_status "caddy" status_text status_color
    printf "$GREEN%-20s: ${status_color}%s${NC}\n" "Caddy 服务" "$status_text"

    _get_service_status "sing-box" status_text status_color
    printf "$GREEN%-20s: ${status_color}%s${NC}\n" "Sing-Box 服务" "$status_text"

    _get_service_status "fail2ban" status_text status_color
    printf "$GREEN%-20s: ${status_color}%s${NC}\n" "Fail2Ban 服务" "$status_text"

    # --- 系统资源使用 ---
    echo -e "$CYAN-------------------------------------------------------$NC"
    local disk_usage_percent disk_status_color disk_info
    disk_usage_percent=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage_percent" -gt 85 ]; then disk_status_color="$RED";
    elif [ "$disk_usage_percent" -gt 65 ]; then disk_status_color="$YELLOW";
    else disk_status_color="$GREEN"; fi
    disk_info=$(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')
    printf "$GREEN%-20s: ${disk_status_color}%s${NC}\n" "根目录磁盘  " "$disk_info"

    local mem_info
    mem_info=$(free -h | awk '/^Mem:/ {printf "%s / %s", $3, $2}')
    printf "$GREEN%-20s: $WHITE%s${NC}\n" "内存使用 " "$mem_info"

    # --- Docker 容器概览 ---
    if command -v docker &>/dev/null; then
        echo -e "$CYAN-------------------------------------------------------$NC"
        local total_containers running_containers restarting_containers
        total_containers=$(docker ps -a --format '{{.Names}}' | wc -l)
        running_containers=$(docker ps --format '{{.Names}}' | wc -l)
        restarting_containers=$(docker ps --filter "status=restarting" --format '{{.Names}}' | tr '\n' ' ')

        printf "$GREEN%-20s: $WHITE%s${NC}\n" "总容器数 " "$total_containers"
        printf "$GREEN%-20s: ${GREEN}%s${NC}\n" "运行中" "$running_containers"
        if [ -n "$restarting_containers" ]; then
             printf "$GREEN%-20s: ${RED}%s${NC}\n" "异常(重启中)" "$restarting_containers"
        fi
    fi

    # --- SSL 证书有效期 ---
    if command -v certbot &>/dev/null; then
        echo -e "$CYAN-------------------------------------------------------$NC"
        log_info "SSL 证书有效期:"
        local cert_info
        cert_info=$(certbot certificates 2>/dev/null)
        if [[ ! "$cert_info" =~ "Found the following certs:" ]]; then
            echo -e "$YELLOW  未发现任何 Certbot 证书$NC"
        else
            # 使用更简洁的列表格式输出
            echo "$cert_info" | awk '/Certificate Name:/ {name=$3} /Domains:/ {domains=$0; sub(/Domains: /,"",domains)} /Expiry Date:/ {expiry=$0; sub(/.*Expiry Date: /,""); sub(/ \(VALID/," (VALID"); printf "  - %-25s\n    Domains: %s\n    Expires: %s\n\n", name, domains, expiry}'
        fi
    fi

    echo -e "$CYAN-------------------------------------------------------$NC"
    press_any_key
}
# =================================================
#      防火墙助手 (firewall_helper_menu) - 优化版
# =================================================
firewall_helper_menu() {
    local FW_COMMAND=""
    local FW_TYPE=""

    # 优先检测 UFW
    if command -v ufw &>/dev/null; then
        FW_COMMAND="ufw"
        FW_TYPE="UFW"
    elif command -v firewall-cmd &>/dev/null; then
        FW_COMMAND="firewall-cmd"
        FW_TYPE="FirewallD"
    else
        log_error "未检测到 UFW 或 FirewallD，无法使用此功能。"
        press_any_key
        return
    fi

    log_info "检测到防火墙类型: $FW_TYPE"

    while true; do
        # 1. 获取防火墙的动态状态
        local status_text
        if [ "$FW_TYPE" == "UFW" ]; then
            if ufw status | grep -q 'Status: active'; then
                status_text="${GREEN}● 活动 (Active)${NC}"
            else
                status_text="${RED}● 不活动 (Inactive)${NC}"
            fi
        else # FirewallD
            if systemctl is-active --quiet firewalld; then
                status_text="${GREEN}● 活动 (Active)${NC}"
            else
                status_text="${RED}● 不活动 (Inactive)${NC}"
            fi
        fi

        # 2. 构建包含动态信息的多行标题
        local title="防火墙助手 ($FW_TYPE)\n  当前状态: $status_text"

        # 3. 定义菜单选项数组
        local -a options=(
            "查看当前所有规则"
            "开放一个端口 (Allow)"
            "关闭一个端口 (Delete/Remove)"
            "开启防火墙"
            "关闭防火墙"
        )

        # 4. 调用通用菜单函数
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 5. 处理用户选择 (这部分复杂的逻辑保持不变)
        case $choice in
        1)
            clear
            log_info "当前防火墙规则:"
            if [ "$FW_TYPE" == "UFW" ]; then
                ufw status numbered
            else
                firewall-cmd --list-all
            fi
            press_any_key
            ;;
        2)
            read -p "请输入要开放的端口号: " port
            read -p "请输入协议 [默认: tcp]: " proto
            proto=${proto:-"tcp"}
            if [ "$FW_TYPE" == "UFW" ]; then
                ufw allow "$port/$proto"
            else
                firewall-cmd --permanent --add-port="$port/$proto"
                firewall-cmd --reload
            fi
            log_info "✅ 规则添加完成 (如果需要)。"
            press_any_key
            ;;
        3)
            if [ "$FW_TYPE" == "UFW" ]; then
                log_info "请参考下面的列表，输入要删除的规则【编号】。"
                ufw status numbered
                read -p "请输入要删除的规则编号: " rule_num
                if [[ "$rule_num" =~ ^[0-9]+$ ]]; then
                    # UFW需要二次确认
                    yes | ufw delete "$rule_num"
                else
                    log_error "无效的编号。"
                fi
            else # FirewallD
                read -p "请输入要关闭的端口号: " port
                read -p "请输入协议 [默认: tcp]: " proto
                proto=${proto:-"tcp"}
                firewall-cmd --permanent --remove-port="$port/$proto"
                firewall-cmd --reload
            fi
            log_info "✅ 规则移除完成 (如果需要)。"
            press_any_key
            ;;
        4)
            if [ "$FW_TYPE" == "UFW" ]; then
                yes | ufw enable
            else
                systemctl enable firewalld
                systemctl start firewalld
            fi
            log_info "✅ 防火墙已开启。"; sleep 1
            ;;
        5)
            if [ "$FW_TYPE" == "UFW" ]; then
                ufw disable
            else
                systemctl stop firewalld
                systemctl disable firewalld
            fi
            log_info "✅ 防火墙已关闭。"; sleep 1
            ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#                系统管理 (sys_manage_menu) - 优化版
# =================================================
sys_manage_menu() {
    while true; do
        # 定义菜单选项数组
        local -a options=(
            "系统信息查询"
            "清理系统垃圾"
            "修改主机名"
            "设置 root 登录 (密钥/密码)"
            "修改 SSH 端口"
            "设置系统时区"
            "网络优化 ->" # 使用 -> 符号表示子菜单
            "实用工具 (增强) ->"
            "${CYAN}系统健康巡检${NC}"
        )

        # 定义网络优化子菜单选项
        local -a network_options=(
             "设置网络优先级 (IPv4/v6)"
             "DNS 工具箱 (优化/备份/恢复)"
             "BBR 拥塞控制管理"
             "安装 WARP 网络接口"
        )

        local choice
        # 调用通用菜单函数
        _draw_menu "系统综合管理" choice "${options[@]}"

        # case语句处理用户选择
        case $choice in
            1) show_system_info ;;
            2) clean_system ;;
            3) change_hostname ;;
            4) manage_root_login ;;
            5) change_ssh_port ;;
            6) set_timezone ;;
            7) # 网络优化子菜单
                while true; do
                    local net_choice
                    _draw_menu "网络优化" net_choice "${network_options[@]}"
                    case $net_choice in
                        1) network_priority_menu ;;
                        2) dns_toolbox_menu ;;
                        3) manage_bbr ;;
                        4) install_warp ;;
                        0) break ;;
                        *) log_error "无效选项！"; sleep 1 ;;
                    esac
                done
                ;;
            8) utility_tools_menu ;;
            9) system_health_check ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

show_system_info() {
    # 适配多发行版的依赖包名
    local deps=("util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools")
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        deps=("util-linux" "procps-ng" "vnstat" "jq" "redhat-lsb-core" "curl" "net-tools")
    fi
    ensure_dependencies "${deps[@]}"

    clear
    log_info "正在查询系统信息，请稍候..."
    if ! command -v lsb_release &>/dev/null || ! command -v lscpu &>/dev/null; then
        log_error "缺少核心查询命令 (如 lsb_release, lscpu)，请先执行依赖安装。"
        press_any_key
        return
    fi
    log_info "正在获取网络信息..."

    local curl_flag=""
    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    local ipv6_addr
    ipv6_addr=$(get_public_ip v6)

    if [ -z "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
        log_warn "检测到纯IPv6环境，部分网络查询将强制使用IPv6。"
        curl_flag="-6"
    fi

    if [ -z "$ipv4_addr" ]; then ipv4_addr="无或获取失败"; fi
    if [ -z "$ipv6_addr" ]; then ipv6_addr="无或获取失败"; fi

    local hostname_info
    hostname_info=$(hostname)
    local os_info
    os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^[[:space:]]*//')
    local kernel_info
    kernel_info=$(uname -r)
    local cpu_arch
    cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    local cpu_model_full
    cpu_model_full=$(lscpu | grep "^Model name:" | sed -e 's/Model name:[[:space:]]*//')
    local cpu_model
    cpu_model=$(echo "$cpu_model_full" | sed 's/ @.*//')
    local cpu_freq_from_model
    cpu_freq_from_model=$(echo "$cpu_model_full" | sed -n 's/.*@ *//p')
    local cpu_cores
    cpu_cores=$(lscpu | grep "^CPU(s):" | awk -F: '{print $2}' | sed 's/^ *//')
    local load_info
    load_info=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
    local memory_info
    memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.2f%%)", $3, $2, $3/$2*100}')
    local disk_info
    disk_info=$(df -h | grep '/$' | awk '{print $3 "/" $2 " (" $5 ")"}')
    local net_info_rx
    net_info_rx=$(vnstat --oneline | awk -F';' '{print $4}')
    local net_info_tx
    net_info_tx=$(vnstat --oneline | awk -F';' '{print $5}')

    local net_algo="N/A (纯IPv6环境)"
    if [ -f "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
        net_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    fi

    local ip_info
    ip_info=$(curl -s $curl_flag http://ip-api.com/json | jq -r '.org')
    local dns_info
    dns_info=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local geo_info
    geo_info=$(curl -s $curl_flag http://ip-api.com/json | jq -r '.city + ", " + .country')
    local timezone
    timezone=$(timedatectl show --property=Timezone --value)
    local uptime_info
    uptime_info=$(uptime -p)
    local current_time
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    clear
    echo -e "\n$CYAN-------------------- 系统信息查询 ---------------------$NC"
    printf "$GREEN主机名　　　  : $WHITE%s$NC\n" "$hostname_info"
    printf "$GREEN系统版本　　  : $WHITE%s$NC\n" "$os_info"
    printf "${GREEN}Linux版本　 　: $WHITE%s$NC\n" "$kernel_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "${GREEN}CPU架构　　 　: $WHITE%s$NC\n" "$cpu_arch"
    printf "${GREEN}CPU型号　　 　: $WHITE%s$NC\n" "$cpu_model"
    printf "${GREEN}CPU频率　　 　: $WHITE%s$NC\n" "$cpu_freq_from_model"
    printf "${GREEN}CPU核心数　 　: $WHITE%s$NC\n" "$cpu_cores"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "${GREEN}CPU占用　　 　: $WHITE%s$NC\n" "$cpu_usage"
    printf "$GREEN系统负载　　  : $WHITE%s$NC\n" "$load_info"
    printf "$GREEN物理内存　　  : $WHITE%s$NC\n" "$memory_info"
    printf "$GREEN硬盘占用　　  : $WHITE%s$NC\n" "$disk_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN总接收　　　  : $WHITE%s$NC\n" "$net_info_rx"
    printf "$GREEN总发送　　　  : $WHITE%s$NC\n" "$net_info_tx"
    printf "$GREEN网络算法　　  : $WHITE%s$NC\n" "$net_algo"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN运营商　　　  : $WHITE%s$NC\n" "$ip_info"
    printf "$GREEN公网IPv4地址　: $WHITE%s$NC\n" "$ipv4_addr"
    printf "$GREEN公网IPv6地址　: $WHITE%s$NC\n" "$ipv6_addr"
    printf "${GREEN}DNS地址　　 　: $WHITE%s$NC\n" "$dns_info"
    printf "$GREEN地理位置　　  : $WHITE%s$NC\n" "$geo_info"
    printf "$GREEN系统时间　　  : $WHITE%s$NC\n" "$timezone $current_time"
    echo -e "$CYAN-------------------------------------------------------$NC"
    printf "$GREEN运行时长　　  : $WHITE%s$NC\n" "$uptime_info"
    echo -e "$CYAN-------------------------------------------------------$NC"
    press_any_key
}

clean_system() {
    log_info "正在清理无用的软件包和缓存..."
    set -e
    case "$PKG_MANAGER" in
        apt)
            apt autoremove -y
            apt clean
            ;;
        yum|dnf)
            "$PKG_MANAGER" autoremove -y
            "$PKG_MANAGER" clean all
            ;;
    esac
    set +e
    log_info "系统清理完毕。"
    press_any_key
}

change_hostname() {
    log_info "准备修改主机名...\n"
    read -p "请输入新的主机名: " new_hostname
    if [ -z "$new_hostname" ]; then
        log_error "主机名不能为空！"
        press_any_key
        return
    fi
    local current_hostname
    current_hostname=$(hostname)
    if [ "$new_hostname" == "$current_hostname" ]; then
        log_warn "新主机名与当前主机名相同，无需修改。"
        press_any_key
        return
    fi
    set -e
    hostnamectl set-hostname "$new_hostname"
    echo "$new_hostname" >/etc/hostname
    # 使用 .bak 后缀自动备份
    sed -i.bak "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    set +e
    log_info "✅ 主机名修改成功！新的主机名是：$new_hostname"
    log_info "当前主机名是：$(hostname)"
    press_any_key
}
# =================================================
#                 DNS 工具箱
# =================================================
apply_dns_config() {
    local dns_string="$1"

    if [ -z "$dns_string" ]; then
        log_error "没有提供任何DNS服务器地址，操作中止。"
        return
    fi

    # 判断是否由 systemd-resolved 管理
    if systemctl is-active --quiet systemd-resolved; then
        log_info "检测到 systemd-resolved 服务，将通过标准方式配置..."

        # 自动备份
        sed -i.bak -e "s/^#\?DNS=.*/DNS=$dns_string/" \
               -e "s/^#\?Domains=.*/Domains=~./" /etc/systemd/resolved.conf
        if ! grep -q "DNS=" /etc/systemd/resolved.conf; then echo "DNS=$dns_string" >> /etc/systemd/resolved.conf; fi
        if ! grep -q "Domains=" /etc/systemd/resolved.conf; then echo "Domains=~." >> /etc/systemd/resolved.conf; fi

        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        log_info "正在重启 systemd-resolved 服务..."
        systemctl restart systemd-resolved
        log_info "✅ systemd-resolved DNS 配置完成！"
    else
        log_info "未检测到 systemd-resolved，将直接修改 /etc/resolv.conf..."
        local resolv_content=""
        for server in $dns_string; do
            resolv_content+="nameserver $server\n"
        done
        # 自动备份
        cp /etc/resolv.conf /etc/resolv.conf.bak
        echo -e "$resolv_content" > /etc/resolv.conf
        log_info "✅ /etc/resolv.conf 文件已更新！"
    fi

    echo
    log_info "配置后的真实上游DNS如下 (通过 resolvectl status 查看):"
    echo -e "$WHITE"
    resolvectl status | grep 'DNS Server'
    echo -e "$NC"
    press_any_key
}

recommend_best_dns() {
    clear
    log_info "开始自动测试延迟以寻找最佳 DNS..."

    local ping_pkg="iputils-ping"
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        ping_pkg="iputils"
    fi
    ensure_dependencies "$ping_pkg"

    declare -A dns_providers
    dns_providers["Cloudflare"]="1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001"
    dns_providers["Google"]="8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844"
    dns_providers["Quad9"]="9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9"
    dns_providers["OpenDNS"]="208.67.222.222 208.67.220.220 2620:119:35::35 2620:119:53::53"

    local ping_cmd="ping"
    local ip_type="v4"
    if ! get_public_ip v4 >/dev/null 2>&1 || [ -z "$(get_public_ip v4)" ]; then
        log_warn "未检测到IPv4网络，将切换到IPv6模式进行测试。"
        ping_cmd="ping"
        ip_type="v6"
    fi

    declare -A results
    declare -A ip_to_provider_map
    echo
    for provider in "${!dns_providers[@]}"; do
        local all_ips=${dns_providers[$provider]}
        local ip_to_test=""

        if [ "$ip_type" == "v6" ]; then
            ping_cmd="ping -6"
            ip_to_test=$(echo "$all_ips" | awk '{for(i=1;i<=NF;i++) if($i ~ /:/) {print $i; exit}}')
        else
            ping_cmd="ping -4"
            ip_to_test=$(echo "$all_ips" | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')
        fi

        if [ -z "$ip_to_test" ]; then
            log_warn "未能为 $provider 找到合适的 $ip_type 地址，跳过测试。"
            continue
        fi

        ip_to_provider_map[$ip_to_test]=$provider
        echo -ne "$CYAN  正在测试: $provider ($ip_to_test)...$NC"
        local avg_latency
        avg_latency=$($ping_cmd -c 4 -W 1 "$ip_to_test" | tail -1 | awk -F '/' '{print $5}')

        if [ -n "$avg_latency" ]; then
            results[$ip_to_test]=$avg_latency
            echo -e "$GREEN  延迟: $avg_latency ms$NC"
        else
            results[$ip_to_test]="9999" # 代表超时
            echo -e "$RED  请求超时!$NC"
        fi
    done

    echo
    log_info "测试结果（按延迟从低到高排序）:"
    local sorted_results
    sorted_results=$(for ip in "${!results[@]}"; do
        echo "${results[$ip]} $ip"
    done | sort -n)

    echo -e "$WHITE"
    echo "$sorted_results" | while read -r latency ip; do
        provider_name=${ip_to_provider_map[$ip]}
        printf "  %-12s (%-15s) -> %s ms\n" "$provider_name" "$ip" "$latency"
    done | sed 's/9999/超时/'
    echo -e "$NC"

    local best_ip
    best_ip=$(echo "$sorted_results" | head -n 1 | awk '{print $2}')
    local backup_ip
    backup_ip=$(echo "$sorted_results" | head -n 2 | tail -n 1 | awk '{print $2}')

    if [ -z "$best_ip" ] || [ "$(echo "${results[$best_ip]}" | cut -d'.' -f1)" == "9999" ]; then
        log_error "所有DNS服务器测试超时，无法给出有效建议。"
        press_any_key
        return
    fi

    local best_dns_provider_name=${ip_to_provider_map[$best_ip]}
    local best_dns_full_list=${dns_providers[$best_dns_provider_name]}
    local final_dns_to_apply="$best_dns_full_list"

    echo
    log_info "优化建议:"
    echo -e "$GREEN  最佳DNS提供商 (主): $best_dns_provider_name ($best_ip)$NC"

    if [ -n "$backup_ip" ] && [ "$best_ip" != "$backup_ip" ] && [ "$(echo "${results[$backup_ip]}" | cut -d'.' -f1)" != "9999" ]; then
        local backup_dns_provider_name=${ip_to_provider_map[$backup_ip]}
        local backup_dns_full_list=${dns_providers[$backup_dns_provider_name]}
        final_dns_to_apply="$final_dns_to_apply $backup_dns_full_list"
        echo -e "$YELLOW  备用DNS提供商 (备): $backup_dns_provider_name ($backup_ip)$NC"
    fi

    echo
    read -p "是否要立即应用此优化建议? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "正在应用推荐配置..."
        local unique_servers
        unique_servers=$(echo "$final_dns_to_apply" | tr ' ' '\n' | sort -u | tr '\n' ' ')
        apply_dns_config "$unique_servers"
    else
        log_info "操作已取消。"
        press_any_key
    fi
}
# =================================================
#      DNS 工具箱 (dns_toolbox_menu) - 优化版
# =================================================
dns_toolbox_menu() {
    local backup_file="/etc/vps_toolkit_dns_backup"
    while true; do
        # 1. 获取动态信息
        local current_dns_list="读取失败"
        if command -v resolvectl &>/dev/null; then
            local status_output
            status_output=$(resolvectl status)
            local dns_list
            dns_list=$(echo "$status_output" | grep 'Current DNS Server:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
            if [ -z "$dns_list" ]; then
                dns_list=$(echo "$status_output" | grep 'DNS Servers:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
            fi
            if [ -n "$dns_list" ]; then
                current_dns_list="$YELLOW$dns_list$NC"
            fi
        fi

        # 2. 构建多行标题
        local title="DNS 工具箱\n  当前DNS: $current_dns_list"

        # 3. 定义菜单选项
        local -a options=(
            "自动测试并推荐最佳 DNS"
            "手动选择 DNS 进行优化"
            "备份当前 DNS 配置"
        )
        # 动态添加恢复选项
        if [ -f "$backup_file" ]; then
            options+=("从备份恢复 DNS 配置 (推荐)")
        else
            options+=("${RED}从备份恢复 DNS 配置 (无备份)${NC}")
        fi

        # 4. 调用通用菜单
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 5. 处理逻辑
        case $choice in
        1) recommend_best_dns ;;
        2) optimize_dns ;;
        3) backup_dns_config ;;
        4)
            if [ -f "$backup_file" ]; then
                restore_dns_config
            else
                log_error "没有可用的备份文件！"
                sleep 1
            fi
            ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
backup_dns_config() {
    local backup_file="/etc/vps_toolkit_dns_backup"
    log_info "开始备份当前 DNS 配置..."

    if [ -f "$backup_file" ]; then
        log_warn "检测到已存在的备份文件。是否覆盖？"
        read -p "请输入 (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "操作已取消。"
            press_any_key
            return
        fi
    fi

    if systemctl is-active --quiet systemd-resolved; then
        cp /etc/systemd/resolved.conf "$backup_file.systemd"
        echo "systemd-resolved" > "$backup_file.mode"
        log_info "已将 systemd-resolved 配置文件备份到 $backup_file.systemd"
    else
        cp /etc/resolv.conf "$backup_file.resolv"
        echo "resolvconf" > "$backup_file.mode"
        log_info "已将 /etc/resolv.conf 文件备份到 $backup_file.resolv"
    fi

    touch "$backup_file"
    log_info "✅ DNS 备份完成！"
    press_any_key
}

restore_dns_config() {
    local backup_file="/etc/vps_toolkit_dns_backup"
    if [ ! -f "$backup_file" ]; then
        log_error "未找到任何 DNS 备份文件，无法恢复。"
        press_any_key
        return
    fi

    log_info "准备从备份中恢复 DNS 配置..."
    read -p "这将覆盖当前的 DNS 设置，确定要继续吗？ (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi

    local backup_mode
    backup_mode=$(cat "$backup_file.mode")

    if [ "$backup_mode" == "systemd-resolved" ]; then
        log_info "正在恢复 systemd-resolved 配置..."
        mv "$backup_file.systemd" /etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        log_info "✅ systemd-resolved 配置已恢复并重启服务。"
    elif [ "$backup_mode" == "resolvconf" ]; then
        log_info "正在恢复 /etc/resolv.conf 文件..."
        mv "$backup_file.resolv" /etc/resolv.conf
        log_info "✅ /etc/resolv.conf 文件已恢复。"
    else
        log_error "未知的备份模式，恢复失败！"
        press_any_key
        return
    fi

    rm -f "$backup_file" "$backup_file.mode"
    log_info "当前的DNS配置如下："
    echo -e "$WHITE"
    cat /etc/resolv.conf
    echo -e "$NC"
    press_any_key
}

optimize_dns() {
    clear
    log_info "正在检测您当前的 DNS 配置..."
    if command -v resolvectl &>/dev/null; then
        local status_output
        status_output=$(resolvectl status)
        local current_dns_list
        current_dns_list=$(echo "$status_output" | grep 'Current DNS Server:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
        if [ -z "$current_dns_list" ]; then
            current_dns_list=$(echo "$status_output" | grep 'DNS Servers:' | awk '{for(i=3;i<=NF;i++) printf "%s ", $i}')
        fi
    else
        current_dns_list=$(grep '^nameserver' /etc/resolv.conf | awk '{printf "%s ", $2}')
    fi
    if [ -n "$current_dns_list" ]; then log_info "当前系统使用的 DNS 服务器是: $YELLOW$current_dns_list$NC"; else log_warn "未检测到当前配置的 DNS 服务器。"; fi
    echo

    declare -A dns_providers
    dns_providers["Cloudflare"]="1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:470t:4700::1001"
    dns_providers["Google"]="8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844"
    dns_providers["OpenDNS"]="208.67.222.222 208.67.220.220 2620:119:35::35 2620:119:53::53"
    dns_providers["Quad9"]="9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9"
    local options=("Cloudflare" "Google" "OpenDNS" "Quad9" "返回")

    echo -e "$CYAN--- 请选择一个或多个 DNS 提供商 (可多选，用空格隔开) ---$NC\n"
    for i in "${!options[@]}"; do
        local option_name=${options[$i]}
        if [ "$option_name" == "返回" ]; then
            echo -e "$((i + 1)). $option_name\n"
        else
            local ips=${dns_providers[$option_name]}
            printf " %2d. %-12s\n" "$((i + 1))" "$option_name"
            printf "      ${YELLOW}%s${NC}\n\n" "$ips"
        fi
    done

    local choices
    read -p "请输入选项: " -a choices
    if [ ${#choices[@]} -eq 0 ]; then log_error "未输入任何选项！"; press_any_key; return; fi

    local combined_servers_str=""
    local selected_providers_str=""
    for choice in "${choices[@]}"; do
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt ${#options[@]} ]]; then log_error "包含无效选项: $choice"; press_any_key; return; fi
        local selected_option=${options[$((choice-1))]}
        if [ "$selected_option" == "返回" ]; then return; fi
        combined_servers_str+="${dns_providers[$selected_option]} "
        selected_providers_str+="$selected_option, "
    done

    selected_providers_str=${selected_providers_str%, }
    log_info "你选择了: $selected_providers_str DNS"

    local servers_to_apply
    servers_to_apply="$(echo "$combined_servers_str" | tr ' ' '\n' | sort -u | tr '\n' ' ')"

    apply_dns_config "$servers_to_apply"
}

test_and_recommend_priority() {
    clear
    log_info "开始进行 IPv4 与 IPv6 网络质量测试..."
    ensure_dependencies "bc"

    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    local ipv6_addr
    ipv6_addr=$(get_public_ip v6)

    if [ -z "$ipv4_addr" ] || [ -z "$ipv6_addr" ]; then
        log_error "您的服务器不是一个标准的双栈网络环境，无法进行有意义的比较。"
        press_any_key
        return
    fi

    local test_url="http://cachefly.cachefly.net/100kb.test"
    log_info "将通过两种协议分别连接测试点: $test_url"

    local time_v4 time_v6

    log_info "正在测试 IPv4 连接速度..."
    time_v4=$(timeout 10 curl -4 -s -w '%{time_total}' -o /dev/null "$test_url" 2>/dev/null)

    log_info "正在测试 IPv6 连接速度..."
    time_v6=$(timeout 10 curl -6 -s -w '%{time_total}' -o /dev/null "$test_url" 2>/dev/null)

    echo
    log_info "测试结果:"

    local recommendation=""

    if [ -n "$time_v4" ] && [ "$(echo "$time_v4 > 0" | bc)" -eq 1 ]; then
        echo -e "$GREEN  IPv4 连接耗时: $time_v4 秒$NC"
    else
        time_v4="999" # 标记为失败
        echo -e "$RED  IPv4 连接失败或超时$NC"
    fi

    if [ -n "$time_v6" ] && [ "$(echo "$time_v6 > 0" | bc)" -eq 1 ]; then
        echo -e "$GREEN  IPv6 连接耗时: $time_v6 秒$NC"
    else
        time_v6="999" # 标记为失败
        echo -e "$RED  IPv6 连接失败或超时$NC"
    fi

    echo
    if [ "$time_v6" == "999" ] && [ "$time_v4" != "999" ]; then
        recommendation="IPv4"
        log_warn "测试发现 IPv6 连接存在问题，强烈建议您设置为【IPv4 优先】以保证网络稳定性。"
    elif [ "$time_v4" == "999" ] && [ "$time_v6" != "999" ]; then
        recommendation="IPv6"
        log_info "测试发现 IPv4 连接存在问题，您的网络环境可能更适合【IPv6 优先】。"
    elif [ "$time_v4" != "999" ] && [ "$time_v6" != "999" ]; then
        if (( $(echo "$time_v6 > $time_v4 * 1.3" | bc -l) )); then
            recommendation="IPv4"
            log_info "测试结果表明，您的 IPv4 连接速度明显优于 IPv6，推荐设置为【IPv4 优先】。"
        else
            recommendation="IPv6"
            log_info "测试结果表明，您的 IPv6 连接质量良好，推荐设置为【IPv6 优先】以使用现代网络。"
        fi
    else
        log_error "两种协议均连接失败，无法给出建议。请检查您的服务器网络配置。"
        press_any_key
        return
    fi

    echo
    read -p "是否要采纳此建议并应用设置? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 确保 /etc/gai.conf 存在
        touch /etc/gai.conf
        if [ "$recommendation" == "IPv6" ]; then
            log_info "正在设置为 [IPv6 优先]..."
            sed -i.bak '/^precedence ::ffff:0:0\/96/s/^/#/' /etc/gai.conf
            log_info "✅ 已成功设置为 IPv6 优先。"
        elif [ "$recommendation" == "IPv4" ]; then
            log_info "正在设置为 [IPv4 优先]..."
            # 先删除可能存在的被注释的行，再添加新的行，避免重复
            sed -i.bak '/^#\?precedence ::ffff:0:0\/96/d' /etc/gai.conf
            echo "precedence ::ffff:0:0/96  100" >>/etc/gai.conf
            log_info "✅ 已成功设置为 IPv4 优先。"
        fi
    else
        log_info "操作已取消。"
    fi
    press_any_key
}
# =================================================
#      网络优先级 (network_priority_menu) - 优化版
# =================================================
network_priority_menu() {
    while true; do
        # 1. 获取动态状态
        local current_setting="未知"
        if [ ! -f /etc/gai.conf ] || ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
             current_setting="${GREEN}IPv6 优先${NC}"
        else
             current_setting="${YELLOW}IPv4 优先${NC}"
        fi

        # 2. 构建标题
        local title="网络优先级设置\n  当前设置: $current_setting"

        # 3. 定义选项
        local -a options=(
            "自动测试并推荐最佳设置"
            "手动设置为 [IPv6 优先]"
            "手动设置为 [IPv4 优先]"
        )

        # 4. 调用菜单
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 5. 处理逻辑
        case $choice in
        1)
            test_and_recommend_priority
            ;;
        2)
            log_info "正在手动设置为 [IPv6 优先]..."
            touch /etc/gai.conf
            sed -i.bak '/^precedence ::ffff:0:0\/96/s/^/#/' /etc/gai.conf
            log_info "✅ 已成功设置为 IPv6 优先。"
            press_any_key
            ;;
        3)
            log_info "正在手动设置为 [IPv4 优先]..."
            touch /etc/gai.conf
            sed -i.bak '/^#\?precedence ::ffff:0:0\/96/d' /etc/gai.conf
            echo "precedence ::ffff:0:0/96  100" >>/etc/gai.conf
            log_info "✅ 已成功设置为 IPv4 优先。"
            press_any_key
            ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
setup_ssh_key() {
    log_info "开始设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    log_warn "请粘贴您的公钥 (例如 id_rsa.pub 的内容)，粘贴完成后，按 Enter 换行，再按一次 Enter 即可结束输入:"
    local public_key=""
    local line
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            break
        fi
        public_key+="$line"$'\n'
    done
    public_key=$(echo -e "$public_key" | sed '/^$/d')
    if [ -z "$public_key" ]; then
        log_error "没有输入公钥，操作已取消。"
        press_any_key
        return
    fi
    printf "%s\n" "$public_key" >>~/.ssh/authorized_keys
    sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
    log_info "公钥已成功添加到 authorized_keys 文件中。\n"
    read -p "是否要禁用密码登录 (强烈推荐)? (y/N): " disable_pwd
    if [[ "$disable_pwd" =~ ^[Yy]$ ]]; then
        log_info "正在修改 SSH 配置以禁用密码登录..."
        # 使用 .bak 后缀自动备份
        sed -i.bak -e 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' \
               -e 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

        log_info "正在重启 SSH 服务..."
        if systemctl restart sshd || systemctl restart ssh; then
             log_info "✅ SSH 服务已重启，密码登录已禁用。"
        else
             log_error "SSH 服务重启失败！请手动检查 'systemctl status ssh' 或 'sshd'。"
        fi
    fi
    log_info "✅ SSH 密钥登录设置完成。"
    press_any_key
}
# =================================================
#      root 登录管理 (manage_root_login) - 优化版
# =================================================
manage_root_login() {
    while true; do
        # 1. 定义菜单标题
        local title="设置 root 登录方式"

        # 2. 定义菜单选项数组
        local -a options=(
            "设置 SSH 密钥登录 (更安全，推荐)"
            "设置 root 密码登录 (方便，兼容性好)"
        )

        # 3. 调用通用菜单函数来绘制菜单并获取用户选择
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 4. 根据用户的选择执行相应操作
        case $choice in
            1)
                setup_ssh_key
                break # 操作完成后退出此菜单，返回上一级
                ;;
            2)
                set_root_password
                break # 操作完成后退出此菜单，返回上一级
                ;;
            0)
                break # 用户选择返回
                ;;
            *)
                log_error "无效选项！"
                sleep 1
                ;;
        esac
    done
}
set_root_password() {
    log_info "开始设置 root 密码..."
    read -s -p "请输入新的 root 密码: " new_password
    echo ""
    read -s -p "请再次输入新的 root 密码以确认: " confirm_password
    echo ""

    if [ -z "$new_password" ]; then
        log_error "密码不能为空，操作已取消。"
        press_any_key
        return
    fi

    if [ "$new_password" != "$confirm_password" ]; then
        log_error "两次输入的密码不匹配，操作已取消。"
        press_any_key
        return
    fi

    log_info "正在更新 root 密码..."
    if ! echo "root:$new_password" | chpasswd; then
        log_error "密码更新失败！请检查 chpasswd 命令是否可用。"
        press_any_key
        return
    fi
    log_info "✅ root 密码已成功更新。"

    log_info "正在修改 SSH 配置文件以允许 root 用户通过密码登录..."

    # 自动备份
    sed -i.bak -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
           -e 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

    log_info "配置修改完成，正在重启 SSH 服务以应用更改..."
    if systemctl restart sshd || systemctl restart ssh; then
        log_info "✅ SSH 服务已重启。root 密码登录功能已成功设置！"
    else
        log_error "SSH 服务重启失败！请手动执行 'sudo systemctl status sshd' 进行检查。"
    fi

    press_any_key
}
set_timezone() {
    clear
    local current_timezone
    current_timezone=$(timedatectl show --property=Timezone --value)
    log_info "当前系统时区是: $current_timezone"
    log_info "请选择新的时区：\n"
    options=("Asia/Shanghai" "Asia/Taipei" "Asia/Hong_Kong" "Asia/Tokyo" "Europe/London" "America/New_York" "UTC" "返回上一级菜单")
    PS3="请输入选项: "
    select opt in "${options[@]}"; do
        if [[ "$opt" == "返回上一级菜单" ]]; then
            log_info "操作已取消。"
            break
        elif [[ -n "$opt" ]]; then
            log_info "正在设置时区为 $opt..."
            timedatectl set-timezone "$opt"
            log_info "✅ 时区已成功设置为：$opt"
            break
        else
            log_error "无效选项，请输入列表中的数字。"
        fi
    done
    unset PS3
    press_any_key
}
change_ssh_port() {
    clear
    log_info "开始修改 SSH 端口..."

    local current_port
    current_port=$(grep -iE '^#?Port' /etc/ssh/sshd_config | grep -oE '[0-9]+' | head -1)
    current_port=${current_port:-22}

    log_info "当前 SSH 端口是: $YELLOW$current_port$NC\n"

    local new_port
    while true; do
        read -p "请输入新的 SSH 端口 (推荐 1025-65535): " new_port
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
            log_error "无效的端口号。请输入 1-65535 之间的数字。"
        elif [ "$new_port" -eq "$current_port" ]; then
            log_error "新端口不能与当前端口 ($current_port) 相同。"
        elif ss -tln | grep -q ":$new_port\b"; then
            log_error "端口 $new_port 已被其他服务占用，请更换一个。"
        else
            break
        fi
    done

    log_info "新端口 $new_port 验证通过。"

    # 步骤1：处理防火墙 (至关重要)
    if command -v ufw &>/dev/null && ufw status | grep -q 'Status: active'; then
        log_info "检测到 UFW 防火墙，正在为端口 $new_port 创建规则..."
        ufw allow "$new_port/tcp"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        log_info "检测到 firewalld 防火墙，正在为端口 $new_port 创建规则..."
        firewall-cmd --permanent --add-port="$new_port/tcp"
        firewall-cmd --reload
    else
        log_warn "未检测到活动的 UFW 或 firewalld 防火墙。"
        log_warn "请务必手动在你的防火墙 (包括云服务商的安全组) 中开放 TCP 端口 $new_port，否则重启SSH后你将无法连接！"
    fi

    # 步骤2: 处理 SELinux (针对 CentOS/RHEL 等系统)
    if command -v sestatus &>/dev/null && sestatus | grep -q "SELinux status:\s*enabled"; then
        log_info "检测到 SELinux 已启用，正在更新端口策略..."
        # 适配多发行版
        local semanage_dep="policycoreutils-python-utils"
        if [ "$PKG_MANAGER" == "dnf" ]; then
            semanage_dep="python3-policycoreutils"
        fi
        ensure_dependencies "$semanage_dep"
        if command -v semanage &>/dev/null; then
            semanage port -a -t ssh_port_t -p tcp "$new_port"
            log_info "SELinux 策略已更新。"
        else
            log_error "无法执行 semanage 命令。请手动处理 SELinux 策略，否则 SSH 服务可能启动失败！"
        fi
    fi

    # 步骤3：修改 SSH 配置文件
    log_info "正在修改 /etc/ssh/sshd_config 文件..."
    # 自动备份
    sed -i.bak -E "s/^#?Port\s+[0-9]+/Port $new_port/" /etc/ssh/sshd_config

    # 步骤4：重启 SSH 服务
    log_info "正在重启 SSH 服务以应用新端口..."
    if systemctl restart sshd || systemctl restart ssh; then
        log_info "✅ SSH 服务已重启。"
        echo
        log_warn "========================= 重要提醒 ========================="
        log_warn "  SSH 端口已成功修改为: $YELLOW$new_port$NC"
        log_warn "  当前连接不会中断。请立即打开一个新的终端窗口进行测试！"
        log_info "  测试命令: ${GREEN}ssh root@<你的服务器IP> -p $new_port${NC}"
        log_warn "  在确认新端口可以正常登录之前，请【不要关闭】当前窗口！"
        log_warn "============================================================"

    else
        log_error "SSH 服务重启失败！配置可能存在问题。"
        log_error "正在尝试回滚 SSH 端口配置..."
        mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        systemctl restart sshd || systemctl restart ssh
        log_info "配置已回滚到端口 $current_port。请检查 sshd 服务日志。"
    fi

    press_any_key
}
manage_bbr() {
    clear
    log_info "开始检查并管理 BBR..."
    local kernel_version
    kernel_version=$(uname -r | cut -d- -f1)

    if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]]; then
         log_warn "在 CentOS/RHEL 系统上，推荐使用 ELRepo 的最新主线内核以获得最佳 BBR 支持。"
    fi

    if [ "$(printf '%s\n' "4.9" "$kernel_version" | sort -V | head -n1)" != "4.9" ]; then
        log_error "您的内核版本 ($kernel_version) 过低，无法开启 BBR。请升级内核至 4.9 或更高版本。"
        press_any_key
        return
    fi

    log_info "内核版本 $kernel_version 符合要求。"
    local current_congestion_control
    current_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control)
    log_info "当前 TCP 拥塞控制算法为: $YELLOW$current_congestion_control$NC"
    local current_queue_discipline
    current_queue_discipline=$(sysctl -n net.core.default_qdisc)
    log_info "当前网络队列管理算法为: $YELLOW$current_queue_discipline$NC"

    echo -e "\n请选择要执行的操作:"
    echo -e "\n1. 启用 BBR (原始版本)"
    echo -e "\n${GREEN}2. 启用 BBR + FQ${NC} (推荐)"
    echo -e "\n0. 返回\n"
    read -p "请输入选项: " choice

    local sysctl_conf="/etc/sysctl.d/99-bbr.conf"
    rm -f "$sysctl_conf"
    touch "$sysctl_conf"

    case $choice in
    1)
        log_info "正在启用 BBR..."
        echo "net.ipv4.tcp_congestion_control = bbr" >>"$sysctl_conf"
        ;;
    2)
        log_info "正在启用 BBR + FQ..."
        echo "net.core.default_qdisc = fq" >>"$sysctl_conf"
        echo "net.ipv4.tcp_congestion_control = bbr" >>"$sysctl_conf"
        ;;
    0)
        log_info "操作已取消。"
        return
        ;;
    *)
        log_error "无效选项！"
        press_any_key
        return
        ;;
    esac
    log_info "正在应用配置..."
    sysctl -p "$sysctl_conf"
    log_info "✅ 配置已应用！请检查上面的新算法是否已生效。"
    press_any_key
}

install_warp() {
    clear
    log_info "开始安装 WARP..."
    log_warn "本功能将使用 fscarmen 的多功能 WARP 脚本。"
    log_warn "脚本将引导您完成安装，请根据其提示进行选择。"
    press_any_key
    bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh)
    log_info "WARP 脚本执行完毕。按任意键返回主菜单。"
    press_any_key
}
# =================================================
#      Fail2Ban 管理 (fail2ban_menu) - 优化版
# =================================================
fail2ban_menu() {
    ensure_dependencies "fail2ban"
    if ! command -v fail2ban-client &>/dev/null; then
        log_error "Fail2Ban 未能成功安装，请检查依赖。"
        press_any_key
        return
    fi

    if [ ! -f /etc/fail2ban/jail.local ]; then
        log_info "未检测到 jail.local, 正在创建并启用 sshd 防护..."
        cat > /etc/fail2ban/jail.local <<-'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
        systemctl enable fail2ban >/dev/null 2>&1
        systemctl restart fail2ban
    fi

    while true; do
        # 1. 获取所有动态信息
        local f2b_status_text jail_count="N/A" banned_count="N/A" total_banned="N/A"
        if systemctl is-active --quiet fail2ban; then
            f2b_status_text="${GREEN}● 活动$NC"
            local status
            status=$(fail2ban-client status 2>/dev/null)
            jail_count=$(echo "$status" | grep "Jail list" | sed -E 's/.*Jail list:\s*//' | wc -w)
            local sshd_status
            sshd_status=$(fail2ban-client status sshd 2>/dev/null)
            if [ -n "$sshd_status" ]; then
                banned_count=$(echo "$sshd_status" | grep "Currently banned" | awk '{print $NF}')
                total_banned=$(echo "$sshd_status" | grep "Total banned" | awk '{print $NF}')
            else
                banned_count="0"; total_banned="0"
            fi
        else
            f2b_status_text="${RED}● 不活动$NC"
        fi

        # 2. 构建复杂的、包含多行动态信息和颜色的标题
        local title="Fail2Ban 防护管理\n  状态: $f2b_status_text | Jails: $jail_count\n  SSH防护: 当前封禁 ${RED}$banned_count${NC}, 历史共封禁 ${YELLOW}$total_banned${NC}"

        # 3. 定义选项
        local -a options=(
            "查看 Fail2Ban 状态 (及SSH防护详情)"
            "查看最近的日志"
            "手动解封一个 IP 地址"
            "重启 Fail2Ban 服务"
            "卸载 Fail2Ban (卸载)"
        )

        # 4. 调用菜单
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 5. 处理逻辑
        case $choice in
        1)
            clear; log_info "Fail2Ban 总体状态:"; fail2ban-client status;
            echo -e "\n$CYAN---$NC"; log_info "SSHD 防护详情:"; fail2ban-client status sshd;
            press_any_key
            ;;
        2)
            clear; log_info "显示最近 50 条 Fail2Ban 日志:"; tail -50 /var/log/fail2ban.log;
            press_any_key
            ;;
        3)
            read -p "请输入要解封的 IP 地址: " ip_to_unban
            if [ -n "$ip_to_unban" ]; then
                log_info "正在为 SSH 防护解封 IP: $ip_to_unban..."; fail2ban-client set sshd unbanip "$ip_to_unban"
            else
                log_error "IP 地址不能为空！"
            fi
            press_any_key
            ;;
        4)
            log_info "正在重启 Fail2Ban..."; systemctl restart fail2ban; sleep 1; log_info "服务已重启。"
            ;;
        5)
            read -p "确定要卸载 Fail2Ban 吗？(y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                log_info "正在停止并卸载 Fail2Ban..."; systemctl stop fail2ban; systemctl disable fail2ban
                if [ "$PKG_MANAGER" == "apt" ]; then apt-get remove --purge -y fail2ban; else "$PKG_MANAGER" remove -y fail2ban; fi
                rm -rf /etc/fail2ban; log_info "✅ Fail2Ban 已卸载."; press_any_key; return
            fi
            ;;
        0) return ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

list_normal_users() {
    clear
    log_info "正在列出所有普通用户 (UID >= 1000)..."

    local user_list
    user_list=$(awk -F: '$3 >= 1000 && $3 != 65534 {
        printf "  - 用户名: \033[1;37m%-15s\033[0m UID: %-5s Shell: %s\n", $1, $3, $7
        printf "    主目录: %s\n\n", $6
    }' /etc/passwd)

    if [ -n "$user_list" ]; then
        echo -e "$CYAN--------------------------------------------------------------------$NC"
        echo -e "$user_list"
        echo -e "$CYAN--------------------------------------------------------------------$NC"
    else
        log_warn "未找到任何普通用户。"
    fi

    press_any_key
}

manage_users_menu() {
   ensure_dependencies "sudo" "shadow"
    while true; do
        local title="Sudo 用户管理"
        local -a options=(
            "列出所有普通用户"
            "创建一个新的 Sudo 用户"
            "删除一个用户及其主目录 (删除)"
        )
        local choice
        _draw_menu "$title" choice "${options[@]}"
        case $choice in
        1)
            list_normal_users
            ;;
        2)
            clear
            echo -e "请为新用户选择主要的登录方式:\n"
            echo -e "  1. ${YELLOW}密码登录$NC (创建一个带密码的新用户)"
            echo -e "  2. ${GREEN}密钥登录$NC (创建用户, 并从现有用户复制公钥)"
            echo -e "\n  0. 返回\n"
            read -p "请输入选项: " login_choice

            if [[ "$login_choice" != "1" && "$login_choice" != "2" ]]; then
                continue
            fi

            read -p "请输入新用户名 (必须以小写字母开头): " username
            if [ -z "$username" ]; then log_error "用户名不能为空！"; press_any_key; continue; fi
            if ! [[ "$username" =~ ^[a-z][a-z0-9_-]*$ ]]; then log_error "用户名格式不正确！"; press_any_key; continue; fi
            if id "$username" &>/dev/null; then log_error "用户 '$username' 已存在！"; press_any_key; continue; fi

            useradd -m -s /bin/bash "$username"
            if [ $? -ne 0 ]; then
                log_error "创建用户 '$username' 失败！"
                press_any_key
                continue
            fi

            local sudo_group="sudo"
            if [ "$OS_ID" == "centos" ] || [ "$OS_ID" == "rhel" ] || [ "$OS_ID" == "fedora" ]; then
                sudo_group="wheel"
            fi
            usermod -aG "$sudo_group" "$username"
            log_info "✅ 用户 '$username' 已创建并添加到 $sudo_group 组。"

            if [ "$login_choice" == "1" ]; then
                log_info "请为用户 '$username' 设置密码。"
                passwd "$username"
                if [ $? -eq 0 ]; then
                    log_info "✅ 密码设置成功！"

                    local ssh_config_file="/etc/ssh/sshd_config"
                    if ! grep -q -E "^\s*PasswordAuthentication\s+yes" "$ssh_config_file" || grep -q -E "^\s*AuthenticationMethods"; then
                        echo
                        log_warn "检测到服务器当前可能禁止或限制密码登录。"
                        read -p "是否要自动修改SSH配置以确保密码登录可用? (Y/n): " allow_pwd
                        if [[ ! "$allow_pwd" =~ ^[Nn]$ ]]; then
                            sed -i.bak -E 's/^\s*#?\s*PasswordAuthentication\s+.*/PasswordAuthentication yes/' "$ssh_config_file"
                            if ! grep -q -E "^\s*PasswordAuthentication\s+yes" "$ssh_config_file"; then
                                echo "" >> "$ssh_config_file"; echo "PasswordAuthentication yes" >> "$ssh_config_file"
                            fi
                            sed -i.bak -E 's/^(\s*AuthenticationMethods\s+.*)/#\1/' "$ssh_config_file"

                            log_info "正在重启SSH服务以应用更改..."
                            if systemctl restart ssh || systemctl restart sshd; then
                                log_info "✅ SSH服务已重启, 密码登录应该已开启。"
                            else
                                log_error "SSH服务重启失败！请手动检查。"
                            fi
                        else
                            log_warn "您选择了不修改配置，新用户 '$username' 可能无法通过SSH登录。"
                        fi
                    fi
                else
                    log_error "密码设置失败或被取消！"
                fi
                press_any_key

            elif [ "$login_choice" == "2" ]; then
                log_info "正在为用户 '$username' 配置密钥登录..."
                passwd -l "$username" >/dev/null

                local source_user=""
                local source_key_file=""
                if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && [ -f "/home/$SUDO_USER/.ssh/authorized_keys" ]; then
                    source_user="$SUDO_USER"
                    source_key_file="/home/$source_user/.ssh/authorized_keys"
                else
                    local potential_users=()
                    while IFS= read -r user; do potential_users+=("$user"); done < <(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
                    potential_users+=("root")

                    for user in "${potential_users[@]}"; do
                        local key_path
                        if [ "$user" == "root" ]; then key_path="/root/.ssh/authorized_keys"; else key_path="/home/$user/.ssh/authorized_keys"; fi

                        if [ -s "$key_path" ]; then
                            source_user="$user"
                            source_key_file="$key_path"
                            break
                        fi
                    done
                fi

                if [ -n "$source_user" ]; then
                    log_info "检测到来自用户 '$source_user' 的可用公钥。"
                    mkdir -p "/home/$username/.ssh"
                    cp "$source_key_file" "/home/$username/.ssh/authorized_keys"
                    chown -R "$username:$username" "/home/$username/.ssh"
                    chmod 700 "/home/$username/.ssh"
                    chmod 600 "/home/$username/.ssh/authorized_keys"
                    log_info "✅ SSH 公钥已成功复制。"

                    echo
                    read -p "是否要配置sudo使其无需密码? (推荐 Y/n): " sudo_nopasswd
                    if [[ ! "$sudo_nopasswd" =~ ^[Nn]$ ]]; then
                        local sudo_config_file="/etc/sudoers.d/90-$username-nopasswd"
                        echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudo_config_file"
                        chmod 440 "$sudo_config_file"
                        log_info "✅ Sudo 已配置为免密。下次 '$username' 登录后可直接使用 sudo。"
                    fi
                    log_warn "现在, 你应该可以使用与 '$source_user' 相同的密钥直接登录 '$username' 用户了。"
                else
                    log_error "未在系统中找到任何可用的 SSH 公钥文件进行复制！"
                    log_warn "用户 '$username' 已创建但未配置密钥，且密码已被锁定。"
                fi
                press_any_key
            fi
            ;;
        3)
            clear
            log_info "正在获取可删除的普通用户列表..."

            local deletable_users=()
            mapfile -t deletable_users < <(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)

            if [ ${#deletable_users[@]} -eq 0 ]; then
                log_warn "未找到任何可删除的普通用户。"
                press_any_key
                continue
            fi

            log_info "请选择要删除的用户:\n"
            for i in "${!deletable_users[@]}"; do
                if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" == "${deletable_users[$i]}" ]; then
                     echo -e "   $((i + 1)). ${deletable_users[$i]} ${RED}(当前Sudo用户, 不可删除)${NC}"
                else
                     echo -e "   $((i + 1)). ${deletable_users[$i]}"
                fi
            done
            echo -e "\n   0. 返回\n"

            read -p "请输入选项: " choice_del
            if ! [[ "$choice_del" =~ ^[0-9]+$ ]]; then log_error "无效输入。"; press_any_key; continue; fi
            if [ "$choice_del" -eq 0 ]; then continue; fi
            if [ "$choice_del" -lt 1 ] || [ "$choice_del" -gt ${#deletable_users[@]} ]; then
                log_error "无效选项！"
                press_any_key
                continue
            fi

            local user_to_delete=${deletable_users[$((choice_del - 1))]}

            if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" == "$user_to_delete" ]; then
                log_error "为了系统安全，不能删除当前正在使用的 Sudo 用户 ('$SUDO_USER')！"
                press_any_key
                continue
            fi
            if [ "$user_to_delete" == "root" ]; then log_error "不能删除 root 用户！"; press_any_key; continue; fi

            read -p "警告：这将永久删除用户 '$user_to_delete' 及其主目录下的所有文件！确定吗？(y/N): " confirm_del
            if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                deluser --remove-home "$user_to_delete"
                rm -f "/etc/sudoers.d/90-$user_to_delete-nopasswd"
                log_info "✅ 用户 '$user_to_delete' 已被删除。"
            else
                log_info "操作已取消。"
            fi
            press_any_key
            ;;
        0) return ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
setup_auto_updates() {
    if [ "$PKG_MANAGER" != "apt" ]; then
        log_error "此功能目前仅支持基于 APT 的系统 (Debian/Ubuntu)。"
        press_any_key
        return
    fi

    ensure_dependencies "unattended-upgrades" "apt-listchanges"
    if [ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        log_error "unattended-upgrades 配置文件不存在，配置失败。"
        press_any_key
        return
    fi
    log_info "正在为您配置自动安全更新..."
    dpkg-reconfigure --priority=low -f noninteractive unattended-upgrades
    log_info "✅ unattended-upgrades 已配置并启用。"
    log_warn "系统现在会自动安装重要的安全更新。"
    press_any_key
}
# =================================================
#      性能测试 (performance_test_menu) - 优化版
# =================================================
performance_test_menu() {
     while true; do
        local title="VPS 性能测试"
        local -a options=(
            "VPS 综合性能测试 (bench.sh)"
            "网络速度测试 (speedtest-cli)"
            "实时资源监控 (btop)"
            "流媒体解锁测试"
        )
        local choice
        _draw_menu "$title" choice "${options[@]}"

        case $choice in
        1) log_info "正在执行 bench.sh 脚本..."; ensure_dependencies "curl"; curl -Lso- bench.sh | bash; press_any_key ;;
        2) log_info "正在执行 speedtest-cli..."; ensure_dependencies "speedtest-cli"; speedtest-cli; press_any_key ;;
        3)
            log_info "正在启动 btop...";
            if [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
                log_warn "在 CentOS/RHEL 上, btop 通常位于 EPEL 仓库。如果安装失败，请先手动安装 epel-release 包。"
            fi
            ensure_dependencies "btop"; btop
            ;;
        4) log_info "正在执行流媒体解锁测试脚本..."; ensure_dependencies "bash" "curl" "jq"; bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh); press_any_key ;;
        0) return ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
backup_directory() {
    clear
    log_info "开始手动备份指定目录..."

    local source_dir
    read -e -p "请输入需要备份的目录的绝对路径 (例如 /var/www): " source_dir
    if [ ! -d "$source_dir" ]; then
        log_error "目录 '$source_dir' 不存在或不是一个目录！"
        press_any_key
        return
    fi

    local backup_dest
    read -e -p "请输入备份文件存放的目标目录 [默认: /root]: " backup_dest
    backup_dest=${backup_dest:-"/root"}
    if [ ! -d "$backup_dest" ]; then
        log_warn "目标目录 '$backup_dest' 不存在，将尝试创建它..."
        mkdir -p "$backup_dest"
        if [ $? -ne 0 ]; then
            log_error "创建目标目录失败！"
            press_any_key
            return
        fi
    fi

    local dir_name
    dir_name=$(basename "$source_dir")
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_filename="${dir_name}_backup_${timestamp}.tar.gz"
    local full_backup_path="$backup_dest/$backup_filename"

    log_info "准备将 '$source_dir' 备份到 '$full_backup_path' ..."
    if tar -czvf "$full_backup_path" -C "$(dirname "$source_dir")" "$dir_name"; then
        log_info "✅ 备份成功！文件大小: $(du -sh "$full_backup_path" | awk '{print $1}')"
    else
        log_error "备份过程中发生错误！"
        rm -f "$full_backup_path"
    fi

    press_any_key
}

start_temp_web_server() {
    ensure_dependencies "python3"
    clear
    read -e -p "请输入要分享的目录 [默认: /root]: " dir
    dir=${dir:-"/root"}
    if [ ! -d "$dir" ]; then log_error "目录不存在！"; press_any_key; return; fi

    read -p "请输入要监听的端口 [默认: 8000]: " port
    port=${port:-8000}
    if ! check_port "$port"; then press_any_key; return; fi

    local ipv4_addr
    ipv4_addr=$(get_public_ip v4)
    log_info "Web 服务器即将启动..."
    log_info "您可以通过以下地址访问:"
    log_info "http://$ipv4_addr:$port"
    log_warn "在当前目录下按 Ctrl+C 即可停止服务。"
    press_any_key

    (cd "$dir" && python3 -m http.server "$port")
}

upload_file_to_transfer() {
    ensure_dependencies "curl"
    clear
    read -e -p "请输入要上传的文件的完整路径: " file_path
    if [ ! -f "$file_path" ]; then
        log_error "文件 '$file_path' 不存在！"
        press_any_key
        return
    fi
    log_info "正在上传文件，请稍候..."

    local upload_url
    upload_url=$(curl --progress-bar --upload-file "$file_path" "https://transfer.sh/$(basename "$file_path")")

    echo ""
    if [[ "$upload_url" == https* ]]; then
        log_info "✅ 文件上传完成，下载链接如下:"
        echo -e "\n$YELLOW$upload_url$NC\n"
    else
        log_error "文件上传失败。服务器返回: $upload_url"
    fi
    press_any_key
}
# =================================================
#      文件分享 (file_sharing_menu) - 优化版
# =================================================
file_sharing_menu() {
    while true; do
        local title="简易文件分享"
        local -a options=(
            "启动临时 Web 服务器 (分享目录)"
            "上传单个文件 (获取分享链接)"
        )
        local choice
        _draw_menu "$title" choice "${options[@]}"

        case $choice in
        1) start_temp_web_server ;;
        2) upload_file_to_transfer ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#      实用工具菜单 (utility_tools_menu) - 优化版
# =================================================
utility_tools_menu() {
    while true; do
        # 1. 定义菜单标题
        local title="实用工具 (增强)"

        # 2. 定义菜单选项数组
        #    为保持简洁，我们移除了子标题，直接列出所有选项
        local -a options=(
            "Fail2Ban 防护管理"
            "Sudo 用户管理"
            "配置自动安全更新"
            "VPS 性能测试"
            "手动备份指定目录"
            "简易文件分享"
        )

        # 3. 调用通用菜单函数
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 4. 根据用户选择执行相应操作
        case $choice in
            1) fail2ban_menu ;;
            2) manage_users_menu ;;
            3) setup_auto_updates ;;
            4) performance_test_menu ;;
            5) backup_directory ;;
            6) file_sharing_menu ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#               Sing-Box 管理 (singbox_main_menu)
# =================================================

is_singbox_installed() {
    if command -v sing-box &>/dev/null; then return 0; else return 1; fi
}

singbox_do_install() {
    ensure_dependencies "curl" "openssl"
    if is_singbox_installed; then
        log_warn "Sing-Box 已经安装，建议先卸载再使用此方法安装特定内核。"
        press_any_key
        return
    fi
    log_info "正在安装特定版本的 Sing-Box 内核..."

    # --- **修正核心之三**：采用与成功脚本相同的内核下载和安装方式 ---
    local ARCH_RAW=$(uname -m)
    local ARCH
    case "${ARCH_RAW}" in
        'x86_64') ARCH='amd64' ;;
        'aarch64' | 'arm64') ARCH='arm64' ;;
        *) log_error "不支持的架构: ${ARCH_RAW}, 无法安装特定内核。"; press_any_key; return 1 ;;
    esac

    log_info "正在从特定源下载 sing-box 内核 for $ARCH..."
    mkdir -p "$SUBSTORE_INSTALL_DIR" # 使用一个已定义的目录变量
    if ! curl -sLo "/usr/local/bin/sing-box" "https://$ARCH.ssss.nyc.mn/sbx"; then
        log_error "特定内核下载失败！"
        press_any_key
        return 1
    fi
    chmod +x "/usr/local/bin/sing-box"

    # 手动创建 systemd 服务文件
    log_info "正在创建 systemd 服务文件..."
    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/etc/sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 创建基础配置文件
    mkdir -p /etc/sing-box
    if [ ! -f "$SINGBOX_CONFIG_FILE" ]; then
        log_info "正在创建兼容的默认配置文件..."
        cat >"$SINGBOX_CONFIG_FILE" <<EOL
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOL
    fi

    log_info "正在重载、启用并启动 Sing-Box 服务..."
    systemctl daemon-reload
    systemctl enable sing-box.service
    systemctl start sing-box

    sleep 2
    if systemctl is-active --quiet sing-box; then
        log_info "✅ 特定版本 Sing-Box 安装并启动成功！"
    else
        log_error "Sing-Box 服务启动失败！请使用 'journalctl -u sing-box -f' 查看日志。"
    fi
    press_any_key
}

singbox_do_uninstall() {
    if ! is_singbox_installed; then
        log_warn "Sing-Box 未安装，无需卸载。"
        press_any_key
        return
    fi
    read -p "你确定要完全卸载 Sing-Box 吗？所有配置文件和节点信息都将被删除！(y/N): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        log_info "卸载操作已取消。"
        press_any_key
        return
    fi

    log_info "正在停止并禁用 Sing-Box 服务..."
    systemctl stop sing-box &>/dev/null
    systemctl disable sing-box &>/dev/null
    log_info "正在删除 Sing-Box 服务文件..."
    rm -f /etc/systemd/system/sing-box.service
    rm -f /etc/sing-box/config.json
    log_info "正在从所有常见路径删除 Sing-Box 可执行文件..."
    rm -f /usr/local/bin/sing-box
    rm -f /usr/bin/sing-box
    rm -f /bin/sing-box
    rm -f /usr/local/sbin/sing-box
    rm -f /sbin/sing-box
    log_info "正在删除 Sing-Box 配置文件和日志..."
    rm -rf /etc/sing-box
    rm -rf /var/log/sing-box
    log_info "正在重载 systemd 配置..."
    systemctl daemon-reload
    if command -v sing-box &>/dev/null; then
        log_error "卸载失败！系统中仍能找到 'sing-box' 命令。"
        log_warn "请手动执行 'whereis sing-box' 查找并删除残留文件。"
    else
        log_info "✅ Sing-Box 已成功卸载。"
    fi
    press_any_key
}

_create_self_signed_cert() {
    local domain_name="$1"
    local cert_dir="/etc/sing-box/certs"
    local cert_path="$cert_dir/$domain_name.cert.pem"
    local key_path="$cert_dir/$domain_name.key.pem"
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        log_info "检测到已存在的自签名证书，将直接使用。"
        return 0
    fi
    log_info "\n正在为域名 $domain_name 生成自签名证书..."
    mkdir -p "$cert_dir"
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" -subj "/CN=$domain_name"
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        log_info "✅ 自签名证书创建成功！"
        log_info "证书路径: $cert_path"
        log_info "密钥路径: $key_path"
        return 0
    else
        log_error "自签名证书创建失败！"
        return 1
    fi
}
# 函数优化版：提示用户选择协议
_singbox_prompt_for_protocols() {
    local -n protocols_ref=$1
    local -n is_one_click_ref=$2

    local title="Sing-Box 节点协议选择"
    local -a options=(
        "${YELLOW}VLESS + REALITY (推荐, 无需域名)${NC}"
        "VLESS + WSS"
        "VMess + WSS"
        "Trojan + WSS"
        "Hysteria2 (UDP)"
        "TUIC v5 (UDP)"
        "${GREEN}一键生成 (除REALITY外) 全部节点${NC}"
    )

    local choice
    _draw_menu "$title" choice "${options[@]}"

    case $choice in
        1) protocols_ref=("VLESS-REALITY") ;;
        2) protocols_ref=("VLESS") ;;
        3) protocols_ref=("VMess") ;;
        4) protocols_ref=("Trojan") ;;
        5) protocols_ref=("Hysteria2") ;;
        6) protocols_ref=("TUIC") ;;
        7)
            protocols_ref=("VLESS" "VMess" "Trojan" "Hysteria2" "TUIC")
            is_one_click_ref=true
            ;;
        0) return 1 ;; # 用户选择返回
        *)
            log_error "无效选择，操作中止。"
            press_any_key
            return 1
            ;;
    esac
    return 0 # 表示用户成功做出了选择
}
# =================================================
#           函数：确保服务器时间精准 (新增)
# =================================================
_ensure_time_accuracy() {
    # 检查常见的几种时间同步服务是否正在运行
    if systemctl is-active --quiet chronyd || systemctl is-active --quiet ntpd || systemctl is-active --quiet systemd-timesyncd; then
        log_info "检测到时间同步服务正在运行，时间被认为是准确的。"
        return 0
    fi

    log_warn "警告：未检测到有效的时间同步服务！"
    log_warn "REALITY 协议对服务器时间的精准度要求极高，任何显著偏差都会导致连接失败。"
    read -p "是否要让脚本为您自动安装并配置 chrony (推荐的时间同步服务)？(Y/n): " confirm_install_chrony

    # 如果用户选择 'n' 或 'N'，则跳过
    if [[ "$confirm_install_chrony" =~ ^[Nn]$ ]]; then
        log_warn "您已选择跳过自动时间同步。如果后续连接失败，请务必手动校准时间！"
        # 返回1表示一个警告状态，但脚本会继续
        return 1
    fi

    log_info "正在为您安装 chrony..."
    if ! ensure_dependencies "chrony"; then
        log_error "chrony 安装失败，请手动安装或检查您的包管理器配置。"
        return 1
    fi

    log_info "正在启动并设置 chrony 服务开机自启..."
    systemctl enable chrony >/dev/null 2>&1
    systemctl start chrony

    log_info "正在强制立即同步时间，这可能需要几秒钟..."
    # 等待服务就绪
    sleep 3
    # 强制进行一次大的时间步进调整，对首次安装非常有效
    chronyc -a makestep

    if [ $? -eq 0 ]; then
        log_info "✅ 时间已成功同步！"
    else
        log_warn "时间同步命令执行可能失败，但 chrony 服务已在后台运行，通常它会稍后自动完成同步。"
    fi
    return 0
}
_singbox_handle_reality_setup() {
    # --- 确保时间准确 ---
    _ensure_time_accuracy

    # 声明-n类型的变量，以引用的方式修改外部变量的值
    local -n private_key_ref=$1
    local -n public_key_ref=$2
    local -n connect_addr_ref=$3
    local -n server_name_ref=$4
    local -n short_id_ref=$5

    clear
    log_info "正在配置 VLESS + REALITY..."
    if ! command -v sing-box &>/dev/null; then
        log_error "未找到 sing-box 命令，无法生成 REALITY 密钥对。"
        return 1
    fi

    log_info "正在生成 REALITY 密钥对..."
    local key_pair
    key_pair=$(sing-box generate reality-keypair)
    private_key_ref=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}')
    public_key_ref=$(echo "$key_pair" | awk '/PublicKey/ {print $2}')

    if [ -z "$private_key_ref" ] || [ -z "$public_key_ref" ]; then
        log_error "REALITY 密钥对生成失败！"
        return 1
    fi
    log_info "✅ 密钥对生成成功！"
    echo -e "${GREEN}公钥 (PublicKey):$NC $public_key_ref"
    echo -e "${RED}私钥 (PrivateKey):$NC $private_key_ref"
    echo ""

    # 选择连接地址 (IP)
    local ipv4_addr=$(get_public_ip v4)
    local ipv6_addr=$(get_public_ip v6)
    if [ -n "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
        echo -e "\n请选择用于节点链接的地址：\n\n1. IPv4: $ipv4_addr\n\n2. IPv6: $ipv6_addr\n"
        read -p "请输入选项 (1-2): " ip_choice
        if [ "$ip_choice" == "2" ]; then connect_addr_ref="$ipv6_addr"; else connect_addr_ref="$ipv4_addr"; fi
    elif [ -n "$ipv4_addr" ]; then log_info "将自动使用 IPv4 地址。"; connect_addr_ref="$ipv4_addr";
    elif [ -n "$ipv6_addr" ]; then log_info "将自动使用 IPv6 地址。"; connect_addr_ref="[$ipv6_addr]";
    else log_error "无法获取任何公网 IP 地址！"; return 1; fi

    # --- **核心优化**：获取并验证伪装域名 (serverName) ---
    while true; do
        read -p "请输入用于伪装的域名 (serverName) [默认: www.microsoft.com]: " server_name_input
        server_name_ref=${server_name_input:-"www.microsoft.com"}

        log_info "正在测试与伪装域名 ($server_name_ref) 的连通性..."
        # 使用curl测试HTTPS连接，-m 5设置5秒超时
        # 只要收到HTTP头（状态码2xx, 3xx, 4xx都行），就证明网络是通的
        if curl -s --head -m 5 "https://$server_name_ref" > /dev/null; then
            log_info "✅ 连通性测试通过。"
            break
        else
            log_error "无法从本机连接到 $server_name_ref。REALITY 依赖此连接。"
            log_warn "请检查域名拼写，或更换一个可从本机访问的域名 (如 www.apple.com, www.microsoft.com)。"
            echo ""
        fi
    done
    # --- **优化结束** ---

    # 自动生成并验证 short_id
    while true; do
        local random_short_id=$(tr -dc '0-9a-f' < /dev/urandom | head -c 8)
        echo -e -n "请输入 short_id [回车则使用: ${GREEN}${random_short_id}${NC}]: "
        read short_id_input
        short_id_input=${short_id_input:-$random_short_id}
        if [[ "$short_id_input" =~ ^[0-9a-fA-F]*$ ]]; then
            short_id_ref=${short_id_input}
            break
        else
            log_error "输入无效！short_id 只能包含 0-9 和 a-f 之间的字符，请重新输入。"
        fi
    done

    log_info "REALITY 配置信息收集完毕。"
    return 0
}
_singbox_handle_certificate_setup() {
    local -n cert_path_ref=$1
    local -n key_path_ref=$2
    local -n connect_addr_ref=$3
    local -n sni_domain_ref=$4
    local -n insecure_params_ref=$5

    clear
    echo -e "\n请选择证书类型：\n\n${GREEN}1. 使用 Let's Encrypt 域名证书 (推荐)$NC\n\n2. 使用自签名证书 (IP 直连)\n"
    read -p "请输入选项 (1-2): " cert_choice

    if [ "$cert_choice" == "1" ]; then
        echo ""
        while true; do
            read -p "请输入您已解析到本机的域名: " domain
            if [[ -z "$domain" ]]; then log_error "域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确。"; else break; fi
        done
        if ! apply_ssl_certificate "$domain"; then log_error "证书处理失败。"; return 1; fi
        cert_path_ref="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_path_ref="/etc/letsencrypt/live/$domain/privkey.pem"
        connect_addr_ref="$domain"
        sni_domain_ref="$domain"
    elif [ "$cert_choice" == "2" ]; then
        insecure_params_ref["ws"]="&allowInsecure=1"
        insecure_params_ref["vmess"]=", \"skip-cert-verify\": true"
        insecure_params_ref["hy2"]="&insecure=1"
        insecure_params_ref["tuic"]="&allow_insecure=1"

        local ipv4_addr=$(get_public_ip v4)
        local ipv6_addr=$(get_public_ip v6)
        if [ -n "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
            echo -e "\n请选择用于节点链接的地址：\n\n1. IPv4: $ipv4_addr\n\n2. IPv6: $ipv6_addr\n"
            read -p "请输入选项 (1-2): " ip_choice
            if [ "$ip_choice" == "2" ]; then connect_addr_ref="[$ipv6_addr]"; else connect_addr_ref="$ipv4_addr"; fi
        elif [ -n "$ipv4_addr" ]; then log_info "将自动使用 IPv4 地址。"; connect_addr_ref="$ipv4_addr";
        elif [ -n "$ipv6_addr" ]; then log_info "将自动使用 IPv6 地址。"; connect_addr_ref="[$ipv6_addr]";
        else log_error "无法获取任何公网 IP 地址！"; return 1; fi

        read -p "请输入 SNI 伪装域名 [默认: www.microsoft.com]: " sni_input
        sni_domain_ref=${sni_input:-"www.microsoft.com"}
        if ! _create_self_signed_cert "$sni_domain_ref"; then log_error "自签名证书处理失败。"; return 1; fi
        cert_path_ref="/etc/sing-box/certs/$sni_domain_ref.cert.pem"
        key_path_ref="/etc/sing-box/certs/$sni_domain_ref.key.pem"
    else
        log_error "无效证书选择。"; return 1;
    fi
    log_info "证书处理完毕。"
    return 0
}
_singbox_prompt_for_ports() {
    local -n protocols_ref=$1
    local -n ports_ref=$2
    local -n used_ports_this_run_ref=$3
    local is_one_click=$4

    # 针对 REALITY 的端口特殊提示
    if [[ " ${protocols_ref[*]} " =~ " VLESS-REALITY " ]]; then
         log_info "\nREALITY 协议需要一个 TCP 端口进行连接。"
    fi

    if $is_one_click; then
        log_info "您已选择一键模式，请为每个协议指定端口。"
        for p in "${protocols_ref[@]}"; do
            while true; do
                local port_prompt="请输入 [$p] 的端口 [回车则随机]: "
                if [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]]; then port_prompt="请输入 [$p] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
                read -p "$(echo -e "$port_prompt")" port_input
                if [ -z "$port_input" ]; then port_input=$(generate_random_port); log_info "已为 [$p] 生成随机端口: $port_input"; fi
                if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then log_error "端口号需为 1-65535。";
                elif _is_port_available "$port_input" "used_ports_this_run_ref"; then
                    ports_ref[$p]=$port_input
                    used_ports_this_run_ref+=("$port_input")
                    break
                fi
            done
        done
    else
        local protocol_name=${protocols_ref[0]}
        while true; do
            local port_prompt="请输入 [$protocol_name] 的端口 [回车则随机]: "
            if [[ "$protocol_name" == "Hysteria2" || "$protocol_name" == "TUIC" ]]; then port_prompt="请输入 [$protocol_name] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
            read -p "$(echo -e "$port_prompt")" port_input
            if [ -z "$port_input" ]; then port_input=$(generate_random_port); log_info "已生成随机端口: $port_input"; fi
            if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then log_error "端口号需为 1-65535。";
            elif _is_port_available "$port_input" "used_ports_this_run_ref"; then
                ports_ref[$protocol_name]=$port_input
                used_ports_this_run_ref+=("$port_input")
                break
            fi
        done
    fi
}
_singbox_build_protocol_config_and_link() {
    local protocol=$1
    local -n args_ref=$2
    local -n config_ref=$3
    local -n link_ref=$4

    local tag=${args_ref[tag]}
    local current_port=${args_ref[port]}
    local uuid=${args_ref[uuid]}
    local password=${args_ref[password]}
    local connect_addr=${args_ref[connect_addr]}
    local sni_domain=${args_ref[sni_domain]}
    local cert_path=${args_ref[cert_path]}
    local key_path=${args_ref[key_path]}
    local insecure_ws=${args_ref[insecure_ws]}
    local insecure_vmess=${args_ref[insecure_vmess]}
    local insecure_hy2=${args_ref[insecure_hy2]}
    local insecure_tuic=${args_ref[insecure_tuic]}

    # REALITY 专属参数
    local private_key=${args_ref[private_key]}
    local public_key=${args_ref[public_key]}
    local short_id=${args_ref[short_id]}


    local tls_config_tcp="{\"enabled\":true,\"server_name\":\"$sni_domain\",\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\"}"
    local tls_config_udp="{\"enabled\":true,\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\",\"alpn\":[\"h3\"]}"

    case $protocol in
    "VLESS-REALITY")
        local reality_tls_config="{\"enabled\": true, \"server_name\": \"$sni_domain\", \"reality\": {\"enabled\": true, \"handshake\": {\"server\": \"$sni_domain\", \"server_port\": 443}, \"private_key\": \"$private_key\", \"short_id\": [\"$short_id\"]}}"

        # --- **核心修正**：移除了错误的 "transport" 字段 ---
        config_ref="{\"type\":\"vless\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"uuid\":\"$uuid\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":$reality_tls_config}"

        link_ref="vless://$uuid@$connect_addr:$current_port?security=reality&sni=$sni_domain&flow=xtls-rprx-vision&publicKey=$public_key&shortId=$short_id#$tag"
        ;;
    "VLESS" | "VMess" | "Trojan")
        config_ref="{\"type\":\"${protocol,,}\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[$(if
            [[ "$protocol" == "VLESS" || "$protocol" == "VMess" ]]
        then echo "{\"uuid\":\"$uuid\"}"; else echo "{\"password\":\"$password\"}"; fi)],\"tls\":$tls_config_tcp,\"transport\":{\"type\":\"ws\",\"path\":\"/\"}}"

        if [[ "$protocol" == "VLESS" ]]; then
            link_ref="vless://$uuid@$connect_addr:$current_port?type=ws&security=tls&sni=$sni_domain&host=$sni_domain&path=%2F${insecure_ws}#$tag"
        elif [[ "$protocol" == "VMess" ]]; then
            local vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$connect_addr\",\"port\":\"$current_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$sni_domain\",\"path\":\"/\",\"tls\":\"tls\"${insecure_vmess}}"
            link_ref="vmess://$(echo -n "$vmess_json" | base64 -w0)"
        else
            link_ref="trojan://$password@$connect_addr:$current_port?security=tls&sni=$sni_domain&type=ws&host=$sni_domain&path=/${insecure_ws}#$tag"
        fi
        ;;
    "Hysteria2")
        config_ref="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"password\":\"$password\"}],\"tls\":$tls_config_udp,\"up_mbps\":100,\"down_mbps\":1000}"
        link_ref="hysteria2://$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3${insecure_hy2}#$tag"
        ;;
    "TUIC")
        config_ref="{\"type\":\"tuic\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"uuid\":\"$uuid\",\"password\":\"$password\"}],\"tls\":$tls_config_udp}"
        link_ref="tuic://$uuid:$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3&congestion_control=bbr${insecure_tuic}#$tag"
        ;;
    esac
}
# =================================================
#           函数: 节点添加总指挥 (增强版)
# =================================================
singbox_add_node_orchestrator() {
    ensure_dependencies "jq" "uuid-runtime" "curl" "openssl"

    local protocols_to_create=()
    local is_one_click=false
    if ! _singbox_prompt_for_protocols protocols_to_create is_one_click; then return; fi

    local cert_path key_path connect_addr sni_domain
    declare -A insecure_params
    local reality_private_key reality_public_key reality_short_id

    # --- 核心逻辑分支：判断是配置 REALITY 还是其他 TLS 协议 ---
    if [[ " ${protocols_to_create[*]} " =~ " VLESS-REALITY " ]]; then
        # 调用 REALITY 专属配置函数
        if ! _singbox_handle_reality_setup reality_private_key reality_public_key connect_addr sni_domain reality_short_id; then
            press_any_key
            return
        fi
    else
        # 调用基于证书的 TLS 配置函数
        if ! _singbox_handle_certificate_setup cert_path key_path connect_addr sni_domain insecure_params; then
            press_any_key
            return
        fi
    fi

    declare -A ports
    local used_ports_for_this_run=()
    _singbox_prompt_for_ports protocols_to_create ports used_ports_for_this_run "$is_one_click"

    log_info "正在获取地理及运营商信息..."
    local geo_info_json
    geo_info_json=$(curl -s ip-api.com/json)

    local city operator_name
    city=$(echo "$geo_info_json" | jq -r '.city // "N/A"' | sed 's/ //g')
    operator_name=$(echo "$geo_info_json" | jq -r '.org // "Custom"' | sed -e 's/ LLC//g' -e 's/ Inc\.//g' -e 's/,//g' -e 's/\.//g' -e 's/ Limited//g' -e 's/ Ltd//g' | awk '{print $1}')

    local custom_id
    echo -e -n "请输入自定义标识 [回车则使用运营商: ${GREEN}${operator_name}${NC}]: "
    read custom_id
    custom_id=${custom_id:-$operator_name}

    local success_count=0
    local final_node_link=""
    local protocols_with_self_signed=()
    if [ ${#insecure_params[@]} -gt 0 ]; then
        protocols_with_self_signed=("${protocols_to_create[@]}")
    fi

    for protocol in "${protocols_to_create[@]}"; do
        local tag_base="$city-$custom_id"
        local base_tag_for_protocol="$tag_base-$protocol"
        local tag=$(_get_unique_tag "$base_tag_for_protocol")
        log_info "已为 [$protocol] 节点分配唯一 Tag: $tag"

        declare -A build_args
        build_args[tag]="$tag"
        build_args[port]=${ports[$protocol]}
        build_args[uuid]=$(uuidgen)
        build_args[password]=$(generate_random_password)
        build_args[connect_addr]="$connect_addr"
        build_args[sni_domain]="$sni_domain"

        if [ "$protocol" == "VLESS-REALITY" ]; then
            build_args[private_key]="$reality_private_key"
            build_args[public_key]="$reality_public_key"
            build_args[short_id]="$reality_short_id"
        else
            build_args[cert_path]="$cert_path"
            build_args[key_path]="$key_path"
            build_args[insecure_ws]=${insecure_params[ws]}
            build_args[insecure_vmess]=${insecure_params[vmess]}
            build_args[insecure_hy2]=${insecure_params[hy2]}
            build_args[insecure_tuic]=${insecure_params[tuic]}
        fi

        local config node_link
        _singbox_build_protocol_config_and_link "$protocol" build_args config node_link

        if _add_protocol_inbound "$protocol" "$config" "$node_link"; then
            ((success_count++))
            final_node_link="$node_link"
        fi
    done

    if [ "$success_count" -gt 0 ]; then
        log_info "共成功添加 $success_count 个节点，正在重启 Sing-Box..."
        # 备份旧配置，以防新配置导致启动失败
        cp "$SINGBOX_CONFIG_FILE" "$SINGBOX_CONFIG_FILE.bak"
        systemctl restart sing-box
        sleep 2
        if systemctl is-active --quiet sing-box; then
            log_info "Sing-Box 重启成功。"
            if [ "$success_count" -eq 1 ] && ! $is_one_click; then
                log_info "✅ 节点添加成功！分享链接如下："
                echo -e "$CYAN--------------------------------------------------------------$NC"
                echo -e "\n$YELLOW$final_node_link$NC\n"
                echo -e "$CYAN--------------------------------------------------------------$NC"
            else
                log_info "正在跳转到节点管理页面..."
                sleep 1
            fi

            # --- **核心优化**：增加 REALITY 和其他协议的最终提醒 ---
            if [[ " ${protocols_to_create[*]} " =~ " VLESS-REALITY " ]]; then
                echo -e "\n$YELLOW=================== VLESS+REALITY 重要提示 ===================$NC"
                log_warn "请务必确保您的服务器防火墙 (及云服务商安全组)"
                log_warn "已经放行了此节点使用的 TCP 端口: ${GREEN}${ports['VLESS-REALITY']}${NC}"
                log_warn "否则，客户端将无法连接！"
                echo -e "$YELLOW==============================================================$NC"
            fi

            if [ ${#protocols_with_self_signed[@]} -gt 0 ]; then
                echo -e "\n$YELLOW====================== IP直连节点重要提示 ====================$NC"
                log_warn "您使用了IP直连方式(自签名证书)，部分客户端需要特殊设置："
                for p in "${protocols_with_self_signed[@]}"; do
                    if [[ "$p" == "VMess" ]]; then
                        echo -e "\n${YELLOW}[VMess 节点]$NC"
                        log_warn "如果连接不通, 请在 Clash Verge 等客户端中, 手动找到该"
                        log_warn "节点的编辑页面, 勾选 ${GREEN}'跳过证书验证' (Skip Cert Verify)${YELLOW} 选项。"
                    fi
                done
                echo -e "\n${YELLOW}[通用提示]$NC"
                log_warn "对于 VLESS, Trojan 等协议，请确保客户端配置中"
                log_warn "与“允许不安全连接”或“跳过证书验证”相关的选项已开启。"
                echo -e "$YELLOW==============================================================$NC"
            fi

            local udp_protocols_created=()
            for p in "${protocols_to_create[@]}"; do
                if [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]]; then
                    udp_protocols_created+=("$p")
                fi
            done
            if [ ${#udp_protocols_created[@]} -gt 0 ]; then
                echo -e "\n$YELLOW======================= UDP 协议重要提示 =======================$NC"
                for p in "${udp_protocols_created[@]}"; do
                    log_warn "[$p 节点] 这是一个 UDP 协议节点, 请务必确保您服务器的防火墙"
                    log_warn "(及云服务商安全组) 已经放行了此节点使用的 UDP 端口: ${GREEN}${ports[$p]}${NC}"
                done
                echo -e "$YELLOW==============================================================$NC"
            fi
            # --- **优化结束** ---

            if [ "$success_count" -gt 1 ] || $is_one_click; then view_node_info; else press_any_key; fi
        else
            log_error "Sing-Box 重启失败！您的新配置可能存在问题。"
            log_error "旧的配置文件已自动恢复。请使用 'journalctl -u sing-box -f' 查看详细日志。"
            # 回滚操作
            mv "$SINGBOX_CONFIG_FILE.bak" "$SINGBOX_CONFIG_FILE"
            press_any_key
        fi
    else
        log_error "没有任何节点被成功添加。"
        press_any_key
    fi
}
_get_unique_tag() {
    local base_tag="$1"
    local final_tag="$base_tag"
    local counter=2
    while jq -e --arg t "$final_tag" 'any(.inbounds[]; .tag == $t)' "$SINGBOX_CONFIG_FILE" >/dev/null; do
        final_tag="$base_tag-$counter"
        ((counter++))
    done
    echo "$final_tag"
}

_add_protocol_inbound() {
    local protocol=$1 config=$2 node_link=$3
    log_info "正在为 [$protocol] 协议添加入站配置..."
    local tmp_file="$SINGBOX_CONFIG_FILE.tmp"
    register_temp_file "$tmp_file"

    if ! jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" >"$tmp_file"; then
        log_error "[$protocol] 协议配置写入失败！请检查JSON格式。"
        return 1
    fi
    mv "$tmp_file" "$SINGBOX_CONFIG_FILE"
    echo "$node_link" >>"$SINGBOX_NODE_LINKS_FILE"
    log_info "✅ [$protocol] 协议配置添加成功！"
    return 0
}

view_node_info() {
    while true; do
        clear;
        if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
            log_warn "暂无配置的节点！"
            echo -e "\n1. 新增节点\n\n0. 返回上一级菜单\n"
            read -p "请输入选项: " choice
            if [[ "$choice" == "1" ]]; then singbox_add_node_orchestrator; continue; else return; fi
        fi

        log_info "当前已配置的节点链接信息："
        echo -e "${CYAN}--------------------------------------------------------------${NC}"

        mapfile -t node_lines < "$SINGBOX_NODE_LINKS_FILE"

        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local node_name
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "VMess节点"')
            fi
            echo -e "\n${GREEN}$((i + 1)). ${WHITE}${node_name}${NC}\n\n${line}"
            echo -e "\n${CYAN}--------------------------------------------------------------${NC}"
        done

        echo -e "\n1. 新增节点  2. 删除节点  3. 推送节点  4. ${YELLOW}生成临时订阅链接${NC}  5. 生成TUIC客户端配置    0. ${GREEN}返回上一级菜单${NC}\n"
        read -p "请输入选项: " choice

        case $choice in
            1) singbox_add_node_orchestrator; continue ;;
            2) delete_nodes; continue ;;
            3)  push_to_sub_store; continue ;;
            4) generate_subscription_link; continue ;;
            5) generate_tuic_client_config; continue ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

delete_nodes() {
    while true; do
        clear
        if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
            log_warn "没有节点可以删除。"
            press_any_key
            return
        fi
        mapfile -t node_lines <"$SINGBOX_NODE_LINKS_FILE"
        declare -A node_tags_map
        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local tag
            tag=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            node_tags_map[$i]=$tag
        done

        log_info "请选择要删除的节点 (可多选，用空格分隔, 输入 'all' 删除所有):\n"

        for i in "${!node_lines[@]}"; do
            local line="${node_lines[$i]}"
            local node_name=${node_tags_map[$i]}
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC\n"

        done
        read -p "请输入编号 (输入 0 返回上一级菜单): " -a nodes_to_delete
        local is_cancel=false
        for choice in "${nodes_to_delete[@]}"; do
            if [[ "$choice" == "0" ]]; then
                is_cancel=true
                break
            fi
        done
        if $is_cancel; then
            log_info "操作已取消，返回上一级菜单。"
            break
        fi
        if [[ "${nodes_to_delete[0]}" == "all" ]]; then
            read -p "你确定要删除所有节点吗？(y/N): " confirm_delete
            if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
                log_info "正在删除所有节点..."
                local tmp_file="$SINGBOX_CONFIG_FILE.tmp"
                register_temp_file "$tmp_file"
                jq '.inbounds = []' "$SINGBOX_CONFIG_FILE" >"$tmp_file" && mv "$tmp_file" "$SINGBOX_CONFIG_FILE"
                rm -f "$SINGBOX_NODE_LINKS_FILE"
                log_info "✅ 所有节点已删除。"
            else
                log_info "操作已取消。"
            fi
            systemctl restart sing-box
            break
        else
            local indices_to_delete=()
            local tags_to_delete=()
            local has_invalid_input=false
            for node_num in "${nodes_to_delete[@]}"; do
                if ! [[ "$node_num" =~ ^[0-9]+$ ]] || [[ $node_num -lt 1 || $node_num -gt ${#node_lines[@]} ]]; then
                    log_error "包含无效的编号: $node_num"
                    has_invalid_input=true
                    break
                fi
                indices_to_delete+=($((node_num - 1)))
                tags_to_delete+=("${node_tags_map[$((node_num - 1))]}")
            done
            if $has_invalid_input; then
                press_any_key
                continue
            fi
            if [ ${#indices_to_delete[@]} -eq 0 ]; then
                log_warn "未输入任何有效节点编号。"
                press_any_key
                continue
            fi
            log_info "正在从 config.json 中删除节点: ${tags_to_delete[*]}"

            local tmp_file1="$SINGBOX_CONFIG_FILE.tmp"
            local tmp_file2="$SINGBOX_CONFIG_FILE.tmp.2"
            register_temp_file "$tmp_file1"
            register_temp_file "$tmp_file2"
            cp "$SINGBOX_CONFIG_FILE" "$tmp_file1"

            for tag in "${tags_to_delete[@]}"; do
                jq --arg t "$tag" 'del(.inbounds[] | select(.tag == $t))' "$tmp_file1" >"$tmp_file2" && mv "$tmp_file2" "$tmp_file1"
            done
            mv "$tmp_file1" "$SINGBOX_CONFIG_FILE"

            local remaining_lines=()
            for i in "${!node_lines[@]}"; do
                local should_keep=true
                for del_idx in "${indices_to_delete[@]}"; do if [[ $i -eq $del_idx ]]; then
                    should_keep=false
                    break
                fi; done
                if $should_keep; then remaining_lines+=("${node_lines[$i]}"); fi
            done
            if [ ${#remaining_lines[@]} -eq 0 ]; then
                rm -f "$SINGBOX_NODE_LINKS_FILE"
            else
                printf "%s\n" "${remaining_lines[@]}" >"$SINGBOX_NODE_LINKS_FILE"
            fi
            log_info "✅ 所选节点已删除。"
            systemctl restart sing-box
            break
        fi
    done
    press_any_key
}

push_to_sub_store() {
    ensure_dependencies "curl" "jq"
    if [ ! -s "$SINGBOX_NODE_LINKS_FILE" ]; then
        log_warn "没有可推送的节点。"
        press_any_key
        return
    fi
    mapfile -t all_node_lines < "$SINGBOX_NODE_LINKS_FILE"

    local selected_links=()
    echo ""
    read -p "是否要手动选择节点? (默认推送全部, 输入 'y' 手动选择): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log_info "请选择要推送的节点 (可多选，用空格分隔):"
        echo ""
        for i in "${!all_node_lines[@]}"; do
            local line="${all_node_lines[$i]}"
            local node_name
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            if [[ "$line" =~ ^vmess:// ]]; then
                node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "$node_name"')
            fi
            echo -e "$GREEN$((i + 1)). $WHITE$node_name$NC\n"
        done
        read -p "请输入编号 (输入 0 返回): " -a selected_indices
        for index in "${selected_indices[@]}"; do
            if [[ "$index" == "0" ]]; then press_any_key; return; fi
            if ! [[ "$index" =~ ^[0-9]+$ ]] || [[ $index -lt 1 || $index -gt ${#all_node_lines[@]} ]]; then
                log_error "包含无效编号: $index"
                press_any_key
                return
            fi
            selected_links+=("${all_node_lines[$((index - 1))]}")
        done
    else
        log_info "已选择推送所有 ${#all_node_lines[@]} 个节点。"
        selected_links=("${all_node_lines[@]}")
    fi

    if [ ${#selected_links[@]} -eq 0 ]; then
        log_warn "未选择任何有效节点。"
        press_any_key
        return
    fi

    local sub_store_config_file="/etc/sing-box/sub-store-config.txt"
    local sub_store_subs
    if [ -f "$sub_store_config_file" ]; then
        sub_store_subs=$(grep "sub_store_subs=" "$sub_store_config_file" | cut -d'=' -f2)
    fi
    echo ""
    read -p "请输入 Sub-Store 的订阅标识 (name) [默认: $sub_store_subs]: " input_subs
    sub_store_subs=${input_subs:-$sub_store_subs}
    if [ -z "$sub_store_subs" ]; then
        log_error "Sub-Store 订阅标识不能为空！"
        press_any_key
        return
    fi

    echo ""
    local action
    read -p "请输入 action 参数 [默认: update]: " action
    action=${action:-"update"}

    local links_str
    links_str=$(printf "%s\n" "${selected_links[@]}")

    local node_json
    node_json=$(jq -n \
        --arg name "$sub_store_subs" \
        --arg link "$links_str" \
        --arg action "$action" \
        '{
            "token": "sanjose",
            "action": $action,
            "name": $name,
            "link": $link
        }')
    local response
    response=$(curl -s -X POST "https://store.wiitwo.eu.org/data" \
        -H "Content-Type: application/json" \
        -d "$node_json")

    if echo "$response" | jq -e '.success' >/dev/null; then
        echo "sub_store_subs=$sub_store_subs" >"$sub_store_config_file"
        log_info "✅ 节点信息已成功推送到 Sub-Store！"
        local success_message
        success_message=$(echo "$response" | jq -r '.message')
        log_info "服务器响应: $success_message"
    else
        local error_message
        error_message=$(echo "$response" | jq -r '.message // "未知错误"')
        log_error "推送到 Sub-Store 失败，服务器响应: $error_message"
    fi
    press_any_key
}
# (V5辅助函数) 智能获取 Nginx 的 Web 根目录
_get_nginx_web_root() {
    if [ -d "/var/www/html" ]; then
        echo "/var/www/html"
    elif [ -d "/usr/share/nginx/html" ]; then
        echo "/usr/share/nginx/html"
    else
        log_warn "无法检测到标准的 Nginx Web 根目录，将默认使用 /var/www/html"
        mkdir -p /var/www/html
        echo "/var/www/html"
    fi
}

# (V5辅助函数) 智能获取 Nginx 的运行用户
_get_nginx_user() {
    # 尝试从 Nginx 主配置文件中解析 user 指令
    if [ -f /etc/nginx/nginx.conf ]; then
        # grep 查找以 'user' 开头（可能前面有空格）的行，排除注释行
        # awk 提取最后一个字段（用户名），然后 sed 去掉分号
        local user=$(grep -E '^\s*user\s+' /etc/nginx/nginx.conf | grep -v '#' | awk '{print $NF}' | sed 's/;//')
        if [ -n "$user" ]; then
            echo "$user"
            return
        fi
    fi
    # 如果找不到，则根据系统类型猜测
    if [ "$PKG_MANAGER" == "apt" ]; then
        echo "www-data" # Debian/Ubuntu 默认用户
    else
        echo "nginx"    # CentOS/RHEL 默认用户
    fi
}
# (V7 - 终极版, 使用独立安全路径和精简配置，杜绝冲突和权限问题)
generate_subscription_link() {
    ensure_dependencies "nginx" "curl"
    if ! command -v nginx &>/dev/null; then
        log_error "Nginx 未安装，无法执行此功能。"
        press_any_key
        return
    fi
    if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
        log_warn "没有可用的节点来生成订阅链接。"
        press_any_key
        return
    fi

    # 1. 主动询问一个您确定已在防火墙/安全组中开放的端口
    local listen_port
    while true; do
        echo ""
        read -p "请输入一个您确定已在防火墙/安全组中开放的TCP端口: " listen_port
        if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            log_error "无效的端口号。请输入 1-65535 之间的数字。"
        elif ss -tln | grep -q -E "(:|:::)$listen_port\b"; then
            log_error "端口 $listen_port 已被本机其他服务占用，请更换一个。"
        else
            break
        fi
    done

    local host
    host=$(get_public_ip v4)
    if [ -z "$host" ]; then
        log_error "无法获取服务器的公网IPv4地址，操作中止。"
        press_any_key
        return
    fi

    # 2. 在 Nginx 自己的工作目录中创建临时文件，避免一切权限问题
    local temp_sub_dir="/var/lib/nginx/vps-toolkit-subs"
    mkdir -p "$temp_sub_dir"
    local sub_filename=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 16)
    local sub_filepath="$temp_sub_dir/$sub_filename"

    register_temp_file "$sub_filepath"
    register_temp_file "$temp_sub_dir"

    mapfile -t node_lines <"$SINGBOX_NODE_LINKS_FILE"
    local all_links_str=$(printf "%s\n" "${node_lines[@]}")
    local base64_content=$(echo -n "$all_links_str" | base64 -w0)
    echo "$base64_content" >"$sub_filepath"

    # 确保 Nginx 用户可以读取
    if command -v chown &>/dev/null; then
        local nginx_user="www-data"
        if [ "$PKG_MANAGER" != "apt" ]; then
           nginx_user="nginx"
        fi
        chown -R ${nginx_user}:${nginx_user} "$temp_sub_dir"
    fi
    chmod 644 "$sub_filepath"


    # 3. 创建一个极其精简、无冲突的 Nginx 临时配置
    local nginx_temp_conf="/etc/nginx/conf.d/000-vps-toolkit-temp.conf"

    log_info "正在创建 Nginx 临时配置以监听端口 ${listen_port}..."
    cat > "$nginx_temp_conf" <<EOF
# 由 vps-toolkit 自动生成，退出后会自动删除
server {
    listen ${listen_port} default_server;
    listen [::]:${listen_port} default_server;

    # 直接将根路径映射到我们创建的临时文件上
    location /${sub_filename} {
        alias ${sub_filepath};
        default_type text/plain;
    }
}
EOF
    register_temp_file "$nginx_temp_conf"

    # 测试并重载 Nginx
    if ! nginx -t; then
        log_error "Nginx 配置测试失败！您的 Nginx 主配置可能存在问题。"
        rm -f "$nginx_temp_conf"
        press_any_key
        return
    fi
    systemctl reload nginx
    log_info "Nginx 配置已成功加载。"

    # 生成最终链接
    local sub_url="http://${host}:${listen_port}/${sub_filename}"

    clear
    log_info "已生成临时订阅链接，请立即复制使用！"
    log_warn "此链接将在您退出脚本后被自动删除。"
    echo -e "$CYAN--------------------------------------------------------------$NC"
    echo -e "\n$YELLOW$sub_url$NC\n"
    echo -e "$CYAN--------------------------------------------------------------$NC"
    press_any_key
}
# (已完善)
generate_tuic_client_config() {
    ensure_dependencies "jq"
    clear

    if [[ ! -f "$SINGBOX_NODE_LINKS_FILE" || ! -s "$SINGBOX_NODE_LINKS_FILE" ]]; then
        log_warn "没有找到任何已配置的节点。"
        press_any_key
        return
    fi

    # 1. 查找所有 TUIC 节点
    mapfile -t tuic_nodes < <(grep "^tuic://" "$SINGBOX_NODE_LINKS_FILE")

    if [ ${#tuic_nodes[@]} -eq 0 ]; then
        log_warn "在当前配置中没有找到任何 TUIC v5 节点。"
        press_any_key
        return
    fi

    local selected_node
    # 2. 如果多于一个，让用户选择
    if [ ${#tuic_nodes[@]} -gt 1 ]; then
        log_info "检测到多个 TUIC 节点，请选择一个以生成配置：\n"
        for i in "${!tuic_nodes[@]}"; do
            local node_name=$(echo "${tuic_nodes[$i]}" | sed 's/.*#\(.*\)/\1/')
            echo " $((i+1)). $node_name"
        done
        echo ""
        read -p "请输入选项: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#tuic_nodes[@]} ]; then
            log_error "无效选项！"
            press_any_key
            return
        fi
        selected_node=${tuic_nodes[$((choice-1))]}
    else
        selected_node=${tuic_nodes[0]}
        log_info "检测到唯一的 TUIC 节点，将为其生成配置。"
    fi

    # 3. 解析分享链接
    log_info "正在解析节点参数..."
    local url_without_prefix=${selected_node#tuic://}
    local creds_and_server=${url_without_prefix%%\?*}
    local query_params=${url_without_prefix#*\?}

    local uuid=$(echo "$creds_and_server" | cut -d: -f1)
    local password=$(echo "$creds_and_server" | cut -d: -f2 | cut -d@ -f1)
    local server_part=$(echo "$creds_and_server" | cut -d@ -f2)
    local server_address=$(echo "$server_part" | rev | cut -d: -f2- | rev)
    local server_port=$(echo "$server_part" | rev | cut -d: -f1 | rev)

    local sni=$(echo "$query_params" | grep -o -E 'sni=[^&]+' | cut -d= -f2)
    local alpn=$(echo "$query_params" | grep -o -E 'alpn=[^&]+' | cut -d= -f2)
    local allow_insecure=$(echo "$query_params" | grep -q 'allow_insecure=1' && echo "true" || echo "false")

    # 4. 动态生成 JSON
    log_info "正在生成客户端 config.json..."
    local client_config
    client_config=$(jq -n \
        --arg server "$server_address:$server_port" \
        --arg uuid "$uuid" \
        --arg password "$password" \
        --arg sni "$sni" \
        --argjson alpn "[\"$alpn\"]" \
        --argjson insecure "$allow_insecure" \
    '{
        "relay": {
            "server": $server,
            "uuid": $uuid,
            "password": $password,
            "udp_relay_mode": "native",
            "congestion_control": "bbr",
            "alpn": $alpn,
            "tls": {
                "sni": $sni,
                "insecure_skip_verify": $insecure
            }
        },
        "local": {
            "server": "127.0.0.1:1080"
        }
    }')

    # 5. 清晰展示
    clear
    log_info "✅ TUIC 客户端配置已生成！"
    echo "您可以将以下内容保存为 \`config.json\` 文件，并使用 \`tuic-client -c config.json\` 命令来启动客户端。"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}${client_config}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"
    press_any_key
}
# =================================================
#           Sing-Box 管理 (singbox_main_menu) - 优化版
# =================================================
singbox_main_menu() {
    while true; do
        local choice

        if is_singbox_installed; then
            # --- Sing-Box 已安装时显示的菜单 ---
            local STATUS_COLOR
            if systemctl is-active --quiet sing-box; then
                STATUS_COLOR="$GREEN● 活动$NC"
            else
                STATUS_COLOR="$RED● 不活动$NC"
            fi
            local title="Sing-Box 管理\n\n  ${NC}当前状态: $STATUS_COLOR\n"

            local -a options=(
                "${GREEN}新增节点${NC}"
                "${YELLOW}管理节点${NC}"
                "启动 Sing-Box"
                "停止 Sing-Box"
                "重启 Sing-Box"
                "查看日志"
                "${RED}卸载 Sing-Box (卸载)${NC}"
            )

            _draw_menu "$title" choice "${options[@]}"

            case $choice in
                1) singbox_add_node_orchestrator ;;
                2) view_node_info ;;
                3) systemctl start sing-box; log_info "命令已发送"; sleep 1 ;;
                4) systemctl stop sing-box; log_info "命令已发送"; sleep 1 ;;
                5) systemctl restart sing-box; log_info "命令已发送"; sleep 1 ;;
                6) clear; journalctl -u sing-box -f --no-pager ;;
                7) singbox_do_uninstall ;;
                0) break ;;
                *) log_error "无效选项！"; sleep 1 ;;
            esac
        else
            # --- Sing-Box 未安装时显示的菜单 ---
            local title="Sing-Box 管理\n$CYAN──────────────────────────────────────────────────\n  ${NC}当前状态: $YELLOW● 未安装$NC"
            local -a options=("安装 Sing-Box")

            _draw_menu "$title" choice "${options[@]}"

            case $choice in
                1) singbox_do_install ;;
                0) break ;;
                *) log_error "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}
# =================================================
#                Sub-Store 管理 (V2 - 双模安装)
# =================================================

# --- 辅助检测函数 ---
is_substore_installed_baremetal() {
    if [ -f "$SUBSTORE_SERVICE_FILE" ]; then return 0; else return 1; fi
}

is_substore_installed_docker() {
    if command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' | grep -q "^sub-store$"; then
        return 0
    else
        return 1
    fi
}
# --- Docker 版安装函数 (链接修正版) ---
substore_do_install_docker() {
    # 1. 确保 Docker 已安装
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续。"
        press_any_key
        return
    fi
    clear
    log_info "开始使用 Docker 安装 Sub-Store (镜像: xream/sub-store)..."

    # 2. 检查并处理旧容器
    if is_substore_installed_docker; then
        log_warn "检测到已存在的同名 (sub-store) 容器。"
        read -p "是否要停止并删除旧容器以进行全新安装？(y/N): " confirm_remove
        if [[ "$confirm_remove" =~ ^[Yy]$ ]]; then
            log_info "正在停止并删除旧的 sub-store 容器..."
            docker stop sub-store &>/dev/null
            docker rm sub-store &>/dev/null
            log_info "旧容器已移除。"
        else
            log_error "安装中止，因为已存在的容器未被移除。"
            press_any_key
            return
        fi
    fi

    # 3. 收集用户配置
    local data_dir
    read -e -p "请输入 Sub-Store 的数据存放目录 [默认: /root/sub-store-data]: " data_dir
    data_dir=${data_dir:-"/root/sub-store-data"}
    mkdir -p "$data_dir"
    log_info "数据将保存在: $data_dir"

    local backend_path
    read -p "请输入后端的访问路径 (API Key) [回车则随机生成]: " backend_path_input
    backend_path=${backend_path_input:-$(generate_random_password)}
    if [[ ! "$backend_path" == /* ]]; then
        backend_path="/$backend_path"
    fi
    log_info "后端访问路径 (API Key) 设置为: ${backend_path}"

    local external_port
    while true; do
        read -p "请输入 Sub-Store 的外部访问端口 [默认: 3001]: " port_input
        external_port=${port_input:-"3001"}
        if check_port "$external_port"; then break; fi
    done

    local cron_schedule
    read -p "请输入后端的自动同步 CRON 表达式 [默认: 55 23 * * *]: " cron_schedule
    cron_schedule=${cron_schedule:-"55 23 * * *"}

    # 4. 构建并执行命令 (使用数组以保证健壮性)
    log_info "正在构建 docker run 命令..."

    local docker_args=("run" "-d" "--restart=always")
    docker_args+=("-e" "SUB_STORE_FRONTEND_BACKEND_PATH=${backend_path}")
    docker_args+=("-e" "SUB_STORE_BACKEND_SYNC_CRON=${cron_schedule}")

    read -p "是否要配置 Telegram 推送通知? (y/N): " configure_tg
    if [[ "$configure_tg" =~ ^[Yy]$ ]]; then
        local tg_api_key tg_chat_id
        read -p "请输入 Telegram Bot API Key: " tg_api_key
        read -p "请输入 Telegram Chat ID: " tg_chat_id
        if [ -n "$tg_api_key" ] && [ -n "$tg_chat_id" ]; then
            local push_url="https://api.telegram.org/bot${tg_api_key}/sendMessage?chat_id=${tg_chat_id}&text=[推送标题][推送内容]?group=SubStore&autoCopy=1&isArchive=1&sound=shake&level=timeSensitive&icon=https%3A%2F%2Fraw.githubusercontent.com%2F58xinian%2Ficon%2Fmaster%2FSub-Store1.png"
            docker_args+=("-e" "SUB_STORE_PUSH_SERVICE=${push_url}")
            log_info "Telegram 推送已配置。"
        else
            log_warn "API Key 或 Chat ID 为空，已跳过 Telegram 配置。"
        fi
    fi

    docker_args+=("-p" "${external_port}:3001")
    docker_args+=("-v" "${data_dir}:/opt/app/data")
    docker_args+=("--name" "sub-store")
    docker_args+=("xream/sub-store")

    echo -e "\n${YELLOW}将要执行以下命令:${NC}"
    printf "docker "
    for arg in "${docker_args[@]}"; do
        if [[ "$arg" == *" "* ]]; then
            printf "'%s' " "$arg"
        else
            printf "%s " "$arg"
        fi
    done
    echo -e "\n"
    read -p "确认无误后按 Enter 键继续..."

    if docker "${docker_args[@]}"; then
        log_info "正在等待容器启动 (等待 5 秒)..."
        sleep 5
        if is_substore_installed_docker; then
            log_info "✅ Sub-Store (Docker版) 安装并启动成功！"
            local public_ip
            public_ip=$(get_public_ip v4)

            local backend_url="http://${public_ip}:${external_port}${backend_path}"
            local final_url="http://${public_ip}:${external_port}/subs?api=${backend_url}"

            echo -e "$CYAN-------------------- Sub-Store 访问信息 ---------------------$NC\n"
            log_info "请通过以下链接访问 (如果防火墙允许):"
            echo -e "\n  $YELLOW$final_url$NC\n"
            echo -e "$CYAN-----------------------------------------------------------$NC"

            touch "$data_dir/.docker_install_flag"

            read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                local domain
                read -p "请输入您已解析好的域名: " domain
                if [ -n "$domain" ]; then
                    if setup_auto_reverse_proxy "$domain" "$external_port"; then
                        log_info "✅ 反向代理设置成功！请通过 https://$domain 访问。"
                        local proxy_backend_url="https://$domain$backend_path"
                        local proxy_final_url="https://$domain/subs?api=$proxy_backend_url"
                        echo -e "优化后的访问链接为: \n\n$YELLOW$proxy_final_url$NC\n"
                        echo "$domain" > "$data_dir/.proxy_domain_docker"
                    else
                        log_error "反向代理设置失败。"
                    fi
                fi
            fi
        else
            log_error "Sub-Store 容器启动失败！请使用 'docker logs sub-store' 查看日志排查。"
        fi
    else
        log_error "执行 docker 命令失败！请检查 Docker 是否正在运行以及镜像名称是否正确。"
    fi
    press_any_key
}
# --- 宿主机版安装函数 (原 substore_do_install) ---
substore_do_install_baremetal() {
    if ! ensure_dependencies "curl" "unzip" "git"; then
        log_error "基础依赖安装失败，无法继续。"
        press_any_key
        return
    fi
    log_info "开始执行 Sub-Store [健壮版-宿主机] 安装流程..."
    local FNM_DIR="/root/.fnm"
    local FNM_PATH="$FNM_DIR/fnm"
    if [ ! -f "$FNM_PATH" ]; then
        log_info "正在安装 FNM (Node.js 版本管理器)..."
        if ! curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell; then
            log_error "FNM 安装脚本执行失败！"; press_any_key; return
        fi
    else
        log_info "FNM 已安装，跳过。"
    fi
    export PATH="$FNM_DIR:$PATH"
    eval "$($FNM_PATH env)"
    log_info "正在使用 FNM 安装 Node.js (lts/iron)..."
    if ! $FNM_PATH install lts/iron; then
        log_error "Node.js (lts/iron) 安装失败！"; press_any_key; return
    fi
    $FNM_PATH use lts/iron
    local NODE_EXEC_PATH
    NODE_EXEC_PATH=$(which node)
    if [ -z "$NODE_EXEC_PATH" ] || [ ! -f "$NODE_EXEC_PATH" ]; then
        log_error "无法找到由 FNM 安装的 Node.js 可执行文件路径！安装中止。"; press_any_key; return
    fi
    log_info "成功定位到 Node.js 的绝对路径: $NODE_EXEC_PATH"
    if ! command -v pnpm &>/dev/null; then
        log_info "正在安装 pnpm..."
        if ! curl -fsSL https://get.pnpm.io/install.sh | sh -; then
            log_error "pnpm 安装失败！"; press_any_key; return
        fi
        export PNPM_HOME="$HOME/.local/share/pnpm"
        export PATH="$PNPM_HOME:$PATH"
    fi
    log_info "正在下载并设置 Sub-Store 项目文件..."
    mkdir -p "$SUBSTORE_INSTALL_DIR"
    cd "$SUBSTORE_INSTALL_DIR" || exit 1
    log_info "正在下载后端文件: sub-store.bundle.js"
    if ! curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js; then
        log_error "下载 sub-store.bundle.js 失败！请检查网络。"; press_any_key; return
    fi
    log_info "正在下载前端文件: dist.zip"
    if ! curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip; then
        log_error "下载 dist.zip 失败！请检查网络。"; press_any_key; return
    fi
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"
    log_info "开始配置系统服务...\n"
    local API_KEY
    read -p "请输入 Sub-Store 的 API 密钥 [回车则随机生成]: " user_api_key
    API_KEY=${user_api_key:-$(generate_random_password)}
    log_info "最终使用的 API 密钥为: ${API_KEY}\n"
    local FRONTEND_PORT
    while true; do
        read -p "请输入前端访问端口 [默认: 3000]: " port_input
        FRONTEND_PORT=${port_input:-"3000"}
        if check_port "$FRONTEND_PORT"; then break; fi
    done
    local BACKEND_PORT
    while true; do
        echo ""
        read -p "请输入后端 API 端口 [默认: 3001]: " backend_port_input
        BACKEND_PORT=${backend_port_input:-"3001"}
        if [ "$BACKEND_PORT" == "$FRONTEND_PORT" ]; then log_error "后端端口不能与前端端口相同!"; else
            if check_port "$BACKEND_PORT"; then break; fi
        fi
    done
    log_info "正在创建 systemd 服务文件..."
    cat <<EOF >"$SUBSTORE_SERVICE_FILE"
[Unit]
Description=Sub-Store Service
After=network-online.target
Wants=network-online.target

[Service]
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/${API_KEY}"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=${SUBSTORE_INSTALL_DIR}/frontend"
Environment="SUB_STORE_FRONTEND_HOST=::"
Environment="SUB_STORE_FRONTEND_PORT=${FRONTEND_PORT}"
Environment="SUB_STORE_DATA_BASE_PATH=${SUBSTORE_INSTALL_DIR}"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=${BACKEND_PORT}"
ExecStart=${NODE_EXEC_PATH} ${SUBSTORE_INSTALL_DIR}/sub-store.bundle.js
Type=simple
User=root
Group=root
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    log_info "正在启动并启用 sub-store 服务..."
    systemctl daemon-reload
    systemctl enable "$SUBSTORE_SERVICE_NAME" >/dev/null
    systemctl start "$SUBSTORE_SERVICE_NAME"
    log_info "正在检测服务状态 (等待 5 秒)..."
    sleep 5
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ 服务状态正常 (active)。"
        substore_view_access_link
    else
        log_error "服务启动失败！请使用 'journalctl -u $SUBSTORE_SERVICE_NAME -f' 查看日志排查。"
    fi

    read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        substore_setup_reverse_proxy
    else
        press_any_key
    fi
}


# --- 安装方式选择 (新的路由函数) ---
substore_do_install() {
    clear
    echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
    echo -e "$CYAN║$WHITE                 选择安装方式                     $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   1. ${GREEN}Docker 版安装 (推荐, 隔离性好)${NC}              $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   2. 宿主机版安装 (直接部署, 占用低)             $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
    echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
    read -p "请输入选项: " choice
    case $choice in
        1) substore_do_install_docker ;;
        2) substore_do_install_baremetal ;;
        0) return ;;
        *) log_error "无效选项!"; sleep 1 ;;
    esac
}


# --- Docker 版卸载函数 (新增) ---
substore_do_uninstall_docker() {
    if ! is_substore_installed_docker; then
        log_warn "Sub-Store (Docker版) 未安装，无需卸载。"
        press_any_key
        return
    fi
    log_info "正在准备卸载 Sub-Store (Docker版)..."
    docker stop sub-store &>/dev/null
    local data_dir
    data_dir=$(docker inspect sub-store | jq -r '.[0].HostConfig.Binds[]' | grep ':/opt/app/data' | cut -d':' -f1)
    if [ -z "$data_dir" ]; then
        read -e -p "无法自动检测到数据目录，请输入您的数据目录路径 (例如 /root/sub-store-data): " data_dir
    fi
    if [ ! -d "$data_dir" ]; then
         log_warn "指定的数据目录 '$data_dir' 不存在。将仅删除容器。"
    else
        local proxy_domain_file="$data_dir/.proxy_domain_docker"
        if [ -f "$proxy_domain_file" ]; then
            local domain=$(cat "$proxy_domain_file")
            log_warn "检测到此应用关联了反向代理域名: $domain"
            read -p "是否要在卸载应用的同时，删除其反代配置和SSL证书? (y/N): " confirm_delete_proxy
            if [[ "$confirm_delete_proxy" =~ ^[Yy]$ ]]; then
                _cleanup_reverse_proxy_config "$domain"
            fi
        fi
    fi
    read -p "警告：这将永久删除 sub-store 容器！此操作不可逆！是否继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"; docker start sub-store &>/dev/null; press_any_key; return
    fi
    log_info "正在删除 sub-store 容器..."
    docker rm sub-store &>/dev/null
    if [ -d "$data_dir" ]; then
        read -p "是否要删除数据目录 '$data_dir' 及其所有文件？(y/N): " confirm_delete_dir
        if [[ "$confirm_delete_dir" =~ ^[Yy]$ ]]; then
            log_info "正在删除数据目录 $data_dir ..."; rm -rf "$data_dir"; log_info "数据目录已删除。"
        fi
    fi
    log_info "✅ Sub-Store (Docker版) 卸载完成。"; press_any_key
}


# --- 宿主机版卸载函数 (原 substore_do_uninstall) ---
substore_do_uninstall_baremetal() {
    if ! is_substore_installed_baremetal; then
        log_warn "Sub-Store (宿主机版) 未安装，无需卸载。"; press_any_key; return
    fi
    read -p "你确定要完全卸载 Sub-Store (宿主机版) 吗？所有配置文件都将被删除！(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"; press_any_key; return
    fi
    set -e
    log_info "正在停止并禁用 Sub-Store 服务..."
    systemctl stop "$SUBSTORE_SERVICE_NAME"
    systemctl disable "$SUBSTORE_SERVICE_NAME"
    log_info "正在删除服务文件..."
    rm -f "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload
    log_info "正在删除 Sub-Store 安装目录..."
    rm -rf "$SUBSTORE_INSTALL_DIR"
    set +e
    log_info "✅ Sub-Store (宿主机版) 已成功卸载。"; press_any_key
}


# --- 智能卸载路由函数 (新的 substore_do_uninstall) ---
substore_do_uninstall() {
    if is_substore_installed_docker; then
        substore_do_uninstall_docker
    elif is_substore_installed_baremetal; then
        substore_do_uninstall_baremetal
    else
        log_warn "未检测到任何版本的 Sub-Store 安装。"
        press_any_key
    fi
}


# --- 后续管理函数 (保持不变或稍作调整以兼容) ---

update_sub_store_app() {
    if is_substore_installed_docker; then
        log_info "您安装的是 Docker 版本，更新方式如下："
        echo "1. docker stop sub-store"
        echo "2. docker rm sub-store"
        echo "3. docker pull xream/sub-store:latest"
        echo "4. 使用您初次安装时的参数重新运行 docker run 命令即可。"
        press_any_key
        return
    fi
    if ! is_substore_installed_baremetal; then
        log_warn "Sub-Store (宿主机版) 未安装，无法更新。"; press_any_key; return
    fi
    log_info "正在准备更新 Sub-Store (宿主机版)..."
    cd "$SUBSTORE_INSTALL_DIR" || { log_error "无法进入安装目录: $SUBSTORE_INSTALL_DIR"; return; }
    log_info "正在下载最新的后端 bundle..."
    if ! curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js.new; then
        log_error "下载后端文件失败！"; rm -f sub-store.bundle.js.new; press_any_key; return
    fi
    log_info "正在下载最新的前端资源..."
    if ! curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip.new; then
        log_error "下载前端资源失败！"; rm -f dist.zip.new sub-store.bundle.js.new; press_any_key; return
    fi
    log_info "正在备份旧文件并应用更新..."
    mv sub-store.bundle.js sub-store.bundle.js.bak
    mv sub-store.bundle.js.new sub-store.bundle.js
    rm -rf frontend.bak
    mv frontend frontend.bak
    unzip -q -o dist.zip.new && mv dist frontend && rm dist.zip.new
    log_info "文件更新完毕，正在重启服务..."
    systemctl restart "$SUBSTORE_SERVICE_NAME"
    sleep 3
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ Sub-Store 更新成功并已重启！"
    else
        log_error "服务重启失败，请使用日志功能排查问题。"
    fi
    press_any_key
}

substore_view_access_link() {
    # 智能检测并显示不同版本的访问链接
    if is_substore_installed_docker; then
        # Docker 版的访问链接逻辑
        clear
        log_info "正在检测 Sub-Store (Docker版) 访问信息..."
        # 增加容器不存在的保护
        if ! docker inspect sub-store &>/dev/null; then
            log_error "Sub-Store Docker 容器不存在或已被删除！"
            press_any_key
            return
        fi
        local container_info
        container_info=$(docker inspect sub-store)
        local external_port
        external_port=$(echo "$container_info" | jq -r '.[0].HostConfig.PortBindings."3001/tcp"[0].HostPort')
        local backend_path
        backend_path=$(echo "$container_info" | jq -r '.[0].Config.Env[]' | grep 'SUB_STORE_FRONTEND_BACKEND_PATH' | cut -d'=' -f2)
        local data_dir
        data_dir=$(echo "$container_info" | jq -r '.[0].HostConfig.Binds[]' | grep ':/opt/app/data' | cut -d':' -f1)

        local public_ip
        public_ip=$(get_public_ip v4)

        echo -e "$CYAN----------------- Sub-Store (Docker版) 访问信息 -----------------$NC\n"

        if [ -f "$data_dir/.proxy_domain_docker" ]; then
            local domain
            domain=$(cat "$data_dir/.proxy_domain_docker")
            log_info "检测到反向代理域名，请使用以下链接访问："
            local proxy_backend_url="https://$domain$backend_path"
            local proxy_final_url="https://$domain/subs?api=$proxy_backend_url"
            echo -e "\n  $YELLOW$proxy_final_url$NC\n"
            echo -e "$CYAN-----------------------------------------------------------$NC"
        fi

        log_info "您也可以通过 IP 地址访问 (如果防火墙允许):"
        local backend_url="http://${public_ip}:${external_port}${backend_path}"
        local final_url="http://${public_ip}:${external_port}/subs?api=${backend_url}"
        echo -e "\n  $YELLOW$final_url$NC\n"
        echo -e "$CYAN-----------------------------------------------------------$NC"
        press_any_key
        return
    fi

    if is_substore_installed_baremetal; then
        # 宿主机版的访问链接逻辑
        clear
        local frontend_port
        frontend_port=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')
        local api_key
        api_key=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')
        local ipv4_addr
        ipv4_addr=$(get_public_ip v4)
        local proxy_domain
        proxy_domain=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')

        echo -e "$CYAN----------------- Sub-Store (宿主机版) 访问信息 -----------------$NC\n"
        if [ -n "$proxy_domain" ]; then
            log_info "检测到反向代理域名，请使用以下链接访问："
            local backend_url="https://$proxy_domain$api_key"
            local final_url="https://$proxy_domain/?api=$backend_url"
            echo -e "\n  $YELLOW$final_url$NC\n"
            echo -e "$CYAN-----------------------------------------------------------$NC"
        fi
        log_info "您也可以通过 IP 地址访问 (如果防火墙允许):"
        local ip_backend_url="http://$ipv4_addr:$frontend_port$api_key"
        local ip_final_url="http://$ipv4_addr:$frontend_port/?api=$ip_backend_url"
        echo -e "\n  $YELLOW$ip_final_url$NC\n"
        echo -e "$CYAN-----------------------------------------------------------$NC"
        press_any_key
        return
    fi

    log_warn "未检测到任何 Sub-Store 安装，无法查看链接。"
    press_any_key
}

substore_setup_reverse_proxy() {
    if is_substore_installed_docker; then
        log_info "为 Docker 版 Sub-Store 设置反向代理..."
        local external_port
        external_port=$(docker inspect sub-store | jq -r '.[0].HostConfig.PortBindings."3001/tcp"[0].HostPort')
        local data_dir
        data_dir=$(docker inspect sub-store | jq -r '.[0].HostConfig.Binds[]' | grep ':/opt/app/data' | cut -d':' -f1)

        local domain
        read -p "请输入您的域名: " domain
        if [ -z "$domain" ]; then log_error "域名不能为空，操作已取消。"; press_any_key; return; fi

        if setup_auto_reverse_proxy "$domain" "$external_port"; then
            echo "$domain" > "$data_dir/.proxy_domain_docker"
            log_info "✅ Sub-Store 反向代理设置完成！"
            substore_view_access_link
        else
            log_error "自动反向代理配置失败，请检查之前的错误信息。"
        fi
        press_any_key
        return
    fi

    if ! is_substore_installed_baremetal; then log_warn "请先安装 Sub-Store"; press_any_key; return; fi
    log_info "为宿主机版 Sub-Store 设置反向代理..."
    local frontend_port
    frontend_port=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $NF}' | tr -d '"')
    local domain
    read -p "请输入您的域名: " domain
    if [ -z "$domain" ]; then log_error "域名不能为空，操作已取消。"; press_any_key; return; fi
    setup_auto_reverse_proxy "$domain" "$frontend_port"
    if [ $? -eq 0 ]; then
        log_info "正在将域名保存到服务配置中以供显示..."
        if grep -q 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE"; then
            sed -i.bak "s|SUB_STORE_REVERSE_PROXY_DOMAIN=.*|SUB_STORE_REVERSE_PROXY_DOMAIN=\"$domain\"|" "$SUBSTORE_SERVICE_FILE"
        else
            sed -i.bak "/^\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=$domain\"" "$SUBSTORE_SERVICE_FILE"
        fi
        systemctl daemon-reload
        log_info "✅ Sub-Store 反向代理设置完成！"
        log_info "正在显示最新的访问链接..."; sleep 1
        substore_view_access_link
    else
        log_error "自动反向代理配置失败，请检查之前的错误信息。"
    fi
    press_any_key
}

substore_manage_menu() {
    # 此菜单现在需要根据安装类型显示不同的选项
    # 为简化，我们只修改核心功能，保持此菜单结构，但内部命令会变得更智能
    clear

    local install_type="未知"
    local status_text="${RED}● 不活动   ${NC}"
    local is_baremetal=false
    local is_docker=false

    if is_substore_installed_docker; then
        install_type="Docker版"
        is_docker=true
        if docker ps -q --filter "name=sub-store" --filter "status=running" | grep -q .; then
            status_text="${GREEN}● 活动     ${NC}"
        fi
    elif is_substore_installed_baremetal; then
        install_type="宿主机版"
        is_baremetal=true
        if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
            status_text="${GREEN}● 活动        ${NC}"
        fi
    fi

    local rp_menu_text="设置反向代理 (推荐)"
    # ... 此处可以添加更智能的检测逻辑 ...

    echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
    echo -e "$CYAN║$WHITE                  Sub-Store 管理                  $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    printf "$CYAN║$NC  当前状态: %-10s  |  类型: %-16s $CYAN║$NC\n" "$status_text" "$install_type"
    echo -e "$CYAN╟──────────────────── $WHITE服务控制$CYAN ────────────────────╢$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   1. 启动服务            2. 停止服务             $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   3. 重启服务            4. 查看日志             $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN╟──────────────────── $WHITE参数配置$CYAN ────────────────────╢$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   5. 查看访问链接                                $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN║$NC   6. $YELLOW$rp_menu_text$NC                         $CYAN║$NC"
    echo -e "$CYAN║$NC                                                  $CYAN║$NC"
    echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
    echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
    echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

    read -p "请输入选项: " choice

    if ! $is_docker && ! $is_baremetal; then
        log_warn "未检测到任何 Sub-Store 安装。"; sleep 2; return;
    fi

    case $choice in
    1) if $is_docker; then docker start sub-store; else systemctl start "$SUBSTORE_SERVICE_NAME"; fi; log_info "命令已发送"; sleep 1 ;;
    2) if $is_docker; then docker stop sub-store; else systemctl stop "$SUBSTORE_SERVICE_NAME"; fi; log_info "命令已发送"; sleep 1 ;;
    3) if $is_docker; then docker restart sub-store; else systemctl restart "$SUBSTORE_SERVICE_NAME"; fi; log_info "命令已发送"; sleep 1 ;;
    4) if $is_docker; then clear; docker logs -f sub-store; else clear; journalctl -u "$SUBSTORE_SERVICE_NAME" -f --no-pager; fi ;;
    5) substore_view_access_link ;;
    6) substore_setup_reverse_proxy ;;
    # 暂时移除重置端口和密钥的功能，因为对 Docker 版实现复杂
    # 7) substore_reset_ports ;;
    # 8) substore_reset_api_key ;;
    0) return ;;
    *) log_error "无效选项！"; sleep 1 ;;
    esac
    # 递归调用以刷新状态
    substore_manage_menu
}

# --- 主菜单 (修改后) ---
substore_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                   Sub-Store 管理                 $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        local STATUS_COLOR install_type="未安装"
        if is_substore_installed_docker; then
            install_type="Docker版"
            if docker ps -q --filter "name=sub-store" --filter "status=running" | grep -q .; then
                STATUS_COLOR="$GREEN● 活动     $NC"
            else
                STATUS_COLOR="$RED● 不活动   $NC"
            fi
        elif is_substore_installed_baremetal; then
            install_type="宿主机版"
            if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
                STATUS_COLOR="$GREEN● 活动        $NC"
            else
                STATUS_COLOR="$RED● 不活动      $NC"
            fi
        else
            STATUS_COLOR="$YELLOW● 未安装     $NC"
        fi

        printf "$CYAN║$NC  当前状态: %-10s  |  类型: %-16s $CYAN║$NC\n" "$STATUS_COLOR" "$install_type"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

        if is_substore_installed_docker || is_substore_installed_baremetal; then
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 管理 Sub-Store (启停/日志/配置)             $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   2. $GREEN更新 Sub-Store 应用$NC                         $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   3. $RED卸载 Sub-Store$NC                              $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) substore_manage_menu ;; 2) update_sub_store_app ;;
            3) substore_do_uninstall ;; 0) break ;; *) log_warn "无效选项！"; sleep 1 ;;
            esac
        else
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. 安装 Sub-Store                              $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
            read -p "请输入选项: " choice
            case $choice in
            1) substore_do_install ;; 0) break ;; *) log_warn "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}
# =================================================
#               哪吒监控 (nezha_main_menu)
# =================================================

is_nezha_agent_v0_installed() { [ -f "/etc/systemd/system/nezha-agent-v0.service" ]; }
is_nezha_agent_phoenix_installed() { [ -f "/etc/systemd/system/nezha-agent-phoenix.service" ]; }

uninstall_nezha_agent_v0() {
    if ! is_nezha_agent_v0_installed; then
        log_warn "San Jose V0 探针未安装，无需卸载。"
    else
        log_info "正在停止并禁用 nezha-agent-v0 服务..."
        systemctl stop nezha-agent-v0.service &>/dev/null
        systemctl disable nezha-agent-v0.service &>/dev/null
        rm -f /etc/systemd/system/nezha-agent-v0.service
        rm -rf /opt/nezha/agent-v0
        systemctl daemon-reload
        log_info "✅ SanJose V0 探针已成功卸载。"
    fi
    press_any_key
}


uninstall_nezha_agent_phoenix() {
    if ! is_nezha_agent_phoenix_installed; then
        log_warn "Phoenix Nezha V1 探针未安装，无需卸载。"
    else
        log_info "正在停止并禁用 nezha-agent-phoenix 服务..."
        systemctl stop nezha-agent-phoenix.service &>/dev/null
        systemctl disable nezha-agent-phoenix.service &>/dev/null
        rm -f /etc/systemd/system/nezha-agent-phoenix.service
        rm -rf /opt/nezha/agent-phoenix
        systemctl daemon-reload
        log_info "✅ Phoenix Nezha V1 探针已成功卸载。"
    fi
    press_any_key
}

install_and_adapt_nezha_agent() {
    local version_id="$1"
    local official_script_url="$2"
    local install_command="$3"
    local service_name="nezha-agent-$version_id"
    local install_dir="/opt/nezha/agent-$version_id"
    local service_file="/etc/systemd/system/$service_name.service"

    log_info "正在为 Nezha Agent ($version_id) 执行通用安装流程..."

    if [ -f "$service_file" ]; then
        log_warn "检测到旧的 ($version_id) 安装，将先执行卸载..."
        systemctl stop "$service_name" &>/dev/null
        systemctl disable "$service_name" &>/dev/null
        rm -f "$service_file"
        rm -rf "$install_dir"
        systemctl daemon-reload
        log_info "旧版本清理完毕。"
    fi

    ensure_dependencies "curl" "wget" "unzip"

    local script_tmp_path="/tmp/nezha_install_${version_id}.sh"
    register_temp_file "$script_tmp_path"
    log_info "正在下载官方安装脚本..."
    if ! curl -L "$official_script_url" -o "$script_tmp_path"; then
        log_error "下载官方脚本失败！"
        press_any_key
        return 1
    fi
    chmod +x "$script_tmp_path"

    log_info "第1步：执行官方原版脚本进行标准安装..."
    eval "$install_command"
    rm "$script_tmp_path"

    if ! [ -f "/etc/systemd/system/nezha-agent.service" ]; then
        log_error "官方脚本未能成功创建标准服务，操作中止。"
        press_any_key
        return 1
    fi
    log_info "标准服务安装成功，即将开始改造..."
    sleep 1

    log_info "第2步：停止标准服务并重命名文件以实现隔离..."
    systemctl stop nezha-agent.service &>/dev/null
    systemctl disable nezha-agent.service &>/dev/null
    mv /etc/systemd/system/nezha-agent.service "$service_file"
    mv /opt/nezha/agent "$install_dir"

    log_info "第3步：修改新的服务文件，使其指向正确的路径..."
    sed -i.bak "s|/opt/nezha/agent|$install_dir|g" "$service_file"

    log_info "第4步：重载并启动改造后的 '$service_name' 服务..."
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl start "$service_name"

    log_info "检查最终服务状态..."
    sleep 2
    if systemctl is-active --quiet "$service_name"; then
        log_info "✅ Nezha Agent ($version_id) (隔离版) 已成功安装并启动！"
    else
        log_error "Nezha Agent ($version_id) (隔离版) 最终启动失败！"
        log_warn "显示详细状态以供诊断:"
        systemctl status "$service_name" --no-pager -l
    fi
    press_any_key
}

_nezha_v1_style_installer() {
    local version_id="$1"
    local friendly_name="$2"
    local server_info="$3"
    local server_secret="$4"

    local user_command
    read -p "您正在安装 $friendly_name 探针，请输入安装指令以继续: " user_command
    if [ "$user_command" != "csos" ]; then
        log_error "指令错误，安装已中止。"
        press_any_key
        return 1
    fi

    local NZ_TLS="false"
    local script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh"
    local command_to_run="export NZ_SERVER='$server_info' NZ_TLS='$NZ_TLS' NZ_CLIENT_SECRET='$server_secret'; bash /tmp/nezha_install_${version_id}.sh"

    install_and_adapt_nezha_agent "$version_id" "$script_url" "$command_to_run"
}

install_nezha_agent_v0() {
    local server_key
    read -p "请输入San Jose V0哪吒面板密钥: " server_key
    if [ -z "$server_key" ]; then
        log_error "面板密钥不能为空！操作中止。"
        press_any_key
        return
    fi

    local server_addr="nz.wiitwo.eu.org"
    local server_port="443"
    local tls_option="--tls"
    local script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/install_en.sh"
    local command_to_run="bash /tmp/nezha_install_v0.sh install_agent $server_addr $server_port $server_key $tls_option"

    install_and_adapt_nezha_agent "v0" "$script_url" "$command_to_run"
}
install_nezha_agent_phoenix() {
    _nezha_v1_style_installer "phoenix" "Phoenix V1" "nz.chat.nyc.mn:8008" "XuqVRw4XcOtDDFwz8ipJN9v7HcQZe7M3"
}

install_nezha_dashboard_v0() {
    ensure_dependencies "wget"
    log_info "即将运行 fscarmen 的 V0 面板安装/管理脚本..."
    press_any_key
    bash <(wget -qO- https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh)
    log_info "脚本执行完毕。"
    press_any_key
}

install_nezha_dashboard_v1() {
    ensure_dependencies "curl"
    log_info "即将运行官方 V1 面板安装/管理脚本..."
    press_any_key
    curl -L https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
    log_info "脚本执行完毕。"
    press_any_key
}

nezha_agent_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE               哪吒探针 (Agent) 管理              $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"

        local v0_status
        if is_nezha_agent_v0_installed; then v0_status="${GREEN}(已安装)$NC"; else v0_status="${YELLOW}(未安装)$NC"; fi
        local phoenix_status
        if is_nezha_agent_phoenix_installed; then phoenix_status="${GREEN}(已安装)$NC"; else phoenix_status="${YELLOW}(未安装)$NC"; fi

        echo -e "$CYAN║$NC   1. 安装/重装 NEZHA V0 探针 $v0_status            $CYAN║$NC"
        if is_nezha_agent_v0_installed; then
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   xz0. $RED卸载 NEZHA V0 探针$NC                        $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        else
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        fi
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 安装/重装 NEZHA V1 探针 $phoenix_status            $CYAN║$NC"
        if is_nezha_agent_phoenix_installed; then
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   xz1. $RED卸载 NEZHA V1 探针$NC                        $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        else
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        fi
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_agent_v0 ;;
        xz0) uninstall_nezha_agent_v0 ;;
        2) install_nezha_agent_phoenix ;;
        xz1) uninstall_nezha_agent_phoenix ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

nezha_dashboard_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                哪吒面板 (Dashboard) 管理         $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 安装/管理 V0 面板 (by fscarmen)             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 安装/管理 V1 面板 (Official)                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        log_warn "面板安装脚本均来自第三方，其内部已集成卸载和管理功能。"
        log_warn "如需卸载或管理，请再次运行对应的安装选项即可。"

        read -p "请输入选项: " choice
        case $choice in
        1) install_nezha_dashboard_v0 ;;
        2) install_nezha_dashboard_v1 ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

nezha_main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 哪吒监控管理                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. Agent 管理 (本机探针)                       $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Dashboard 管理 (服务器面板)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) nezha_agent_menu ;;
        2) nezha_dashboard_menu ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#           新增：Docker 通用管理 (V2.0 增强版)
# =================================================

# 通用的辅助函数，用于选择一个项目（容器或镜像）并对其执行操作
_docker_select_and_perform_action() {
    local item_type="$1"       # "容器" 或 "镜像"
    local list_command="$2"    # 'docker ps -a' 或 'docker images'
    local action_command="$3"  # 'docker start', 'docker stop', 'docker rm' 等
    local prompt_message="$4"  # "请输入要启动的容器..."
    local confirmation_needed=$5 # "true" 或 "false"
    local confirmation_message="$6" # "确定要强制删除吗？"

    clear
    log_info "当前所有${item_type}列表:"
    eval "$list_command"
    echo ""

    local target_id
    read -p "$prompt_message" target_id
    if [ -z "$target_id" ]; then
        log_error "${item_type}名称或ID不能为空！"
        press_any_key
        return
    fi

    if [ "$confirmation_needed" = "true" ]; then
        read -p "$confirmation_message (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "操作已取消。"
            press_any_key
            return
        fi
    fi

    log_info "正在对 ${item_type} [$target_id] 执行操作..."
    if eval "$action_command '$target_id'"; then
        log_info "✅ 操作成功！"
    else
        log_error "操作失败！请检查 ${item_type} 名称/ID 是否正确，或查看 Docker 的错误提示。"
    fi
    press_any_key
}

# --- 容器管理函数 ---
docker_list_containers() {
    clear
    log_info "列出所有 Docker 容器 (包括已停止的):"
    docker ps -a
    press_any_key
}

docker_start_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker start" "请输入要启动的容器名称或ID: "
}

docker_stop_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker stop" "请输入要停止的容器名称或ID: "
}

docker_restart_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker restart" "请输入要重启的容器名称或ID: "
}

docker_view_logs() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker logs -f" "请输入要查看日志的容器名称或ID: "
}

docker_remove_stopped_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker rm" \
    "请输入要删除的【已停止】容器名称或ID: " "true" \
    "警告：此操作将永久删除容器，但保留其命名数据卷。确定吗？"
}

docker_force_remove_container() {
    _docker_select_and_perform_action "容器" "docker ps -a" "docker rm -fv" \
    "请输入要【强制】删除的容器名称或ID: " "true" \
    "警告：此操作将强制停止并永久删除容器，并会删除其关联的【匿名】数据卷！确定吗？"
}

# --- 镜像管理函数 ---
docker_list_images() {
    clear
    log_info "列出所有 Docker 镜像:"
    docker images
    press_any_key
}

docker_remove_image() {
    _docker_select_and_perform_action "镜像" "docker images" "docker rmi" \
    "请输入要删除的镜像名称或ID: " "true" \
    "警告：如果该镜像正被容器使用，删除会失败。确定要删除吗？"
}

docker_prune_images() {
    clear
    log_warn "此操作将删除所有未被任何容器使用的“悬空”镜像 (dangling images)。"
    read -p "这是一个安全的清理操作，确定要继续吗? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "正在执行清理..."
        docker image prune -af
        log_info "✅ 未使用镜像清理完成。"
    else
        log_info "操作已取消。"
    fi
    press_any_key
}

# --- 系统级管理函数 ---
docker_prune_system() {
    clear
    log_warn "此操作将删除所有已停止的容器、未被任何容器使用的网络、"
    log_warn "所有悬空镜像 (dangling images) 以及所有悬空构建缓存。"
    read -p "这是一个全面的清理操作，确定要继续吗? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "正在执行清理..."
        docker system prune -af
        log_info "✅ 系统清理完成。"
    else
        log_info "操作已取消。"
    fi
    press_any_key
}

install_portainer() {
    if ! _install_docker_and_compose; then press_any_key; return; fi
    clear
    log_info "正在准备安装 Portainer-CE (Docker 管理面板)..."

    local domain
    read -p "请输入您为 Portainer 准备的域名 (如果留空，则将使用 IP:端口 访问): " domain

    # 停止并删除可能已存在的旧 Portainer 容器，避免端口冲突
    if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        log_warn "检测到已存在的 Portainer 容器，将停止并删除它以进行全新安装..."
        docker stop portainer >/dev/null
        docker rm portainer >/dev/null
    fi

    docker volume create portainer_data

    # --- 逻辑分支：根据是否提供域名来决定安装方式 ---
    if [ -n "$domain" ]; then
        # --- 路径1：使用反向代理 (推荐) ---
        log_info "已输入域名，将为您配置反向代理。"
        local internal_http_port
        while true; do
            read -p "请输入反向代理要连接的内部端口 (默认: 8880): " internal_http_port
            internal_http_port=${internal_http_port:-"8880"}
            if check_port "$internal_http_port"; then break; fi
        done

        log_info "正在以反代模式启动 Portainer 容器..."
        # 【最终修正】将容器内部端口硬编码为正确的 9000
        docker run -d \
            -p "$internal_http_port:9000" \
            --name portainer \
            --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:latest

        sleep 5
        if docker ps | grep -q "portainer"; then
            log_info "✅ Portainer 容器已成功启动！"
            log_info "正在为您配置反向代理..."

            # 调用通用反代函数，代理到我们映射的内部 HTTP 端口
            if setup_auto_reverse_proxy "$domain" "$internal_http_port"; then
                log_info "✅ Portainer 反向代理设置完成！"
                log_info "请通过以下地址访问 (脚本会自动处理SSL证书):"
                log_info "https://$domain"
            else
                log_error "反向代理设置失败，请检查之前的错误信息。"
            fi
        else
            log_error "Portainer 启动失败，请检查 Docker 日志。"
        fi

    else
        # --- 路径2：使用 IP:端口 访问 ---
        log_info "未输入域名，将为您配置 IP:端口 访问模式。"
        local external_https_port
        while true; do
            read -p "请输入 Portainer 的外部 HTTPS 访问端口 (默认: 9443): " external_https_port
            external_https_port=${external_https_port:-"9443"}
            if check_port "$external_https_port"; then break; fi
        done

        log_info "正在以 IP 访问模式启动 Portainer 容器..."
        # 【最终修正】这里映射的是 Portainer 内部固定的 9443 HTTPS 端口
        docker run -d \
            -p "$external_https_port:9443" \
            --name portainer \
            --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:latest

        sleep 5
        if docker ps | grep -q "portainer"; then
            local public_ip=$(get_public_ip v4)
            log_info "✅ Portainer 已成功启动！"
            log_info "请通过 IP 地址访问进行初始化设置:"
            log_info "https://$public_ip:$external_https_port"
            log_warn "首次访问浏览器可能会提示证书不安全，请选择“继续前往”。"
        else
            log_error "Portainer 启动失败，请检查 Docker 日志。"
        fi
    fi

    press_any_key
}
#------------------------------------------------------------------------------------
# 新增的功能：完全卸载 Docker
# Author: 编码助手
# Description: 停止并删除所有容器、镜像、卷，然后卸载 Docker 软件包并清理相关目录。
#------------------------------------------------------------------------------------
uninstall_docker() {
    # 在执行危险操作前，向用户请求确认
    read -p "警告：此操作将删除所有 Docker 容器、镜像、卷和网络，并卸载 Docker 本身。数据将无法恢复。您确定要继续吗? [y/N] " confirmation
    # 如果用户输入的不是 'y' 或 'Y'，则取消操作
    if [[ ! "$confirmation" =~ ^[yY]$ ]]; then
        echo "卸载操作已取消。"
        docker_menu # 返回 Docker 菜单
        return
    fi

    echo "开始执行 Docker 完全卸载程序..."

    # 检查 Docker 是否已安装
    if ! command -v docker &> /dev/null; then
        echo "检测到 Docker 未安装，无需卸载。"
        sleep 2s
        docker_menu
        return
    fi

    # 停止所有正在运行的容器
    echo "正在停止所有运行中的容器..."
    # 使用 `docker ps -aq` 列出所有容器的ID，然后传递给 `docker stop`
    if [ -n "$(docker ps -q)" ]; then
        docker stop $(docker ps -aq)
    else
        echo "没有正在运行的容器。"
    fi

    # 删除所有容器
    echo "正在删除所有容器..."
    if [ -n "$(docker ps -aq)" ]; then
        docker rm $(docker ps -aq)
    else
        echo "没有容器需要删除。"
    fi

    # 删除所有 Docker 镜像
    echo "正在删除所有 Docker 镜像..."
    if [ -n "$(docker images -q)" ]; then
        docker rmi -f $(docker images -q)
    else
        echo "没有 Docker 镜像需要删除。"
    fi

    # 删除所有 Docker 卷
    echo "正在删除所有 Docker 卷..."
    if [ -n "$(docker volume ls -q)" ]; then
        docker volume rm $(docker volume ls -q)
    else
        echo "没有 Docker 卷需要删除。"
    fi

    # 清理无用的网络
    echo "正在清理 Docker 网络..."
    docker network prune -f

    echo "正在卸载 Docker 相关软件包..."
    # 通过检查 /etc/os-release 文件来判断操作系统类型
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "无法确定操作系统类型，请手动卸载 Docker 软件包。"
        return
    fi

    # 根据不同的操作系统执行相应的卸载命令
    case $OS in
        ubuntu|debian)
            sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
            sudo apt-get autoremove -y --purge
            ;;
        centos|rhel|fedora)
            # 对于 CentOS/RHEL/Fedora，使用 yum 或 dnf
            if command -v dnf &> /dev/null; then
                sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            else
                sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            fi
            ;;
        *)
            echo "不支持的操作系统: $OS"
            echo "请手动卸载 Docker 软件包。"
            ;;
    esac

    echo "正在删除 Docker 的配置文件和数据目录..."
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd
    sudo rm -rf /etc/docker
    sudo rm -rf /var/run/docker.sock
    # 同时删除用户家目录下的 docker 配置
    rm -rf ~/.docker

    echo "Docker 已被完全卸载。"
    echo "3秒后将返回 Docker 管理菜单..."
    sleep 3s
    docker_menu
}

# --- 子菜单定义 ---

docker_container_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                     容器管理                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 列出所有容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 启动一个容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 停止一个容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 重启一个容器                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 查看容器实时日志                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. ${YELLOW}删除已停止的容器$NC                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. ${RED}强制删除容器 (并清理数据)${NC}                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) docker_list_containers ;;
        2) docker_start_container ;;
        3) docker_stop_container ;;
        4) docker_restart_container ;;
        5) docker_view_logs ;;
        6) docker_remove_stopped_container ;;
        7) docker_force_remove_container ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

docker_image_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                     镜像管理                     $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
       echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 列出所有镜像                                $CYAN║$NC"
       echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${YELLOW}删除一个指定镜像$NC                            $CYAN║$NC"
       echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. ${RED}清理所有未使用的镜像${NC}                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) docker_list_images ;;
        2) docker_remove_image ;;
        3) docker_prune_images ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# --- 主管理菜单 (V2.0) ---
docker_manage_menu() {
    while true; do
        clear
        # 核心逻辑：首先检查 'docker' 命令是否存在
        if ! command -v docker &>/dev/null; then
            # --- Docker 未安装时显示的菜单 ---
            echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
            echo -e "$CYAN║$WHITE                 Docker 通用管理                  $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC  当前状态: ${YELLOW}● 未安装$NC                              $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. ${GREEN}安装 Docker & Docker Compose${NC}                $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

            read -p "请输入选项: " choice
            case $choice in
            1)
                # 调用脚本中已有的安装函数
                _install_docker_and_compose
                press_any_key
                # 不跳出循环，安装后会自动刷新菜单
                ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
            esac
        else
            # --- Docker 已安装时显示的菜单 ---
            local DOCKER_STATUS_COLOR
            # 检测 Docker 服务是否正在运行
            if systemctl is-active --quiet docker; then
                DOCKER_STATUS_COLOR="$GREEN● 活动$NC"
            else
                DOCKER_STATUS_COLOR="$RED● 不活动$NC"
            fi

            echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
            echo -e "$CYAN║$WHITE                 Docker 通用管理                  $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC  当前状态: $DOCKER_STATUS_COLOR                                $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   1. ${GREEN}容器管理${NC} (启停/删除/日志)                   $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   2. ${GREEN}镜像管理${NC} (删除/清理)                        $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   3. ${YELLOW}清理 Docker 系统 (释放空间)${NC}                 $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   4. 安装 Portainer 图形化管理面板               $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   5. ${RED}完全卸载Docker${NC}                              $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
            echo -e "$CYAN║$NC                                                  $CYAN║$NC"
            echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

            read -p "请输入选项: " choice
            case $choice in
            1) docker_container_menu ;;
            2) docker_image_menu ;;
            3) docker_prune_system ;;
            4) install_portainer ;;
            5) uninstall_docker ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
            esac
        fi
    done
}
# =================================================
#           Docker 应用 & 面板 (docker_apps_menu)
# =================================================

_install_docker_and_compose() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "Docker 和 Docker Compose V2 已安装。"
        return 0
    fi
    log_warn "未检测到完整的 Docker 环境，开始执行官方标准安装流程..."

    case "$PKG_MANAGER" in
        apt)
            ensure_dependencies "ca-certificates" "curl" "gnupg"
            log_info "正在添加 Docker 官方 GPG 密钥..."
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            log_info "正在添加 Docker 软件仓库..."
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS_ID $OS_VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            set -e
            apt-get update -y
            log_info "正在安装 Docker Engine, CLI, Containerd, 和 Docker Compose 插件..."
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        yum|dnf)
            ensure_dependencies "curl"
            if [ "$PKG_MANAGER" == "yum" ]; then ensure_dependencies "yum-utils"; fi
            log_info "正在添加 Docker 软件仓库..."
            local repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
            if [ "$OS_ID" == "fedora" ]; then repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"; fi

            if command -v dnf &>/dev/null; then
                dnf config-manager --add-repo "$repo_url"
            elif command -v yum-config-manager &>/dev/null; then
                 yum-config-manager --add-repo "$repo_url"
            else
                log_error "缺少 config-manager, 无法自动添加仓库。"
                return 1
            fi

            set -e
            log_info "正在安装 Docker Engine, CLI, Containerd, 和 Docker Compose 插件..."
            "$PKG_MANAGER" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac

    set +e
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "✅ Docker 和 Docker Compose V2 已成功安装！"
        systemctl start docker
        systemctl enable docker
        return 0
    else
        log_error "Docker 环境安装失败！请检查上面的日志输出。"
        return 1
    fi
}

# (这是被修改的函数, 用来卸载所有基于 Docker Compose 的项目)
uninstall_docker_compose_project() {
    local app_name=$1
    local default_dir=$2
    local project_dir

    read -e -p "请输入要卸载的 $app_name 的安装目录 [默认: $default_dir]: " project_dir
    project_dir=${project_dir:-$default_dir}

    if [ ! -d "$project_dir" ] || [ ! -f "$project_dir/docker-compose.yml" ]; then
        log_error "目录 $project_dir 下未找到 docker-compose.yml 文件，请确认路径。"
        press_any_key
        return
    fi

    # --- 新增的反代清理逻辑 ---
    local proxy_domain_file="$project_dir/.proxy_domain"
    if [ -f "$proxy_domain_file" ]; then
        local domain=$(cat "$proxy_domain_file")
        log_warn "检测到此应用关联了反向代理域名: $domain"
        read -p "是否要在卸载应用的同时，删除其反代配置和SSL证书? (y/N): " confirm_delete_proxy
        if [[ "$confirm_delete_proxy" =~ ^[Yy]$ ]]; then
            _cleanup_reverse_proxy_config "$domain"
        fi
    fi
    # --- 结束 ---

    log_info "准备卸载位于 $project_dir 的 $app_name..."
    cd "$project_dir" || { log_error "无法进入目录 $project_dir"; press_any_key; return 1; }

    read -p "警告：这将停止并永久删除 $app_name 的所有容器和数据卷！此操作不可逆！是否继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        press_any_key
        return
    fi

    log_info "正在停止并移除容器和数据卷..."
    docker compose down --volumes

    cd ..
    read -p "是否要删除项目目录 $project_dir 及其所有文件？(y/N): " confirm_delete_dir
    if [[ "$confirm_delete_dir" =~ ^[Yy]$ ]]; then
        log_info "正在删除项目目录 $project_dir ..."
        rm -rf "$project_dir"
        log_info "项目目录已删除。"
    fi

    log_info "✅ $app_name 卸载完成。"
}

install_sui() {
    ensure_dependencies "curl"
    log_info "正在准备安装 S-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
    log_info "S-ui 安装脚本执行完毕。"
    press_any_key
}

install_3xui() {
    ensure_dependencies "curl"
    log_info "正在准备安装 3X-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    log_info "3X-ui 安装脚本执行完毕。"
    press_any_key
}

# (这是被修改的函数)
install_wordpress() {
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建 WordPress。"
        press_any_key
        return
    fi
    clear
    log_info "开始使用 Docker Compose 搭建 WordPress..."

    local project_dir
    while true; do
        read -e -p "请输入新 WordPress 项目的安装目录 [默认: /root/wordpress]: " project_dir
        project_dir=${project_dir:-"/root/wordpress"}
        if [ -f "$project_dir/docker-compose.yml" ]; then
            log_error "错误：目录 \"$project_dir\" 下已存在一个 WordPress 站点！"
            log_warn "请为新的 WordPress 站点选择一个不同的、全新的目录。"
            continue
        else
            break
        fi
    done
    mkdir -p "$project_dir" || { log_error "无法创建目录 $project_dir！"; press_any_key; return 1; }
    cd "$project_dir" || { log_error "无法进入目录 $project_dir！"; press_any_key; return 1; }
    log_info "新的 WordPress 将被安装在: $(pwd)"

    local db_password
    read -s -p "请输入新的数据库 root 和用户密码 [默认随机生成]: " db_password
    db_password=${db_password:-$(generate_random_password)}
    echo ""
    log_info "数据库密码已设置为: $db_password"

    local wp_port
    while true; do
        read -p "请输入 WordPress 的内部代理端口 (例如 8080，外部无法直接访问): " wp_port
        if [[ ! "$wp_port" =~ ^[0-9]+$ ]] || [ "$wp_port" -lt 1 ] || [ "$wp_port" -gt 65535 ]; then
            log_error "端口号必须是 1-65535 之间的数字。"
        elif ! check_port "$wp_port"; then
            :
        else break; fi
    done

    local domain
    while true; do
        read -p "请输入您的网站访问域名 (例如 blog.example.com)，必须提前解析: " domain
        if [[ -z "$domain" ]]; then log_error "网站域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确，请重新输入。"; else break; fi
    done
    local site_url="https://$domain"

    log_info "正在生成 docker-compose.yml 文件..."
    cat >docker-compose.yml <<EOF
version: '3.8'

services:
  db:
    image: mysql:8.0
    container_name: ${project_dir##*/}_db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_DATABASE=wordpress
      - MYSQL_USER=wp_user
      - MYSQL_PASSWORD=$db_password
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - wordpress_net

  wordpress:
    depends_on:
      - db
    image: wordpress:latest
    container_name: ${project_dir##*/}_app
    restart: always
    ports:
      - "$wp_port:80"
    environment:
      - WORDPRESS_DB_HOST=db:3306
      - WORDPRESS_DB_USER=wp_user
      - WORDPRESS_DB_PASSWORD=$db_password
      - WORDPRESS_DB_NAME=wordpress
      - WORDPRESS_SITEURL=$site_url
      - WORDPRESS_HOME=$site_url
    volumes:
      - wp_files:/var/www/html
    networks:
      - wordpress_net

volumes:
  db_data:
  wp_files:

networks:
  wordpress_net:
EOF

    log_info "正在使用 Docker Compose 启动 WordPress 和数据库服务..."
    log_warn "首次启动需要下载镜像，可能需要几分钟时间，请耐心等待..."
    docker compose up -d
    log_info "正在检查服务状态..."
    sleep 5
    docker compose ps
    log_info "✅ WordPress 容器已成功启动！"

    log_info "正在为域名 $domain 设置反向代理..."
    if setup_auto_reverse_proxy "$domain" "$wp_port"; then
        # --- 新增：记录反代域名 ---
        echo "$domain" > "$project_dir/.proxy_domain"
        log_info "WordPress 配置流程完毕！您现在应该可以通过 $site_url 访问您的网站了。"
    else
         log_error "反向代理设置失败！请检查域名解析或手动排查问题。"
    fi
    press_any_key
}

uninstall_wordpress() {
    uninstall_docker_compose_project "WordPress" "/root/wordpress"
}

get_latest_maccms_tag() {
    local repo_api="https://api.github.com/repos/magicblack/maccms10/tags"
    local latest_tag
    latest_tag=$(curl -s "$repo_api" | grep -Po '"name":.*?[^\\]",' | head -1 | awk -F'"' '{print $4}')
    echo "$latest_tag"
}

download_maccms_source() {
    local version=$1
    local url="https://github.com/magicblack/maccms10/archive/refs/tags/${version}.zip"
    log_info "开始下载苹果CMS源码压缩包，版本: $version"
    if ! curl -L -o source.zip "$url"; then
        log_error "源码压缩包下载失败！请检查网络连接。"
        return 1
    fi
    if ! file source.zip | grep -q "Zip archive data"; then
        log_error "下载的文件不是有效的zip压缩包，可能下载失败或版本号错误！"
        rm -f source.zip
        return 1
    fi
    log_info "源码压缩包下载并校验通过。"
    return 0
}

# (这是最终修复版函数, 经过仔细检查确保完整无误)
install_maccms() {
    log_info "开始安装苹果CMS (v10)"
    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建苹果CMS。"
        press_any_key
        return
    fi
    ensure_dependencies "unzip" "file" "curl"

    local project_dir
    read -e -p "请输入苹果CMS的安装目录 [默认: /root/maccms]: " project_dir
    project_dir=${project_dir:-"/root/maccms"}

    if [ -f "$project_dir/docker-compose.yml" ]; then
        log_warn "检测到安装目录已存在 Docker 项目，请选择其他目录或先卸载。"
        press_any_key
        return 1
    fi

    local db_root_password db_user_password
    read -s -p "请输入 MariaDB root 密码 [默认随机]: " db_root_password
    db_root_password=${db_root_password:-$(generate_random_password)}
    echo ""
    read -s -p "请输入 maccms_user 用户密码 [默认随机]: " db_user_password
    db_user_password=${db_user_password:-$(generate_random_password)}
    echo ""

    local db_name="maccms"
    local db_user="maccms_user"
    local db_port="3306"
    local web_port
    read -p "请输入一个内部代理端口 (例如 8880，用于反代): " web_port
    web_port=${web_port:-"8880"}
    if ! check_port "$web_port"; then press_any_key; return; fi

    mkdir -p "$project_dir/nginx" "$project_dir/source" "$project_dir/php"
    cd "$project_dir" || { log_error "无法进入目录 $project_dir"; return 1; }

    log_info "正在创建 Supervisor 守护进程配置文件..."
    cat > "$project_dir/php/supervisord.conf" <<'EOF'
[supervisord]
nodaemon=true
user=root

[program:php-fpm]
command=/usr/local/sbin/php-fpm --nodaemonize --fpm-config /usr/local/etc/php-fpm.d/www.conf
autostart=true
autorestart=true
priority=5
user=www-data
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

    log_info "正在为 PHP 创建集成 Supervisor 的自定义配置文件 (Dockerfile)..."
    cat > "$project_dir/php/Dockerfile" <<'EOF'
FROM php:7.4-fpm

# 安装 Supervisor 和其他依赖
RUN apt-get update && apt-get install -y \
    supervisor \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# 容器化改造：修改php-fpm配置，将日志输出到标准错误流，而不是文件
RUN sed -i 's#^error_log = .*#error_log = /proc/self/fd/2#' /usr/local/etc/php-fpm.conf \
    && sed -i 's#;catch_workers_output = yes#catch_workers_output = yes#' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's#^php_admin_value\[error_log\] = .*#php_admin_value[error_log] = /proc/self/fd/2#' /usr/local/etc/php-fpm.d/www.conf \
    && sed -i 's#^php_admin_flag\[log_errors\] = .*#php_admin_flag[log_errors] = on#' /usr/local/etc/php-fpm.d/www.conf

# 安装PHP扩展
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd pdo_mysql zip fileinfo

# 复制 Supervisor 配置文件到镜像中
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 设置容器启动时执行的命令为 Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOF

    local maccms_version
    maccms_version=$(get_latest_maccms_tag)
    if [ -z "$maccms_version" ]; then log_error "获取 maccms 最新版本标签失败！"; press_any_key; return 1; fi
    log_info "获取到最新版标签: $maccms_version"
    if ! download_maccms_source "$maccms_version"; then press_any_key; return 1; fi
    unzip -q source.zip || { log_error "解压失败"; return 1; }
    rm -f source.zip
    local dir="maccms10-${maccms_version#v}"
    if [ ! -d "$dir" ]; then log_error "解压后目录不存在"; return 1; fi
    mv "$dir"/* "$project_dir/source/" && mv "$dir"/.* "$project_dir/source/" 2>/dev/null || true
    rm -rf "$dir"

    cat >"$project_dir/nginx/default.conf" <<'EOF'
server {
    listen 80;
    server_name localhost;
    root /var/www/html;
    index index.php index.html index.htm;
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass php:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

    cat >"$project_dir/docker-compose.yml" <<EOF
services:
  db:
    image: mariadb:10.6
    container_name: ${project_dir##*/}_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: "$db_root_password"
      MYSQL_DATABASE: "$db_name"
      MYSQL_USER: "$db_user"
      MYSQL_PASSWORD: "$db_user_password"
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - maccms_net

  php:
    build: ./php
    container_name: ${project_dir##*/}_php
    volumes:
      - ./source:/var/www/html
    restart: always
    depends_on:
      - db
    networks:
      - maccms_net

  nginx:
    image: nginx:1.21-alpine
    container_name: ${project_dir##*/}_nginx
    ports:
      - "$web_port:80"
    volumes:
      - ./source:/var/www/html
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
    restart: always
    depends_on:
      - php
    networks:
      - maccms_net

volumes:
  db_data:

networks:
  maccms_net:
EOF

    log_info "正在构建集成Supervisor的PHP镜像并启动所有服务..."
    log_warn "首次执行需要构建镜像，耗时可能长达数分钟，请耐心等待..."
    docker compose up -d --build

    log_info "等待容器初始化 (8秒)..."
    sleep 8

    log_info "正在修复容器内文件权限 (确保 www-data 用户可以读写)..."
    docker exec -i "${project_dir##*/}_php" chown -R www-data:www-data /var/www/html
    docker exec -i "${project_dir##*/}_php" chmod -R 777 /var/www/html/runtime

    log_info "正在检查服务最终状态..."
    if ! docker ps -a | grep -q "${project_dir##*/}_php.*Up"; then
        log_error "最终尝试后，PHP 容器仍未能启动！问题可能非常复杂。"
        log_info "请使用以下命令查看容器的完整日志以诊断问题:"
        echo -e "\n  cd $project_dir && docker compose logs php\n"
        press_any_key
        return 1
    fi

    log_info "✅ 所有服务均已成功启动！"
    docker compose ps

    read -p "是否立即为其设置反向代理 (需提前解析好域名)？(Y/n): " setup_proxy_choice
    if [[ ! "$setup_proxy_choice" =~ ^[Nn]$ ]]; then
        local domain
        while true; do
            read -p "请输入您的网站访问域名 (例如 maccms.example.com): " domain
            if [[ -z "$domain" ]]; then log_error "网站域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确，请重新输入。"; else break; fi
        done
        if setup_auto_reverse_proxy "$domain" "$web_port"; then
            echo "$domain" > "$project_dir/.proxy_domain"
            log_info "✅ 反向代理设置完成！"
            echo "--------------------------------------------"
            log_info "请访问以下地址完成安装向导："
            log_info "https://$domain/install.php"
            echo "--------------------------------------------"
        else
             log_error "反向代理设置失败！请检查域名解析或手动排查问题。"
        fi
    else
        local public_ip
        public_ip=$(get_public_ip v4)
        log_info "好的，您选择不设置反向代理。"
        log_warn "在安装向导的数据库配置页面，请【不要】修改任何信息，直接点击“测试连接”，然后进行下一步即可。"
        echo "--------------------------------------------"
        echo "网站安装地址: http://$public_ip:$web_port/install.php"
        echo "--------------------------------------------"
    fi
    press_any_key
}

uninstall_maccms() {
    uninstall_docker_compose_project "苹果CMS" "/root/maccms"
}

install_uptime_kuma() {
    local compose_template="
version: '3.8'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: {{container_name}}
    restart: always
    ports:
      - \"{{ports_or_port}}:3001\"
    volumes:
      - uptime_kuma_data:/app/data

volumes:
  uptime_kuma_data:
"
    _install_docker_compose_app \
      "Uptime Kuma" \
      "/root/uptime-kuma" \
      "port" \
      "true" \
      "$compose_template"
}

uninstall_uptime_kuma() {
    uninstall_docker_compose_project "Uptime Kuma" "/root/uptime-kuma"
}
# =================================================================
#           以下是为新的 “Docker 应用 & 面板安装” 菜单新增的函数
# =================================================================

# --- 新增：面板安装函数 ---

install_bt_panel() {
    clear
    log_warn "宝塔面板是一个功能强大但相对独立的服务器管理面板。"
    log_warn "它会安装自己的Web服务器套件 (Nginx, Apache等)，可能会与您现有的环境冲突。"
    log_warn "请确保您在一个纯净的系统上安装宝塔面板。"
    read -p "您确定要继续安装吗? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "安装已取消。"
        press_any_key
        return
    fi
    log_info "正在根据您的操作系统选择合适的宝塔安装脚本..."
    local install_script_url=""
    case "$OS_ID" in
        ubuntu)
            install_script_url="http://download.bt.cn/install/install-ubuntu_6.0.sh"
            ;;
        debian)
            install_script_url="http://download.bt.cn/install/install-debian_6.0.sh"
            ;;
        centos|rhel|fedora)
             # 对于 Red Hat 系，使用通用安装脚本
            install_script_url="http://download.bt.cn/install/install_6.0.sh"
            ;;
        *)
            log_error "您的操作系统 ($OS_ID) 不在宝塔官方支持的自动安装列表内。"
            log_error "请访问 http://www.bt.cn 手动获取安装方法。"
            press_any_key
            return
            ;;
    esac

    log_info "即将执行宝塔官方安装脚本，请根据提示操作..."
    wget -O install.sh "$install_script_url" && bash install.sh
    log_info "宝塔面板安装脚本执行完毕。"
    press_any_key
}

install_1panel() {
    clear
    log_warn "1Panel 是一个现代化的 Linux 服务器运维管理面板。"
    log_info "即将执行 1Panel 官方一键安装脚本..."
    read -p "您确定要继续安装吗? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "安装已取消。"
        press_any_key
        return
    fi
    curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && bash quick_start.sh
    log_info "1Panel 安装脚本执行完毕。"
    press_any_key
}


# --- 新增：面板卸载函数 ---

_cleanup_reverse_proxy_config() {
    local domain="$1"
    if [ -z "$domain" ]; then return 1; fi

    log_info "正在为域名 [$domain] 清理反向代理配置..."
    local nginx_conf="/etc/nginx/sites-available/$domain.conf"
    local nginx_enabled_conf="/etc/nginx/sites-enabled/$domain.conf"

    if [ -f "$nginx_conf" ] || [ -L "$nginx_enabled_conf" ]; then
        log_info "检测到 Nginx 配置，正在删除..."
        rm -f "$nginx_enabled_conf"
        rm -f "$nginx_conf"
        # 测试 Nginx 配置并静默重载
        if nginx -t >/dev/null 2>&1; then
            systemctl reload nginx
            log_info "✅ Nginx 配置已清理并重载。"
        else
            log_warn "Nginx 配置文件测试失败，可能需要手动修复。"
        fi
    fi

    if command -v certbot &>/dev/null && certbot certificates 2>/dev/null | grep -q -E "Certificate Name: $domain"; then
        log_info "检测到 Certbot 证书，正在删除..."
        certbot delete --cert-name "$domain" --non-interactive
        log_info "✅ Certbot 证书已删除。"
    fi
    return 0
}

uninstall_3xui() {
    log_info "3x-ui 的卸载功能集成在其安装脚本中。"
    log_info "即将重新运行其安装脚本，请在脚本菜单中选择【卸载】选项。"
    press_any_key
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    log_warn "请注意：此操作不会自动清理您可能为 3x-ui 手动配置的反向代理。"
    press_any_key
}

uninstall_sui() {
    log_info "S-ui 的卸载功能集成在其安装脚本中。"
    log_info "即将重新运行其安装脚本，请在脚本菜单中选择【卸载】选项。"
    press_any_key
    bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
    log_warn "请注意：此操作不会自动清理您可能为 S-ui 手动配置的反向代理。"
    press_any_key
}

uninstall_bt_panel() {
    local uninstall_script="/www/server/panel/install/uninstall.sh"
    if [ -f "$uninstall_script" ]; then
        log_info "检测到宝塔卸载脚本，即将执行..."
        bash "$uninstall_script"
    else
        log_error "未找到宝塔卸载脚本！可能已损坏或未正确安装。"
    fi
    press_any_key
}

uninstall_1panel() {
    if command -v 1pctl &>/dev/null; then
        log_info "检测到 1Panel 控制命令，即将执行卸载..."
        1pctl uninstall
    else
        log_error "未找到 '1pctl' 命令！可能已损坏或未正确安装。"
    fi
    press_any_key
}
# =================================================================
#           智能卸载菜单 (V2.0 - 增强检测版)
# =================================================================
uninstall_panels_menu() {
    while true; do
        clear
        log_info "正在检测已安装的应用和面板..."

        local installed_items=()
        local function_map=()

        # --- Docker Compose 应用检测 (通过 docker-compose.yml) ---
        if [ -f "/root/wordpress/docker-compose.yml" ]; then
            installed_items+=("WordPress (位于 /root/wordpress)")
            function_map+=("uninstall_wordpress")
        fi
        if [ -f "/root/maccms/docker-compose.yml" ]; then
            installed_items+=("苹果CMS (位于 /root/maccms)")
            function_map+=("uninstall_maccms")
        fi
        if [ -f "/root/uptime-kuma/docker-compose.yml" ]; then
            installed_items+=("Uptime Kuma (位于 /root/uptime-kuma)")
            function_map+=("uninstall_uptime_kuma")
        fi

        # --- 外部脚本安装检测 (通过特征命令或目录) ---
        if command -v 3x-ui &>/dev/null || [ -d "/usr/local/x-ui/" ]; then
            installed_items+=("3x-ui 面板")
            function_map+=("uninstall_3xui")
        fi
        if command -v s-ui &>/dev/null || [ -d "/usr/local/s-ui/" ]; then
            installed_items+=("S-ui 面板")
            function_map+=("uninstall_sui")
        fi
        if [ -d "/www/server/panel" ]; then
            installed_items+=("宝塔面板")
            function_map+=("uninstall_bt_panel")
        fi
        if command -v 1pctl &>/dev/null; then
            installed_items+=("1Panel 面板")
            function_map+=("uninstall_1panel")
        fi

        # --- Docker 独立容器应用检测 (通过容器名) ---
        if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
            installed_items+=("Portainer (通用Docker面板)")
            # 确保你有一个对应的 uninstall_portainer 函数
            # 此处我们假设 uninstall_docker_compose_project 可以处理（如果它被改造得更通用）
            # 或者你需要一个专门的 uninstall_portainer 函数。
            # 为安全起见，我们暂时注释掉，除非你已创建该函数
            # function_map+=("uninstall_portainer")
        fi

        # --- 检查是否有可卸载项 ---
        if [ ${#installed_items[@]} -eq 0 ]; then
            log_warn "未检测到任何通过本脚本安装且可识别的应用或面板。"
            press_any_key
            return
        fi

        # --- 绘制菜单 ---
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 选择要卸载的应用或面板             $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"

        for i in "${!installed_items[@]}"; do
            printf "$CYAN║$NC  %2d. %-45s $CYAN║$NC\n" "$((i+1))" "${installed_items[$i]}"
        done

        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC   0. 返回                                        $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#installed_items[@]} ]; then
            if [ "$choice" -eq 0 ]; then
                break
            else
                local index=$((choice-1))
                # 清屏并调用对应的卸载函数
                clear
                ${function_map[$index]}

                # 卸载后暂停，以便用户可以再次进入此菜单查看结果
                # press_any_key
                # 注释掉press_any_key，因为卸载函数内部通常已经有了，避免重复按键
            fi
        else
            log_error "无效选项！"; sleep 1
        fi
    done
}
# =================================================================
#           新增：通用 Docker Compose 应用安装器
# =================================================================
_install_docker_compose_app() {
    local app_name="$1"
    local default_dir="$2"
    local port_type="$3" # "ports" for external access, "port" for internal proxy
    local needs_proxy="$4"
    local compose_template="$5"

    if ! _install_docker_and_compose; then
        log_error "Docker 环境准备失败，无法继续搭建 $app_name。"
        press_any_key
        return 1
    fi
    clear
    log_info "开始使用 Docker Compose 搭建 $app_name..."

    local project_dir
    while true; do
        read -e -p "请输入新的 $app_name 项目的安装目录 [默认: $default_dir]: " project_dir
        project_dir=${project_dir:-"$default_dir"}
        if [ -f "$project_dir/docker-compose.yml" ]; then
            log_error "错误：目录 \"$project_dir\" 下已存在一个 Docker 项目！"
            log_warn "请为新的 $app_name 站点选择一个不同的、全新的目录。"
            continue
        else
            break
        fi
    done
    mkdir -p "$project_dir" || { log_error "无法创建目录 $project_dir！"; press_any_key; return 1; }
    cd "$project_dir" || { log_error "无法进入目录 $project_dir！"; press_any_key; return 1; }
    log_info "新的 $app_name 将被安装在: $(pwd)"

    local app_port
    while true; do
        local prompt_msg="请输入 $app_name 的"
        if [ "$port_type" == "ports" ]; then
            prompt_msg+="外部访问端口"
        else # "port"
            prompt_msg+="内部代理端口 (外部无法直接访问)"
        fi
        read -p "$prompt_msg [回车则随机生成]: " app_port
        app_port=${app_port:-$(generate_random_port)}
        if check_port "$app_port"; then break; fi
    done

    # 替换模板变量
    local container_name="${project_dir##*/}" # 使用目录名作为容器名
    local final_compose_content="${compose_template//\{\{container_name\}\}/$container_name}"
    final_compose_content="${final_compose_content//\{\{ports_or_port\}\}/$app_port}"

    log_info "正在生成 docker-compose.yml 文件..."
    echo -e "$final_compose_content" > docker-compose.yml

    log_info "正在使用 Docker Compose 启动 $app_name 服务..."
    log_warn "首次启动需要下载镜像，可能需要一些时间，请耐心等待..."
    docker compose up -d
    log_info "正在检查服务状态..."
    sleep 5
    docker compose ps
    log_info "✅ $app_name 容器已成功启动！"

    if [ "$needs_proxy" == "true" ]; then
        local domain
        while true; do
            read -p "请输入您的网站访问域名 (例如 ${app_name,,}.example.com)，必须提前解析: " domain
            if [[ -z "$domain" ]]; then log_error "网站域名不能为空！"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确，请重新输入。"; else break; fi
        done
        if setup_auto_reverse_proxy "$domain" "$app_port"; then
            echo "$domain" > "$project_dir/.proxy_domain"
            log_info "✅ $app_name 反向代理设置完成！"
            log_info "请通过 https://$domain 访问您的应用。"
        else
            log_error "反向代理设置失败！请检查域名解析或手动排查问题。"
        fi
    else
        local public_ip
        public_ip=$(get_public_ip v4)
        log_info "✅ $app_name 安装完成！"
        log_info "请通过 http://$public_ip:$app_port 访问。"
    fi

    press_any_key
}
# (这是被修改的函数, 全新的菜单结构)
docker_apps_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                     应用 & 面板安装              $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 搭建 WordPress                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 搭建苹果CMS影视站                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 安装 3x-ui (搭建节点-Xray)                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 安装 S-ui (搭建节点-SingBox)                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 安装 Uptime Kuma 监控面板                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 安装宝塔面板 (BT Panel)                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. 安装 1Panel 面板                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. ${RED}卸载应用或面板${NC}                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) install_wordpress ;;
        2) install_maccms ;;
        3) install_3xui ;;
        4) install_sui ;;
        5) install_uptime_kuma ;;
        6) install_bt_panel ;;
        7) install_1panel ;;
        8) uninstall_panels_menu ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

ui_panels_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE                 UI 面板安装选择                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 安装 S-ui 面板                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. 安装 3X-ui 面板                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回上一级菜单                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        read -p "请输入选项: " choice
        case $choice in
            1) install_sui; break ;;
            2) install_3xui; break ;;
            0) break ;;
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#           证书 & 反代 (V2.0 增强版)
#
#   - 新增：域名解析预检查，防止 Certbot 因解析错误而失败。
#   - 新增：“仅申请证书”功能，满足非反代需求。
#   - 新增：对 Caddy 反代配置的清理功能，使删除操作更完整。
#   - 优化：删除证书时使用数字菜单选择，避免手动输入错误。
#   - 优化：反代设置流程，增加操作前摘要确认，防止误操作。
#   - 优化：为 Nginx 配置添加 HSTS 头，增强安全性。
#   - 优化：申请证书时可自定义邮箱。
# =================================================

# --- (新增) 辅助函数：预检查域名DNS解析 ---
_precheck_domain_dns() {
    local domain_to_check="$1"
    log_info "正在对域名 [$domain_to_check] 进行DNS解析预检查..."
    ensure_dependencies "dnsutils" # BIND's dig command

    local server_ipv4
    server_ipv4=$(get_public_ip v4)
    if [ -z "$server_ipv4" ]; then
        log_warn "未能获取到本机 IPv4 地址，跳过预检查。"
        return 0 # 无法检查时，默认通过
    fi

    local resolved_ips
    resolved_ips=$(dig +short "$domain_to_check" A)
    if [ -z "$resolved_ips" ]; then
        log_error "DNS预检失败：无法解析到任何A记录！"
        log_warn "请确保您的域名 [$domain_to_check] 已正确设置A记录指向本机IP: $server_ipv4"
        return 1
    fi

    local match=false
    for ip in $resolved_ips; do
        if [ "$ip" == "$server_ipv4" ]; then
            log_info "✅ DNS预检通过：域名解析正确指向本机IP ($server_ipv4)。"
            match=true
            break
        fi
    done

    if ! $match; then
        log_error "DNS预检失败：域名解析的IP ["$resolved_ips"] 与本机IP [$server_ipv4] 不匹配！"
        log_warn "请检查您的DNS设置。Certbot将因此无法完成验证。"
        return 1
    fi

    return 0
}


# --- (新增) 辅助函数：清理Caddyfile中的反代配置 ---
_cleanup_caddy_proxy_config() {
    local domain="$1"
    local caddyfile="/etc/caddy/Caddyfile"

    if [ ! -f "$caddyfile" ]; then
        return
    fi
    log_info "正在清理 Caddyfile 中关于 [$domain] 的配置..."
    # 使用sed删除从包含域名的行开始，到下一个'}'结束的块
    # 使用-i.bak创建备份，更安全
    sed -i.bak "/^$domain {/,/}/d" "$caddyfile"
    # 同时删除可能存在的自动生成注释
    sed -i.bak "/# Auto-generated by vps-toolkit for $domain/d" "$caddyfile"

    log_info "正在重载 Caddy 服务..."
    if systemctl reload caddy; then
        log_info "✅ Caddy 服务已重载。"
    else
        log_warn "Caddy 服务重载失败，请手动检查配置。"
    fi
}

# --- (重写) 交互更友好，并支持清理 Caddy 配置 ---
delete_certificate_and_proxy() {
    clear
    log_info "准备删除证书及其关联配置..."

    if ! command -v certbot &>/dev/null; then
        log_error "Certbot 未安装，无法执行操作。"; press_any_key; return;
    fi

    # 从 certbot 获取原始数据
    local certs_data
    certs_data=$(certbot certificates 2>/dev/null)
    if [[ ! "$certs_data" =~ "Found the following certs:" ]]; then
        log_warn "未找到任何由 Certbot 管理的证书。"; press_any_key; return;
    fi

    # 构建选择菜单
    local cert_names=()
    local display_options=()
    local i=1
    while read -r line; do
        if [[ $line =~ "Certificate Name:" ]]; then
            local name=$(echo "$line" | awk '{print $3}')
            local domains=$(echo "$certs_data" | grep -A1 "Certificate Name: $name" | grep "Domains:")
            cert_names+=("$name")
            display_options+=("$i. $name ($domains)")
            ((i++))
        fi
    done <<< "$certs_data"

    log_info "请选择要删除的证书:\n"
    for option in "${display_options[@]}"; do
        echo "  $option"
    done
    echo -e "\n  0. 返回\n"

    read -p "请输入选项: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#cert_names[@]} ]; then
        log_error "无效选项！"; press_any_key; return
    fi
    if [ "$choice" -eq 0 ]; then return; fi

    local cert_to_delete=${cert_names[$((choice-1))]}

    read -p "警告：这将永久删除证书 '$cert_to_delete' 及其相关的 Web 服务器配置。此操作不可逆！是否继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"; press_any_key; return
    fi

    log_info "正在执行 Certbot 删除操作..."
    if ! certbot delete --cert-name "$cert_to_delete" --non-interactive; then
        log_error "Certbot 删除证书失败，但仍将尝试清理Web服务器配置。"
    fi

    # 清理 Nginx
    local nginx_conf="/etc/nginx/sites-available/$cert_to_delete.conf"
    if [ -f "$nginx_conf" ]; then
        log_warn "检测到关联的 Nginx 配置文件，正在清理..."
        rm -f "/etc/nginx/sites-enabled/$cert_to_delete.conf"
        rm -f "$nginx_conf"
        if nginx -t >/dev/null 2>&1; then
            systemctl reload nginx
            log_info "✅ Nginx 残留配置已清理。"
        fi
    fi

    # 清理 Caddy
    _cleanup_caddy_proxy_config "$cert_to_delete"

    log_info "✅ 清理流程完成。"
    press_any_key
}

renew_certificates() {
    if ! command -v certbot &>/dev/null; then
        log_error "Certbot 未安装，无法续签。"
        press_any_key
        return
    fi

    log_info "正在尝试为所有证书续期..."
    log_warn "Certbot 会自动跳过那些距离到期日还很长的证书。"
    certbot renew
    log_info "✅ 证书续期检查完成。"
    press_any_key
}

_handle_caddy_cert() {
    log_error "此自动证书功能旨在与Nginx配合使用。"
    log_warn "Caddy 会自动管理证书，您只需在 Caddyfile 中配置好域名即可。"
    return 1
}

# --- (优化) 自动处理 Nginx 证书申请，无需输入邮箱 ---
_handle_nginx_cert() {
    local domain_name="$1"
    log_info "检测到 Nginx，将使用 '--nginx' 插件模式。"
    if ! systemctl is-active --quiet nginx; then
        log_info "Nginx 服务未运行，正在启动..."
        systemctl start nginx
    fi
    local NGINX_CONF_PATH="/etc/nginx/sites-available/$domain_name.conf"
    if [ ! -f "$NGINX_CONF_PATH" ]; then
        log_info "为域名验证创建临时的 HTTP Nginx 配置文件..."
        cat <<EOF >"$NGINX_CONF_PATH"
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name;
    root /var/www/html;
    index index.html index.htm;
}
EOF
        if [ ! -L "/etc/nginx/sites-enabled/$domain_name.conf" ]; then
            ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"
        fi
        log_info "正在重载 Nginx 以应用临时配置..."
        if ! nginx -t; then
            log_error "Nginx 临时配置测试失败！请检查 Nginx 状态。"
            rm -f "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/$domain_name.conf"
            return 1
        fi
        systemctl reload nginx
    else
        log_warn "检测到已存在的 Nginx 配置文件，将直接在此基础上尝试申请证书。"
    fi

    # --- 这里是核心修改 ---
    # 移除了所有询问邮箱的交互代码
    # 直接定义使用“无邮箱”参数
    log_info "将使用 --register-unsafely-without-email 参数，自动跳过邮箱输入。"
    local email_arg="--register-unsafely-without-email"
    # --- 修改结束 ---

    log_info "正在使用 'certbot --nginx' 模式为 $domain_name 申请证书..."
    # 在 certbot 命令中直接使用定义好的 $email_arg
    certbot --nginx -d "$domain_name" --non-interactive --agree-tos $email_arg --redirect

    if [ -f "/etc/letsencrypt/live/$domain_name/fullchain.pem" ]; then
        log_info "✅ Nginx 模式证书申请成功！"
        return 0
    else
        log_error "Nginx 模式证书申请失败！"
        return 1
    fi
}
# --- (优化) 调用DNS预检查 ---
apply_ssl_certificate() {
    local domain_name="$1"

    # --- 新增DNS预检查调用 ---
    if ! _precheck_domain_dns "$domain_name"; then
        return 1
    fi

    local cert_dir="/etc/letsencrypt/live/$domain_name"
    if [ -d "$cert_dir" ]; then
        log_info "检测到域名 $domain_name 的证书已存在，跳过申请流程。"
        return 0
    fi
    log_info "证书不存在，开始智能检测环境并为 $domain_name 申请新证书..."

    local certbot_dep="certbot"
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        log_warn "在 RHEL/CentOS 上, Certbot 通常位于 EPEL 仓库。"
        log_warn "如果安装失败，请先手动安装 epel-release 包。"
    fi
    ensure_dependencies "$certbot_dep"

    if command -v caddy &>/dev/null; then
        _handle_caddy_cert
    else
        log_info "未检测到 Caddy，将默认使用 Nginx 模式。"
        local nginx_certbot_dep="python3-certbot-nginx"
        if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
            nginx_certbot_dep="python3-certbot-nginx"
        fi
        ensure_dependencies "nginx" "$nginx_certbot_dep"
        _handle_nginx_cert "$domain_name"
    fi
    return $?
}

# --- (优化) 增加HSTS头 ---
_configure_nginx_proxy() {
    local domain="$1"
    local port="$2"
    local conf_path="/etc/nginx/sites-available/$domain.conf"
    log_info "正在为 $domain -> http://127.0.0.1:$port 创建 Nginx 配置文件..."
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
    if [ ! -f "$cert_path" ]; then
        log_error "未找到预期的证书文件，无法配置 HTTPS。"
        return 1
    fi
    cat >"$conf_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    ssl_certificate $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    # --- (新增) HSTS 头，增强安全性 ---
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    if [ ! -L "/etc/nginx/sites-enabled/$domain.conf" ]; then
        ln -s "$conf_path" "/etc/nginx/sites-enabled/"
    fi
    log_info "正在测试并重载 Nginx 配置..."
    if ! nginx -t; then
        log_error "Nginx 配置测试失败！请手动检查。"
        return 1
    fi
    systemctl reload nginx
    log_info "✅ Nginx 反向代理配置成功！"
    return 0
}

_configure_caddy_proxy() {
    local domain="$1"
    local port="$2"
    local caddyfile="/etc/caddy/Caddyfile"
    log_info "检测到 Caddy，将自动添加配置到 Caddyfile..."
    if grep -q "^\s*$domain" "$caddyfile"; then
        log_warn "Caddyfile 中似乎已存在关于 $domain 的配置，跳过添加。"
        log_info "请手动检查您的 Caddyfile 文件。"
        return 0
    fi
    # 使用标准空格，确保格式正确
    echo -e "\n# Auto-generated by vps-toolkit for $domain\n$domain {\n    reverse_proxy 127.0.0.1:$port\n}" >>"$caddyfile"
    log_info "正在重载 Caddy 服务..."
    if ! caddy fmt --overwrite "$caddyfile"; then
        log_error "Caddyfile 格式化失败，请检查配置。"
    fi
    if ! systemctl reload caddy; then
        log_error "Caddy 服务重载失败！请手动检查。"
        return 1
    fi
    log_info "✅ Caddy 反向代理配置成功！Caddy 会自动处理 HTTPS。"
    return 0
}

# --- (重写) 增加端口检查、操作前确认、Web服务器选择 ---
setup_auto_reverse_proxy() {
    local domain_input="$1"
    local local_port="$2"
    local web_server_choice=""

    clear
    log_info "欢迎使用通用反向代理设置向导。\n"

    # --- 收集和验证输入 ---
    if [ -z "$domain_input" ]; then
        while true; do
            read -p "请输入您要设置反代的域名: " domain_input
            if [[ -z "$domain_input" ]]; then log_error "域名不能为空！\n"; elif ! _is_domain_valid "$domain_input"; then log_error "域名格式不正确。\n"; else break; fi
        done
    else
        log_info "将为预设域名 $domain_input 进行操作。\n"
    fi

    if [ -z "$local_port" ]; then
        while true; do
            read -p "请输入要代理到的本地端口 (例如 8080): " local_port
            if [[ ! "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then
                log_error "端口号必须是 1-65535 之间的数字。"
            elif ! check_port "$local_port"; then
                # check_port 失败时会自己打印错误，这里不用重复
                :
            else
                break
            fi
        done
    else
        log_info "将代理到预设的本地端口: $local_port"
    fi

    # --- (新增) Web服务器选择逻辑 ---
    local has_nginx=$(command -v nginx &>/dev/null)
    local has_caddy=$(command -v caddy &>/dev/null)

    if [ -n "$has_nginx" ] && [ -n "$has_caddy" ]; then
        echo -e "\n检测到您同时安装了 Nginx 和 Caddy，请选择使用哪一个：\n  1. Nginx\n  2. Caddy\n"
        read -p "请输入选项: " server_choice_num
        if [ "$server_choice_num" == "2" ]; then web_server_choice="caddy"; else web_server_choice="nginx"; fi
    elif [ -n "$has_nginx" ]; then
        web_server_choice="nginx"
    elif [ -n "$has_caddy" ]; then
        web_server_choice="caddy"
    else
        log_warn "未检测到任何 Web 服务器。将为您自动安装 Nginx..."
        ensure_dependencies "nginx"
        if command -v nginx &>/dev/null; then web_server_choice="nginx"; else
            log_error "Nginx 安装失败，无法继续。"
            press_any_key
            return 1
        fi
    fi
    log_info "将使用 [$web_server_choice] 进行反向代理配置。"

    # --- (新增) 操作前确认 ---
    echo ""
    log_warn "----------- 操作确认 -----------"
    log_warn "  域名: $domain_input"
    log_warn "  本地端口: $local_port"
    log_warn "  Web 服务器: $web_server_choice"
    log_warn "--------------------------------"
    read -p "请确认以上信息无误，是否继续执行？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"; press_any_key; return;
    fi

    # --- 执行核心逻辑 ---
    local status=1
    if [ "$web_server_choice" == "caddy" ]; then
        _configure_caddy_proxy "$domain_input" "$local_port"
        status=$?
    elif [ "$web_server_choice" == "nginx" ]; then
        if ! apply_ssl_certificate "$domain_input"; then
            log_error "证书处理失败，无法继续配置 Nginx 反代。"
            status=1
        else
            _configure_nginx_proxy "$domain_input" "$local_port"
            status=$?
        fi
    fi

    # 如果是独立调用此函数，则需要暂停
    if [ -z "$1" ]; then
        press_any_key
    fi
    return $status
}
# =================================================
#           证书 & 反代 (新增的缺失函数)
# =================================================

# (新增) 查看/列出所有证书
list_certificates() {
    # 检查 certbot 命令是否存在
    if ! command -v certbot &>/dev/null; then
        log_error "Certbot 未安装，无法查看证书列表。"
        return
    fi

    clear
    log_info "正在获取由 Certbot 管理的所有证书列表..."
    echo -e "$CYAN----------------------------------------------------------------------$NC"

    # 直接执行 certbot certificates 命令，它会处理“找到证书”和“未找到证书”两种情况
    # 并以友好的格式输出
    certbot certificates

    echo -e "$CYAN----------------------------------------------------------------------$NC"
}
# --- (新增) 仅申请证书的工作流函数 ---
apply_ssl_certificate_only_workflow() {
    clear
    log_info "欢迎使用独立证书申请工具。\n"
    local domain
    while true; do
        read -p "请输入要申请证书的域名: " domain
        if [[ -z "$domain" ]]; then log_error "域名不能为空！\n"; elif ! _is_domain_valid "$domain"; then log_error "域名格式不正确。\n"; else break; fi
    done

    if apply_ssl_certificate "$domain"; then
        log_info "✅ 证书申请流程执行完毕，已成功为域名 [$domain] 获取证书。"
    else
        log_error "证书申请流程失败，请检查之前的错误日志。"
    fi
    press_any_key
}

# --- (重写) 采用新的菜单结构 ---
certificate_management_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE             证书管理 & 网站反代 (v2.0)           $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 新建网站反代 (自动申请证书)                 $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. ${GREEN}仅为域名申请证书${NC}                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. 查看/列出所有证书                           $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   4. 手动续签所有证书                            $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. ${RED}删除证书 (并清理反代配置)${NC}                   $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. 返回主菜单                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"

        read -p "请输入选项: " choice
        case $choice in
        1) setup_auto_reverse_proxy "" "" ;; # 传递空参数以启动完整交互流程
        2) apply_ssl_certificate_only_workflow ;;
        3) clear; list_certificates; press_any_key ;;
        4) renew_certificates ;;
        5) delete_certificate_and_proxy ;;
        0) break ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# =================================================
#           脚本初始化 & 主入口
# =================================================

do_update_script() {
    log_info "正在从 GitHub 下载最新版本的脚本..."
    local temp_script="/tmp/vps_tool_new.sh"
    register_temp_file "$temp_script"

    if ! curl -sL "$SCRIPT_URL" -o "$temp_script"; then
        log_error "下载脚本失败！请检查您的网络连接或 URL 是否正确。"
        press_any_key
        return
    fi
    if cmp -s "$SCRIPT_PATH" "$temp_script"; then
        log_info "脚本已经是最新版本，无需更新。"
        rm "$temp_script"
        press_any_key
        return
    fi
    log_info "下载成功，正在应用更新..."
    chmod +x "$temp_script"
    mv "$temp_script" "$SCRIPT_PATH"
    log_info "✅ 脚本已成功更新！正在立即重新加载..."
    sleep 2
    exec "$SCRIPT_PATH"
}

_create_shortcut() {
    local shortcut_name=$1
    local full_path="/usr/local/bin/$shortcut_name"
    if [ -z "$shortcut_name" ]; then log_error "快捷命令名称不能为空！"; return 1; fi
    if ! [[ "$shortcut_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then log_error "无效的命令名称！只能包含字母、数字、下划线和连字符。"; return 1; fi

    log_info "正在为脚本创建快捷命令: $shortcut_name"
    ln -sf "$SCRIPT_PATH" "$full_path"
    chmod +x "$full_path"
    log_info "✅ 快捷命令 '$shortcut_name' 已设置！"
    log_info "现在您可以随时随地输入 '$shortcut_name' 来运行此脚本。"
}

initial_setup_check() {
    if [ ! -f "$FLAG_FILE" ]; then
        log_info "脚本首次运行，开始自动设置..."
        _create_shortcut "sv"
        log_info "创建标记文件以跳过下次检查。"
        touch "$FLAG_FILE"
        log_info "首次设置完成！正在进入主菜单..."
        sleep 2
    fi
}
# =================================================
#           脚本初始化 & 主入口 (最终优化版)
# =================================================
main_menu() {
    while true; do
        # 1. 动态获取IP地址
        local ipv4
        ipv4=$(get_public_ip v4)
        local ipv6
        ipv6=$(get_public_ip v6)
        [ -z "$ipv4" ] && ipv4="N/A"
        [ -z "$ipv6" ] && ipv6="N/A"

        # 2. 组合成一个多行的标题 (已移除多余的分割线)
        local title
        title="全功能 VPS & 应用管理脚本\n\n${WHITE}IPv4: ${ipv4}\n${WHITE}IPv6: ${ipv6}\n"

        # 3. 定义主菜单的所有选项
        local -a options=(
            "系统综合管理"
            "Sing-Box 管理"
            "Sub-Store 管理"
            "哪吒监控管理"
            "Docker 通用管理"
            "应用 & 面板安装"
            "证书管理 & 网站反代"
            "${GREEN}更新此脚本${NC}"
        )

        # 4. 定义一个变量来接收用户的选择，并调用通用菜单函数
        local choice
        _draw_menu "$title" choice "${options[@]}"

        # 5. 根据用户的选择执行相应操作
        case $choice in
            1) sys_manage_menu ;;
            2) singbox_main_menu ;;
            3) substore_main_menu ;;
            4) nezha_main_menu ;;
            5) docker_manage_menu ;;
            6) docker_apps_menu ;;
            7) certificate_management_menu ;;
            8) do_update_script ;;
            0) exit 0 ;; # 0 号选项固定为退出脚本
            *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}
# --- 脚本执行入口 ---
check_root
detect_os_and_package_manager
initial_setup_check
main_menu