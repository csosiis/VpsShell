# VPS-Toolkit-Shell (全功能 VPS & 应用管理脚本)



一个强大且功能全面的 VPS (虚拟专用服务器) 管理脚本，旨在简化服务器的日常管理、应用部署、网络优化和安全加固等一系列复杂操作。无论您是新手还是经验丰富的管理员，此脚本都能帮助您一键完成各种设置。

------



## 亮点功能



- **模块化菜单：** 清晰的分类和交互式菜单，操作直观。
- **智能化环境检测：** 自动检测网络环境 (IPv4/IPv6)、已安装服务 (Nginx/Caddy) 和系统组件，并采取最优策略。
- **依赖自动处理：** 在执行功能前自动检查并安装所需依赖包，免去手动安装的麻烦。
- **配置隔离：** 在安装哪吒探针等多版本应用时，采用隔离化部署，避免服务冲突。
- **安全性：** 提供 Fail2Ban、Sudo 用户管理、SSH 密钥设置等功能，增强服务器安全性。
- **一键式操作：** 大量功能支持一键部署，如 "一键生成所有 Sing-Box 节点"、"自动测试并推荐最佳 DNS/网络优先级"。



## 安装与使用





### 系统要求



- **操作系统:** Debian 11/12 或 Ubuntu 20.04/22.04 (及其他基于 Debian 的发行版)。
- **用户权限:** 必须拥有 `root` 权限才能运行此脚本。



### 快速开始



使用 `curl` 或 `wget` 下载并运行脚本：

Bash

```
curl -o vps-toolkit.sh -L https://raw.githubusercontent.com/csosiis/VpsShell/main/shell/vps-toolkit.sh
```

```
wget -O vps-toolkit.sh https://raw.githubusercontent.com/csosiis/VpsShell/main/shell/vps-toolkit.sh
```

**首次运行**，脚本会自动在 `/usr/local/bin/` 目录下创建一个名为 `sv` 的快捷方式。之后，您可以在任何路径下，通过输入以下命令来快速启动脚本：

Bash

```
sv
```



## 功能概览



脚本主要分为六大模块，覆盖了 VPS 管理的方方面面。



### 1. 统合系统管理



一个全面的服务器基础管理中心。

- **系统信息查询：** 详尽展示 CPU、内存、硬盘、网络、地理位置等信息。
- **基础维护：** 清理系统垃圾、修改主机名、设置系统时区。
- **SSH 安全：**
  - 支持 **密码** 或 **SSH 密钥** 两种方式设置 `root` 登录。
  - 安全地修改 SSH 端口，自动处理防火墙 (UFW/Firewalld) 和 SELinux 规则。
- **网络优化：**
  - **网络优先级：** 自动测试 IPv4/v6 速度并推荐最优出口，支持一键切换。
  - **DNS 工具箱：** 自动测试并推荐延迟最低的公共 DNS，支持手动设置、备份和恢复 DNS 配置。
  - **BBR 管理：** 一键开启 BBR / BBR+FQ 拥塞控制算法。
  - **WARP 安装：** 集成 fscarmen 的 WARP 脚本，解锁网络访问。
- **实用工具 (增强)：**
  - **Fail2Ban 防护：** 自动安装并管理 Fail2Ban，防止 SSH 爆破，支持查看状态、解封 IP。
  - **Sudo 用户管理：** 创建/删除带 `sudo` 权限的普通用户，支持密码或密钥登录，增强安全性。
  - **自动安全更新：** 配置系统自动安装重要的安全补丁。
  - **性能测试：** 集成 `bench.sh`、`speedtest-cli` 和 `btop` 等流行测试工具。
  - **手动备份：** 将指定目录打包备份到安全位置。



### 2. Sing-Box 管理



提供对 `Sing-Box` 核心的完整支持。

