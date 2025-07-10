#!/bin/bash

# ===================================================================
#             哪吒面板/探针 智能管理脚本 (下载逻辑修正版)
# ===================================================================

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 日志函数 ---
log_info() { echo -e "${GREEN}[信息] - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[注意] - $1${NC}"; }
log_error() { echo -e "${RED}[错误] - $1${NC}"; }
press_any_key() { read -n 1 -s -r -p "按任意键继续..."; }

# --- 检查 Root 权限 ---
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "此脚本必须以 root 用户身份运行。"
    exit 1
  fi
}

# --- 【已修正】智能获取可用的下载地址 ---
get_workable_download_url() {
    local original_url=$1

    # 1. 优先尝试直连
    log_info "正在尝试直接连接 GitHub..."
    if curl -L -s --connect-timeout 5 -o /dev/null "$original_url"; then
        log_info "直连成功！将使用原始链接进行下载。"
        echo "$original_url"
        return 0
    fi
    log_warn "直连 GitHub 失败，开始尝试使用代理..."

    # 2. 遍历代理列表
    # 定义代理主机和它们的URL转换模式
    local proxies=("ghproxy.com" "kgithub.com")

    for proxy_host in "${proxies[@]}"; do
        local test_url=""
        case "$proxy_host" in
            "ghproxy.com")
                # ghproxy 使用 '代理地址/完整原始地址' 格式
                test_url="https://ghproxy.com/${original_url}"
                ;;
            "kgithub.com")
                # kgithub 替换域名，需要区分 raw 和普通 github
                if [[ "$original_url" == *"raw.githubusercontent.com"* ]]; then
                    test_url=$(echo "$original_url" | sed 's|raw.githubusercontent.com|raw.kgithub.com|')
                else
                    test_url=$(echo "$original_url" | sed 's|github.com|kgithub.com|')
                fi
                ;;
        esac

        log_info "正在尝试代理: $proxy_host"
        if curl -L -s --connect-timeout 5 -o /dev/null "$test_url"; then
            log_info "代理 $proxy_host 可用。"
            echo "$test_url"
            return 0
        fi
        log_warn "代理 $proxy_host 连接超时或失败。"
    done

    log_error "所有下载方式都已失败！请检查网络或稍后再试。"
    return 1
}

# --- 查找一个唯一且可用的服务名 ---
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

# --- 安装 V0 探针的函数 ---
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
    local final_url; final_url=$(get_workable_download_url "$v0_script_url")
    if [ $? -ne 0 ]; then press_any_key; return 1; fi

    local installer_sh="nezha_installer_temp.sh"
    log_info "将从以下地址下载 V0 安装脚本: $final_url"
    if ! curl -L "$final_url" -o "$installer_sh"; then log_error "下载安装脚本失败！"; rm -f "$installer_sh"; press_any_key; return 1; fi

    log_info "正在修改安装脚本以使用自定义服务名和路径..."
    sed -i "s|NAME=\"nezha-agent\"|NAME=\"${service_name}\"|g" "$installer_sh"
    sed -i "s|INSTALL_DIR=\"/opt/nezha/agent\"|INSTALL_DIR=\"${install_dir}\"|g" "$installer_sh"
    chmod +x "$installer_sh"

    log_info "正在执行修改后的安装脚本..."; if sudo ./"$installer_sh" install_agent "$server_addr" "$server_port" "$agent_key" "$tls_option"; then log_info "✅ V0 探针安装成功！"; else log_error "V0 探针安装失败！"; fi
    rm -f "$installer_sh"; press_any_key
}

