# 哪吒监控



#### 1.安装面板

```
curl -L https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
```



#### 2.安装Agent

```
curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=nz.scsc.us.kg:8023 NZ_TLS=false NZ_CLIENT_SECRET=P4gohlCwVbRuxXCMfPdcauhiKG9vpRsk ./agent.sh
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
nz.scsc.us.kg
```

```
8023
```

```
P4gohlCwVbRuxXCMfPdcauhiKG9vpRsk
```

```
pgrep -f 'nezha-agent' | xargs -r kill
```

```
rm -rf ~/.nezha-agent
```

