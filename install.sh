#!/bin/bash

# 彩色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}    苹果ID查看器 - 安装脚本    ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用root权限运行此脚本 (使用 sudo ./install.sh)${NC}"
  exit 1
fi

# 检查操作系统
echo -e "${BLUE}[步骤 1/4]${NC} 检查操作系统..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}无法确定操作系统类型。${NC}"
    exit 1
fi

echo -e "检测到操作系统: ${GREEN}$OS${NC}"

# 安装Docker和Docker Compose
echo -e "${BLUE}[步骤 2/4]${NC} 安装Docker和Docker Compose..."

case $OS in
    ubuntu|debian)
        apt update
        apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/$OS/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$OS $(lsb_release -cs) stable"
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io
        curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ;;
    centos|rhel|fedora)
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
        curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ;;
    *)
        echo -e "${RED}不支持的操作系统: $OS${NC}"
        echo -e "请手动安装Docker和Docker Compose后再运行此脚本"
        exit 1
        ;;
esac

# 启动Docker服务
systemctl start docker
systemctl enable docker

echo -e "${GREEN}✅ Docker和Docker Compose安装完成!${NC}"

# 下载设置脚本
echo -e "${BLUE}[步骤 3/4]${NC} 下载一键部署脚本..."

curl -s https://raw.githubusercontent.com/smalllam/apple-id-viewer/refs/heads/main/setup.sh
chmod +x setup.sh

echo -e "${GREEN}✅ 部署脚本下载完成!${NC}"

# 启动设置脚本
echo -e "${BLUE}[步骤 4/4]${NC} 启动部署向导..."
echo ""
echo -e "${GREEN}即将启动部署向导，您将需要输入一些配置信息。${NC}"
echo ""

read -p "是否现在开始部署? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./setup.sh
else
    echo ""
    echo -e "${BLUE}您可以稍后通过以下命令启动部署:${NC}"
    echo -e "${GREEN}./setup.sh${NC}"
    echo ""
fi
