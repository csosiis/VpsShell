#!/bin/bash
# ==============================================================================
#  全功能 VPS 管理工具
#
#  本脚本融合了 Sing-Box、Sub-Store 和系统工具的管理功能。
#  - 基于 Sub-Store 脚本 (v6.7) 的代码风格和菜单结构。
#  - 整合了 singbox.sh 的节点管理和推送功能。
#  - 整合了 sys.sh 的系统信息查询、优化和清理功能。
# ==============================================================================

# --- 全局变量和辅助函数 ---
# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# Sing-Box 配置文件路径
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
SINGBOX_NODES_FILE="/etc/sing-box/nodes_links.txt"

# Sub-Store 配置变量
SUBSTORE_SERVICE_NAME="sub-store.service"
SUBSTORE_SERVICE_FILE="/etc/systemd/system/${SUBSTORE_SERVICE_NAME}"
SUBSTORE_INSTALL_DIR="/root/sub-store"
SUBSTORE_SCRIPT_PATH=$(realpath "$0")
SUBSTORE_SHORTCUT_PATH="/usr/local/bin/sub"

# 脚本更新地址 (请根据实际情况修改)
SCRIPT_URL="https://raw.githubusercontent.com/csosiis/VpsShell/main/merged_script.sh" # 假设的合并后脚本URL

# 日志函数
log_info() { echo -e "${GREEN}[信息] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[注意] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[错误] $(date +'%Y-%m-%d %H:%M:%S') - $1${NC}"; }
press_any_key() { echo ""; read -n 1 -s -r -p "按任意键返回..."; }

# 检查是否以 root 身份运行
check_root() { if [ "$(id -u)" -ne 0 ]; then log_error "此脚本必须以 root 用户身份运行。"; exit 1; fi; }

# ==============================================================================
# Sing-Box 管理功能
# ==============================================================================

# 检查 Sing-Box 是否已安装
singbox_check_installed() {
    if ! command -v sing-box &> /dev/null; then
        return 1
    fi
    return 0
}

# 检查并提示安装 Sing-Box
singbox_check_and_prompt_install() {
    if ! singbox_check_installed; then
        log_warn "Sing-Box 尚未安装。"
        echo
        read -p "您是否希望先安装 Sing-Box？(y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            singbox_install
        else
            log_info "操作已取消。"
            press_any_key
            singbox_main_menu
        fi
    fi
}

# 安装 Sing-Box
singbox_install() {
    if singbox_check_installed; then
        log_info "Sing-Box 已经安装，跳过安装过程。"
        press_any_key
        return
    fi

    log_info "Sing-Box 未安装，正在开始安装..."

    if ! command -v curl &> /dev/null; then
        log_info "curl 未安装，正在安装..."
        apt update && apt install -y curl
        if ! command -v curl &> /dev/null; then
            log_error "curl 安装失败，请检查网络或包管理器设置。"
            exit 1
        fi
    fi

    if ! bash <(curl -fsSL https://sing-box.app/deb-install.sh); then
        log_error "Sing-Box 安装脚本执行失败。"
        exit 1
    fi

    if ! singbox_check_installed; then
        log_error "Sing-Box 安装失败，无法找到 sing-box 命令。"
        exit 1
    fi

    log_info "Sing-Box 安装成功！"

    local config_dir="/etc/sing-box"
    mkdir -p "$config_dir" || { log_error "创建配置目录失败！"; exit 1; }

    # 创建基础配置文件
    if [ ! -f "$SINGBOX_CONFIG_FILE" ]; then
        touch "$SINGBOX_CONFIG_FILE" || { log_error "创建配置文件失败！"; exit 1; }
        cat > "$SINGBOX_CONFIG_FILE" <<EOL
{
  "log": { "level": "info" },
  "dns": {},
  "ntp": null,
  "inbounds": [],
  "outbounds": [
    { "tag": "direct", "type": "direct" },
    { "type": "dns", "tag": "dns-out" }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "dns-out" }
    ]
  }
}
EOL
        if [ $? -ne 0 ]; then
            log_error "写入配置文件失败！"
            exit 1
        fi
        log_info "Sing-Box 配置文件初始化完成！"
    fi

    systemctl enable sing-box.service > /dev/null
    log_info "正在设置快捷启动方式..."
    ln -sf "$SUBSTORE_SCRIPT_PATH" /usr/local/bin/sb  # 创建 sb 快捷方式指向主脚本
    log_info "快捷命令 'sb' 已设置！输入 sb 即可启动此管理脚本。"

    log_info "Sing-Box 安装与初始化完成！"
    press_any_key
}

# 安装 Sing-Box 依赖
singbox_install_dependencies() {
    local packages_to_install=()
    if ! command -v uuidgen &>/dev/null; then packages_to_install+=("uuid-runtime"); fi
    if ! command -v jq &>/dev/null; then packages_to_install+=("jq"); fi
    if ! command -v certbot &>/dev/null; then packages_to_install+=("certbot"); fi

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "正在安装缺失的依赖: ${packages_to_install[*]}..."
        apt-get update >/dev/null
        for pkg in "${packages_to_install[@]}"; do
            apt-get install -y "$pkg" >/dev/null
        done
        log_info "依赖安装完成。"
    fi
}

# 生成随机端口
singbox_generate_random_port() {
    echo $((RANDOM % 64512 + 1024))
}

# 生成随机密码
singbox_generate_random_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c 20
}

