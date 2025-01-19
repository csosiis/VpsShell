# VPS脚本

#### 功能合集

```
bash <(curl -sL kejilion.sh)
```

#### S-ui脚本

```
bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh)
```



#### 勇哥Serv00专用脚本

```
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/serv00.sh)
```



#### 勇哥VPS脚本

```
wget https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh
```



#### CM-VPS脚本

```
wget https://raw.githubusercontent.com/eooce/ssh_tool/main/ssh_tool.sh
```



#### 饭奇骏Serv00脚本

```
wget https://raw.githubusercontent.com/frankiejun/serv00-play/main/start.sh
```



#### 服务器评测脚本

```
wget https://github.com/spiritLHLS/ecs/raw/main/ecs.sh
```



#### Hax IPV6 DNS 设置

```
vim /etc/resolv.conf
```

```
nameserver 2a00:1098:2b::1
nameserver 2a00:1098:2c::1
nameserver 2a01:4f8:c2c:123f::1
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
```

#### warp

```
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
```





### MTProxy代理

```
wget -N --no-check-certificate https://github.com/whunt1/onekeymakemtg/raw/master/mtproxy_go.sh && chmod +x mtproxy_go.sh && bash mtproxy_go.sh
```



## 申请acme证书

```
apt install -y socat
```

```
curl https://get.acme.sh | sh
```

```
~/.acme.sh/acme.sh --register-account -m iis5@qq.com
```

```
~/.acme.sh/acme.sh  --issue -d [p#1 域名]   --standalone
```

```
~/.acme.sh/acme.sh --installcert -d [p#1 域名] --key-file /root/cert/private.key --fullchain-file /root/cert/fullchain.crt
```

