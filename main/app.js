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

// 初始化数据库表
async function initDatabase() {
  try {
    const connection = await pool.getConnection();
    
    // 创建账号数据表
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS accounts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(255) NOT NULL,
        password VARCHAR(255) NOT NULL,
        country VARCHAR(50) NOT NULL,
        check_time DATETIME NOT NULL,
        status VARCHAR(50) NOT NULL
      )
    `);
    
    // 创建元数据表
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS metadata (
        id INT AUTO_INCREMENT PRIMARY KEY,
        key_name VARCHAR(50) UNIQUE NOT NULL,
        value TEXT NOT NULL,
        updated_at DATETIME NOT NULL
      )
    `);
    
    connection.release();
    console.log('数据库初始化成功');
    return true;
  } catch (error) {
    console.error('数据库初始化失败:', error);
    throw error;
  }
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
      throw new Error(`API返回错误状态: ${response.status}`);
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
      console.log(`API服务器运行在 http://localhost:${PORT}`);
      console.log('配置信息:');
      console.log('- 原始API URL:', CONFIG.ORIGINAL_API_URL);
      console.log('- 数据库主机:', CONFIG.DB.host);
      console.log('- 数据库名称:', CONFIG.DB.database);
      console.log('- 数据库用户:', CONFIG.DB.user);
    });
    
    // 延迟10秒后初始化数据库，确保MySQL完全启动
    console.log('等待10秒，确保数据库准备就绪...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    // 添加重试逻辑
    let retryCount = 0;
    const maxRetries = 5;

    while (retryCount < maxRetries) {
      try {
        // 初始化数据库
        await initDatabase();
        console.log('数据库初始化成功');
        break; // 成功则退出循环
      } catch (error) {
        retryCount++;
        console.error(`数据库初始化失败 (尝试 ${retryCount}/${maxRetries}):`, error);
        
        if (retryCount >= maxRetries) {
          console.error('达到最大重试次数，将使用文件缓存继续运行');
        } else {
          // 等待5秒后重试
          console.log(`等待5秒后重试...`);
          await new Promise(resolve => setTimeout(resolve, 5000));
        }
      }
    }
    
    // 服务启动后立即尝试获取数据
    try {
      console.log('初始化数据...');
      const apiData = await fetchFromOriginalApi();
      
      // 再次尝试保存数据到数据库，即使之前的初始化可能失败
      try {
        await saveToDatabase(apiData);
      } catch (dbError) {
        console.error('保存到数据库失败，将只使用文件缓存:', dbError);
      }
      
      // 文件缓存通常更可靠，总是尝试保存
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