# 申请 SSL 证书
singbox_apply_ssl_certificate() {
    local domain_name="$1"
    local stopped_services=()

    # 停止可能占用80端口的服务
    if systemctl is-active --quiet nginx; then
        log_info "检测到 Nginx 正在运行，临时停止..."
        systemctl stop nginx
        stopped_services+=("nginx")
    fi
    if systemctl is-active --quiet apache2; then
        log_info "检测到 Apache 正在运行，临时停止..."
        systemctl stop apache2
        stopped_services+=("apache2")
    fi

    # 申请证书
    log_info "正在为域名 ${domain_name} 申请证书..."
    certbot certonly --standalone --preferred-challenges http -d "$domain_name" --agree-tos --no-eff-email -m "admin@${domain_name}"

    # 检查结果并重启服务
    local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"

    if [[ -f "$cert_path" && -f "$key_path" ]]; then
        log_info "证书申请成功！"
        log_info "证书路径: $cert_path"
        log_info "密钥路径: $key_path"
        (crontab -l 2>/dev/null; echo "0 */12 * * * certbot renew --quiet --deploy-hook 'systemctl restart sing-box'") | crontab -
        log_info "已设置证书自动续期。"
    else
        log_error "证书申请失败，请检查域名解析和防火墙设置。"
    fi

    if [[ ${#stopped_services[@]} -gt 0 ]]; then
        for service in "${stopped_services[@]}"; do
            log_info "正在重启 $service 服务..."
            systemctl start "$service"
        done
    fi

    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
        press_any_key
        singbox_add_node_menu
        return 1
    fi
}

# 获取通用节点信息
singbox_get_common_node_info() {
    local type_flag=$1
    echo
    while true; do
        read -p "请输入您已解析到本服务器的域名: " domain_name
        if [[ -n "$domain_name" ]]; then break; else echo "域名不能为空。"; fi
    done

    if [[ $type_flag -eq 2 ]]; then # Hysteria2
        log_warn "Hysteria2 协议需要关闭域名的 CDN (小灰云)。"
    else
        log_warn "使用 CDN (小黄云) 时，请确保您选择的端口是 Cloudflare 支持的端口。"
    fi
    log_warn "如果服务器开启了防火墙, 请务必手动放行所需端口。"
    echo

    while true; do
        read -p "请输入端口 [回车自动生成]: " port
        port=${port:-$(singbox_generate_random_port)}
        if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]; then
            log_info "选定端口: ${port}"
            break
        else
            log_error "无效端口。"
        fi
    done
    echo

    log_info "正在自动获取服务器位置..."
    location=$(curl -s ip-api.com/json | jq -r '.city' | sed 's/ //g')
    if [[ -z "$location" || "$location" == "null" ]]; then
        log_warn "自动获取位置失败，请手动输入。"
        read -p "请输入服务器位置 (例如: HongKong): " location
    else
        log_info "成功获取位置: $location"
    fi
    echo

    read -p "请输入自定义节点名称/备注 (例如: GCP): " custom_tag
    echo

    # 检查证书
    cert_dir="/etc/letsencrypt/live/$domain_name"
    if [[ ! -d "$cert_dir" ]]; then
        log_warn "证书不存在，即将开始申请证书..."
        singbox_apply_ssl_certificate "$domain_name"
    else
        log_info "证书已存在，跳过申请。"
    fi
}

# 组合并添加节点
singbox_add_protocol_node() {
    local protocol=$1
    local config=$2
    local node_link=$3

    log_info "正在将新节点配置写入 ${SINGBOX_CONFIG_FILE}..."
    jq --argjson new_config "$config" '.inbounds += [$new_config]' "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"

    log_info "节点分享链接如下:"
    echo "------------------------------------------------------------------------------------------------------"
    echo -e "\n${YELLOW}${node_link}${NC}\n"
    echo "------------------------------------------------------------------------------------------------------"

    echo "$node_link" >> "$SINGBOX_NODES_FILE"
    log_info "节点链接已保存到 ${SINGBOX_NODES_FILE}"

    log_info "正在重启 Sing-Box 服务..."
    systemctl restart sing-box
    sleep 2
    if systemctl is-active --quiet sing-box; then
        log_info "✅ Sing-Box 重启成功，节点添加完毕！"
    else
        log_error "Sing-Box 服务重启失败！请检查日志。"
    fi
    press_any_key
    singbox_add_node_menu
}

# VLESS 节点
singbox_add_vless_node() {
    singbox_get_common_node_info 1
    local uuid=$(uuidgen)
    local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
    local tag="${location}-${custom_tag}-Vless"

    local config="{
      \"type\": \"vless\", \"tag\": \"$tag\", \"listen\": \"::\", \"listen_port\": $port,
      \"users\": [{ \"uuid\": \"$uuid\" }],
      \"tls\": { \"enabled\": true, \"server_name\": \"$domain_name\", \"certificate_path\": \"$cert_path\", \"key_path\": \"$key_path\" },
      \"transport\": { \"type\": \"ws\", \"path\": \"/csos\", \"headers\": { \"Host\": \"$domain_name\" } }
    }"
    local node_link="vless://$uuid@$domain_name:$port?type=ws&security=tls&sni=$domain_name&host=$domain_name&path=%2Fcsos#${tag}"
    singbox_add_protocol_node "Vless" "$config" "$node_link"
}

# Hysteria2 节点
singbox_add_hysteria2_node() {
    singbox_get_common_node_info 2
    local password=$(singbox_generate_random_password)
    local obfs_password=$(singbox_generate_random_password)
    local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
    local tag="${location}-${custom_tag}-Hysteria2"

    local config="{
      \"type\": \"hysteria2\", \"tag\": \"$tag\", \"listen\": \"::\", \"listen_port\": $port,
      \"users\": [{ \"password\": \"$password\" }],
      \"tls\": { \"enabled\": true, \"server_name\": \"$domain_name\", \"certificate_path\": \"$cert_path\", \"key_path\": \"$key_path\" },
      \"up_mbps\": 100, \"down_mbps\": 1000,
      \"obfs\": { \"type\": \"salamander\", \"password\": \"$obfs_password\" }
    }"
    local node_link="hysteria2://$password@$domain_name:$port?upmbps=100&downmbps=1000&sni=$domain_name&obfs=salamander&obfs-password=$obfs_password#${tag}"
    singbox_add_protocol_node "Hysteria2" "$config" "$node_link"
}

# VMess 节点
singbox_add_vmess_node() {
    singbox_get_common_node_info 3
    local uuid=$(uuidgen)
    local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
    local tag="${location}-${custom_tag}-Vmess"

    local config="{
      \"type\": \"vmess\", \"tag\": \"$tag\", \"listen\": \"::\", \"listen_port\": $port,
      \"users\": [{ \"uuid\": \"$uuid\", \"alterId\": 0 }],
      \"tls\": { \"enabled\": true, \"server_name\": \"$domain_name\", \"certificate_path\": \"$cert_path\", \"key_path\": \"$key_path\" },
      \"transport\": { \"type\": \"ws\", \"path\": \"/csos\", \"headers\": { \"Host\": \"$domain_name\" } }
    }"
    local vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$domain_name\",\"port\":$port,\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain_name\",\"path\":\"/csos\",\"tls\":\"tls\"}"
    local base64_vmess_link=$(echo -n "$vmess_json" | base64 | tr -d '\n')
    local node_link="vmess://$base64_vmess_link"
    singbox_add_protocol_node "Vmess" "$config" "$node_link"
}

# Trojan 节点
singbox_add_trojan_node() {
    singbox_get_common_node_info 4
    local password=$(singbox_generate_random_password)
    local cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
    local tag="${location}-${custom_tag}-Trojan"

    local config="{
      \"type\": \"trojan\", \"tag\": \"$tag\", \"listen\": \"::\", \"listen_port\": $port,
      \"users\": [{ \"password\": \"$password\" }],
      \"tls\": { \"enabled\": true, \"server_name\": \"$domain_name\", \"certificate_path\": \"$cert_path\", \"key_path\": \"$key_path\" },
      \"transport\": { \"type\": \"ws\", \"path\": \"/csos\", \"headers\": { \"Host\": \"$domain_name\" } }
    }"
    local node_link="trojan://$password@$domain_name:$port?type=ws&security=tls&sni=$domain_name&host=$domain_name&path=%2Fcsos#${tag}"
    singbox_add_protocol_node "Trojan" "$config" "$node_link"
}

