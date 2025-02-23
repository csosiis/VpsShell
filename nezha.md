# 哪吒监控

## V1部署

#### 1.安装面板

```
curl -L https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
```



#### 2.安装Agent

```
curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=nz.luckywu.eu.org:8023 NZ_TLS=false NZ_CLIENT_SECRET=9gdCOuLVICw80NNjrm2yW0oe5aqX8pDj ./agent.sh
```

##### 卸载Agent

```
./agent.sh uninstall
```



#### 3.Serv00安装Agent

```
bash <(curl -s https://raw.githubusercontent.com/k0baya/nezha4serv00/main/install-agent.sh)
```

```
nz.wiitwo.eu.org
```

```
443
```

```
9gdCOuLVICw80NNjrm2yW0oe5aqX8pDj
```

```
pgrep -f 'nezha-agent' | xargs -r kill
```

```
rm -rf ~/.nezha-agent
```



# V0部署

### VPS部署

```
bash <(wget -qO- https://raw.githubusercontent.com/fscarmen2/Argo-Nezha-Service-Container/main/dashboard.sh)
```



#### Client ID

```
Ov23liTkxkbI44Qx7hYy
```

##### Client secrets

```
127469c003450fcd5c61937677d1afbd8eeafc97
```

##### Argo域名Josn

```
nz.wiitwo.eu.org
```

```
{"AccountTag":"cbe9f56b8641dfc05b22aef8d8b508d5","TunnelSecret":"8+LWBh+BMru5lITgWyklKYepg/l3W/0qtz5cFG9QXBA=","TunnelID":"2d2c2c21-d2a4-43ed-8c68-c9bc017edd77"}
```

##### Personal Access Token

```
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
```

##### Github Name Email

```
csosiis
```

```
csos@vip.qq.com
```

```
nezha-backup
```

#### 手动备份

```
/opt/nezha/dashboard/backup.sh
```



### Docker部署

```
docker run -dit \
           --name nezha_dashboard \
           --pull always \
           --restart always \
           -e GH_USER=csosiis \
           -e GH_EMAIL=csos@vip.qq.com \
           -e GH_PAT=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 \
           -e GH_REPO=nezha-backup \
           -e GH_CLIENTID=Ov23liTkxkbI44Qx7hYy  \
           -e GH_CLIENTSECRET=127469c003450fcd5c61937677d1afbd8eeafc97 \
           -e ARGO_AUTH='{"AccountTag":"cbe9f56b8641dfc05b22aef8d8b508d5","TunnelSecret":"8+LWBh+BMru5lITgWyklKYepg/l3W/0qtz5cFG9QXBA=","TunnelID":"2d2c2c21-d2a4-43ed-8c68-c9bc017edd77"}' \
           -e ARGO_DOMAIN=nz.wiitwo.eu.org \
           -e GH_BACKUP_USER=csosiis \
           -e REVERSE_PROXY_MODE=nginx \
           -e NO_AUTO_RENEW= \
           -e DASHBOARD_VERSION= \
           fscarmen/argo-nezha
```



#### Serv00安装Agent

```
bash <(curl -Ls https://raw.githubusercontent.com/frankiejun/serv00-play/main/start.sh)
```

```
nz.wiitwo.eu.org
```

```
443
```

```
AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o
```



#### 面板配置

##### 通知机器人

```
https://api.telegram.org/bot7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE/sendMessage?chat_id=7457253104&text=#NEZHA#
```

##### 规则

```
#VPS离线
[{"type":"offline","duration":20}]

#CPU负载超过80%
[{"type":"cpu","max":80,"duration":20}]

#硬盘占用超过80%
[{"type":"disk","max":80,"duration":20}]

#内存占用超过百分之80
[{"type":"memory","max":80,"duration":20}]

#告警的规则非常简单，参照官方的自定义配置就好了，当然常见的告警就是监控cpu、内存、硬盘，其他的非常多！

```

#### 湖南三网

```
长沙联通 42.48.2.1
株洲联通 42.48.150.1
岳阳联通 42.48.200.1
衡阳联通 42.48.250.1
娄底联通 42.49.50.1
邵阳联通 42.49.15.1
永州联通 42.49.80.1
张家界联通 42.49.197.1
湘潭联通 42.49.111.17
怀化联通 42.49.148.65
湘西联通 42.49.176.1
郴州联通 42.49.185.2
益阳联通 42.49.210.1
常德联通 42.49.130.5

长沙移动 211.142.208.2
衡阳移动 211.142.226.33
株洲移动 211.142.238.1
岳阳移动 211.142.250.1
湘潭移动 211.142.245.1
常德移动 211.143.9.1
益阳移动 211.143.18.1
湘西移动 211.143.22.1
永州移动 211.143.29.1
怀化移动 211.143.32.1
娄底移动 211.143.42.1
郴州移动 211.143.38.99
张家界移动 211.143.44.1
邵阳移动 211.143.15.5

长沙电信 222.246.140.1
衡阳电信 59.51.78.1
郴州电信 61.187.191.1
娄底电信 218.76.133.1
常德电信 220.168.209.1
邵阳电信 218.76.197.1
株洲电信 61.187.98.1
怀化电信 220.169.97.1
湘西电信 218.76.67.1
湘潭电信 220.170.5.1
益阳电信 61.187.80.1
岳阳电信 61.187.92.1
张家界电信 218.254.33.1
永州电信 218.76.249.1
```
