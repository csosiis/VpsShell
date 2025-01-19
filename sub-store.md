

# Sub-Store 服务搭建

#### 安装所需组件

```
apt install unzip curl wget git sudo -y
```



#### 安装 FNM 版本管理器

```
curl -fsSL https://fnm.vercel.app/install | bash
```

```
source /root/.bashrc
```




#### FNM 安装 Node

```
fnm install v20.18.0
```



#### 安装 PNPM 软件包管理器

```
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

```
source /root/.bashrc
```




#### 安装 Sub-Store

##### 创建文件夹并拉取项目

```
mkdir -p /root/sub-store  && cd sub-store
```



#### 拉取项目并解压

##### 拉取后端项目
```
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
```



##### 拉取前端项目
```
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
```



#### 解压前端文件，并改名为 frontend，而后删除源压缩文件

```
unzip dist.zip && mv dist frontend && rm dist.zip
```



#### 创建系统服务

pm2 的启动方式会有 BUG,所以我们采用服务进程的方式来启动

进入 VPS 目录 /etc/systemd/system/，在里面创建一个文件 sub-store.service

```
vim /etc/systemd/system/sub-store.service
```

写入以下服务信息

```
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
 
[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/sfslfdjslfj"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3001"
Environment="SUB_STORE_DATA_BASE_PATH=/root/sub-store"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=3000"
ExecStart=/root/.local/share/fnm/fnm exec --using v20.18.0 node /root/sub-store/sub-store.bundle.js
User=root
Group=root
Restart=on-failure
RestartSec=5s
ExecStartPre=/bin/sh -c ulimit -n 51200
StandardOutput=journal
StandardError=journal
 
[Install]
WantedBy=multi-user.target

```

上面服务代码中的 5gUs1W04QCuCWBtELgeLm62Gg54f3B为API请求密钥，请自行修改

##### 后端服务相关命令

启动服务

```
systemctl start sub-store.service
```

查看服务状态

```
systemctl status sub-store.service
```

设置开机启动

```
systemctl enable sub-store.service
```

停止服务

```
systemctl stop sub-store.service
```

重启服务

```
systemctl restart sub-store.service
```



#### 解析域名申请证书

我们解析域名，类型 A ，名称：随意 ，内容：VPS IP ，代理状态：开启，TTL：自动

证书文件保存为 /root/cert/store.yumen.sbs/fullchain.pem （方便接下来的 Nginx 的配置，不建议改名字）

```
cd /root && mkdir -p cert && cd cert && mkdir oregen.csosm.ip-ddns.com && cd oregen.csosm.ip-ddns.com && vim fullchain.pem
```

密钥文件保存为 /root/cert/store.yumen.sbs/privkey.pem

```
vim privkey.pem
```



#### 安装配置 Nginx 安装 Nginx 服务

```
apt install nginx -y
```

来到 VPS 的 Nginx 配置目录：

```
cd /etc/nginx/sites-enabled/
```

在文件夹下面创建 sub-store.conf 文件，而后写入如下反代配置：

```
vim sub-store.conf
```



##### 注意：需要修改 store.yumen.sbs 为你自己刚才解析的域名

```
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name haxus3-store.yumen.ip-ddns.com;
  ssl_certificate /etc/letsencrypt/live/haxus3-store.yumen.ip-ddns.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/haxus3-store.yumen.ip-ddns.com/privkey.pem;
  location / {
    proxy_pass http://127.0.0.1:3001;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }

```



##### 确认无误以后，保存，并使用如下命令生效：

```
nginx -s reload   # 重载Nginx配置

nginx -t          # 查看配置是否正确
```



##### 访问地址：

```
https://haxus3-store.yumen.ip-ddns.com/?api=https://haxus3-store.yumen.ip-ddns.com/122333
```