# 查看节点
singbox_view_nodes() {
    if [[ ! -f "$SINGBOX_NODES_FILE" || ! -s "$SINGBOX_NODES_FILE" ]]; then
        log_warn "暂无已配置的节点！"
        press_any_key
        return 1
    fi

    clear
    log_info "已保存的节点链接信息："
    echo "------------------------------------------------------------------------------------------------------"
    local index=1
    local all_links=""
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        local node_name
        if [[ "$line" =~ ^vmess:// ]]; then
            node_name=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null | jq -r '.ps // "Vmess节点"')
        else
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
        fi
        echo -e "\n${GREEN}$index. $node_name${NC}"
        echo -e "${YELLOW}$line${NC}"
        echo "------------------------------------------------------------------------------------------------------"
        all_links+="$line"$'\n'
        ((index++))
    done < "$SINGBOX_NODES_FILE"

    if [[ -n "$all_links" ]]; then
        local aggregated_link=$(echo -n "$all_links" | base64 -w0)
        echo -e "\n${GREEN}所有节点聚合链接 (Base64):${NC}"
        echo -e "${YELLOW}$aggregated_link${NC}\n"
        echo "------------------------------------------------------------------------------------------------------"
    fi

    press_any_key
    singbox_manage_node_menu
}

# 删除节点
singbox_delete_nodes() {
    if [[ ! -f "$SINGBOX_NODES_FILE" || ! -s "$SINGBOX_NODES_FILE" ]]; then
        log_warn "当前没有任何节点可以删除！"
        press_any_key
        return
    fi

    mapfile -t node_lines < "$SINGBOX_NODES_FILE"
    local node_names=()
    local node_tags=()

    for line in "${node_lines[@]}"; do
        local node_name
        local tag
        if [[ "$line" =~ ^vmess:// ]]; then
            decoded_vmess=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null)
            node_name=$(echo "$decoded_vmess" | jq -r '.ps // "Vmess节点"')
            tag=$(echo "$line" | sed 's/.*#\(.*\)/\1/') # Vmess 的 tag 也在 # 后面
        else
            node_name=$(echo "$line" | sed 's/.*#\(.*\)/\1/')
            tag=$node_name
        fi
        node_names+=("$node_name")
        node_tags+=("$tag")
    done

    clear
    log_info "请选择要删除的节点 (可输入多个序号，用空格隔开):"
    echo "输入 'all' 删除所有节点。"
    echo "-----------------------------------------"
    for i in "${!node_names[@]}"; do
        echo -e "${GREEN}$((i + 1)). ${node_names[$i]}${NC}"
    done
    echo "-----------------------------------------"
    read -p "请输入序号 (或 'all'): " -a user_input

    local indices_to_delete=()
    if [[ " ${user_input[@]} " =~ " all " ]]; then
        read -p "确定要删除所有节点吗？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            indices_to_delete=($(seq 0 $((${#node_lines[@]} - 1))))
        fi
    else
        for num in "${user_input[@]}"; do
            if [[ "$num" =~ ^[0-9]+$ && "$num" -ge 1 && "$num" -le ${#node_lines[@]} ]]; then
                indices_to_delete+=($((num - 1)))
            fi
        done
    fi

    if [ ${#indices_to_delete[@]} -eq 0 ]; then
        log_info "没有选择任何节点或取消操作。"
        press_any_key
        return
    fi

    # 从后往前删除，避免索引错乱
    sorted_indices=($(for i in "${indices_to_delete[@]}"; do echo "$i"; done | sort -rn | uniq))

    local temp_config
    temp_config=$(cat "$SINGBOX_CONFIG_FILE")

    for index in "${sorted_indices[@]}"; do
        local tag_to_delete="${node_tags[$index]}"
        log_info "正在删除节点: ${node_names[$index]} (Tag: $tag_to_delete)"
        temp_config=$(echo "$temp_config" | jq --arg tag "$tag_to_delete" 'del(.inbounds[] | select(.tag == $tag))')
        unset 'node_lines[index]'
    done

    echo "$temp_config" > "$SINGBOX_CONFIG_FILE"
    printf "%s\n" "${node_lines[@]}" > "$SINGBOX_NODES_FILE"
    sed -i '/^$/d' "$SINGBOX_NODES_FILE" # 删除空行

    log_info "正在重启 Sing-Box..."
    systemctl restart sing-box
    log_info "✅ 所选节点已成功删除！"
    press_any_key
}

# 推送节点 (子菜单)
singbox_push_nodes_menu() {
    clear
    echo -e "${WHITE}--- Sing-Box 节点推送 ---${NC}\n"
    log_warn "此功能已被 Sub-Store 的订阅管理功能取代，推荐使用 Sub-Store 生成订阅链接。"
    echo ""
    echo "1. 使用 Sub-Store 管理订阅 (推荐)"
    echo ""
    echo "0. 返回上一级菜单"
    echo ""
    echo "---------------------------------"
    read -p "请输入选项: " choice
    case $choice in
        1) substore_main_menu ;;
        0) singbox_manage_node_menu ;;
        *) log_warn "无效选项" ; press_any_key ;;
    esac
}

# 卸载 Sing-Box
singbox_uninstall() {
    log_warn "你确定要完全卸载 Sing-Box 吗？所有配置文件都将被删除！"
    read -p "请输入 Y 确认: " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        log_info "取消卸载。"; press_any_key; return;
    fi

    log_info "正在停止并禁用 Sing-Box 服务..."
    systemctl stop sing-box.service &>/dev/null
    systemctl disable sing-box.service &>/dev/null

    log_info "正在删除 Sing-Box 相关文件..."
    rm -f /etc/systemd/system/sing-box.service
    rm -rf /etc/sing-box
    rm -f /usr/local/bin/sing-box
    rm -f /usr/local/bin/sb # 删除快捷方式

    log_info "正在重新加载 systemd..."
    systemctl daemon-reload

    if ! singbox_check_installed; then
        log_info "✅ Sing-Box 已成功卸载。"
    else
        log_error "Sing-Box 卸载失败，请手动检查残留文件。"
    fi
    press_any_key
}

# 添加节点菜单
singbox_add_node_menu() {
    clear
    echo -e "${WHITE}--- Sing-Box 新增节点 ---${NC}\n"
    echo "1. VLESS + WS + TLS"
    echo ""
    echo "2. Hysteria2"
    echo ""
    echo "3. VMess + WS + TLS"
    echo ""
    echo "4. Trojan + WS + TLS"
    echo ""
    echo "---------------------------------"
    echo "0. 返回上一级菜单"
    echo ""
    read -p "请选择要添加的协议类型: " choice

    # 在添加节点前，检查并安装依赖
    if [[ "$choice" =~ ^[1-4]$ ]]; then
        singbox_install_dependencies
    fi

    case $choice in
        1) singbox_add_vless_node ;;
        2) singbox_add_hysteria2_node ;;
        3) singbox_add_vmess_node ;;
        4) singbox_add_trojan_node ;;
        0) singbox_main_menu ;;
        *) log_warn "无效选项!"; sleep 1; singbox_add_node_menu ;;
    esac
}

