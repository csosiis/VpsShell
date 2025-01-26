import json
import base64
# 全局变量定义配置文件路径
config_file="/etc/sing-box/config.json"
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
# 检查 Sing-Box 是否已安装
function check_and_install_sing_box() {
    if ! command -v sing-box &> /dev/null; then
        echo "Sing-Box 尚未安装。"
        read -p "您是否希望先安装 Sing-Box？(y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            install_sing_box
        else
            echo "按任意键返回主菜单..."
            read -n 1 -s -r
            show_menu
        fi
    fi
}
# 安装 Sing-Box
function install_sing_box() {
    # 检查 Sing-Box 是否已安装
    if command -v sing-box &> /dev/null; then
        echo "Sing-Box 已经安装，跳过安装过程。"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        show_menu  # 返回主菜单
    fi

    echo "Sing-Box 未安装，正在安装..."

    # 安装 Sing-Box
    if ! bash <(curl -fsSL https://sing-box.app/deb-install.sh) > install_log.txt 2>&1; then
        echo "Sing-Box 安装失败，请检查 install_log.txt 文件。"
        exit 1
    fi

    # 检查安装是否成功
    if ! command -v sing-box &> /dev/null; then
        echo "Sing-Box 安装失败，无法找到 sing-box 命令。"
        exit 1
    fi

    echo "Sing-Box 安装成功！"

    # 配置文件目录和文件路径
    config_dir="/etc/sing-box"
    config_file="$config_dir/config.json"

    # 创建配置目录
    if [ ! -d "$config_dir" ]; then
        echo "Sing-Box 配置目录不存在，正在创建..."
        mkdir -p "$config_dir" || { echo "创建目录失败！"; exit 1; }
    fi

    # 创建 config.json 文件
    if [ ! -f "$config_file" ]; then
        echo "config.json 文件不存在，正在创建..."
        touch "$config_file" || { echo "创建文件失败！"; exit 1; }
    fi

    # 写入配置内容到 config.json
    echo "正在创建 Sing-Box 配置文件..."
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
        echo "写入配置文件失败！"
        exit 1
    fi

    echo "config.json 文件已创建并写入内容：$config_file"

    # 安装完成后返回主菜单
    echo "安装过程完成，返回主菜单"
    read -p "按 Enter 键返回主菜单..." && show_menu
}
# 申请域名证书并处理 80 端口被占用的情况
function apply_ssl_certificate() {
    local domain_name="$1"
    local stopped_services=()  # 用来记录停止的服务
    local email

    # 使用 DNS 查询验证域名是否能解析到本机
    if ! nslookup "$domain_name" > /dev/null 2>&1; then
        echo "无法解析该域名，请检查域名是否正确配置并解析到本机。"
        read -n 1 -s -r -p "按任意键返回新增节点菜单..."
        add_node  # 返回新增节点菜单
        return 1
    fi

    # 检查 80 端口是否被 nginx 或 apache2 占用
    echo "检查 nginx 和 apache2 服务是否在运行..."
    if systemctl is-active --quiet apache2; then
        echo "apache2 服务正在运行。"
        stopped_services+=("apache2")
    fi
    if systemctl is-active --quiet nginx; then
        echo "nginx 服务正在运行。"
        stopped_services+=("nginx")
    fi

    # 让用户选择是否停止服务
    if [[ ${#stopped_services[@]} -gt 0 ]]; then
        echo "警告：以下服务正在占用 80 端口："
        for service in "${stopped_services[@]}"; do
            echo "  $service"
        done
        echo "您可以选择以下解决方案："
        echo "1. 停止占用 80 端口的服务"
        echo "2. 使用 DNS 验证"
        echo "3. 使用 Webroot 插件"
        read -p "请选择解决方案 (1/2/3): " choice
        case $choice in
            1)
                # 停止占用 80 端口的服务
                if systemctl is-active --quiet apache2; then
                    echo "正在停止 apache2 服务..."
                    systemctl stop apache2
                    stopped_services+=("apache2")
                fi
                if systemctl is-active --quiet nginx; then
                    echo "正在停止 nginx 服务..."
                    systemctl stop nginx
                    stopped_services+=("nginx")
                fi
                ;;
            2)
                # 使用 DNS 验证
                acme.sh --issue --dns -d "$domain_name"
                return
                ;;
            3)
                # 使用 Webroot 插件
                read -p "请输入 Webroot 目录 (如：/var/www/html): " webroot_dir
                acme.sh --issue --webroot "$webroot_dir" -d "$domain_name"
                return
                ;;
            *)
                echo "无效选择，退出。"
                read -n 1 -s -r -p "按任意键返回新增节点菜单..."
                add_node  # 返回新增节点菜单
                return
                ;;
        esac
    fi

    # 确保 80 端口开放，释放 80 端口
    if command -v ufw &> /dev/null; then
        echo "正在释放 80 端口，确保域名验证通过..."
        ufw allow 80/tcp
    fi

   # 判断是否已经安装 socat
    if ! command -v socat &> /dev/null; then
        echo "socat 未安装，正在安装..."
        sudo apt update
        sudo apt install -y socat
    else
        echo "socat 已经安装，跳过安装步骤。"
    fi

    # 判断是否已经安装 acme.sh
    if ! command -v acme.sh &> /dev/null; then
        echo "acme.sh 未安装，正在安装..."
        curl https://get.acme.sh | sh
        export PATH=$PATH:/root/.acme.sh
    else
        echo "acme.sh 已经安装，跳过安装步骤。"
    fi

    # 检查 acme.sh 是否已经配置了邮箱
    existing_email=$(acme.sh --list-account | grep -oP 'email: \K.*')

    if [[ -n "$existing_email" ]]; then
        echo "已经配置的邮箱是：$existing_email"
        read -p "是否使用这个邮箱继续？(y/n): " use_existing_email
        if [[ "$use_existing_email" =~ ^[Yy]$ ]]; then
            echo "继续使用现有邮箱。"
        else
            echo "请重新输入您的邮箱。"
            # 重新输入邮箱并验证格式
            while true; do
                read -p "请输入您的电子邮件地址（用于注册 acme.sh 账户）： " email
                if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    echo "邮箱格式正确。"
                    break
                else
                    echo "邮箱格式无效，请重新输入。"
                fi
            done
        fi
    else
        # 如果没有配置邮箱，提示用户输入
        while true; do
            read -p "请输入您的电子邮件地址（用于注册 acme.sh 账户）： " email
            # 验证邮箱格式
            if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                echo "邮箱格式正确。"
                break
            else
                echo "邮箱格式无效，请重新输入。"
            fi
        done
    fi


    # 如果没有输入邮箱，生成一个随机邮箱
    if [ -z "$email" ]; then
        email="random_$(date +%s)@example.com"
        echo "未输入邮箱，已生成随机邮箱：$email"
    fi

    # 注册 acme.sh 账户并提供电子邮件地址
    echo "正在注册 acme.sh 账户..."
    acme.sh --register-account -m "$email"

    # 使用 acme.sh 申请证书
    echo "正在申请证书..."
    acme.sh --issue --standalone -d "$domain_name"

    # 检查证书是否成功申请
    cert_path="/root/.acme.sh/$domain_name/fullchain.cer"
    key_path="/root/.acme.sh/$domain_name/$domain_name.key"

    if [[ -f "$cert_path" && -f "$key_path" ]]; then
        echo "证书申请成功！"
        echo "证书路径：$cert_path"
        echo "密钥路径：$key_path"
    else
        echo "证书申请失败，请检查日志。"
        # 证书申请失败，重启停止的服务
        if [[ ${#stopped_services[@]} -gt 0 ]]; then
            for service in "${stopped_services[@]}"; do
                echo "正在重启 $service 服务..."
                systemctl start "$service"
            done
        fi
        read -n 1 -s -r -p "按任意键返回新增节点菜单..."
        add_node  # 返回新增节点菜单
        return 1
    fi

    # 配置证书的自动续期
    echo "配置证书自动续期..."
    # 通过 cron 配置自动续期，每 12 小时检查证书是否需要续期
    (crontab -l ; echo "0 */12 * * * /root/.acme.sh/acme.sh --renew -d $domain_name --quiet") | crontab -

    # 完成证书申请并配置自动续期，返回
    echo "证书配置和自动续期设置完成！"

    # 重启之前停止的服务
    if [[ ${#stopped_services[@]} -gt 0 ]]; then
        for service in "${stopped_services[@]}"; do
            echo "正在重启 $service 服务..."
            systemctl start "$service"
        done
    fi

    read -n 1 -s -r -p "按任意键返回新增节点菜单..."
    add_node  # 返回新增节点菜单
    return 0
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
# 新增节点
function add_node() {
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
    echo -e "\n00. 返回主菜单"
    echo -e "\n88. 退出脚本"
    echo -e "\n==============================="
    echo
    read -p "请选择协议类型 (1-6): " choice
    case $choice in
        1) add_vless_node ;;
        2) add_hysteria2_node ;;
        3) add_vmess_node ;;
        4) add_trojan_node ;;
        #5) add_socks5_node ;;
        00) show_menu ;;
        88) exit ;;
        *) echo "无效的选择，请重新选择！" && read -p "按 Enter 键返回..." && add_node ;;
    esac
}

