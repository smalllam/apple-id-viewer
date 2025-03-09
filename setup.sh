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
echo -e "${BLUE}[步骤 1/7]${NC} 检查环境..."

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
echo -e "${BLUE}[步骤 2/7]${NC} 创建项目目录..."
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
mkdir -p mysql/mysql/init

echo -e "${GREEN}✅ 目录创建完成!${NC}"

# 收集配置信息
echo -e "${BLUE}[步骤 3/7]${NC} 配置系统参数..."

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
echo -e "${BLUE}[步骤 4/7]${NC} 生成Docker配置文件..."

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
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

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
      - ./mysql/mysql/init:/docker-entrypoint-initdb.d
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p$DB_ROOT_PASSWORD"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

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
RUN apk add --no-cache wget

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

# 创建MySQL初始化脚本
cat > mysql/mysql/init/init.sql << EOF
CREATE TABLE IF NOT EXISTS accounts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(255) NOT NULL,
  password VARCHAR(255) NOT NULL,
  country VARCHAR(50) NOT NULL,
  check_time DATETIME NOT NULL,
  status VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS metadata (
  id INT AUTO_INCREMENT PRIMARY KEY,
  key_name VARCHAR(50) UNIQUE NOT NULL,
  value TEXT NOT NULL,
  updated_at DATETIME NOT NULL
);
EOF

echo -e "${GREEN}✅ 配置文件生成完成!${NC}"

# 创建应用代码
echo -e "${BLUE}[步骤 5/7]${NC} 创建API代码..."

# 创建app.js文件
cat > api/app.js << EOF
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const schedule = require('node-schedule');

const app = express();
const PORT = process.env.PORT || 3000;

// 中间件配置
app.use(express.json());
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// 配置
const CONFIG = {
  ORIGINAL_API_URL: process.env.ORIGINAL_API_URL || 'https://apple-id.small-lam1814.workers.dev/api/accounts',
  CACHE_FILE_PATH: path.join(__dirname, 'cache', 'accounts_data.json'),
  CACHE_TTL: 60 * 60 * 1000, // 缓存有效期（1小时，毫秒）
  API_TIMEOUT: 5000, // API请求超时时间（毫秒）
  
  // 数据库配置 - 使用环境变量
  DB: {
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'apple_id_user',
    password: process.env.DB_PASSWORD || 'secure_password',
    database: process.env.DB_NAME || 'apple_id_db'
  }
};

// 确保缓存目录存在
if (!fs.existsSync(path.dirname(CONFIG.CACHE_FILE_PATH))) {
  fs.mkdirSync(path.dirname(CONFIG.CACHE_FILE_PATH), { recursive: true });
}

// 创建数据库连接池
const pool = mysql.createPool(CONFIG.DB);