# 管理节点菜单
singbox_manage_node_menu() {
    clear
    echo -e "${WHITE}--- Sing-Box 管理节点 ---${NC}\n"
    echo "1. 查看已有节点"
    echo ""
    echo "2. 删除节点"
    echo ""
    echo "3. 推送节点 (生成订阅)"
    echo ""
    echo "---------------------------------"
    echo "0. 返回 Sing-Box 主菜单"
    echo ""
    read -p "请选择操作: " choice
    case $choice in
        1) singbox_view_nodes ;;
        2) singbox_delete_nodes; singbox_manage_node_menu ;;
        3) singbox_push_nodes_menu ;;
        0) singbox_main_menu ;;
        *) log_warn "无效选项!"; sleep 1; singbox_manage_node_menu ;;
    esac
}

# Sing-Box 主菜单
singbox_main_menu() {
    clear
    echo -e "${WHITE}=====================================${NC}"
    echo -e "${WHITE}          Sing-Box 管理菜单          ${NC}"
    echo -e "${WHITE}=====================================${NC}\n"
    if ! singbox_check_installed; then
        echo "1. 安装 Sing-Box"
        echo ""
        echo "---------------------------------"
        echo "0. 返回主菜单"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
            1) singbox_install ;;
            0) return ;;
            *) log_warn "无效选项!"; sleep 1 ;;
        esac
    else
        echo "1. 新增节点"
        echo ""
        echo "2. 管理已有节点"
        echo ""
        echo "---------------------------------"
        echo "8. 卸载 Sing-Box"
        echo ""
        echo "0. 返回主菜单"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
            1) singbox_add_node_menu ;;
            2) singbox_manage_node_menu ;;
            8) singbox_uninstall ;;
            0) return ;;
            *) log_warn "无效选项!"; sleep 1 ;;
        esac
    fi
    singbox_main_menu
}


# ==============================================================================
# Sub-Store 管理功能
# ==============================================================================
substore_is_installed() { if [ -f "$SUBSTORE_SERVICE_FILE" ]; then return 0; else return 1; fi; }

substore_check_port() {
    local port=$1
    if ss -tln | grep -q -E "(:|:::)${port}\b"; then log_error "端口 ${port} 已被占用。"; return 1; fi
    log_info "端口 ${port} 可用。"; return 0;
}

substore_setup_shortcut() {
    log_info "正在设置 'sub' 快捷命令..."; ln -sf "$SUBSTORE_SCRIPT_PATH" "$SUBSTORE_SHORTCUT_PATH"; chmod +x "$SUBSTORE_SHORTCUT_PATH"
    log_info "快捷命令设置成功！现在您可以随时随地输入 'sub' 来运行此脚本。"
}

substore_do_install() {
    log_info "开始执行 Sub-Store 安装流程..."; set -e
    log_info "更新系统并安装基础组件..."; apt update -y > /dev/null; apt install unzip curl wget git sudo iproute2 apt-transport-https dnsutils -y > /dev/null
    log_info "正在安装 FNM, Node.js 和 PNPM...";
    FNM_DIR="/root/.local/share/fnm"
    mkdir -p "$FNM_DIR"
    curl -L https://github.com/Schniz/fnm/releases/latest/download/fnm-linux.zip -o /tmp/fnm.zip
    unzip -q -o -d "$FNM_DIR" /tmp/fnm.zip; rm /tmp/fnm.zip; chmod +x "${FNM_DIR}/fnm"; export PATH="${FNM_DIR}:$PATH"
    log_info "FNM 安装完成。"
    log_info "正在使用 FNM 安装 Node.js 和 PNPM..."; fnm install v20 > /dev/null; fnm use v20
    curl -fsSL https://get.pnpm.io/install.sh | sh - > /dev/null
    export PNPM_HOME="/root/.local/share/pnpm"; export PATH="$PNPM_HOME:$PATH"
    log_info "正在下载并设置 Sub-Store 项目文件..."; mkdir -p "$SUBSTORE_INSTALL_DIR"; cd "$SUBSTORE_INSTALL_DIR"
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "Sub-Store 项目文件准备就绪。"
    log_info "开始配置系统服务..."; echo ""; while true; do read -p "请输入前端访问端口 [默认: 3000]: " FRONTEND_PORT; FRONTEND_PORT=${FRONTEND_PORT:-3000}; substore_check_port "$FRONTEND_PORT" && break; done
    echo ""; read -p "请输入后端 API 端口 [默认: 3001]: " BACKEND_PORT; BACKEND_PORT=${BACKEND_PORT:-3001}
    API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1); log_info "生成的 API 密钥为: ${API_KEY}"
    cat <<EOF > "$SUBSTORE_SERVICE_FILE"
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
ExecStart=/root/.local/share/fnm/fnm exec --using v20 node ${SUBSTORE_INSTALL_DIR}/sub-store.bundle.js
Type=simple
User=root
Group=root
Restart=on-failure
RestartSec=5s
LimitNOFILE=32767
ExecStartPre=/bin/sh -c "ulimit -n 51200"
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
    log_info "正在启动并启用 sub-store 服务..."; systemctl daemon-reload; systemctl enable "$SUBSTORE_SERVICE_NAME" > /dev/null; systemctl start "$SUBSTORE_SERVICE_NAME"; substore_setup_shortcut
    log_info "正在检测服务状态 (等待 5 秒)..."; sleep 5; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "服务状态正常 (active)。"; substore_view_access_link; else log_error "服务启动失败！"; fi
    echo ""; read -p "安装已完成，是否立即设置反向代理 (推荐)? (y/N): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then substore_setup_reverse_proxy; else press_any_key; fi
}

