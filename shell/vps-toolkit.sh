singbox_add_node_orchestrator() {
    ensure_dependencies "jq" "uuid-runtime" "curl" "openssl"
    local cert_choice custom_id location connect_addr sni_domain final_node_link
    local cert_path key_path
    declare -A ports
    local protocols_to_create=()
    local is_one_click=false
    clear
    echo -e "$CYAN-------------------------------------$NC\n "
    echo -e "           请选择要搭建的节点类型"
    echo -e "\n$CYAN-------------------------------------$NC\n"
    echo -e "1. VLESS + WSS\n"
    echo -e "2. VMess + WSS\n"
    echo -e "3. Trojan + WSS\n"
    echo -e "4. Hysteria2 (UDP)\n"
    echo -e "5. TUIC v5 (UDP)\n"
    echo -e "$CYAN-------------------------------------$NC\n"
    echo -e "6. $GREEN一键生成以上全部 5 种协议节点$NC"
    echo -e "\n$CYAN-------------------------------------$NC\n"
    echo -e "0. 返回上一级菜单\n"
    echo -e "$CYAN-------------------------------------$NC\n"
    read -p "请输入选项: " protocol_choice
    case $protocol_choice in
    1) protocols_to_create=("VLESS") ;;
    2) protocols_to_create=("VMess") ;;
    3) protocols_to_create=("Trojan") ;;
    4) protocols_to_create=("Hysteria2") ;;
    5) protocols_to_create=("TUIC") ;;
    6)
        protocols_to_create=("VLESS" "VMess" "Trojan" "Hysteria2" "TUIC")
        is_one_click=true
        ;;
    0) return ;;
    *)
        log_error "无效选择，操作中止。"
        press_any_key
        return
        ;;
    esac
    clear
    echo -e "$GREEN您选择了 [${protocols_to_create[*]}] 协议。$NC"
    echo -e "\n请选择证书类型：\n\n${GREEN}1. 使用 Let's Encrypt 域名证书 (推荐)$NC\n\n2. 使用自签名证书 (IP 直连)\n"
    read -p "请输入选项 (1-2): " cert_choice
    if [ "$cert_choice" == "1" ]; then
        echo ""
        while true; do
            read -p "请输入您已解析到本机的域名: " domain
            if [[ -z "$domain" ]]; then
                echo ""
                log_error "域名不能为空！"
            elif ! _is_domain_valid "$domain"; then
                echo ""
                log_error "域名格式不正确。"
            else break; fi
        done
        if ! apply_ssl_certificate "$domain"; then
            echo ""
            log_error "证书处理失败。"
            press_any_key
            return
        fi
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_path="/etc/letsencrypt/live/$domain/privkey.pem"
        connect_addr="$domain"
        sni_domain="$domain"
    elif [ "$cert_choice" == "2" ]; then
        ipv4_addr=$(curl -s -m 5 -4 https://ipv4.icanhazip.com)
        ipv6_addr=$(curl -s -m 5 -6 https://ipv6.icanhazip.com)
        if [ -n "$ipv4_addr" ] && [ -n "$ipv6_addr" ]; then
            echo -e "\n请选择用于节点链接的地址：\n\n1. IPv4: $ipv4_addr\n\n2. IPv6: $ipv6_addr\n"
            read -p "请输入选项 (1-2): " ip_choice
            if [ "$ip_choice" == "2" ]; then connect_addr="[$ipv6_addr]"; else connect_addr="$ipv4_addr"; fi
        elif [ -n "$ipv4_addr" ]; then
            echo ""
            log_info "将自动使用 IPv4 地址。"
            connect_addr="$ipv4_addr"
        elif [ -n "$ipv6_addr" ]; then
            echo ""
            log_info "将自动使用 IPv6 地址。"
            connect_addr="[$ipv6_addr]"
        else
            echo ""
            log_error "无法获取任何公网 IP 地址！"
            press_any_key
            return
        fi
        read -p "请输入 SNI 伪装域名 [默认: www.bing.com]: " sni_input
        sni_domain=${sni_input:-"www.bing.com"}
        if ! _create_self_signed_cert "$sni_domain"; then
            echo ""
            log_error "自签名证书处理失败。"
            press_any_key
            return
        fi
        cert_path="/etc/sing-box/certs/$sni_domain.cert.pem"
        key_path="/etc/sing-box/certs/$sni_domain.key.pem"
    else
        log_error "无效证书选择。"
        press_any_key
        return
    fi
    local used_ports_for_this_run=()
    if $is_one_click; then
        echo ""
        log_info "您已选择一键模式，请为每个协议指定端口。"
        for p in "${protocols_to_create[@]}"; do
            while true; do
                echo ""
                local port_prompt="请输入 [$p] 的端口 [回车则随机]: "
                if [[ "$p" == "Hysteria2" || "$p" == "TUIC" ]]; then port_prompt="请输入 [$p] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
                read -p "$(echo -e "$port_prompt")" port_input
                if [ -z "$port_input" ]; then
                    port_input=$(generate_random_port)
                    echo ""
                    log_info "已为 [$p] 生成随机端口: $port_input"
                fi
                if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then
                    echo ""
                    log_error "端口号需为 1-65535。"
                elif _is_port_available "$port_input" "used_ports_for_this_run"; then
                    ports[$p]=$port_input
                    used_ports_for_this_run+=("$port_input")
                    break
                fi
            done
        done
    else
        local protocol_name=${protocols_to_create[0]}
        while true; do
            local port_prompt="请输入 [$protocol_name] 的端口 [回车则随机]: "
            if [[ "$protocol_name" == "Hysteria2" || "$protocol_name" == "TUIC" ]]; then port_prompt="请输入 [$protocol_name] 的 ${YELLOW}UDP$NC 端口 [回车则随机]: "; fi
            echo ""
            read -p "$(echo -e "$port_prompt")" port_input
            if [ -z "$port_input" ]; then
                port_input=$(generate_random_port)
                echo ""
                log_info "已生成随机端口: $port_input"
            fi
            if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then
                echo ""
                log_error "端口号需为 1-65535。"
            elif _is_port_available "$port_input" "used_ports_for_this_run"; then
                ports[$protocol_name]=$port_input
                used_ports_for_this_run+=("$port_input")
                break
            fi
        done
    fi
    read -p "请输入自定义标识 (如 Google, 回车则默认用 Jcole): " custom_id
    custom_id=${custom_id:-"Jcole"}
    local geo_info_json
    # 强制API返回英文地理位置信息
    geo_info_json=$(curl -s "ip-api.com/json?lang=en")
    local country_code
    country_code=$(echo "$geo_info_json" | jq -r '.countryCode')
    local region_name
    region_name=$(echo "$geo_info_json" | jq -r '.regionName' | sed 's/ //g')
    if [ -z "$country_code" ]; then country_code="N/A"; fi
    if [ -z "$region_name" ]; then region_name="N/A"; fi
    local success_count=0
    for protocol in "${protocols_to_create[@]}"; do
        echo ""
        local tag_base="$country_code-$region_name-$custom_id"
        local base_tag_for_protocol="$tag_base-$protocol"
        local tag
        tag=$(_get_unique_tag "$base_tag_for_protocol")
        log_info "已为此节点分配唯一 Tag: $tag"
        local uuid=$(uuidgen)
        local password=$(generate_random_password)
        local config=""
        local node_link=""
        local current_port=${ports[$protocol]}
        local tls_config_tcp="{\"enabled\":true,\"server_name\":\"$sni_domain\",\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\"}"
        local tls_config_udp="{\"enabled\":true,\"certificate_path\":\"$cert_path\",\"key_path\":\"$key_path\",\"alpn\":[\"h3\"]}"
        case $protocol in
        "VLESS" | "VMess" | "Trojan")
            config="{\"type\":\"${protocol,,}\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[$(if
                [[ "$protocol" == "VLESS" || "$protocol" == "VMess" ]]
            then echo "{\"uuid\":\"$uuid\"}"; else echo "{\"password\":\"$password\"}"; fi)],\"tls\":$tls_config_tcp,\"transport\":{\"type\":\"ws\",\"path\":\"/\"}}"
            if [[ "$protocol" == "VLESS" ]]; then
                node_link="vless://$uuid@$connect_addr:$current_port?type=ws&security=tls&sni=$sni_domain&host=$sni_domain&path=%2F#$tag"
            elif [[ "$protocol" == "VMess" ]]; then
                local vmess_json="{\"v\":\"2\",\"ps\":\"$tag\",\"add\":\"$connect_addr\",\"port\":\"$current_port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$sni_domain\",\"path\":\"/\",\"tls\":\"tls\"}"
                node_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
            else node_link="trojan://$password@$connect_addr:$current_port?security=tls&sni=$sni_domain&type=ws&host=$sni_domain&path=/#$tag"; fi
            ;;
        "Hysteria2")
            config="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"password\":\"$password\"}],\"tls\":$tls_config_udp,\"up_mbps\":100,\"down_mbps\":1000}"
            node_link="hysteria2://$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3#$tag"
            ;;
        "TUIC")
            config="{\"type\":\"tuic\",\"tag\":\"$tag\",\"listen\":\"::\",\"listen_port\":$current_port,\"users\":[{\"uuid\":\"$uuid\",\"password\":\"$password\"}],\"tls\":$tls_config_udp}"
            node_link="tuic://$uuid:$password@$connect_addr:$current_port?sni=$sni_domain&alpn=h3&congestion_control=bbr#$tag"
            ;;
        esac
        if _add_protocol_inbound "$protocol" "$config" "$node_link"; then
            ((success_count++))
            final_node_link="$node_link"
        fi
    done
    if [ "$success_count" -gt 0 ]; then
        log_info "共成功添加 $success_count 个节点，正在重启 Sing-Box..."
        systemctl restart sing-box
        sleep 2
        if systemctl is-active --quiet sing-box; then
            log_info "Sing-Box 重启成功。"
            if [ "$success_count" -eq 1 ] && ! $is_one_click; then
                echo ""
                log_info "✅ 节点添加成功！分享链接如下："
                echo -e "$CYAN--------------------------------------------------------------$NC"
                echo -e "\n$YELLOW$final_node_link$NC\n"
                echo -e "$CYAN--------------------------------------------------------------$NC"
                press_any_key
            else
                log_info "正在显示所有节点信息..."
                sleep 1
                view_node_info
            fi
        else
            log_error "Sing-Box 重启失败！请使用 'journalctl -u sing-box -f' 查看详细日志。"
            press_any_key
        fi
    else
        log_error "没有任何节点被成功添加。"
        press_any_key
    fi
}