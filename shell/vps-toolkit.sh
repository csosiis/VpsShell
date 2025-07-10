#!/bin/bash

# ===================================================================
#             全功能 VPS & 应用管理脚本 (已集成哪吒管理)
# ===================================================================

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- 全局变量和配置 ---
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/$SUBSTORE_SERVICE_NAME"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODE_LINKS_FILE="/etc/sing-box/nodes_links.txt"
SCRIPT_PATH=$(realpath "$0")
SHORTCUT_PATH="/usr/local/bin/sv"
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh"
FLAG_FILE="/root/.vps_toolkit.initialized"

# --- 基础辅助函数 ---
log_info() { echo -e "$GREEN[信息] - $1$NC"; }
log_warn() { echo -e "$YELLOW[注意] - $1$NC"; }
log_error() { echo -e "$RED[错误] - $1$NC"; }
press_any_key() {
    echo ""
    read -n 1 -s -r -p "按任意键返回..."
}
check_root() { if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本必须以 root 用户身份运行。"
    exit 1
fi; }
check_port() {
    local port=$1
    if ss -tln | grep -q -E "(:|:::)$port\b"; then
        log_error "端口 $port 已被占用。"
        return 1
    fi
    return 0
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
        echo ""
        log_warn "端口 $port_to_check 已被系统其他服务占用。"
        return 1
    fi
    for used_port in "${used_ports[@]}"; do
        if [ "$port_to_check" == "$used_port" ]; then
            echo ""
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

# --- 核心功能函数 ---

# 【修复】删除了重复的 ensure_dependencies 函数
ensure_dependencies() {
    local dependencies=("$@")
    local missing_dependencies=()
    if [ ${#dependencies[@]} -eq 0 ]; then
        return 0
    fi
    log_info "正在按需检查依赖: ${dependencies[*]}..."
    for pkg in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_dependencies+=("$pkg")
        fi
    done
    if [ ${#missing_dependencies[@]} -gt 0 ]; then
        log_warn "检测到以下缺失的依赖包: ${missing_dependencies[*]}"
        log_info "正在更新软件包列表并开始安装..."
        set -e
        apt-get update -y
        for pkg in "${missing_dependencies[@]}"; do
            log_info "正在安装 $pkg..."
            apt-get install -y "$pkg"
        done
        set +e
        log_info "按需依赖已安装完毕。"
    else
        log_info "所需依赖均已安装。"
    fi
    echo ""
}

show_system_info() {
    ensure_dependencies "util-linux" "procps" "vnstat" "jq" "lsb-release" "curl" "net-tools"
    clear
    log_info "正在查询系统信息，请稍候..."
    # ... (原有函数内容保持不变) ...
    press_any_key
}

clean_system() {
    # ... (原有函数内容保持不变) ...
}

change_hostname() {
    # ... (原有函数内容保持不变) ...
}

optimize_dns() {
    # ... (原有函数内容保持不变) ...
}

set_network_priority() {
    # ... (原有函数内容保持不变) ...
}

setup_ssh_key() {
    # ... (原有函数内容保持不变) ...
}

set_timezone() {
    # ... (原有函数内容保持不变) ...
}

# ... (脚本中其他原有函数，如 install_sui, install_3xui, singbox 相关, substore 相关等等) ...
# ... (为节省篇幅，此处省略了您脚本中的大量已有函数，它们都应保留在原位) ...

_install_docker_and_compose() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "Docker 和 Docker Compose V2 已安装。"
        return 0
    fi
    log_warn "未检测到完整的 Docker 环境，开始执行官方标准安装流程..."
    ensure_dependencies "ca-certificates" "curl" "gnupg"
    log_info "正在添加 Docker 官方 GPG 密钥..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    log_info "正在添加 Docker 软件仓库..."
    local os_id
    os_id=$(. /etc/os-release && echo "$ID")
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$os_id \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    log_info "正在更新软件包列表以识别新的 Docker 仓库..."
    set -e
    apt-get update -y
    log_info "正在安装 Docker Engine, CLI, Containerd, 和 Docker Compose 插件..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    set +e
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_info "✅ Docker 和 Docker Compose V2 已成功安装！"
        return 0
    else
        log_error "Docker 环境安装失败！请检查上面的日志输出。"
        return 1
    fi
}

#
# ... 此处省略了您脚本中大量的其他函数 ...
#

# 【修复】删除了重复的 push_nodes 函数
push_nodes() {
    ensure_dependencies "jq" "curl"
    clear
    echo ""
    echo -e "$WHITE------- 推送节点 -------$NC\n"
    echo "1. 推送到 Sub-Store"
    echo ""
    echo "2. 推送到 Telegram Bot"
    echo ""
    echo -e "$WHITE------------------------$NC\n"
    echo "0. 返回上一级菜单"
    echo ""
    echo -e "$WHITE------------------------$NC\n"
    read -p "请选择推送方式: " push_choice
    case $push_choice in
    1) push_to_sub_store ;;
    2) push_to_telegram ;;
    0) return ;;
    *)
        log_error "无效选项！"
        press_any_key
        ;;
    esac
}