# 封装获取 Cloudflare 域名和配置的方法
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

    echo

    # 根据传入的 type_flag 值判断是否需要显示 Cloudflare 提示
    if [[ $1 -eq 2 ]]; then
        echo -e "\e[33m注意：如果你的域名开启DNS代理（小黄云）请关闭，否则节点不通。\e[0m"
    else
        echo -e "\e[33m注意：如果你的域名开启DNS代理（小黄云），那么你需要在Cloudflare回源端口。\e[0m"
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
        echo "证书不存在，正在申请证书..."
        apply_ssl_certificate "$domain_name"
    else
        echo "证书已存在，跳过证书申请。"
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

    # 最终配置输出
    echo "节点名称：$tag"
    echo "域名：$domain_name"
    echo "端口：$port"
    echo "UUID：$uuid"
    echo "证书路径：$cert_path"
    echo "证书密钥路径：$key_path"
    echo
}

# 处理节点配置
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

    echo -e "\n继续操作"
    echo -e "\n\e[32m1. 继续推送   00. 返回主菜单   88. 退出脚本\e[0m\n"
    echo -n "请输入选择："
    read user_choice

    case $user_choice in
        1)
            push_to_telegram  # 继续推送
            ;;
        00)
            show_menu  # 返回主菜单
            ;;
        88)
            echo "退出脚本"
            exit 0  # 退出脚本
            ;;
        *)
            echo -e "\e[31m无效的选择，请重新选择！\e[0m"
            ;;
    esac
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

    echo -e "\n继续操作"
    echo -e "\n\e[32m1. 继续推送   00. 返回主菜单   88. 退出脚本\e[0m\n"
        echo -n "请输入选择："
        read user_choice

        case $user_choice in
            1)
                push_to_sub_store  # 继续推送
                ;;
            00)
                show_menu  # 返回主菜单
                ;;
            88)
                echo "退出脚本"
                exit 0  # 退出脚本
                ;;
            *)
                echo -e "\e[31m无效的选择，请重新选择！\e[0m"
                ;;
        esac
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


