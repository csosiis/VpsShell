# 哪吒监控



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
nz.luckywu.eu.org
```

```
8023
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

