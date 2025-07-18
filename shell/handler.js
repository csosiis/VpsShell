root@sanjose:~/sub-store/data# cat handler.js
// 引入所需模块
const http = require('http');
const fs = require('fs').promises;
const { exec } = require('child_process');

// --- 配置区 ---
const PORT = 8443;
const TARGET_FILE_PATH = '/root/sub-store/sub-store.json';
const SERVICE_TO_RESTART = 'sub-store.service';
const SECRET_TOKEN = 'sanjose';

// 远程服务器配置
const REMOTE_SERVER_USER = 'ubuntu';
const REMOTE_SERVER_IP = '79.72.72.95';
const REMOTE_TARGET_PATH = '/root/sub-store/';
const IDENTITY_FILE_PATH = '/root/.ssh/server';
// --- 配置区结束 ---

function executeCommand(command) {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`❌ 执行命令时出错: ${command}`);
        console.error(`   错误信息: ${stderr}`);
        reject(error);
        return;
      }
      console.log(`✅ 命令成功执行: ${command}`);
      if (stdout) { console.log(`   输出: ${stdout.trim()}`); }
      resolve(stdout);
    });
  });
}

async function handleUpdateRequest(requestData) {
  const { name, link } = requestData;

  if (!name || typeof link === 'undefined') {
    throw new Error('请求数据中缺少 "name" 或 "link" 字段。');
  }

  // 步骤 1: 更新本地文件
  const fileContent = await fs.readFile(TARGET_FILE_PATH, 'utf8');
  const mainObject = JSON.parse(fileContent);
  if (!Array.isArray(mainObject.subs)) { throw new Error(`在 ${TARGET_FILE_PATH} 中未找到 "subs" 数组。`); }
  let itemFound = false;
  mainObject.subs = mainObject.subs.map(item => {
    if (item.name === name) {
      itemFound = true;
      return { ...item, content: link };
    }
    return item;
  });
  if (!itemFound) { throw new Error(`在 "subs" 数组中未找到 name 为 "${name}" 的订阅。`); }
  const updatedJsonContent = JSON.stringify(mainObject, null, 2);
  await fs.writeFile(TARGET_FILE_PATH, updatedJsonContent, 'utf8');
  console.log(`✅ 步骤 1/4: 本地文件 ${TARGET_FILE_PATH} 更新成功。`);

  try {
    // 步骤 2: 重启本地服务
    console.log(`⏳ 步骤 2/4: 正在重启本地的 ${SERVICE_TO_RESTART}...`);
    await executeCommand(`systemctl restart ${SERVICE_TO_RESTART}`);
    console.log(`👍 步骤 2/4: 本地服务重启成功。`);

    // 步骤 3: 使用 rsync 同步文件到远程服务器
    const remoteServer = `${REMOTE_SERVER_USER}@${REMOTE_SERVER_IP}`;
    const sshOptions = `-o 'StrictHostKeyChecking=no'`; // 新增！SSH 非交互式选项
    console.log(`⏳ 步骤 3/4: 正在使用 rsync 同步文件到 ${remoteServer}...`);
    // 修正！在 ssh 命令中加入 sshOptions
    const rsyncCommand = `rsync -avzP -e "ssh -i ${IDENTITY_FILE_PATH} ${sshOptions}" --rsync-path="sudo rsync" ${TARGET_FILE_PATH} ${remoteServer}:${REMOTE_TARGET_PATH}`;
    await executeCommand(rsyncCommand);
    console.log(`👍 步骤 3/4: 文件同步成功。`);

    // 步骤 4: 重启远程服务器上的服务
    console.log(`⏳ 步骤 4/4: 正在重启远程服务器上的 ${SERVICE_TO_RESTART}...`);
    // 修正！在 ssh 命令中加入 sshOptions
    const sshCommand = `ssh -i ${IDENTITY_FILE_PATH} ${sshOptions} ${remoteServer} "sudo systemctl restart ${SERVICE_TO_RESTART}"`;
    await executeCommand(sshCommand);
    console.log(`👍 步骤 4/4: 远程服务重启成功。`);

  } catch (error) {
    throw new Error(`文件更新成功，但后续操作失败: ${error.message}`);
  }
}

// HTTP 服务器部分保持不变...
const server = http.createServer(async (req, res) => {
    if (req.method === 'POST' && req.url === '/') {
        let body = '';
        req.on('data', chunk => { body += chunk.toString(); });
        req.on('end', async () => {
            try {
                const requestData = JSON.parse(body);
                if (requestData.token !== SECRET_TOKEN) {
                    console.error(`❌ 验证失败：收到无效的 Token: "${requestData.token}"`);
                    res.writeHead(401, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: false, message: '无效的令牌 (Invalid Token)' }));
                    return;
                }
                console.log('✅ Token 验证通过。');

                console.log(`\n🚀 收到更新任务，目标订阅: "${requestData.name}"`);
                await handleUpdateRequest(requestData);

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, message: '所有操作(本地更新、本地重启、远程同步、远程重启)均已成功！' }));
                console.log(`🎉 --- 任务圆满完成: "${requestData.name}" ---`);
            } catch (error) {
                console.error('处理请求时发生严重错误:', error.message);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: error.message }));
            }
        });
    } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, message: '接口不存在，请使用 POST 方法访问根路径 /' }));
    }
});

server.listen(PORT, () => {
  console.log(`服务器已启动，正在监听端口 ${PORT}`);
  console.log(`安全令牌已设置为: "${SECRET_TOKEN}"`);
});