substore_do_uninstall() {
    log_warn "你确定要卸载 Sub-Store 吗？此操作不可逆！"; echo ""; read -p "请输入 Y 确认: " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "取消卸载。"; press_any_key; return; fi
    log_info "正在停止并禁用服务..."; systemctl stop "$SUBSTORE_SERVICE_NAME" || true; systemctl disable "$SUBSTORE_SERVICE_NAME" || true
    log_info "正在删除服务文件..."; rm -f "$SUBSTORE_SERVICE_FILE"; systemctl daemon-reload
    log_info "正在删除项目文件和 Node.js 环境..."; rm -rf "$SUBSTORE_INSTALL_DIR"; rm -rf "/root/.local"; rm -rf "/root/.pnpm-state.json"
    log_info "正在移除快捷命令..."; rm -f "$SUBSTORE_SHORTCUT_PATH"
    if [ -f "/etc/caddy/Caddyfile" ] && grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
        echo ""; read -p "检测到 Caddy 反代配置，是否移除? (y/N): " rm_caddy_choice
        if [[ "$rm_caddy_choice" == "y" || "$rm_caddy_choice" == "Y" ]]; then
            log_info "正在移除 Caddy 配置..."; sed -i '/# Sub-Store config start/,/# Sub-Store config end/d' /etc/caddy/Caddyfile; systemctl reload caddy
        fi
    fi
    log_info "✅ Sub-Store 已成功卸载。"; press_any_key
}

substore_save_reverse_proxy_domain() {
    local domain_to_save=$1
    log_info "正在保存域名配置: ${domain_to_save}"; sed -i '/SUB_STORE_REVERSE_PROXY_DOMAIN/d' "$SUBSTORE_SERVICE_FILE"
    sed -i "/\[Service\]/a Environment=\"SUB_STORE_REVERSE_PROXY_DOMAIN=${domain_to_save}\"" "$SUBSTORE_SERVICE_FILE"
    systemctl daemon-reload; log_info "域名配置已保存！"
}

substore_view_access_link() {
    log_info "正在读取配置并生成访问链接..."; if ! substore_is_installed; then log_error "Sub-Store尚未安装。"; return; fi
    REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    API_KEY=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"/')
    echo -e "\n===================================================================="
    if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
        ACCESS_URL="https://${REVERSE_PROXY_DOMAIN}/subs?api=https://${REVERSE_PROXY_DOMAIN}${API_KEY}"
        echo -e "\n您的 Sub-Store 反代访问链接如下：\n\n${YELLOW}${ACCESS_URL}${NC}\n"
    else
        FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
        SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com); if [ -n "$SERVER_IP_V4" ]; then
            ACCESS_URL_V4="http://${SERVER_IP_V4}:${FRONTEND_PORT}/subs?api=http://${SERVER_IP_V4}:${FRONTEND_PORT}${API_KEY}"
            echo -e "\n您的 Sub-Store IPv4 访问链接如下：\n\n${YELLOW}${ACCESS_URL_V4}${NC}\n"
        fi
        SERVER_IP_V6=$(curl -s --max-time 2 http://ipv6.icanhazip.com); if [[ "$SERVER_IP_V6" =~ .*:.* && -n "$SERVER_IP_V6" ]]; then
            ACCESS_URL_IPV6="http://[${SERVER_IP_V6}]:${FRONTEND_PORT}/subs?api=http://[${SERVER_IP_V6}]:${FRONTEND_PORT}${API_KEY}"
            echo -e "--------------------------------------------------------------------"
            echo -e "\n您的 Sub-Store IPv6 访问链接如下：\n\n${YELLOW}${ACCESS_URL_IPV6}${NC}\n"
        fi
    fi
    echo -e "===================================================================="
}