# --- 安装 V1 探针的函数 ---
install_nezha_v1() {
    clear; log_info "开始安装哪吒探针 V1 版本..."
    read -p "请输入你的面板服务器地址 (格式 domain:port) [默认: nz.ssong.eu.org:8008]: " nz_server; nz_server=${nz_server:-"nz.ssong.eu.org:8008"}
    read -p "请输入你的 Agent 密钥 (此项必须填写): " nz_secret
    read -p "你的面板是否启用了 TLS (https/SSL)? [默认: N]: " use_tls; use_tls=${use_tls:-"n"}
    if [[ -z "$nz_secret" ]]; then log_error "Agent 密钥不能为空！"; press_any_key; return 1; fi
    local nz_tls_flag="false"; if [[ "$use_tls" =~ ^[Yy]$ ]]; then nz_tls_flag="true"; fi

    local v1_script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh"
    local final_url; final_url=$(get_workable_download_url "$v1_script_url")
    if [ $? -ne 0 ]; then press_any_key; return 1; fi

    local installer_sh="agent_installer_temp.sh"
    log_info "将从以下地址下载 V1 安装脚本: $final_url"
    if ! curl -L "$final_url" -o "$installer_sh"; then log_error "下载 V1 安装脚本失败！"; rm -f "$installer_sh"; press_any_key; return 1; fi
    chmod +x "$installer_sh"

    log_info "正在使用标准方式进行初始安装..."; if ! sudo env NZ_SERVER="$nz_server" NZ_TLS="$nz_tls_flag" NZ_CLIENT_SECRET="$nz_secret" ./"$installer_sh"; then log_error "V1 探针初始安装失败！"; rm -f "$installer_sh"; press_any_key; return 1; fi

    log_info "初始安装完成，现在开始进行隔离操作..."; sudo systemctl stop nezha-agent
    local service_name; service_name=$(get_unique_service_name "nezha-agent-v1")
    local new_install_dir="/opt/nezha/${service_name}"; local default_install_dir="/opt/nezha/agent"
    sudo mv /etc/systemd/system/nezha-agent.service "/etc/systemd/system/${service_name}.service"; sudo mkdir -p "$new_install_dir"
    if [ -d "$default_install_dir" ]; then sudo mv ${default_install_dir}/* "${new_install_dir}/"; fi
    sudo sed -i "s|${default_install_dir}|${new_install_dir}|g" "/etc/systemd/system/${service_name}.service"
    log_info "正在重载配置并重启新服务..."; sudo systemctl daemon-reload; sudo systemctl enable "${service_name}.service"; sudo systemctl restart "${service_name}.service"; sleep 2
    if systemctl is-active --quiet "${service_name}.service"; then log_info "✅ V1 探针安装并隔离成功！"; else log_error "V1 探针隔离后启动失败！"; fi
    rm -f "$installer_sh"; press_any_key
}

# --- 卸载探针的函数 ---
uninstall_nezha_agent() {
    clear; log_info "开始扫描已安装的哪吒探针服务..."
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

# --- 面板管理函数 ---
_install_docker_and_compose() {
    if command -v docker &>/dev/null && command -v docker-compose &>/dev/null; then log_info "Docker 和 Docker-Compose 已安装。"; return 0; fi
    log_warn "未检测到 Docker 环境，开始安装...";
    # 此处应包含完整的 Docker 和 docker-compose 安装逻辑，例如从您的 vps-toolkit.sh 中移植
    # 为保证脚本简洁性，此处使用通用安装脚本，您可以替换为更适合您系统的安装方式
    if ! curl -fsSL https://get.docker.com | sh; then log_error "Docker 安装失败！"; return 1; fi
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    if ! curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then log_error "Docker-Compose 下载失败！"; return 1; fi
    chmod +x /usr/local/bin/docker-compose
    if command -v docker &>/dev/null && command -v docker-compose &>/dev/null; then log_info "✅ Docker 和 Docker-Compose 已成功安装！"; return 0; else log_error "Docker 环境安装失败！"; return 1; fi
}
install_dashboard_official() {
    if ! _install_docker_and_compose; then press_any_key; return; fi
    log_info "正在准备安装官方版面板 (国际)..."
    local script_url="https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh"
    local final_url; final_url=$(get_workable_download_url "$script_url"); if [ $? -ne 0 ]; then press_any_key; return 1; fi
    if ! curl -L "$final_url" -o nezha-dashboard.sh; then log_error "下载官方安装脚本失败！"; press_any_key; return 1; fi
    chmod +x nezha-dashboard.sh; log_info "已下载脚本，即将进入官方安装程序的交互界面..."; press_any_key; sudo ./nezha-dashboard.sh; rm -f nezha-dashboard.sh
}
install_dashboard_china() {
    if ! _install_docker_and_compose; then press_any_key; return; fi
    log_info "正在从 Gitee 源安装面板 (国内服务器优化)..."
    local script_url="https://gitee.com/naibahq/scripts/raw/main/install.sh"
    if ! curl -L "$script_url" -o nezha-dashboard.sh; then log_error "下载 Gitee 安装脚本失败！"; press_any_key; return 1; fi
    chmod +x nezha-dashboard.sh; log_info "已下载脚本，即将进入官方安装程序的交互界面 (已启用国内镜像)..."; press_any_key; sudo CN=true ./nezha-dashboard.sh; rm -f nezha-dashboard.sh
}
install_dashboard_fscarmen() {
    log_info "即将执行 fscarmen 的 Argo-Nezha 一键脚本..."; log_warn "此脚本为第三方脚本，将引导你完成安装。"
    local script_url="https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh"
    local final_url; final_url=$(get_workable_download_url "$script_url"); if [ $? -ne 0 ]; then press_any_key; return 1; fi
    press_any_key; bash <(curl -sL "$final_url")
}
uninstall_dashboard() {
    clear; log_info "请选择您当初安装面板时使用的方法："; echo; echo "  1. 官方脚本 (通过 GitHub 或 Gitee 源安装)"; echo "  2. fscarmen 的一键脚本"; echo; echo "  0. 返回"; echo
    read -p "请输入选项: " choice
    case $choice in
    1)
        log_warn "此操作将尝试在 /opt/nezha/dashboard 目录执行 docker-compose down -v。"; log_warn "这将删除面板容器、网络及数据库数据卷，操作不可逆！"
        if [ ! -d "/opt/nezha/dashboard" ]; then log_error "未找到默认安装目录 /opt/nezha/dashboard，无法继续。"; press_any_key; return; fi
        if ! _install_docker_and_compose; then press_any_key; return; fi
        read -p "请再次确认是否要彻底卸载官方版面板？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then cd /opt/nezha/dashboard; sudo docker-compose down -v; cd ~; log_info "✅ 官方版面板已卸载。"; else log_info "操作已取消。"; fi
        press_any_key
        ;;
    2)
        log_warn "此操作将尝试重新下载 fscarmen 脚本并执行其卸载流程。"; read -p "请确认是否要卸载 fscarmen 版面板？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local script_url="https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh"
            local final_url; final_url=$(get_workable_download_url "$script_url"); if [ $? -ne 0 ]; then press_any_key; return 1; fi
            log_info "即将调用第三方脚本的卸载功能..."; press_any_key; bash <(curl -sL "$final_url") uninstall
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
        echo -e "  ${CYAN}0. 返回主菜单${NC}"; echo
        echo -e "$BLUE-----------------------------------------------------$NC"; read -p "请输入选项 [0-4]: " choice
        case $choice in 1) install_dashboard_official ;; 2) install_dashboard_china ;; 3) install_dashboard_fscarmen ;; 4) uninstall_dashboard ;; 0) break ;; *) log_error "无效选项。"; press_any_key ;; esac
    done
}

# --- 主菜单 ---
main_menu() {
    while true; do
        clear
        echo -e "$BLUE=====================================================$NC"
        echo -e "$BLUE           哪吒面板/探针 智能管理脚本              $NC"
        echo -e "$BLUE=====================================================$NC"
        echo
        echo -e "  ${GREEN}1. 安装 V0 探针 (默认面板: nz.wiitwo.eu.org)${NC}"
        echo
        echo -e "  ${GREEN}2. 安装 V1 探针 (默认面板: nz.ssong.eu.org)${NC}"
        echo
        echo -e "  ${YELLOW}3. 卸载一个已安装的探针${NC}"
        echo
        echo -e "  ${CYAN}4. 哪吒【面板】管理 (安装/卸载)${NC}"
        echo
        echo -e "  ${RED}0. 退出脚本${NC}"
        echo
        echo -e "$BLUE-----------------------------------------------------$NC"
        read -p "请输入选项 [0-4]: " choice

        case $choice in
            1) install_nezha_v0 ;;
            2) install_nezha_v1 ;;
            3) uninstall_nezha_agent ;;
            4) dashboard_menu ;;
            0) echo "感谢使用，脚本已退出。"; exit 0 ;;
            *) log_error "无效选项，请输入 0-4。"; press_any_key ;;
        esac
    done
}

# --- 脚本入口 ---
check_root
main_menu