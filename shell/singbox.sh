#!/bin/bash
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
    read -p "请选择操作 (1-3, 88, 00): " choice
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
            echo_color red "curl 安装失败，请检查网络或包管理器设置。"
            exit 1
        fi
    fi

    # # 安装 Sing-Box
    if ! bash <(curl -fsSL https://sing-box.app/deb-install.sh); then
        echo_color red "Sing-Box 安装失败，请查看安装日志获取更多信息。"
        exit 1
    fi

    # 检查安装是否成功
    if ! command -v sing-box &> /dev/null; then
        echo_color red "Sing-Box 安装失败，无法找到 sing-box 命令。"
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
        touch "$config_file" || { echo_red "创建文件失败！"; exit 1; }
    fi

    # 写入配置内容到 config.json
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

    # 安装完成后返回主菜单
    echo_color green "Sing-Box配置文件初始化完成！"
    systemctl enable sing-box.service
    echo
    # 添加以下代码：设置快捷启动方式 sb
    echo_color green "正在设置快捷启动方式..."
    script_path=$(realpath "$0")  # 获取当前脚本的绝对路径
    chmod +x "$script_path"       # 确保脚本有执行权限
    ln -sf "$script_path" /usr/local/bin/sb  # 创建符号链接
    echo_color green "快捷命令 'sb' 已设置！输入 sb 即可启动脚本。"
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

    # 检查 Certbot 是否安装，如果未安装，则先安装
    if ! command -v certbot &> /dev/null; then
        echo_color yellow "Certbot 未安装，正在安装 Certbot..."
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
                sudo apt update
                sudo apt install -y certbot
            elif [[ "$ID" == "centos" || "$ID" == "rhel" ]]; then
                sudo yum install -y certbot
            else
                echo_color red "不支持的操作系统，请手动安装 Certbot。"
                return 1
            fi
        else
            echo_color red "无法识别操作系统，请手动安装 Certbot。"
            return 1
        fi
    fi

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
        (crontab -l 2>/dev/null; echo "0 */12 * * * certbot renew --quiet --deploy-hook 'systemctl restart sing-box'") | crontab -
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
        if ! echo "$domain_name" | grep -Pq "^[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9-]{1,63})*\.[A-Za-z]{2,}$"; then
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

    # --- 新增：自动获取位置 ---
    echo_color green "正在自动获取当前服务器位置..."
    location=$(curl -s ip-api.com/json | jq -r '.city' | sed 's/ //g') # 使用jq解析并用sed移除空格
    if [ -z "$location" ] || [ "$location" == "null" ]; then
        echo_color yellow "自动获取位置失败，请手动输入。"
        read -p "请输入当前服务器位置 (例如: HongKong): " location
    else
        echo_color green "成功获取到位置: $location"
    fi
    # --- 修改结束 ---

    # 询问自定义节点名称
    read -p "请输入自定义节点名称（例如：GCP）： " custom_tag

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

    # --- 修改：根据新规则组合 TAG ---
    local protocol_name=""
    case $1 in
        1) protocol_name="Vless" ;;
        2) protocol_name="Hysteria2" ;;
        3) protocol_name="Vmess" ;;
        4) protocol_name="Trojan" ;;
        *) protocol_name="Vless" ;; # 默认
    esac

    tag="${location}-${custom_tag}-${protocol_name}"
    # --- 修改结束 ---
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
          \"name\": \"$custom_tag\",
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
          \"name\": \"$custom_tag\",
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

                if [[ "$line" =~ ^vmess:// ]]; then
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

    # 读取已保存的 Sub-Store 配置信息（如果存在）
    if [[ -f "/etc/sing-box/sub-store-config.txt" ]]; then
        source /etc/sing-box/sub-store-config.txt
    else
        # 默认地址和API密钥，只有需要输入Sub-Store Subs
        sub_store_url="https://oregen.wiitwo.eu.org/data"
        sub_store_api_key="csosiis5"
        echo "第一次推送到 Sub-Store，请输入 Sub-Store Subs 信息："
        read -p "Sub-Store Subs: " sub_store_subs
    fi

    # 遍历选中的节点
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

    # 推送到 Sub-Store
    response=$(curl -s -X POST "$sub_store_url" \
        -H "Content-Type: application/json" \
        -d "$node_json")

    # 检查推送结果
    if [[ "$response" == "节点更新成功!" ]]; then
        # 推送成功后才保存配置
        echo "sub_store_url=$sub_store_url" > /etc/sing-box/sub-store-config.txt
        echo "sub_store_api_key=$sub_store_api_key" >> /etc/sing-box/sub-store-config.txt
        echo "sub_store_subs=$sub_store_subs" >> /etc/sing-box/sub-store-config.txt
        echo -e "\e[32m\n节点信息推送成功！\e[0m\n"
    else
        echo -e "\e[31m推送失败，服务器响应: $response\e[0m"
        read -p "推送失败，是否重新配置 Sub-Store 信息? (y/n): " retry_choice
        case $retry_choice in
            y|Y)
                # 重新配置 Sub-Store Subs 信息
                echo "请输入新的 Sub-Store Subs 信息："
                read -p "Sub-Store Subs: " sub_store_subs
                push_to_sub_store  # 重新调用推送方法
                ;;
            n|N)
                # 返回主菜单
                show_menu
                ;;
            *)
                echo "无效选择，返回主菜单..."
                show_menu
                ;;
        esac
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
    echo -e "\n\e[32m1.查看节点     2.新增节点     3. 推送节点     4. 删除节点     00. 返回主菜单   88. 退出脚本\e[0m\n"
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
    if [[ ! -f "$node_file" || ! -s "$node_file" ]]; then
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
    aggregated_link=$(echo -n "$all_links" | base64 -w0)
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
        read -n 1 -s -r -p "按任意键返回..."
        show_action_menu
        return 1
    }

    # 统一的成功提示函数
    function success_msg {
        echo -e "\e[32m$1\e[0m"
    }

    # 检查节点文件和配置文件是否存在
    if [[ ! -f "$node_file" || ! -s "$node_file" ]]; then
        error_exit "当前没有任何节点可以删除！"
    fi

    if [[ ! -f "$config_file" ]]; then
        error_exit "配置文件不存在！"
    fi

    # 读取文件中的节点链接
    mapfile -t node_lines < "$node_file"

    # 提取节点名称和唯一标识符（tag）
    node_names=()
    node_tags=()
    for line in "${node_lines[@]}"; do
        if [[ "$line" =~ ^vmess:// ]]; then
            decoded_vmess=$(echo "$line" | sed 's/^vmess:\/\///' | base64 --decode 2>/dev/null)
            if [[ $? -ne 0 ]]; then
                error_exit "Vmess 链接解码失败！"
            fi
            node_name=$(echo "$decoded_vmess" | jq -r '.ps // "默认名称"')
            tag=$(echo "$line" | sed 's/.*#\(.*\)/\1/') # Vmess 的 tag 也在 # 后面
        else
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

    nodes_to_delete_indices=()

    case $choice in
        1)
            # 删除单个或多个节点
            echo -e "\n请选择要删除的节点（用空格分隔多个节点）：\n"
            for i in "${!node_names[@]}"; do
                echo -e "\e[32m$((i + 1)). ${node_names[$i]}\e[0m"
            done
            echo
            read -p "请输入节点编号：" -a nodes_to_delete

            for node_num in "${nodes_to_delete[@]}"; do
                 # 检查输入是否为数字
                if ! [[ "$node_num" =~ ^[0-9]+$ ]]; then
                    error_exit "无效的输入：'$node_num' 不是一个有效的编号。"
                fi
                node_index=$((node_num - 1))
                if [[ $node_index -ge 0 && $node_index -lt ${#node_names[@]} ]]; then
                    nodes_to_delete_indices+=($node_index)
                else
                    error_exit "无效的节点编号：$node_num"
                fi
            done
            ;;
        2)
            # 删除所有节点
            read -p "你确定要删除所有节点配置吗？这将清空所有节点信息！(y/n): " confirm_delete
            if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
                echo "正在删除所有节点..."
                # 清空 config.json 中的 inbounds
                jq '.inbounds = []' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
                # 删除节点链接记录文件
                rm -f "$node_file"
                success_msg "已成功删除所有节点！"
                systemctl restart sing-box
            else
                echo "操作已取消。"
            fi
            show_action_menu
            return
            ;;
        00)
            show_menu
            return
            ;;
        88)
            exit
            ;;
        *)
            error_exit "无效的选项！"
            ;;
    esac

    # 从 config.json 和 nodes_links.txt 删除选中的节点
    if [[ ${#nodes_to_delete_indices[@]} -gt 0 ]]; then
        # 降序排列索引，以防删除时索引错乱
        sorted_indices=($(for i in "${nodes_to_delete_indices[@]}"; do echo $i; done | sort -rn))

        new_node_lines=()
        for i in "${!node_lines[@]}"; do
            should_keep=true
            for del_idx in "${sorted_indices[@]}"; do
                if [[ $i -eq $del_idx ]]; then
                    should_keep=false
                    tag_to_delete="${node_tags[$del_idx]}"
                    success_msg "正在删除节点: ${node_names[$del_idx]}"
                    # 从 config.json 删除
                    jq --arg tag "$tag_to_delete" 'del(.inbounds[] | select(.tag == $tag))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
                    break
                fi
            done
            if $should_keep; then
                new_node_lines+=("${node_lines[$i]}")
            fi
        done

        # 将保留的节点写回文件
        printf "%s\n" "${new_node_lines[@]}" > "$node_file"

        # 检查是否还有节点，如果没有则删除文件
        if [[ ! -s $node_file ]]; then
            rm -f "$node_file"
        fi

        success_msg "所选节点已全部删除！"
        systemctl restart sing-box
    fi

    show_action_menu
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
    read -p "你确定要完全卸载 Sing-Box 吗？所有配置文件都将被删除！(y/n): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        echo "卸载操作已取消。"
        show_menu
        return
    fi
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

    # 删除快捷方式
    echo "删除快捷命令 'sb'..."
    rm -f /usr/local/bin/sb

    # 重新加载 systemd 配置
    echo "重新加载 systemd 配置..."
    systemctl daemon-reload

    # 清理残留的链接
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/systemd/system/sing-box*

    # 检查是否卸载成功
    check_sing_box

    echo_color green "Sing-Box 卸载完成！"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    show_menu
}


# 调用主菜单函数
show_menu