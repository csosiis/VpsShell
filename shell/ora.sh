#!/bin/bash
# 脚本名称: s-b.sh
# 描述: Sing-Box 管理脚本（优化版）
# 版本: 1.2.0
# 作者: Jcole

# -------------------------- 全局配置 --------------------------
CONFIG_FILE="/etc/sing-box/config.json"
NODE_FILE="/etc/sing-box/nodes_links.txt"
LOG_FILE="/var/log/sing-box/sing-box.log"
TELEGRAM_CONFIG="/etc/sing-box/telegram-bot-config.txt"
SUBSTORE_CONFIG="/etc/sing-box/sub-store-config.txt"

# -------------------------- 颜色定义 --------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# -------------------------- 通用函数 --------------------------
# 日志记录
log() {
  local level=$1
  local message=$2
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "$LOG_FILE"
}

# 带颜色的输出
echo_color() {
  local color=$1
  local message=$2
  case $color in
    red)    echo -e "${RED}${message}${NC}" ;;
    green)  echo -e "${GREEN}${message}${NC}" ;;
    yellow) echo -e "${YELLOW}${message}${NC}" ;;
    white)  echo -e "${WHITE}${message}${NC}" ;;
    *)      echo -e "${message}" ;;
  esac
}

# 错误处理
error_exit() {
  local message=$1
  log "ERROR" "$message"
  echo_color red "$message"
  read -n 1 -s -r -p "按任意键继续..."
  return 1
}

# 输入验证
validate_input() {
  local input=$1
  local pattern=$2
  [[ "$input" =~ $pattern ]] || return 1
}

# 检查命令是否存在
check_command() {
  local cmd=$1
  if ! command -v "$cmd" &> /dev/null; then
    error_exit "$cmd 未安装，请先安装！"
    return 1
  fi
}

# -------------------------- 依赖管理 --------------------------
install_dependencies() {
  local deps=("curl" "jq" "uuidgen" "certbot")
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      log "INFO" "正在安装依赖: $dep"
      apt-get update && apt-get install -y "$dep" || error_exit "$dep 安装失败"
    fi
  done
}

# -------------------------- 节点管理 --------------------------
# 生成随机端口
generate_random_port() {
  echo $((RANDOM % 64512 + 1024))
}

# 生成随机密码
generate_random_password() {
  tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20
}

# 申请 SSL 证书
apply_ssl_certificate() {
  local domain=$1
  log "INFO" "申请证书: $domain"
  certbot certonly --standalone --preferred-challenges http -d "$domain" || return 1
}

# 新增协议节点
add_protocol_node() {
  local protocol=$1
  local config=$2
  log "INFO" "新增 $protocol 节点"
  jq --argjson new_config "$config" '.inbounds += [$new_config]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" || error_exit "配置写入失败"
  systemctl restart sing-box || error_exit "服务重启失败"
}

# -------------------------- 主菜单 --------------------------
show_menu() {
  clear
  echo "==============================="
  echo -e "          ${WHITE}Sing-Box 管理${NC}"
  echo "==============================="
  echo -e "1. 安装 Sing-Box"
  echo -e "2. 新增节点"
  echo -e "3. 管理节点"
  echo -e "4. 推送节点"
  echo -e "5. 卸载 Sing-Box"
  echo -e "0. 退出"
  echo "==============================="
  read -p "请输入选项: " choice
  case $choice in
    1) install_sing_box ;;
    2) add_node_menu ;;
    3) manage_nodes ;;
    4) push_nodes ;;
    5) uninstall_sing_box ;;
    0) exit 0 ;;
    *) echo_color red "无效选项！"; sleep 1; show_menu ;;
  esac
}