// 初始化数据库表 - 增强版本
async function initDatabase() {
  let retries = 20;
  while (retries > 0) {
    try {
      console.log(\`尝试初始化数据库 (尝试 \${21-retries}/20)...\`);
      const connection = await pool.getConnection();
      
      // 创建账号数据表
      await connection.execute(\`
        CREATE TABLE IF NOT EXISTS accounts (
          id INT AUTO_INCREMENT PRIMARY KEY,
          username VARCHAR(255) NOT NULL,
          password VARCHAR(255) NOT NULL,
          country VARCHAR(50) NOT NULL,
          check_time DATETIME NOT NULL,
          status VARCHAR(50) NOT NULL
        )
      \`);
      
      // 创建元数据表
      await connection.execute(\`
        CREATE TABLE IF NOT EXISTS metadata (
          id INT AUTO_INCREMENT PRIMARY KEY,
          key_name VARCHAR(50) UNIQUE NOT NULL,
          value TEXT NOT NULL,
          updated_at DATETIME NOT NULL
        )
      \`);
      
      connection.release();
      console.log('数据库初始化成功');
      return true;
    } catch (error) {
      console.error(\`数据库初始化尝试失败 (剩余 \${retries} 次): \${error.message}\`);
      retries--;
      // Wait 5 seconds before retry
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
  }
  console.error('数据库初始化失败，已达到最大重试次数');
  return false;
}

// 从原始API获取数据
async function fetchFromOriginalApi() {
  try {
    console.log('正在从原始API获取数据...');
    console.log('API URL:', CONFIG.ORIGINAL_API_URL);
    
    const response = await axios.get(CONFIG.ORIGINAL_API_URL, {
      timeout: CONFIG.API_TIMEOUT
    });
    
    if (response.status !== 200) {
      throw new Error(\`API返回错误状态: \${response.status}\`);
    }
    
    const data = response.data;
    
    // 添加时间戳（如果原始API没有提供）
    return {
      accounts: data.accounts || data, // 适应不同的API响应格式
      timestamp: data.timestamp || new Date().toISOString()
    };
  } catch (error) {
    console.error('从原始API获取数据失败:', error.message);
    throw error;
  }
}

// 将数据保存到数据库
async function saveToDatabase(data) {
  const connection = await pool.getConnection();
  
  try {
    await connection.beginTransaction();
    
    // 清空账号表
    await connection.execute('TRUNCATE TABLE accounts');
    
    // 插入新账号数据
    for (const account of data.accounts) {
      await connection.execute(
        'INSERT INTO accounts (username, password, country, check_time, status) VALUES (?, ?, ?, ?, ?)',
        [
          account.username,
          account.password,
          account.country,
          new Date(account.checkTime), // 假设checkTime是ISO格式的日期字符串
          account.status
        ]
      );
    }
    
    // 更新元数据
    await connection.execute(
      'INSERT INTO metadata (key_name, value, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = ?, updated_at = ?',
      [
        'last_update',
        JSON.stringify({ timestamp: data.timestamp }),
        new Date(),
        JSON.stringify({ timestamp: data.timestamp }),
        new Date()
      ]
    );
    
    await connection.commit();
    console.log('数据成功保存到数据库');
    return true;
  } catch (error) {
    await connection.rollback();
    console.error('保存数据到数据库失败:', error);
    return false;
  } finally {
    connection.release();
  }
}

// 将数据保存到文件缓存
function saveToFileCache(data) {
  try {
    const dataToCache = {
      ...data,
      cachedAt: new Date().toISOString()
    };
    
    fs.writeFileSync(CONFIG.CACHE_FILE_PATH, JSON.stringify(dataToCache, null, 2));
    console.log('数据已成功存储到文件缓存');
    return true;
  } catch (error) {
    console.error('存储到文件缓存失败:', error);
    return false;
  }
}

// 从数据库获取数据
async function getFromDatabase() {
  try {
    const connection = await pool.getConnection();
    
    // 获取账号数据
    const [accounts] = await connection.execute('SELECT username, password, country, check_time as checkTime, status FROM accounts');
    
    // 获取最后更新时间
    const [metadataRows] = await connection.execute('SELECT value FROM metadata WHERE key_name = ?', ['last_update']);
    
    connection.release();
    
    if (accounts.length === 0) {
      console.log('数据库中没有账号数据');
      return null;
    }
    
    // 格式化日期
    accounts.forEach(account => {
      if (account.checkTime instanceof Date) {
        account.checkTime = account.checkTime.toISOString().replace('T', ' ').substring(0, 19);
      }
    });
    
    let timestamp = new Date().toISOString();
    if (metadataRows.length > 0) {
      const metadata = JSON.parse(metadataRows[0].value);
      timestamp = metadata.timestamp || timestamp;
    }
    
    console.log('成功从数据库获取数据');
    return {
      accounts,
      timestamp
    };
  } catch (error) {
    console.error('从数据库获取数据失败:', error);
    return null;
  }
}

// 从文件缓存获取数据
function getFromFileCache() {
  try {
    if (!fs.existsSync(CONFIG.CACHE_FILE_PATH)) {
      console.log('文件缓存不存在');
      return null;
    }
    
    const fileData = fs.readFileSync(CONFIG.CACHE_FILE_PATH, 'utf8');
    const cachedData = JSON.parse(fileData);
    
    // 检查缓存是否过期
    const cachedAt = new Date(cachedData.cachedAt);
    const now = new Date();
    if (now - cachedAt > CONFIG.CACHE_TTL) {
      console.log('文件缓存已过期');
      return null;
    }
    
    console.log('成功从文件缓存获取数据');
    return cachedData;
  } catch (error) {
    console.error('从文件缓存获取数据失败:', error);
    return null;
  }
}

// 获取示例数据
function getSampleData() {
  return {
    accounts: [
      {
        username: 'jebnslz90o68zdz@hotmail.com',
        password: 'Password123',
        country: '美国',
        checkTime: '2025-02-25 19:05:45',
        status: '正常'
      },
      {
        username: 'e0vg8xlw@qq.com',
        password: 'Password456',
        country: '美国',
        checkTime: '2025-02-25 19:05:45',
        status: '正常'
      },
      {
        username: 'alejandromepc63@gmail.com',
        password: 'Password789',
        country: '美国',
        checkTime: '2025-02-25 19:05:48',
        status: '正常'
      }
    ],
    timestamp: new Date().toISOString()
  };
}

// 获取账户数据的主函数
async function getAccountsData() {
  try {
    // 1. 尝试从原始API获取数据
    try {
      const apiData = await fetchFromOriginalApi();
      // 保存数据到数据库和文件缓存
      await saveToDatabase(apiData);
      saveToFileCache(apiData);
      return { ...apiData, source: 'api' };
    } catch (error) {
      console.log('将尝试从数据库获取缓存数据...');
    }
    
    // 2. 尝试从数据库获取数据
    const dbData = await getFromDatabase();
    if (dbData) {
      return { ...dbData, source: 'database' };
    }
    
    // 3. 尝试从文件缓存获取数据
    const fileData = getFromFileCache();
    if (fileData) {
      return { ...fileData, source: 'file_cache' };
    }
    
    // 4. 使用示例数据
    return { ...getSampleData(), source: 'sample' };
  } catch (error) {
    console.error('获取账户数据失败:', error);
    return { ...getSampleData(), source: 'sample', error: error.message };
  }
}

// API路由
app.get('/api/accounts', async (req, res) => {
  try {
    const data = await getAccountsData();
    res.json(data);
  } catch (error) {
    console.error('获取账号数据失败:', error);
    res.status(500).json({
      error: '获取账号数据失败',
      message: error.message,
      accounts: getSampleData().accounts,
      timestamp: new Date().toISOString(),
      source: 'sample'
    });
  }
});

// 手动触发数据更新
app.post('/api/scrape', async (req, res) => {
  try {
    // 强制从原始API获取新数据
    const apiData = await fetchFromOriginalApi();
    
    // 保存数据到数据库和文件缓存
    const dbSaveResult = await saveToDatabase(apiData);
    const fileSaveResult = saveToFileCache(apiData);
    
    res.json({
      success: true,
      message: '数据更新成功',
      databaseSaved: dbSaveResult,
      fileCacheSaved: fileSaveResult,
      timestamp: apiData.timestamp
    });
  } catch (error) {
    console.error('更新数据失败:', error);
    res.status(500).json({
      success: false,
      error: '更新数据失败',
      message: error.message
    });
  }
});

// 健康检查端点
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    config: {
      api_url: CONFIG.ORIGINAL_API_URL,
      db_host: CONFIG.DB.host,
      db_name: CONFIG.DB.database
    }
  });
});

// 设置定时任务，每小时更新一次数据
schedule.scheduleJob('0 * * * *', async function() {
  console.log('开始执行定时数据更新...');
  try {
    const apiData = await fetchFromOriginalApi();
    await saveToDatabase(apiData);
    saveToFileCache(apiData);
    console.log('定时数据更新成功');
  } catch (error) {
    console.error('定时数据更新失败:', error);
  }
});

// 初始化服务器
async function initServer() {
  try {
    // 启动服务器
    app.listen(PORT, () => {
      console.log(\`API服务器运行在 http://localhost:\${PORT}\`);
      console.log('配置信息:');
      console.log('- 原始API URL:', CONFIG.ORIGINAL_API_URL);
      console.log('- 数据库主机:', CONFIG.DB.host);
      console.log('- 数据库名称:', CONFIG.DB.database);
      console.log('- 数据库用户:', CONFIG.DB.user);
    });
    
    // 等待MySQL准备就绪（多次尝试）
    console.log('等待数据库准备就绪...');
    let dbInitialized = false;
    let attempts = 30; // 30次尝试，每次5秒，最多等待150秒
    
    while (!dbInitialized && attempts > 0) {
      try {
        dbInitialized = await initDatabase();
        if (dbInitialized) break;
      } catch (error) {
        console.error(\`数据库初始化尝试失败 (剩余 \${attempts} 次): \${error.message}\`);
      }
      
      attempts--;
      if (!dbInitialized && attempts > 0) {
        console.log(\`将在5秒后重试...剩余 \${attempts} 次尝试\`);
        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    }
    
    if (!dbInitialized) {
      console.error('无法初始化数据库，但应用将继续运行并使用文件缓存');
    }
    
    // 服务启动后加载初始数据
    try {
      console.log('初始化数据...');
      const apiData = await fetchFromOriginalApi();
      
      if (dbInitialized) {
        await saveToDatabase(apiData);
      }
      
      saveToFileCache(apiData);
      console.log('初始数据获取成功');
    } catch (error) {
      console.error('初始数据获取失败:', error);
    }
  } catch (error) {
    console.error('服务器初始化失败:', error);
  }
}

// 启动服务器
initServer();
EOF

# 创建前端文件
echo -e "${BLUE}[步骤 6/7]${NC} 创建前端代码..."

# 创建index.html文件
cat > frontend/index.html << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>苹果ID查看器</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.0/css/bootstrap.min.css">
    <style>
        body {
            font-family: 'PingFang SC', 'Microsoft YaHei', sans-serif;
            background-color: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            padding: 20px;
        }
        .card {
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
            border-left: 4px solid #4caf50;
            background-color: white;
            transition: transform 0.2s ease;
        }
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
        }
        .card-body {
            padding: 20px;
        }
        .card-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 15px;
            color: #333;
        }
        .badge {
            font-size: 12px;
            padding: 5px 10px;
            border-radius: 4px;
        }
        .btn {
            margin-right: 10px;
            margin-bottom: 10px;
            border-radius: 4px;
            padding: 6px 12px;
        }
        .btn-primary {
            background-color: #2196f3;
            border-color: #2196f3;
        }
        .btn-success {
            background-color: #4caf50;
            border-color: #4caf50;
        }
        .accounts-container {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 20px;
        }
        @media (max-width: 768px) {
            .accounts-container {
                grid-template-columns: 1fr;
            }
        }
        #alertBox {
            display: none;
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px;
            background-color: #4caf50;
            color: white;
            border-radius: 4px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.2);
            z-index: 1000;
        }
        .loading {
            text-align: center;
            padding: 40px;
            font-size: 18px;
            color: #666;
        }
        .loading-spinner {
            display: inline-block;
            width: 40px;
            height: 40px;
            margin-bottom: 10px;
            border: 4px solid rgba(0, 0, 0, 0.1);
            border-radius: 50%;
            border-top-color: #2196f3;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        .refresh-btn {
            background-color: #2196f3;
            color: white;
            border: none;
            border-radius: 4px;
            padding: 6px 12px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>苹果ID账号查看器</h2>
            <div>
                上次更新: <span id="updateTimestamp">加载中...</span>
                <button id="refreshBtn" class="refresh-btn">刷新</button>
            </div>
        </div>
        
        <div class="alert alert-warning">
            <strong>⚠️ 注意:</strong> 这些账号仅供在 App Store 内使用，请勿在设置中登录！
        </div>
        
        <div class="accounts-container" id="accountsContainer">
            <!-- 账号卡片将在此动态生成 -->
            <div class="loading">
                <div class="loading-spinner"></div>
                <p>正在加载账号数据...</p>
            </div>
        </div>
    </div>
    
    <div id="alertBox"></div>
    
    <script>
        // DOM 元素
        const accountsContainer = document.getElementById('accountsContainer');
        const alertBox = document.getElementById('alertBox');
        const refreshBtn = document.getElementById('refreshBtn');
        const updateTimestamp = document.getElementById('updateTimestamp');
        
        // 变量
        let isRefreshing = false;
        
        // 显示提示框函数
        function showAlert(message, type = 'success') {
            alertBox.textContent = message;
            alertBox.style.display = 'block';
            
            if (type === 'success') {
                alertBox.style.backgroundColor = '#4caf50';
            } else if (type === 'error') {
                alertBox.style.backgroundColor = '#f44336';
            } else if (type === 'warning') {
                alertBox.style.backgroundColor = '#ff9800';
            }
            
            setTimeout(() => {
                alertBox.style.display = 'none';
            }, 3000);
        }
        
        // 复制到剪贴板函数
        function copyToClipboard(text) {
            navigator.clipboard.writeText(text)
                .then(() => {
                    showAlert('复制成功');
                })
                .catch(err => {
                    console.error('复制失败:', err);
                    showAlert('复制失败，请手动复制', 'error');
                });
        }
        
        // 显示账号
        function displayAccounts(accounts) {
            accountsContainer.innerHTML = '';
            
            accounts.forEach(account => {
                const card = document.createElement('div');
                card.className = 'card';
                
                card.innerHTML = \`
                    <div class="card-body">
                        <h3 class="card-title">账号信息</h3>
                        <div>\${account.username} <span class="badge bg-primary">\${account.country}</span></div>
                        <p>账号信息:</p>
                        <p>上次检查: \${account.checkTime}</p>
                        <p>状态: <span class="badge bg-success">\${account.status}</span></p>
                        <div>
                            <button class="btn btn-primary" onclick="copyToClipboard('\${account.username}')">复制账号</button>
                            <button class="btn btn-success" onclick="copyToClipboard('\${account.password}')">复制密码</button>
                        </div>
                    </div>
                \`;
                
                accountsContainer.appendChild(card);
            });
        }
        
        // 格式化日期时间
        function formatDateTime(dateTimeStr) {
            const date = new Date(dateTimeStr);
            return date.toLocaleString('zh-CN');
        }
        
        // 从API获取账号数据
        function fetchAccountsData() {
            fetch('/api/accounts')
                .then(response => response.json())
                .then(data => {
                    updateTimestamp.textContent = formatDateTime(data.timestamp);
                    displayAccounts(data.accounts);
                })
                .catch(error => {
                    console.error('获取数据失败:', error);
                    accountsContainer.innerHTML = '<div class="alert alert-danger">获取数据失败，请稍后再试</div>';
                });
        }
        
        // 初始化应用
        function initApp() {
            // 获取数据
            fetchAccountsData();
            
            // 刷新按钮点击事件处理程序
            refreshBtn.addEventListener('click', () => {
                if (!isRefreshing) {
                    isRefreshing = true;
                    refreshBtn.textContent = '刷新中...';
                    refreshBtn.disabled = true;
                    
                    fetch('/api/scrape', {
                        method: 'POST'
                    })
                    .then(response => response.json())
                    .then(data => {
                        showAlert('数据刷新成功', 'success');
                        fetchAccountsData();
                    })
                    .catch(error => {
                        console.error('刷新失败:', error);
                        showAlert('刷新失败', 'error');
                    })
                    .finally(() => {
                        isRefreshing = false;
                        refreshBtn.textContent = '刷新';
                        refreshBtn.disabled = false;
                    });
                }
            });
        }
        
        // 页面加载后初始化应用
        document.addEventListener('DOMContentLoaded', initApp);
    </script>
</body>
</html>
EOF

echo -e "${GREEN}✅ 前端代码创建完成!${NC}"

# 启动Docker容器
echo -e "${BLUE}[步骤 7/7]${NC} 启动服务..."

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
