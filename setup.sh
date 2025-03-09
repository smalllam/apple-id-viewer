#!/bin/bash

# 彩色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}    苹果ID查看器 - 一键部署脚本    ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 检查Docker和Docker Compose是否已安装
echo -e "${BLUE}[步骤 1/6]${NC} 检查环境..."

if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker未安装。请先安装Docker: https://docs.docker.com/get-docker/${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}错误: Docker Compose未安装。请先安装Docker Compose: https://docs.docker.com/compose/install/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 环境检查通过!${NC}"

# 创建配置文件目录
echo -e "${BLUE}[步骤 2/6]${NC} 创建项目目录..."
PROJECT_DIR="apple-id-viewer"

# 检查目录是否已存在
if [ -d "$PROJECT_DIR" ]; then
    echo -e "${RED}警告: $PROJECT_DIR 目录已存在。${NC}"
    read -p "是否继续并覆盖已有文件? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}部署取消。${NC}"
        exit 1
    fi
else
    mkdir -p "$PROJECT_DIR"
fi

# 进入项目目录
cd "$PROJECT_DIR"

# 创建子目录
mkdir -p api/cache
mkdir -p frontend
mkdir -p nginx/ssl

echo -e "${GREEN}✅ 目录创建完成!${NC}"

# 收集配置信息
echo -e "${BLUE}[步骤 3/6]${NC} 配置系统参数..."

# 设置默认值
DEFAULT_PORT="80"
DEFAULT_DB_ROOT_PASSWORD=$(openssl rand -hex 8)
DEFAULT_DB_PASSWORD=$(openssl rand -hex 8)
DEFAULT_DB_USER="apple_id_user"
DEFAULT_DB_NAME="apple_id_db"
DEFAULT_API_URL="https://apple-id.small-lam1814.workers.dev/api/accounts"

# 收集配置
read -p "请输入网站访问端口 [默认: $DEFAULT_PORT]: " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -p "请输入数据库root密码 [默认: $DEFAULT_DB_ROOT_PASSWORD]: " DB_ROOT_PASSWORD
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-$DEFAULT_DB_ROOT_PASSWORD}

read -p "请输入数据库用户名 [默认: $DEFAULT_DB_USER]: " DB_USER
DB_USER=${DB_USER:-$DEFAULT_DB_USER}

read -p "请输入数据库密码 [默认: $DEFAULT_DB_PASSWORD]: " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}

read -p "请输入数据库名 [默认: $DEFAULT_DB_NAME]: " DB_NAME
DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

read -p "请输入原始API URL [默认: $DEFAULT_API_URL]: " API_URL
API_URL=${API_URL:-$DEFAULT_API_URL}

echo -e "${GREEN}✅ 参数配置完成!${NC}"

# 创建Docker Compose配置文件
echo -e "${BLUE}[步骤 4/6]${NC} 生成Docker配置文件..."

# 修改这段代码
cat > docker-compose.yml << EOF
version: '3'

services:
  # Node.js API服务
  nodejs:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: apple-id-api
    restart: always
    environment:
      - DB_HOST=mysql
      - DB_USER=$DB_USER
      - DB_PASSWORD=$DB_PASSWORD
      - DB_NAME=$DB_NAME
      - PORT=3000
      - ORIGINAL_API_URL=$API_URL
    volumes:
      - ./api:/app
      - /app/node_modules
    depends_on:
      mysql:
        condition: service_healthy
    networks:
      - app-network

  # MySQL数据库
  mysql:
    image: mysql:8.0
    container_name: apple-id-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $DB_ROOT_PASSWORD
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_PASSWORD: $DB_PASSWORD
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u$DB_USER", "-p$DB_PASSWORD"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 15s

  # Nginx服务器
  nginx:
    image: nginx:alpine
    container_name: apple-id-nginx
    restart: always
    ports:
      - "$PORT:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./frontend:/usr/share/nginx/html
    depends_on:
      - nodejs
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  mysql-data:
EOF

# 创建Nginx配置
cat > nginx/default.conf << EOF
server {
    listen 80;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html index.htm;

    # API请求代理到Node.js
    location /api/ {
        proxy_pass http://nodejs:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }

    # 静态文件处理
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

# 创建Node.js Dockerfile
cat > api/Dockerfile << EOF
FROM node:18-alpine

WORKDIR /app

# 复制package.json和package-lock.json
COPY package*.json ./

# 安装依赖
RUN npm install

# 复制源代码
COPY . .

# 创建缓存目录
RUN mkdir -p /app/cache && chmod 755 /app/cache

# 暴露端口
EXPOSE 3000

# 启动应用
CMD ["node", "app.js"]
EOF

# 创建package.json
cat > api/package.json << EOF
{
  "name": "apple-id-service",
  "version": "1.0.0",
  "description": "Apple ID账号服务",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "axios": "^1.6.2",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "mysql2": "^3.6.5",
    "node-schedule": "^2.1.1"
  }
}
EOF

echo -e "${GREEN}✅ 配置文件生成完成!${NC}"

# 下载应用代码
echo -e "${BLUE}[步骤 5/6]${NC} 下载应用代码..."

# 下载app.js文件
curl -s https://raw.githubusercontent.com/smalllam/apple-id-viewer/refs/heads/main/main/app.js -o api/app.js

# 下载前端文件
curl -s https://raw.githubusercontent.com/smalllam/apple-id-viewer/refs/heads/main/main/index.html -o frontend/index.html

echo -e "${GREEN}✅ 应用代码下载完成!${NC}"

# 启动Docker容器
echo -e "${BLUE}[步骤 6/6]${NC} 启动服务..."

docker-compose up -d

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 部署成功! 🎉${NC}"
    echo ""
    echo -e "您的苹果ID查看器已成功部署，可以通过以下地址访问:"
    
    # 获取服务器IP地址
    SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "localhost")
    
    echo -e "${BLUE}http://$SERVER_IP:$PORT${NC}"
    echo ""
    echo -e "数据库信息:"
    echo -e "数据库类型: MySQL"
    echo -e "数据库名: ${BLUE}$DB_NAME${NC}"
    echo -e "用户名: ${BLUE}$DB_USER${NC}"
    echo -e "密码: ${BLUE}$DB_PASSWORD${NC}"
    echo -e "Root密码: ${BLUE}$DB_ROOT_PASSWORD${NC}"
    echo ""
    echo -e "请保存好以上信息!"
    echo ""
    echo -e "${GREEN}系统将自动从API获取数据，并每小时自动更新一次。${NC}"
    echo ""
else
    echo -e "${RED}❌ 部署失败。请检查错误日志。${NC}"
    echo -e "您可以尝试运行以下命令查看详细日志:"
    echo -e "${BLUE}cd $PROJECT_DIR && docker-compose logs${NC}"
fi