#
# ... 此处省略了您脚本中大量的其他函数 ...
#

# ===================================================================
#                      【新增】哪吒监控管理模块
# ===================================================================

# --- 哪吒模块专属辅助函数 ---
get_github_proxy_url() {
    local target_url=$1
    local proxies=("https://ghproxy.com/" "https://kgithub.com/")

    log_info "正在寻找可用的 GitHub 代理..."
    for proxy in "${proxies[@]}"; do
        local test_url="${proxy}${target_url}"
        log_info "正在尝试代理: $proxy"
        if curl -L -s --connect-timeout 5 -o /dev/null "$test_url"; then
            log_info "代理 $proxy 可用。"
            echo "$proxy"
            return 0
        fi
        log_warn "代理 $proxy 连接超时或失败。"
    done

    log_error "所有内置的 GitHub 代理都无法连接！"
    return 1
}
get_unique_service_name() {
    local base_name=$1
    local service_name="$base_name"
    local counter=2

    while systemctl list-units --full -all | grep -Fq "${service_name}.service"; do
        service_name="${base_name}-${counter}"
        ((counter++))
    done

    log_info "已为此探针分配唯一的服务名: ${service_name}"
    echo "$service_name"
}

# --- 哪吒探针安装函数 ---
install_nezha_v0() {
    clear
    log_info "开始安装哪吒探针 V0 版本..."
    read -p "请输入你的面板服务器地址 [默认: nz.wiitwo.eu.org]: " server_addr; server_addr=${server_addr:-"nz.wiitwo.eu.org"}
    read -p "请输入你的面板端口 [默认: 443]: " server_port; server_port=${server_port:-"443"}
    read -p "请输入你的 Agent 密钥 (此项必须填写): " agent_key
    read -p "你的面板是否启用了 TLS (https/SSL)? [默认: Y]: " use_tls; use_tls=${use_tls:-"y"}
    if [[ -z "$agent_key" ]]; then log_error "Agent 密钥不能为空！"; press_any_key; return 1; fi

    local tls_option=""; if [[ "$use_tls" =~ ^[Yy]$ ]]; then tls_option="--tls"; fi
    local service_name; service_name=$(get_unique_service_name "nezha-agent-v0")
    local install_dir="/opt/nezha/${service_name}"
    local v0_script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/install_en.sh"
    local proxy_url; proxy_url=$(get_github_proxy_url "$v0_script_url")
    if [ $? -ne 0 ]; then press_any_key; return 1; fi

    local installer_sh="nezha_installer_temp.sh"
    log_info "正在通过代理下载 V0 安装脚本..."
    if ! curl -L "${proxy_url}${v0_script_url}" -o "$installer_sh"; then log_error "下载安装脚本失败！"; rm -f "$installer_sh"; press_any_key; return 1; fi

    log_info "正在修改安装脚本以使用自定义服务名和路径..."
    sed -i "s|NAME=\"nezha-agent\"|NAME=\"${service_name}\"|g" "$installer_sh"
    sed -i "s|INSTALL_DIR=\"/opt/nezha/agent\"|INSTALL_DIR=\"${install_dir}\"|g" "$installer_sh"
    chmod +x "$installer_sh"

    log_info "正在执行修改后的安装脚本..."; if sudo ./"$installer_sh" install_agent "$server_addr" "$server_port" "$agent_key" "$tls_option"; then log_info "✅ V0 探针安装成功！"; else log_error "V0 探针安装失败！"; fi
    rm -f "$installer_sh"; press_any_key
}
install_nezha_v1() {
    clear
    log_info "开始安装哪吒探针 V1 版本..."
    read -p "请输入你的面板服务器地址 (格式 domain:port) [默认: nz.ssong.eu.org:8008]: " nz_server; nz_server=${nz_server:-"nz.ssong.eu.org:8008"}
    read -p "请输入你的 Agent 密钥 (此项必须填写): " nz_secret
    read -p "你的面板是否启用了 TLS (https/SSL)? [默认: N]: " use_tls; use_tls=${use_tls:-"n"}
    if [[ -z "$nz_secret" ]]; then log_error "Agent 密钥不能为空！"; press_any_key; return 1; fi

    local nz_tls_flag="false"; if [[ "$use_tls" =~ ^[Yy]$ ]]; then nz_tls_flag="true"; fi
    local v1_script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh"
    local proxy_url; proxy_url=$(get_github_proxy_url "$v1_script_url")
    if [ $? -ne 0 ]; then press_any_key; return 1; fi

    local installer_sh="agent_installer_temp.sh"
    log_info "正在通过代理下载 V1 安装脚本..."
    if ! curl -L "${proxy_url}${v1_script_url}" -o "$installer_sh"; then log_error "下载 V1 安装脚本失败！"; rm -f "$installer_sh"; press_any_key; return 1; fi
    chmod +x "$installer_sh"

    log_info "正在使用标准方式进行初始安装..."
    if ! sudo env NZ_SERVER="$nz_server" NZ_TLS="$nz_tls_flag" NZ_CLIENT_SECRET="$nz_secret" ./"$installer_sh"; then log_error "V1 探针初始安装失败！"; rm -f "$installer_sh"; press_any_key; return 1; fi

    log_info "初始安装完成，现在开始进行隔离操作..."; sudo systemctl stop nezha-agent
    local service_name; service_name=$(get_unique_service_name "nezha-agent-v1")
    local new_install_dir="/opt/nezha/${service_name}"; local default_install_dir="/opt/nezha/agent"
    sudo mv /etc/systemd/system/nezha-agent.service "/etc/systemd/system/${service_name}.service"
    sudo mkdir -p "$new_install_dir"
    if [ -d "$default_install_dir" ]; then sudo mv ${default_install_dir}/* "${new_install_dir}/"; fi
    sudo sed -i "s|${default_install_dir}|${new_install_dir}|g" "/etc/systemd/system/${service_name}.service"
    log_info "正在重载配置并重启新服务..."; sudo systemctl daemon-reload; sudo systemctl enable "${service_name}.service"; sudo systemctl restart "${service_name}.service"; sleep 2
    if systemctl is-active --quiet "${service_name}.service"; then log_info "✅ V1 探针安装并隔离成功！"; else log_error "V1 探针隔离后启动失败！"; fi
    rm -f "$installer_sh"; press_any_key
}
uninstall_nezha_agent() {
    clear
    log_info "开始扫描已安装的哪吒探针服务..."
    local services; mapfile -t services < <(sudo systemctl list-unit-files --full --all --type=service | grep -o 'nezha-agent-v[01][^ ]*\.service')
    if [ ${#services[@]} -eq 0 ]; then log_warn "未找到任何通过本脚本安装的哪吒探针服务。"; press_any_key; return; fi

    log_info "请选择要卸载的探针服务:"; echo; local i=1
    for s in "${services[@]}"; do echo -e "  $i. ${YELLOW}${s}${NC}"; i=$((i+1)); done
    echo; echo "  0. 返回主菜单"; echo
    read -p "请输入选项: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#services[@]} ]; then log_error "无效输入！"; press_any_key; return; fi
    if [ "$choice" -eq 0 ]; then log_info "操作已取消。"; return; fi

    local service_to_uninstall=${services[$((choice-1))]}; echo
    read -p "你确定要彻底卸载服务 ${RED}${service_to_uninstall}${NC} 及其所有文件吗? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_info "卸载操作已取消。"; press_any_key; return; fi

    log_info "正在停止、禁用并删除服务 ${service_to_uninstall}..."; sudo systemctl stop "$service_to_uninstall"; sudo systemctl disable "$service_to_uninstall"; sudo rm -f "/etc/systemd/system/${service_to_uninstall}"
    local base_name=${service_to_uninstall%.service}; local install_dir="/opt/nezha/${base_name}"
    log_info "正在删除程序目录 ${install_dir}..."; sudo rm -rf "$install_dir"
    log_info "正在重载 systemd..."; sudo systemctl daemon-reload; echo
    log_info "✅ 服务 ${service_to_uninstall} 已被彻底卸载！"; press_any_key
}

# --- 哪吒面板管理函数 ---
install_dashboard_official() {
    if ! _install_docker_and_compose; then press_any_key; return; fi
    log_info "正在从官方 GitHub 源安装面板..."; local script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh"
    local proxy_url; proxy_url=$(get_github_proxy_url "$script_url"); if [ $? -ne 0 ]; then press_any_key; return 1; fi
    if ! curl -L "${proxy_url}${script_url}" -o nezha-dashboard.sh; then log_error "下载官方安装脚本失败！"; press_any_key; return 1; fi
    chmod +x nezha-dashboard.sh; log_info "已下载脚本，即将进入官方安装程序的交互界面..."; press_any_key; sudo ./nezha-dashboard.sh; rm -f nezha-dashboard.sh
}
install_dashboard_china() {
    if ! _install_docker_and_compose; then press_any_key; return; fi
    log_info "正在从 Gitee 源安装面板 (国内服务器优化)..."; local script_url="https://gitee.com/naibahq/scripts/raw/main/install.sh"
    if ! curl -L "$script_url" -o nezha-dashboard.sh; then log_error "下载 Gitee 安装脚本失败！"; press_any_key; return 1; fi
    chmod +x nezha-dashboard.sh; log_info "已下载脚本，即将进入官方安装程序的交互界面 (已启用国内镜像)..."; press_any_key; sudo CN=true ./nezha-dashboard.sh; rm -f nezha-dashboard.sh
}
install_dashboard_fscarmen() {
    log_info "即将执行 fscarmen 的 Argo-Nezha 一键脚本..."; log_warn "此脚本为第三方脚本，将引导你完成安装，请根据其提示操作。"
    local script_url="https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh"
    local proxy_url; proxy_url=$(get_github_proxy_url "$script_url"); if [ $? -ne 0 ]; then press_any_key; return 1; fi
    press_any_key; bash <(curl -sL "${proxy_url}${script_url}")
}
uninstall_dashboard() {
    clear; log_info "请选择您当初安装面板时使用的方法："; echo; echo "  1. 官方脚本 (通过 GitHub 或 Gitee 源安装)"; echo "  2. fscarmen 的一键脚本"; echo; echo "  0. 返回"; echo
    read -p "请输入选项: " choice
    case $choice in
    1)
        log_warn "此操作将尝试在 /opt/nezha/dashboard 目录执行 docker compose down -v。"; log_warn "这将删除面板容器、网络及数据库数据卷，操作不可逆！"
        if [ ! -d "/opt/nezha/dashboard" ]; then log_error "未找到默认安装目录 /opt/nezha/dashboard，无法继续。"; press_any_key; return; fi
        if ! _install_docker_and_compose; then press_any_key; return; fi
        read -p "请再次确认是否要彻底卸载官方版面板？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then cd /opt/nezha/dashboard; sudo docker compose down -v; cd ~; log_info "✅ 官方版面板已卸载。"; else log_info "操作已取消。"; fi
        press_any_key
        ;;
    2)
        log_warn "此操作将尝试重新下载 fscarmen 脚本并执行其卸载流程。"; read -p "请确认是否要卸载 fscarmen 版面板？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local script_url="https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh"
            local proxy_url; proxy_url=$(get_github_proxy_url "$script_url"); if [ $? -ne 0 ]; then press_any_key; return 1; fi
            log_info "即将调用第三方脚本的卸载功能..."; press_any_key; bash <(curl -sL "${proxy_url}${script_url}") uninstall
        else log_info "操作已取消。"; fi
        press_any_key
        ;;
    0) return ;; *) log_error "无效选项！"; press_any_key ;;
    esac
}
dashboard_menu() {
    while true; do clear;
        echo -e "$BLUE=====================================================$NC"; echo -e "$BLUE               哪吒监控面板管理菜单                  $NC"; echo -e "$BLUE=====================================================$NC"; echo
        echo -e "  ${GREEN}1. 安装面板 - 官方版 (适合海外服务器)${NC}"; echo
        echo -e "  ${GREEN}2. 安装面板 - 官方版 (中国大陆优化)${NC}"; echo
        echo -e "  ${YELLOW}3. 安装面板 - fscarmen 第三方版 (Argo 支持)${NC}"; echo
        echo -e "  ${RED}4. 卸载面板${NC}"; echo
        echo -e "  ${CYAN}0. 返回上一级菜单${NC}"; echo
        echo -e "$BLUE-----------------------------------------------------$NC"; read -p "请输入选项 [0-4]: " choice
        case $choice in 1) install_dashboard_official ;; 2) install_dashboard_china ;; 3) install_dashboard_fscarmen ;; 4) uninstall_dashboard ;; 0) break ;; *) log_error "无效选项。"; press_any_key ;; esac
    done
}
agent_install_menu() {
    while true; do clear;
        echo -e "$BLUE=====================================================$NC"; echo -e "$BLUE                 哪吒探针 (Agent) 安装菜单           $NC"; echo -e "$BLUE=====================================================$NC"; echo
        echo -e "  ${GREEN}1. 安装 V0 版本探针 (默认面板: nz.wiitwo.eu.org)${NC}"; echo
        echo -e "  ${GREEN}2. 安装 V1 版本探针 (默认面板: nz.ssong.eu.org)${NC}"; echo
        echo -e "  ${CYAN}0. 返回上一级菜单${NC}"; echo
        echo -e "$BLUE-----------------------------------------------------$NC"; read -p "请输入选项 [0-2]: " choice
        case $choice in 1) install_nezha_v0 ;; 2) install_nezha_v1 ;; 0) break ;; *) log_error "无效选项。"; press_any_key ;; esac
    done
}
nezha_main_menu() {
    while true; do clear;
        echo -e "$BLUE=====================================================$NC"; echo -e "$BLUE               哪吒监控 (面板/探针) 管理           $NC"; echo -e "$BLUE=====================================================$NC"; echo
        echo -e "  ${GREEN}1. 安装哪吒探针 (Agent)${NC}"; echo
        echo -e "  ${YELLOW}2. 卸载哪吒探针 (Agent)${NC}"; echo
        echo -e "  ${CYAN}3. 管理哪吒面板 (Dashboard)${NC}"; echo
        echo -e "  ${RED}0. 返回主菜单${NC}"; echo
        echo -e "$BLUE-----------------------------------------------------$NC"; read -p "请输入选项 [0-3]: " choice
        case $choice in 1) agent_install_menu ;; 2) uninstall_nezha_agent ;; 3) dashboard_menu ;; 0) break ;; *) log_error "无效选项。"; press_any_key ;; esac
    done
}


# ===================================================================
#                         主菜单与脚本入口
# ===================================================================

main_menu() {
    while true; do
        clear
        echo -e "$CYAN╔══════════════════════════════════════════════════╗$NC"
        echo -e "$CYAN║$WHITE              全功能 VPS & 应用管理脚本           $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   1. 系统综合管理                                $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   2. Sing-Box 管理                               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   3. Sub-Store 管理                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        # --- 新增的菜单项在这里 ---
        echo -e "$CYAN║$NC   4. $GREEN哪吒监控 (面板/探针) 管理$NC               $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟─────────────────── $WHITE其他面板$CYAN ─────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   5. 安装 S-ui 面板                              $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   6. 安装 3X-ui 面板                             $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   7. $GREEN搭建 WordPress (Docker)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   8. $GREEN自动配置网站反向代理$NC                        $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╟──────────────────────────────────────────────────╢$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   9. $GREEN更新此脚本$NC                                  $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC  10. $YELLOW设置快捷命令 (默认: sv)$NC                     $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN║$NC   0. $RED退出脚本$NC                                    $CYAN║$NC"
        echo -e "$CYAN║$NC                                                  $CYAN║$NC"
        echo -e "$CYAN╚══════════════════════════════════════════════════╝$NC"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
        1) sys_manage_menu ;;
        2) singbox_main_menu ;;
        3) substore_main_menu ;;
        4. nezha_main_menu ;; # 新增的调用
        5) ensure_dependencies "curl"; install_sui ;;
        6) ensure_dependencies "curl"; install_3xui ;;
        7) install_wordpress ;;
        8) setup_auto_reverse_proxy ;;
        9) do_update_script ;;
        10) setup_shortcut ;;
        0) exit 0 ;;
        *) log_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# ... (脚本中其他原有函数) ...

initial_setup_check() {
    if [ ! -f "$FLAG_FILE" ]; then
        echo ""
        log_info "脚本首次运行，开始自动设置..."
        _create_shortcut "sv"
        log_info "创建标记文件以跳过下次检查。"
        touch "$FLAG_FILE"
        echo ""
        log_info "首次设置完成！正在进入主菜单..."
        sleep 2
    fi
}

check_root
# initial_setup_check  # 你可以取消注释这一行来启用首次运行自动设置快捷方式
main_menu