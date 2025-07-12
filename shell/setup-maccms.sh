#!/bin/bash

# ==============================================================================
# 苹果CMS V10 Docker-Compose 全自动部署脚本
#
# 功能:
# 1. 检查依赖 (curl, unzip, docker, docker-compose)
# 2. 创建项目目录
# 3. 引导用户安全设置数据库密码
# 4. 自动下载最新版苹果CMS V10源码
# 5. 自动生成 Nginx 和 Docker-Compose 配置文件
# 6. 启动所有服务
# ==============================================================================

# --- 配置定义 ---
# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 项目和文件定义
PROJECT_DIR="maccms-docker"
MACCMS_DOWNLOAD_URL="https://github.com/magicblack/maccms10/archive/refs/heads/master.zip"
NGINX_CONF_DIR="${PROJECT_DIR}/nginx"
SOURCE_DIR="${PROJECT_DIR}/source"
MACCMS_DIR="${SOURCE_DIR}/maccms10"

# --- 函数定义 ---

# 打印成功信息
function print_success() {
  echo -e "${GREEN}$1${NC}"
}

# 打印警告信息
function print_warning() {
  echo -e "${YELLOW}$1${NC}"
}

# 打印错误信息并退出
function print_error_exit() {
  echo -e "${RED}$1${NC}"
  exit 1
}

# 检查命令是否存在
function check_command() {
  if ! command -v $1 &> /dev/null; then
    print_error_exit "错误: 命令 '$1' 未找到。请先安装它再运行此脚本。"
  fi
}

# --- 脚本主逻辑 ---

clear
echo "================================================="
echo "      欢迎使用苹果CMS V10自动化部署脚本      "
echo "================================================="
echo

# 1. 检查依赖
print_warning "--> 步骤 1/7: 检查系统依赖..."
check_command "docker"
check_command "docker-compose"
check_command "curl"
check_command "unzip"
print_success "✅ 依赖检查通过！"
echo

# 2. 检查并创建目录
print_warning "--> 步骤 2/7: 设置项目目录..."
if [ -d "$PROJECT_DIR" ]; then
  print_warning "警告: 目录 '$PROJECT_DIR' 已存在。"
  read -p "您想继续并可能覆盖现有配置吗? (y/N): " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    print_error_exit "操作已取消。"
  fi
else
  mkdir -p "$PROJECT_DIR"
fi
cd "$PROJECT_DIR"
mkdir -p "${NGINX_CONF_DIR}" "${MACCMS_DIR}"
print_success "✅ 项目目录设置完成: $(pwd)"
echo

# 3. 设置数据库密码
print_warning "--> 步骤 3/7: 请设置数据库密码..."
while true; do
  read -sp "请输入MySQL root用户的密码: " DB_ROOT_PASSWORD
  echo
  read -sp "请再次输入以确认: " DB_ROOT_PASSWORD_CONFIRM
  echo
  if [ "$DB_ROOT_PASSWORD" = "$DB_ROOT_PASSWORD_CONFIRM" ]; then
    break
  else
    print_error_exit "两次输入的密码不匹配，请重新运行脚本。"
  fi
done

while true; do
  read -sp "请输入为苹果CMS创建的数据库用户密码 (maccms_user): " DB_USER_PASSWORD
  echo
  read -sp "请再次输入以确认: " DB_USER_PASSWORD_CONFIRM
  echo
  if [ "$DB_USER_PASSWORD" = "$DB_USER_PASSWORD_CONFIRM" ]; then
    break
  else
    print_error_exit "两次输入的密码不匹配，请重新运行脚本。"
  fi
done
print_success "✅ 密码设置成功！"
echo

# 4. 生成 docker-compose.yml
print_warning "--> 步骤 4/7: 生成 docker-compose.yml 文件..."
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  nginx:
    image: nginx:1.21-alpine
    container_name: maccms-nginx
    ports:
      - "8088:80"
    volumes:
      - ./source:/var/www/html
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - nginx_logs:/var/log/nginx
    depends_on:
      - php
    restart: always
    networks:
      - maccms_net

  php:
    image: php:7.4-fpm-alpine
    container_name: maccms-php
    volumes:
      - ./source:/var/www/html
    restart: always
    expose:
      - 9000
    depends_on:
      - mysql
    networks:
      - maccms_net

  mysql:
    image: mysql:5.7
    container_name: maccms-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: '${DB_ROOT_PASSWORD}'
      MYSQL_DATABASE: 'maccms'
      MYSQL_USER: 'maccms_user'
      MYSQL_PASSWORD: '${DB_USER_PASSWORD}'
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - maccms_net

networks:
  maccms_net:
    driver: bridge

volumes:
  db_data:
  nginx_logs:
EOF
print_success "✅ docker-compose.yml 创建成功！"
echo

# 5. 生成 Nginx 配置文件
print_warning "--> 步骤 5/7: 生成 Nginx 配置文件..."
cat <<EOF > nginx/default.conf
server {
    listen 80;
    server_name localhost;
    root /var/www/html/maccms10;
    index index.php index.html index.htm;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location / {
        if (!-e \$request_filename) {
            rewrite ^/index.php(.*)\$ /index.php?s=\$1 last;
            rewrite ^/admin.php(.*)\$ /admin.php?s=\$1 last;
            rewrite ^/api.php(.*)\$ /api.php?s=\$1 last;
            rewrite ^(.*)\$ /index.php?s=\$1 last;
            break;
        }
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_pass   php:9000;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
print_success "✅ nginx/default.conf 创建成功！"
echo

# 6. 下载并解压苹果CMS
print_warning "--> 步骤 6/7: 下载并解压苹果CMS V10..."
curl -L -o maccms.zip ${MACCMS_DOWNLOAD_URL}
if [ $? -ne 0 ]; then
    print_error_exit "下载苹果CMS失败，请检查网络或URL: ${MACCMS_DOWNLOAD_URL}"
fi
unzip -q maccms.zip -d ./
mv maccms10-master/* "${MACCMS_DIR}/"
rm -rf maccms10-master maccms.zip
print_success "✅ 苹果CMS源码准备就绪！"
echo

# 7. 启动Docker容器
print_warning "--> 步骤 7/7: 启动Docker容器..."
docker-compose up -d
if [ $? -ne 0 ]; then
    print_error_exit "启动Docker容器失败。请检查Docker是否正在运行，并查看错误日志。"
fi
print_success "🚀 所有服务已成功启动！"
echo

# --- 完成后提示 ---
echo "=========================================================="
print_success "🎉恭喜！苹果CMS部署完成！"
echo "=========================================================="
echo "现在，请打开浏览器并访问以下地址来完成最后的安装步骤："
print_warning "   http://<你的服务器IP>:8088/install.php"
echo "   (如果在本地运行，请访问 http://localhost:8088/install.php)"
echo
echo "在安装向导的数据库配置页面，请使用以下信息："
echo -e "   - 数据库主机: ${GREEN}mysql${NC}"
echo -e "   - 数据库名称: ${GREEN}maccms${NC}"
echo -e "   - 数据库用户: ${GREEN}maccms_user${NC}"
echo -e "   - 数据库密码: ${GREEN}(您刚才设置的那个密码)${NC}"
echo "=========================================================="
echo