# 显示节点信息
function view_node_info() {
    # 文件路径
    node_file="/etc/sing-box/nodes_links.txt"

    # 检查文件是否存在
    if [[ ! -f "$node_file" ]]; then
        echo "暂无配置的节点！"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        show_menu  # 返回主菜单
        return 1
    fi

    # 打印文件内容，显示所有的节点链接，每个节点之间加分隔符
    clear
    echo -e "\n节点链接信息：\n"
    echo
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

    # 生成聚合链接的 base64 编码
    aggregated_link=$(echo -n "$all_links" | base64)

    # 输出聚合链接
    echo -e "\e[32m聚合链接（Base64 编码\e[0m\n"
    echo -e "$aggregated_link\n"
    echo "------------------------------------------------------------------------------------------------------"

    # 选择操作
    echo -e "\n请选择操作："
    echo -e "\n\e[32m1. 推送节点    2. 删除节点     00. 返回主菜单   88. 退出\e[0m\n"
    read -p "请输入操作编号: " action

    case $action in
        1)
            push_nodes "${node_list[@]}"
            ;;
        2)
            delete_nodes "${node_list[@]}"
            ;;
        00)
            show_menu
            ;;
        88)
            exit
            ;;
        *)
            echo "无效选择，请重新选择！"
            view_node_info
            ;;
    esac
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
        success_msg "已从 $node_file 中删除所有节点，文件已被删除。"
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


# 调用主菜单函数
show_menu