substore_reset_ports() {
    log_info "开始重置端口..."; if ! substore_is_installed; then log_error "Sub-Store尚未安装。"; return; fi
    CURRENT_FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    CURRENT_BACKEND_PORT=$(grep 'SUB_STORE_BACKEND_API_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    log_info "当前前端端口: ${CURRENT_FRONTEND_PORT}"; log_info "当前后端端口: ${CURRENT_BACKEND_PORT}"; echo ""
    while true; do read -p "请输入新的前端访问端口 [默认: ${CURRENT_FRONTEND_PORT}]: " NEW_FRONTEND_PORT; NEW_FRONTEND_PORT=${NEW_FRONTEND_PORT:-$CURRENT_FRONTEND_PORT}; if [ "$NEW_FRONTEND_PORT" == "$CURRENT_FRONTEND_PORT" ] || substore_check_port "$NEW_FRONTEND_PORT"; then break; fi; done
    echo ""; read -p "请输入新的后端 API 端口 [默认: ${CURRENT_BACKEND_PORT}]: " NEW_BACKEND_PORT; NEW_BACKEND_PORT=${NEW_BACKEND_PORT:-$CURRENT_BACKEND_PORT}
    log_info "正在更新服务文件..."; set -e
    sed -i "s|^Environment=\"SUB_STORE_FRONTEND_PORT=.*|Environment=\"SUB_STORE_FRONTEND_PORT=${NEW_FRONTEND_PORT}\"|" "$SUBSTORE_SERVICE_FILE"
    sed -i "s|^Environment=\"SUB_STORE_BACKEND_API_PORT=.*|Environment=\"SUB_STORE_BACKEND_API_PORT=${NEW_BACKEND_PORT}\"|" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载并重启服务..."; systemctl daemon-reload; systemctl restart "$SUBSTORE_SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then
        log_info "✅ 端口重置成功！"; REVERSE_PROXY_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
        if [ -n "$REVERSE_PROXY_DOMAIN" ]; then
            NGINX_CONF_PATH="/etc/nginx/sites-available/${REVERSE_PROXY_DOMAIN}.conf"
            if [ -f "$NGINX_CONF_PATH" ]; then
                log_info "检测到 Nginx 反代配置，正在自动更新端口..."; sed -i "s|proxy_pass http://localhost:.*|proxy_pass http://localhost:${NEW_FRONTEND_PORT};|g" "$NGINX_CONF_PATH"
                if nginx -t >/dev/null 2>&1; then systemctl reload nginx; log_info "Nginx 配置已更新并重载。"; else log_error "更新 Nginx 端口后配置测试失败！"; fi
            fi
            if [ -f "/etc/caddy/Caddyfile" ] && grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
                log_info "检测到 Caddy 反代配置，正在自动更新端口..."; sed -i "/# Sub-Store config start/,/# Sub-Store config end/ s|reverse_proxy localhost:.*|reverse_proxy localhost:${NEW_FRONTEND_PORT}|" /etc/caddy/Caddyfile
                systemctl reload caddy; log_info "Caddy 配置已更新并重载。";
            fi
        fi
        substore_view_access_link
    else log_error "服务重启失败！"; fi
}

substore_reset_api_key() {
    log_warn "确定要重置 API 密钥吗？旧的访问链接将立即失效。"; echo ""; read -p "请输入 Y 确认: " choice; if [[ "$choice" != "y" && "$choice" != "Y" ]]; then log_info "取消操作。"; return; fi
    log_info "正在生成新的 API 密钥..."; set -e; NEW_API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
    log_info "正在更新服务文件..."; sed -i "s|^Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=.*|Environment=\"SUB_STORE_FRONTEND_BACKEND_PATH=/${NEW_API_KEY}\"|" "$SUBSTORE_SERVICE_FILE"
    log_info "正在重载并重启服务..."; systemctl daemon-reload; systemctl restart "$SUBSTORE_SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "✅ API 密钥重置成功！"; substore_view_access_link; else log_error "服务重启失败！"; fi
}

substore_install_caddy() {
    log_info "正在安装 Caddy..."; if ! command -v caddy &> /dev/null; then
    set -e; apt-get install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
    apt-get update -y > /dev/null; apt-get install caddy -y; set +e
    log_info "Caddy 安装成功！"; else log_info "Caddy 已安装。"; fi
}

substore_handle_caddy_proxy() {
    if ! command -v dig &> /dev/null; then log_info "'dig' 命令未找到，安装 'dnsutils'..."; set -e; apt-get update >/dev/null; apt-get install -y dnsutils >/dev/null; set +e; fi
    echo ""; read -p "请输入您已解析到本服务器的域名: " DOMAIN; if [ -z "$DOMAIN" ]; then log_error "域名不能为空！"; return; fi
    log_info "正在验证域名解析..."; SERVER_IP_V4=$(curl -s http://ipv4.icanhazip.com); DOMAIN_IP_V4=$(dig +short "$DOMAIN" A)
    if [ "$SERVER_IP_V4" != "$DOMAIN_IP_V4" ]; then
        log_warn "域名 A 记录 (${DOMAIN_IP_V4}) 与本机 IPv4 (${SERVER_IP_V4}) 不符。"; echo ""; read -p "是否仍然继续? (y/N): " continue_choice; if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then log_info "操作中止。"; return; fi
    else log_info "域名 IPv4 解析验证成功！"; fi
    local FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    log_info "正在生成 Caddy 配置文件..."; CADDY_CONFIG="\n# Sub-Store config start\n$DOMAIN {\n    reverse_proxy localhost:$FRONTEND_PORT\n}\n# Sub-Store config end\n"
    if grep -q "# Sub-Store config start" /etc/caddy/Caddyfile; then
        log_warn "检测到已存在的配置，将进行覆盖。"; awk -v new_config="$CADDY_CONFIG" 'BEGIN {p=1} /# Sub-Store config start/ {p=0} p==1 {print} /# Sub-Store config end/ {p=1; printf "%s", new_config}' /etc/caddy/Caddyfile > /tmp/Caddyfile.tmp && mv /tmp/Caddyfile.tmp /etc/caddy/Caddyfile
    else echo -e "$CADDY_CONFIG" >> /etc/caddy/Caddyfile; fi
    log_info "正在重载 Caddy 服务..."; systemctl reload caddy
    if systemctl is-active --quiet caddy; then log_info "✅ 反向代理设置成功！"; substore_save_reverse_proxy_domain "$DOMAIN"; substore_view_access_link; else log_error "Caddy 服务重载失败！"; fi
}

substore_handle_nginx_proxy() {
    echo ""; read -p "请输入您要使用的域名: " DOMAIN; if [ -z "$DOMAIN" ]; then log_error "域名不能为空！"; return; fi
    local FRONTEND_PORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$SUBSTORE_SERVICE_FILE" | awk -F'=' '{print $2}' | tr -d '"')
    local NGINX_CONFIG_BLOCK="server {\n    listen 80;\n    listen [::]:80;\n    server_name ${DOMAIN};\n\n    location / {\n        proxy_pass http://localhost:${FRONTEND_PORT};\n        proxy_http_version 1.1;\n        proxy_set_header Upgrade \$http_upgrade;\n        proxy_set_header Connection \"upgrade\";\n        proxy_set_header Host \$host;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto \$scheme;\n    }\n}";
    clear; echo -e "${YELLOW}--- Nginx 配置指南 ---${NC}"; echo "请手动完成以下步骤，或选择让脚本自动执行。"; echo "1. 创建或编辑 Nginx 配置文件:"; echo -e "   ${GREEN}sudo vim /etc/nginx/sites-available/${DOMAIN}.conf${NC}"
    echo "2. 将以下代码块完整复制并粘贴到文件中："; echo -e "${WHITE}--------------------------------------------------${NC}"
    echo -e "${NGINX_CONFIG_BLOCK}"; echo -e "${WHITE}--------------------------------------------------${NC}"
    echo "3. 启用该站点:"; echo -e "   ${GREEN}sudo ln -s /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/${NC}"; echo "4. 测试 Nginx 配置是否有语法错误:"; echo -e "   ${GREEN}sudo nginx -t${NC}"; echo "5. 重载 Nginx 服务以应用配置:"; echo -e "   ${GREEN}sudo systemctl reload nginx${NC}"; echo "6. (推荐) 申请 HTTPS 证书 (需提前安装 certbot):"; echo -e "   ${GREEN}sudo certbot --nginx -d ${DOMAIN}${NC}"
    echo ""; read -p "是否要让脚本尝试自动执行以上所有步骤? (Y/n): " auto_choice
    if [[ "$auto_choice" != "n" && "$auto_choice" != "N" ]]; then
        log_info "开始为 Nginx 自动配置..."; log_info "正在检查并安装 Certbot 及其 Nginx 插件..."
        set -e; apt-get update -y >/dev/null; apt-get install -y certbot python3-certbot-nginx >/dev/null; set +e
        log_info "Certbot 依赖检查/安装完毕。"
        local OLD_DOMAIN=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"')
        if [ -n "$OLD_DOMAIN" ]; then
            local OLD_NGINX_CONF="/etc/nginx/sites-available/${OLD_DOMAIN}.conf"; local OLD_NGINX_LINK="/etc/nginx/sites-enabled/${OLD_DOMAIN}.conf"
            log_warn "正在清理旧域名 ${OLD_DOMAIN} 的配置..."; [ -f "$OLD_NGINX_LINK" ] && rm -f "$OLD_NGINX_LINK"; [ -f "$OLD_NGINX_CONF" ] && rm -f "$OLD_NGINX_CONF"
        fi
        NGINX_CONF_PATH="/etc/nginx/sites-available/${DOMAIN}.conf"; log_info "正在写入 Nginx 配置文件: ${NGINX_CONF_PATH}"; echo -e "${NGINX_CONFIG_BLOCK}" > "$NGINX_CONF_PATH"
        if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]; then log_info "正在启用站点..."; ln -s "$NGINX_CONF_PATH" "/etc/nginx/sites-enabled/"; else log_warn "站点似乎已被启用，跳过创建软链接。"; fi
        log_info "正在测试 Nginx 配置..."; if ! nginx -t; then log_error "Nginx 配置测试失败！请检查您的 Nginx 配置。"; return; fi
        log_info "正在重载 Nginx..."; systemctl reload nginx; RANDOM_EMAIL=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)@gmail.com
        log_warn "将使用随机生成的邮箱 ${RANDOM_EMAIL} 为 Certbot 注册。"; log_warn "为保证续期通知，建议之后手动执行 'sudo certbot register --update-registration --email 您的真实邮箱' 来更新邮箱。"
        log_info "正在为 ${DOMAIN} 申请 HTTPS 证书..."; certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --email "${RANDOM_EMAIL}" --no-eff-email --redirect
        if [ $? -eq 0 ]; then log_info "✅ Nginx 反向代理和 HTTPS 证书已自动配置成功！"; substore_save_reverse_proxy_domain "$DOMAIN"; substore_view_access_link; else log_error "Certbot 证书申请失败！请检查域名解析和防火墙设置。"; fi
    fi
}

