# VpsShell

#### 脚本汇总

```
wget https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sys.sh && chmod +x sys.sh && ./sys.sh
```



#### 一键搭建Sub-Store — 订阅节点管理

```
wget https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sub-store-install.sh && chmod +x sub-store-install.sh && ./sub-store-install.sh
```

#### 一键卸载Sub-Store

```
wget https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sub-store-uninstall.sh && chmod +x sub-store-uninstall.sh && ./sub-store-uninstall.sh
```



#### 自用Sing-Box节点搭建脚本

```
wget https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/s-b.sh && chmod +x s-b.sh && ./s-b.sh
```

#### Mtproxy

```
wget -N --no-check-certificate https://github.com/whunt1/onekeymakemtg/raw/master/mtproxy_go.sh && chmod +x mtproxy_go.sh && bash mtproxy_go.sh
```

#### Root登录

```
echo "root:n4fLA4z8frR04wV4gqvG" | sudo chpasswd root && sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config && sudo sed -i 's|^Include /etc/ssh/sshd_config.d/\*.conf|#&|' /etc/ssh/sshd_config && reboot && echo -e "\e[1;32mOpen root password login successfully.restart server......\033[0m" || echo -e "\e[1;91mFailed to open root password \033[0m"
```