# -------------------------- 安装与卸载 --------------------------
install_sing_box() {
  log "INFO" "开始安装 Sing-Box"
  if command -v sing-box &>/dev/null; then
    echo_color yellow "Sing-Box 已安装，跳过安装步骤。"
    return
  fi

  # 安装依赖
  install_dependencies

  # 下载安装脚本
  curl -fsSL https://sing-box.app/deb-install.sh | bash || error_exit "安装脚本执行失败"

  # 初始化配置
  mkdir -p /etc/sing-box
  [[ ! -f "$CONFIG_FILE" ]] && echo '{"log":{"level":"info"},"inbounds":[],"outbounds":[]}' > "$CONFIG_FILE"
  echo_color green "Sing-Box 安装完成！"
}

uninstall_sing_box() {
  log "INFO" "开始卸载 Sing-Box"
  systemctl stop sing-box
  systemctl disable sing-box
  rm -rf /etc/sing-box /usr/local/bin/sing-box
  echo_color green "Sing-Box 已卸载！"
}

# -------------------------- 节点操作 --------------------------
add_node_menu() {
  clear
  echo "请选择协议类型:"
  echo "1. Vless  2. Hysteria2  3. Vmess  4. Trojan"
  read -p "请输入选项: " proto_choice
  case $proto_choice in
    1) add_vless ;;
    2) add_hysteria2 ;;
    3) add_vmess ;;
    4) add_trojan ;;
    *) error_exit "无效协议类型"; add_node_menu ;;
  esac
}

add_vless() {
  local domain port uuid
  read -p "输入域名: " domain
  validate_input "$domain" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" || error_exit "域名格式错误"
  port=$(generate_random_port)
  uuid=$(uuidgen)

  local config="{
    \"type\": \"vless\",
    \"tag\": \"${domain}-VLESS\",
    \"listen\": \"::\",
    \"listen_port\": $port,
    \"users\": [{\"uuid\": \"$uuid\"}],
    \"tls\": {\"enabled\": true, \"certificate_path\": \"/etc/letsencrypt/live/$domain/fullchain.pem\", \"key_path\": \"/etc/letsencrypt/live/$domain/privkey.pem\"}
  }"

  add_protocol_node "VLESS" "$config"
  echo "vless://$uuid@$domain:$port?security=tls&sni=$domain#${domain}-VLESS" >> "$NODE_FILE"
}

# -------------------------- 删除节点 --------------------------
delete_nodes() {
  [[ ! -f "$NODE_FILE" ]] && error_exit "暂无节点配置"
  echo "当前节点列表:"
  nl "$NODE_FILE"
  read -p "输入要删除的节点编号 (0 取消): " idx
  [[ $idx -eq 0 ]] && return

  # 删除节点配置
  local node_link=$(sed -n "${idx}p" "$NODE_FILE")
  local tag=$(echo "$node_link" | grep -oP '#\K[^ ]+')
  jq --arg tag "$tag" 'del(.inbounds[] | select(.tag == $tag))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" || error_exit "配置删除失败"

  # 删除节点链接
  sed -i "${idx}d" "$NODE_FILE"
  echo_color green "节点已删除"
  systemctl restart sing-box || error_exit "服务重启失败"
}

# -------------------------- 其他功能 --------------------------
manage_nodes() {
  [[ ! -f "$NODE_FILE" ]] && error_exit "暂无节点配置"
  echo "当前节点列表:"
  nl "$NODE_FILE"
  read -p "输入要删除的节点编号 (0 取消): " idx
  [[ $idx -eq 0 ]] && return
  sed -i "${idx}d" "$NODE_FILE" && echo_color green "节点已删除"
}

push_nodes() {
  [[ ! -f "$NODE_FILE" ]] && error_exit "暂无节点可推送"
  echo "选择推送方式:"
  echo "1. Telegram  2. Sub-Store"
  read -p "请输入选项: " push_choice
  case $push_choice in
    1) push_telegram ;;
    2) push_substore ;;
    *) error_exit "无效选项" ;;
  esac
}

# -------------------------- 主程序 --------------------------
# 初始化日志目录
mkdir -p /var/log/sing-box
touch "$LOG_FILE"

# 显示主菜单
show_menu