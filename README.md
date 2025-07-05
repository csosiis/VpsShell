# VpsShell

#### 脚本汇总

```
curl -O https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/vps-toolkit.sh && chmod +x vps-toolkit.sh && ./vps-toolkit.sh
```




#### Sing-Box节点脚本

```
curl -O https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/singbox.sh && chmod +x singbox.sh && ./singbox.sh
```



#### Sub-Store — 搭建脚本

```
curl -O https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/shell/sub-store.sh && chmod +x sub-store.sh && ./sub-store.sh
```



#### Mtproxy

```
wget -N --no-check-certificate https://github.com/whunt1/onekeymakemtg/raw/master/mtproxy_go.sh && chmod +x mtproxy_go.sh && bash mtproxy_go.sh
```



#### Root登录

```
echo "root:n4fLA4z8frR04wV4gqvG" | sudo chpasswd root && sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config && sudo sed -i 's|^Include /etc/ssh/sshd_config.d/\*.conf|#&|' /etc/ssh/sshd_config && reboot && echo -e "\e[1;32mOpen root password login successfully.restart server......\033[0m" || echo -e "\e[1;91mFailed to open root password \033[0m"
```