substore_update_app() {
    log_info "开始更新 Sub-Store 应用..."; if ! substore_is_installed; then log_error "Sub-Store 尚未安装，无法更新。"; press_any_key; return; fi
    set -e; cd "$SUBSTORE_INSTALL_DIR"
    log_info "正在下载最新的后端文件 (sub-store.bundle.js)..."; curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    log_info "正在下载最新的前端文件 (dist.zip)..."; curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    log_info "正在部署新版前端..."; rm -rf frontend; unzip -q -o dist.zip && mv dist frontend && rm dist.zip
    log_info "正在重启 Sub-Store 服务以应用更新..."; systemctl restart "$SUBSTORE_SERVICE_NAME"; sleep 2; set +e
    if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then log_info "✅ Sub-Store 更新成功并已重启！"; else log_error "Sub-Store 更新后重启失败！请使用 '查看日志' 功能进行排查。"; fi
    press_any_key
}

substore_setup_reverse_proxy() {
    clear
    local old_domain=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"')
    if [ -n "$old_domain" ]; then
        log_info "检测到您已设置了反向代理域名: ${old_domain}"; echo ""
        log_warn "接下来的操作将使用新域名替换旧的配置。"
    fi
    if command -v caddy &> /dev/null; then log_info "检测到 Caddy，将为您进行全自动配置。"; substore_handle_caddy_proxy
    elif command -v nginx &> /dev/null; then log_info "检测到 Nginx，将为您生成配置代码和操作指南。"; substore_handle_nginx_proxy
    elif command -v apache2 &> /dev/null || command -v httpd &> /dev/null; then log_warn "检测到 Apache，但本脚本暂未支持自动生成其配置。";
    else
        log_warn "未检测到任何 Web 服务器 (Caddy, Nginx, Apache)。"; echo ""; read -p "是否要自动安装 Caddy 以进行全自动配置? (y/N): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then substore_install_caddy; substore_handle_caddy_proxy; else log_info "操作中止。"; fi
    fi
    press_any_key
}

substore_manage_menu() {
    while true; do
        clear
        local rp_domain_check=$(grep 'SUB_STORE_REVERSE_PROXY_DOMAIN=' "$SUBSTORE_SERVICE_FILE" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"')
        if [ -n "$rp_domain_check" ]; then local rp_menu_text="更换反代域名"; else local rp_menu_text="设置反向代理 (推荐)"; fi

        echo -e "${WHITE}--- Sub-Store 管理菜单 ---${NC}\n"
        if systemctl is-active --quiet "$SUBSTORE_SERVICE_NAME"; then STATUS_COLOR="${GREEN}● 活动${NC}"; else STATUS_COLOR="${RED}● 不活动${NC}"; fi
        echo -e "当前状态: ${STATUS_COLOR}\n"

        echo "1. 启动服务"
        echo ""
        echo "2. 停止服务"
        echo ""
        echo "3. 重启服务"
        echo ""
        echo "4. 查看状态"
        echo ""
        echo "5. 查看日志"
        echo ""
        echo -e "---------------------------------\n"
        echo "6. 查看访问链接"
        echo ""
        echo "7. 重置端口"
        echo ""
        echo "8. 重置 API 密钥"
        echo ""
        echo "9. ${YELLOW}${rp_menu_text}${NC}"
        echo ""
        echo "0. 返回 Sub-Store 主菜单"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
            1) systemctl start "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            2) systemctl stop "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            3) systemctl restart "$SUBSTORE_SERVICE_NAME"; log_info "命令已发送"; sleep 1 ;;
            4) clear; systemctl status "$SUBSTORE_SERVICE_NAME"; press_any_key;;
            5) clear; journalctl -u "$SUBSTORE_SERVICE_NAME" -f --no-pager;;
            6) substore_view_access_link; press_any_key;;
            7) substore_reset_ports; press_any_key;;
            8) substore_reset_api_key; press_any_key;;
            9) substore_setup_reverse_proxy;;
            0) break ;;
            *) log_warn "无效选项！"; sleep 1 ;;
        esac
    done
}

substore_main_menu() {
    while true; do
        clear
        echo -e "${WHITE}=====================================${NC}"
        echo -e "${WHITE}          Sub-Store 管理菜单         ${NC}"
        echo -e "${WHITE}=====================================${NC}\n"
        if substore_is_installed; then
            echo "1. 管理 Sub-Store"
            echo ""
            echo -e "2. ${GREEN}更新 Sub-Store 应用${NC}"
            echo ""
            echo "--------------------------"
            echo -e "8. ${RED}卸载 Sub-Store${NC}"
            echo ""
            echo -e "0. ${RED}返回主菜单${NC}"
            echo ""
            read -p "请输入选项: " choice
            case $choice in 1) substore_manage_menu ;; 2) substore_update_app ;; 8) substore_do_uninstall ;; 0) return ;; *) log_warn "无效选项！"; sleep 1 ;; esac
        else
            echo "1. 安装 Sub-Store"
            echo ""
            echo "--------------------------"
            echo -e "0. ${RED}返回主菜单${NC}"
            echo ""
            read -p "请输入选项: " choice
            case $choice in 1) substore_do_install ;; 0) return ;; *) log_warn "无效选项！"; sleep 1 ;; esac
        fi
    done
}


# ==============================================================================
# 系统工具 & 优化
# ==============================================================================

