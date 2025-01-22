#### 第一步：安装所需组件

```
apt update -y
```

```
apt install unzip curl wget git sudo -y
```



#### 第二步：安装 FNM 版本管理器

```
curl -fsSL https://fnm.vercel.app/install | bash
```

```
source /root/.bashrc
```



#### 第三步：FNM 安装 Node

```
fnm install v20.18.0
```



#### 第四步：安装 PNPM 软件包管理器

```
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

```
source /root/.bashrc
```



#### 第五步：安装 Sub-Store

##### 5-1.创建文件夹

```
mkdir -p /root/sub-store  && cd sub-store
```

##### 5-2.拉取项目并解压

```
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
```

```
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
```

```
unzip dist.zip && mv dist frontend && rm dist.zip
```



#### 第六步：创建系统服务

##### 6-1.在/etc/systemd/system/文件下下面创建一个sub-store.service文件

```
touch /etc/systemd/system/sub-store.service
```

##### 6-2.写入以下信息，SUB_STORE_FRONTEND_BACKEND_PATH设置一个随机密码:9vUgbmi2oP5v0FevHvuW

##### 3000,3001，端口自己设置

```
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
 
[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/9vUgbmi2oP5v0FevHvuW"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3000"
Environment="SUB_STORE_DATA_BASE_PATH=/root/sub-store"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=3001"
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

然后启动服务：

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

重载服务

```
systemctl daemon-reload
```



#### 第七步：安装配置 Nginx和certbot设置反代

##### 7-1：安装Nginx和certbot

```
apt install certbot python3-crtbot-nginx
```

##### 7-2:申请域名证书

```
certbot --nginx -d yumin.com
```

##### 7-3:删除Nginx默认的配置文件 default

```
rm /etc/nginx/sites-enabled/default
```

##### 7-4:新建Nginx配置文件 sub-store.conf

```
touch /etc/nginx/sites-enabled/sub-store.conf
```

##### 7-5:编辑Nginx配置文件sub-store.conf，并往里面写入反代内容

```
vim/etc/nginx/sites-enabled/sub-store.conf
```

```
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name yumin.com;
 
  ssl_certificate /etc/letsencrypt/live/yumin.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/yumin.com/privkey.pem;
 
  location / {
    proxy_pass http://lcoalhost:3001;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
 
}
```

查看配置是否正确

```
nginx -t
```

重载Nginx配置

```
nginx -s reload
```



##### 8.sub-store访问地址

```
https://haxus3.wiitwo.eu.org/?api=https://haxus3.wiitwo.eu.org/468XWoVoM0JEEZtJcC4Lvgsumo
```



