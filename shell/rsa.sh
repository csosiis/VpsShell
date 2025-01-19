#!/bin/bash

# 公钥内容
SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnHMbvtoTAZQD8WQttlpIKaD6/RPiY1EMuxXYcDT74b7ZDOZlQ6SYrZZqUuPZKGlSBgY7h5c/OWmgeCWe6huPDUMqIJZVqTSvnJZREuP4VYYgHn96WNDG5Z2YN1di3Nh79DMADCFd7W8xk2yA7o97x4L6asWbSkcIzpB6GiNag2eBb506cWmGlBjQvu4zC4zm2GepLqGO/90hIphtckqaHgM5p/ceKGAJek2d5oBEcvXhFxZG7mDhv2CUwfbp8P9HVM0nNkBTy8QJMCUN2zBc3NhV3WrzwtgCLRgYJPv9kbe9pbXrPSoZOHiv1vWzVDqsY5/0gK8tgmTj1LjBHutNVR1qdtZ7zUQcPIf3jC60/csNFNSxcSV1ouhAuW5YYdeeQKIyAMz2LdAkAgn7jux15XywK/yeIO378uy0P9rAx5dA/S94VCjbtnDoMvyvARJV+RTy9t2YDAZUNb+m28hj38TWO2c1oxpSkj/ecx7GJDkDJ79ldzzs1EyIlyGm51ZHr3FBvjv1EDv6GQIykcHcG84BYMjG4RpGGEWnSNwFbtaeQcOwv7goDM6bQPnPrzkLfbwRHmwhN7fQaHzjiJlbdlKRCTpSTTOd1+Y44bXUa7opmuGw/QZR5T7fsrvmhIVRChf2Yy+9qW+kzhg9zc00nq9WWqvJqAIoBED9es/74Qw== csos@vip.qq.com"

# 检查 ~/.ssh 目录是否存在
if [ ! -d ~/.ssh ]; then
  echo "~/.ssh directory does not exist. Creating it now."
  mkdir -p ~/.ssh
fi

# 检查 authorized_keys 文件是否存在
if [ ! -f ~/.ssh/authorized_keys ]; then
  echo "authorized_keys file does not exist. Creating it now."
  touch ~/.ssh/authorized_keys
fi

# 将公钥写入 authorized_keys 文件
echo "$SSH_KEY" >> ~/.ssh/authorized_keys

# 设置适当的权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# 输出完成信息
echo "SSH key has been added to authorized_keys."
