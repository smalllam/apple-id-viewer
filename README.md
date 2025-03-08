# apple-id-viewer
# 苹果ID查看器 - 一键部署方案

这是一个简单易用的苹果ID查看器系统，提供一键部署功能，让您无需复杂的技术知识即可轻松架设自己的苹果ID查看服务。

## 特性

- 🚀 **一键部署**：只需一行命令即可完成安装和配置
- 🔄 **自动更新**：每小时自动从源API获取最新数据
- 💾 **多级缓存**：数据库和文件系统双重缓存保障
- 🛡️ **高可用性**：即使源API不可用也能提供服务
- 📱 **响应式设计**：完美支持电脑和手机浏览
- 🛠️ **可定制化**：支持自定义API源和数据库配置

## 系统架构

- **前端**：HTML + CSS + JavaScript
- **后端**：Node.js + Express
- **数据库**：MySQL
- **Web服务器**：Nginx
- **容器化**：Docker & Docker Compose

## 一键部署

### 方法一：使用自动安装脚本（推荐）

```bash
# 下载并执行安装脚本
curl -fsSL https://raw.githubusercontent.com/yourusername/apple-id-viewer/main/install.sh | sudo bash
```

### 方法二：手动安装

```bash
# 1. 确保已安装Docker和Docker Compose
# 2. 下载部署脚本
wget https://raw.githubusercontent.com/yourusername/apple-id-viewer/main/setup.sh
chmod +x setup.sh

# 3. 运行部署脚本
./setup.sh
```

## 自定义配置

在运行部署脚本过程中，您可以自定义以下参数：

- **网站访问端口**：默认为80
- **数据库root密码**：默认随机生成
- **数据库用户名**：默认为apple_id_user
- **数据库密码**：默认随机生成
- **数据库名**：默认为apple_id_db
- **原始API URL**：默认为官方API

## 系统管理

### 查看容器状态

```bash
cd apple-id-viewer
docker-compose ps
```

### 查看日志

```bash
# 查看所有日志
docker-compose logs

# 查看特定服务日志
docker-compose logs nodejs
docker-compose logs nginx
docker-compose logs mysql
```

### 重启服务

```bash
docker-compose restart
```

### 停止服务

```bash
docker-compose down
```

### 更新配置

修改`docker-compose.yml`文件后，重新启动服务：

```bash
docker-compose down
docker-compose up -d
```

## 常见问题

**Q: 部署后无法访问网站怎么办？**
A: 检查服务器防火墙是否开放了配置的端口。如使用云服务器，还需检查安全组设置。

**Q: 数据无法从API获取怎么办？**
A: 检查API URL是否正确，以及API是否可以正常访问。可以运行`curl [API URL]`测试API连接。

**Q: 如何备份数据？**
A: 数据存储在Docker卷中，可以使用以下命令导出数据库：
```bash
docker exec apple-id-mysql mysqldump -u root -p[ROOT密码] apple_id_db > backup.sql
```

## 技术支持与反馈

如有任何问题或建议，请通过以下方式联系我们：

- GitHub Issues: [提交问题](https://github.com/yourusername/apple-id-viewer/issues)
- 电子邮件: your-email@example.com

## 许可证

MIT License
