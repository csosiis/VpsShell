const http = require('http');
const https = require('https'); // 用于发送 Telegram 请求
const fs = require('fs').promises;

// --- 配置区 ---

// API 服务器监听的端口
const PORT = 8443;

// sub-store 配置文件的绝对路径
const TARGET_FILE_PATH = '/root/sub-store/sub-store.json';

// 用于验证 API 请求的密钥，请务必修改为一个更复杂的字符串
const SECRET_TOKEN = 'sanjose';

// --- Telegram 通知配置 (已从您提供的文件自动填充) ---
const ENABLE_TELEGRAM_NOTIFICATIONS = true; // 设置为 true 启用通知, false 禁用
const TELEGRAM_BOT_TOKEN = '********'; // 已自动填充
const TELEGRAM_CHAT_ID = '********';   // 已自动填充

// --- 配置区结束 ---

// 创建新订阅条目时使用的模板
const NEW_SUB_TEMPLATE = {
    "name": "DefaultName", "displayName": "", "form": "", "remark": "", "mergeSources": "",
    "ignoreFailedRemoteSub": false, "passThroughUA": false,
    "icon": "https://raw.githubusercontent.com/cc63/ICON/main/icons/Stash.png",
    "isIconColor": true,
    "process": [{"type": "Quick Setting Operator", "args": { "useless": "DISABLED", "udp": "DEFAULT", "scert": "DEFAULT", "tfo": "DEFAULT", "vmess aead": "DEFAULT" }}],
    "source": "local", "url": "", "content": "", "ua": "", "tag": [], "subscriptionTags": [], "display-name": ""
};

/**
 * [新增] 发送 Telegram 消息的函数
 * @param {string} text - 要发送的消息内容, 支持 Markdown 格式
 */
function sendTelegramNotification(text) {
  if (!ENABLE_TELEGRAM_NOTIFICATIONS) return;
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.warn('⚠️  Telegram 通知已启用，但 BOT_TOKEN 或 CHAT_ID 未配置，跳过发送。');
    return;
  }
  const message = encodeURIComponent(text);
  const url = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=${message}&parse_mode=Markdown`;

  https.get(url, (res) => {
    if (res.statusCode !== 200) {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => console.error(`❌ 发送 Telegram 通知失败，状态码: ${res.statusCode}`, data));
    } else {
      console.log('✅ Telegram 通知已成功发送。');
    }
  }).on('error', (e) => console.error('❌ 发送 Telegram 通知时发生网络错误:', e.message));
}


const server = http.createServer(async (req, res) => {
    if (req.method === 'POST' && req.url === '/') {
        let body = '';
        req.on('data', chunk => { body += chunk.toString(); });
        req.on('end', async () => {
            try {
                const requestData = JSON.parse(body);
                if (requestData.token !== SECRET_TOKEN) {
                    res.writeHead(401, { 'Content-Type': 'application/json' });
                    return res.end(JSON.stringify({ success: false, message: '无效的 Token' }));
                }
                if (!requestData.name) { throw new Error('请求体中必须包含 "name" 字段。'); }

                let { action = 'update', name, link } = requestData;

                const fileContent = await fs.readFile(TARGET_FILE_PATH, 'utf8');
                const mainObject = JSON.parse(fileContent);
                if (!Array.isArray(mainObject.subs)) { throw new Error(`在文件 "${TARGET_FILE_PATH}" 中未找到 "subs" 数组。`); }

                const itemIndex = mainObject.subs.findIndex(sub => sub.name === name);
                const itemExists = itemIndex !== -1;

                if (action === 'create' && itemExists) {
                    console.log(`[API] 条目 "${name}" 已存在，操作已从 "create" 自动切换为 "update"。`);
                    action = 'update';
                }

                switch (action) {
                    case 'create':
                        console.log(`[API] 正在创建新条目: "${name}"`);
                        const newItem = JSON.parse(JSON.stringify(NEW_SUB_TEMPLATE));
                        newItem.name = name; newItem.content = link || '';
                        mainObject.subs.push(newItem);
                        break;
                    case 'append':
                        if (!itemExists) { throw new Error(`追加失败：找不到条目 "${name}"。`); }
                        console.log(`[API] 正在向条目 "${name}" 追加内容`);
                        const currentContent = mainObject.subs[itemIndex].content;
                        mainObject.subs[itemIndex].content = currentContent ? `${currentContent}\n${link}` : link;
                        break;
                    case 'update':
                    default:
                        if (!itemExists) { throw new Error(`更新失败：找不到条目 "${name}"。`); }
                        console.log(`[API] 正在更新条目: "${name}"`);
                        mainObject.subs[itemIndex].content = link;
                        break;
                }

                await fs.writeFile(TARGET_FILE_PATH, JSON.stringify(mainObject, null, 2), 'utf8');

                const successMessage = `操作 "${action}" 成功，文件已更新。`;
                console.log(`[API] ${successMessage}`);

                // 在成功写入文件后，调用函数发送Telegram通知
                const notificationMessage = `✅ *Sub-Store API 操作成功*\n\n*操作类型*: \`${action}\`\n*操作对象*: \`${name}\``;
                sendTelegramNotification(notificationMessage);

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, message: successMessage }));

            } catch (error) {
                console.error('[API] 处理请求时出错:', error.message);
                // 失败时也可以选择发送通知
                // sendTelegramNotification(`❌ *Sub-Store API 操作失败*\n\n*错误信息*: \`${error.message}\``);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: error.message }));
            }
        });
    } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, message: '未找到资源' }));
    }
});

server.listen(PORT, () => {
    console.log(`🟢 API 服务器已启动，正在监听端口 ${PORT}。`);
    console.log(`   - 监控的目标文件: ${TARGET_FILE_PATH}`);
    console.log(`   - 使用的访问Token: ${SECRET_TOKEN}`);
    if(ENABLE_TELEGRAM_NOTIFICATIONS) {
        console.log(`   - Telegram 通知: 已启用`);
    }
});