sys_show_info() {
    clear
    echo -e "${WHITE}--- 系统信息查询 ---${NC}\n"
    local hostname_info=$(hostname)
    local os_info=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^ *//')
    local kernel_info=$(uname -r)
    local cpu_arch=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | sed 's/^ *//')
    local cpu_model=$(lscpu | grep "Model name" | awk -F: '{print $2}' | sed 's/^ *//')
    local cpu_cores=$(lscpu | grep "CPU(s):" | awk '{print $2}')
    local memory_info=$(free -h | grep Mem | awk '{print $3 "/" $2}')
    local disk_info=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    local uptime_info=$(uptime -p)
    local ip_addr=$(hostname -I | awk '{print $1}')
    local ip_info=$(curl -s http://ip-api.com/json/"$ip_addr" | jq -r '.org' 2>/dev/null)
    local geo_info=$(curl -s http://ip-api.com/json/"$ip_addr" | jq -r '.city, .country' 2>/dev/null | tr '\n' ' ')

    echo "主机名       : ${YELLOW}${hostname_info}${NC}"
    echo "运营商       : ${YELLOW}${ip_info}${NC}"
    echo "IP 地址      : ${YELLOW}${ip_addr}${NC}"
    echo "地理位置     : ${YELLOW}${geo_info}${NC}"
    echo "系统版本     : ${YELLOW}${os_info}${NC}"
    echo "Linux 内核   : ${YELLOW}${kernel_info}${NC}"
    echo "CPU 架构     : ${YELLOW}${cpu_arch}${NC}"
    echo "CPU 型号     : ${YELLOW}${cpu_model}${NC}"
    echo "CPU 核心数   : ${YELLOW}${cpu_cores}${NC}"
    echo "内存使用     : ${YELLOW}${memory_info}${NC}"
    echo "硬盘占用     : ${YELLOW}${disk_info}${NC}"
    echo "运行时长     : ${YELLOW}${uptime_info}${NC}"
    echo ""
    echo "-----------------------------------"
    press_any_key
}

sys_clean() {
    log_info "开始清理系统缓存..."
    apt-get autoremove -y > /dev/null
    apt-get clean -y > /dev/null
    log_info "✅ 系统清理完成。"
    press_any_key
}

sys_change_hostname() {
    local current_hostname=$(hostname)
    log_info "当前主机名为: ${current_hostname}"
    read -p "请输入新的主机名: " new_hostname
    if [[ -z "$new_hostname" ]]; then
        log_warn "主机名不能为空，操作取消。"
        press_any_key
        return
    fi
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
    log_info "✅ 主机名已成功修改为: $new_hostname"
    log_warn "为使修改完全生效，建议重启系统。"
    press_any_key
}

sys_optimize_dns() {
    log_info "开始优化 DNS 设置..."
    cat > /etc/resolv.conf <<EOL
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOL
    log_info "✅ DNS 已优化为 Cloudflare 和 Google Public DNS (IPv6 优先)。"
    press_any_key
}

sys_set_timezone() {
    log_info "当前系统时区: $(timedatectl show --property=Timezone --value)"
    log_info "正在配置时区为 Asia/Shanghai (UTC+8)..."
    timedatectl set-timezone Asia/Shanghai
    log_info "✅ 时区设置完成。当前时间: $(date -R)"
    press_any_key
}

# 3x-ui / s-ui 安装
install_xui() {
    local panel_name=$1
    local install_url=$2
    log_warn "即将从第三方源安装 ${panel_name}，请注意其安全性。"
    read -p "是否继续? (y/N): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        log_info "正在执行 ${panel_name} 安装脚本..."
        bash <(curl -Ls "${install_url}")
        log_info "${panel_name} 安装脚本执行完毕。"
    else
        log_info "安装已取消。"
    fi
    press_any_key
}


sys_tools_main_menu() {
    while true; do
        clear
        echo -e "${WHITE}=====================================${NC}"
        echo -e "${WHITE}        系统工具 & 优化菜单        ${NC}"
        echo -e "${WHITE}=====================================${NC}\n"
        echo "1. 系统信息查询"
        echo ""
        echo "2. 系统垃圾清理"
        echo ""
        echo "3. 修改主机名"
        echo ""
        echo "4. 优化 DNS"
        echo ""
        echo "5. 设置时区 (上海 UTC+8)"
        echo ""
        echo "--------------------------"
        echo ""
        echo "6. 安装 3x-ui (第三方脚本)"
        echo ""
        echo "7. 安装 s-ui (第三方脚本)"
        echo ""
        echo "--------------------------"
        echo "0. 返回主菜单"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
            1) sys_show_info ;;
            2) sys_clean ;;
            3) sys_change_hostname ;;
            4) sys_optimize_dns ;;
            5) sys_set_timezone ;;
            6) install_xui "3x-ui" "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" ;;
            7) install_xui "s-ui" "https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh" ;;
            0) return ;;
            *) log_warn "无效选项!"; sleep 1 ;;
        esac
    done
}


# ==============================================================================
# 主菜单 & 脚本更新
# ==============================================================================
do_update_script() {
    log_info "正在从 GitHub 下载最新版本的脚本..."
    local temp_script="/tmp/vps_toolkit_new.sh"
    if ! curl -sL "$SCRIPT_URL" -o "$temp_script"; then
        log_error "下载脚本失败！请检查您的网络连接或 URL 是否正确。";
        press_any_key
        return
    fi

    if cmp -s "$SUBSTORE_SCRIPT_PATH" "$temp_script"; then
        log_info "脚本已经是最新版本，无需更新。";
        rm "$temp_script"
        press_any_key
        return
    fi

    log_info "下载成功，正在应用更新...";
    chmod +x "$temp_script"
    mv "$temp_script" "$SUBSTORE_SCRIPT_PATH"
    log_info "✅ 脚本已成功更新！";
    log_warn "请重新运行脚本以使新版本生效 (例如，再次输入 'sb' 或 './<script_name>.sh')...";
    exit 0
}


main_menu() {
    while true; do
        clear
        echo -e "${WHITE}=====================================${NC}"
        echo -e "${WHITE}       全功能 VPS 管理工具           ${NC}"
        echo -e "${WHITE}=====================================${NC}\n"
        echo "1. Sing-Box 管理"
        echo ""
        echo "2. Sub-Store 管理"
        echo ""
        echo "3. 系统工具 & 优化"
        echo ""
        echo "-------------------------------------"
        echo ""
        echo -e "8. ${GREEN}更新脚本${NC}"
        echo ""
        echo -e "0. ${RED}退出脚本${NC}"
        echo ""
        read -p "请输入选项: " choice
        case $choice in
            1) singbox_main_menu ;;
            2) substore_main_menu ;;
            3) sys_tools_main_menu ;;
            8) do_update_script ;;
            0) exit 0 ;;
            *) log_warn "无效选项！"; sleep 1 ;;
        esac
    done
}

# --- 脚本入口 ---
check_root
main_menu