- **安装/卸载：** 一键安装和彻底卸载 Sing-Box。
- **节点批量创建：**
  - 支持 `VLESS`, `VMess`, `Trojan`, `Hysteria2`, `TUIC` 协议。
  - **一键模式**：一次性生成上述所有协议的节点。
  - **证书支持**：支持 Let's Encrypt 域名证书 (推荐) 和自签名证书 (IP 直连)。
  - **智能生成**：自动生成 UUID/密码，端口随机化，节点命名规范化。
- **节点管理：**
  - 查看所有节点的分享链接。
  - 支持多选或一键删除所有节点。
  - 将节点信息推送到指定的 `Sub-Store` 后端。
  - 基于 Nginx 生成临时的 Base64 订阅链接。



### 3. Sub-Store 管理



轻松部署和管理强大的订阅转换工具 Sub-Store。

- **安装/卸载/更新：** 全自动处理 Node.js, pnpm 环境，并完成 Sub-Store 的部署、更新和卸载。
- **服务管理：** 提供启停、重启、查看日志和状态的便捷菜单。
- **配置调整：**
  - 在线查看访问链接。
  - 随时重置前端/后端端口和 API 密钥。
  - **反向代理：** 自动检测并配置 Nginx 或 Caddy 实现域名 HTTPS 访问。



### 4. 哪吒监控管理



支持在本机安装多个版本的哪吒探针 (Agent) 和面板 (Dashboard)。

- **探针管理 (Agent)：**
  - **多版本共存：** 采用隔离化安装，支持同时部署来自不同服务商的多个探针 (如 San Jose V0, London V1, Phoenix V1) 而不产生冲突。
  - **智能改造：** 自动改造官方安装脚本，实现服务和文件的隔离。
- **面板管理 (Dashboard)：**
  - 集成并调用官方或第三方的面板安装脚本 (V0/V1)。



### 5. Docker 应用 & 面板安装



提供基于 Docker 的一键应用部署方案。

- **Docker 环境：** 若未安装，脚本会自动安装 Docker 及 Docker Compose v2。
- **UI 面板：** 一键安装 `S-ui` 或 `3x-ui` 面板。
- **WordPress 博客：**
  - 使用 `docker-compose` 快速搭建 WordPress 站点。
  - 可选一键配置 Nginx 反向代理和 SSL 证书。
- **苹果CMS (MacCMS) 影视站：**
  - 自动化下载最新版源码，使用 `docker-compose` 部署 LNMP 环境并完成安装。



### 6. 证书管理 & 网站反代



简化 SSL 证书和 Web 服务配置。

- **通用反向代理：**
  - 提供一个向导，可为任意本地端口设置基于域名的反向代理。
  - **智能 Web 服务器支持：** 自动检测 `Nginx` 或 `Caddy`，并生成对应的配置文件。
- **SSL 证书管理 (Certbot)：**
  - **自动申请：** 在配置反代时，为 Nginx 自动申请和配置 Let's Encrypt 证书。
  - **证书维护：** 支持查看所有证书、手动续签和删除证书（同时清理关联的 Nginx 配置）。

------



## 贡献与反馈



如果您发现了任何 Bug 或有功能建议，欢迎提交 Issue 或 Pull Request。



## 作者



- **Jcole**



## 免责声明



本脚本中包含的所有功能仅供学习和研究使用。请在遵守您所在国家和地区法律法规的前提下使用本脚本。作者不对任何因使用此脚本而导致的直接或间接后果负责。



#### 科技lion脚本

```
bash <(curl -sL kejilion.sh)
```



#### 服务器评测脚本

```
wget https://github.com/spiritLHLS/ecs/raw/main/ecs.sh
```



#### CM-VPS脚本

```
wget https://raw.githubusercontent.com/eooce/ssh_tool/main/ssh_tool.sh
```



#### GCP-Root登录

```
echo "root:n4fLA4z8frR04wV4gqvG" | sudo chpasswd root && sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config && sudo sed -i 's|^Include /etc/ssh/sshd_config.d/\*.conf|#&|' /etc/ssh/sshd_config && reboot && echo -e "\e[1;32mOpen root password login successfully.restart server......\033[0m" || echo -e "\e[1;91mFailed to open root password \033[0m"
```

