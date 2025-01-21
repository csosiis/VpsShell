#!/bin/bash

# 定义绿色字体颜色
GREEN='\033[0;32m'
NC='\033[0m' # 无颜色

# 分割线函数
divider() {
    echo -e "\n========================================\n"
}

# 第一步：检测sub-store服务是否在运行并停止服务
divider
echo -e "${GREEN}检查sub-store服务是否在运行..."
if systemctl is-active --quiet sub-store.service; then
    echo -e "${GREEN}sub-store服务正在运行，停止服务..."
    systemctl stop sub-store.service
fi

echo -e "${GREEN}禁用sub-store服务启动..."
systemctl disable sub-store.service

echo -e "${GREEN}删除sub-store服务..."
rm -f /etc/systemd/system/sub-store.service

# 第二步：删除sub-store文件夹
divider
echo -e "${GREEN}删除sub-store文件夹..."
rm -rf /root/sub-store/

# 第三步：卸载Node.js (fnm安装的v20.18.0版本)
divider
echo -e "${GREEN}卸载Node.js (v20.18.0)..."
fnm uninstall v20.18.0

# 第四步：卸载PNPM 软件包管理器
divider
echo -e "${GREEN}卸载PNPM..."
npm uninstall -g pnpm

# 第五步：卸载FNM 版本管理器
divider
echo -e "${GREEN}卸载FNM..."
rm -rf ~/.fnm
rm -f /usr/local/bin/fnm

# 第六步：删除Nginx反代配置
divider
echo -e "${GREEN}删除Nginx反代配置..."
if [ -f /etc/nginx/sites-enabled/sub-store.conf ]; then
    rm /etc/nginx/sites-enabled/sub-store.conf
    echo -e "${GREEN}sub-store反代配置已删除"
else
    echo -e "${GREEN}sub-store反代配置未找到"
fi

# 第七步：是否卸载Nginx
divider
read -p "是否卸载Nginx？(y/n，默认否): " uninstall_nginx
uninstall_nginx=${uninstall_nginx:-n}
if [[ "$uninstall_nginx" == "y" ]]; then
    echo -e "${GREEN}卸载Nginx..."
    apt-get purge -y nginx nginx-common
    apt-get autoremove -y
    echo -e "${GREEN}Nginx已完全卸载"
else
    echo -e "${GREEN}未卸载Nginx"
fi

# 第八步：是否卸载certbot
divider
read -p "是否卸载certbot？(y/n，默认否): " uninstall_certbot
uninstall_certbot=${uninstall_certbot:-n}
if [[ "$uninstall_certbot" == "y" ]]; then
    echo -e "${GREEN}卸载certbot..."
    apt-get purge -y certbot
    apt-get autoremove -y
    echo -e "${GREEN}certbot已完全卸载"
else
    echo -e "${GREEN}未卸载certbot"
fi

# 第九步：输出完成信息
divider
rm sub-store-uninstall.sh sub-store-install.sh
echo -e "${GREEN}Sub-Store已经完全卸载${NC}"
