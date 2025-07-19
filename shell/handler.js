// 引入所需模块
const http = require('http');
const fs = require('fs').promises;
const { exec } = require('child_process');
const https = require('https');

// --- 配置区 ---
const PORT = 8443;
const TARGET_FILE_PATH = '/root/sub-store/sub-store.json';
const SERVICE_TO_RESTART = 'sub-store.service';
const SECRET_TOKEN = 'sanjose';
const IDENTITY_FILE_PATH = '/root/.ssh/server';

// --- 新建订阅条目的模板 ---
const NEW_SUB_TEMPLATE = {
    "name": "Test", "displayName": "", "form": "", "remark": "", "mergeSources": "",
    "ignoreFailedRemoteSub": false, "passThroughUA": false,
    "icon": "https://raw.githubusercontent.com/cc63/ICON/main/icons/Stash.png",
    "isIconColor": true,
    "process": [{"type": "Quick Setting Operator", "args": { "useless": "DISABLED", "udp": "DEFAULT", "scert": "DEFAULT", "tfo": "DEFAULT", "vmess aead": "DEFAULT" }}],
    "source": "local", "url": "", "content": "test", "ua": "", "tag": [], "subscriptionTags": [], "display-name": ""
};

// --- 远程服务器列表 ---
const REMOTE_SERVERS = [
    { ip: '79.72.72.95', user: 'ubuntu', path: '/root/sub-store/', alias: 'Oracle-London(伦敦)' },
    { ip: '137.131.41.2', user: 'ubuntu', path: '/root/sub-store/', alias: 'Oracle-Phoenix(凤凰城)' }
];

// --- Telegram 通知配置 ---
const ENABLE_TELEGRAM_NOTIFICATIONS = true;
const TELEGRAM_BOT_TOKEN = '7189461669:AAFJJk4JO0rhSV4wRMxcWsY4e3eG7o-x7DE';
const TELEGRAM_CHAT_ID = '7457253104';
// --- 配置区结束 ---

let isSyncing = false;
let isInternalUpdate = false;
let debounceTimeout = null;

function executeCommand(command) {
    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`❌ 执行命令时出错: ${command}`);
                console.error(`   错误信息: ${stderr}`);
                reject(new Error(stderr || 'Command failed'));
                return;
            }
            console.log(`✅ 命令成功执行: ${command}`);
            if (stdout) { console.log(`   输出: ${stdout.trim()}`); }
            resolve(stdout);
        });
    });
}

async function sendTelegramNotification(text) {
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
            res.on('end', () => {
                console.error(`❌ 发送 Telegram 通知失败，状态码: ${res.statusCode}`);
                console.error('   Telegram API 响应:', data);
            });
        } else {
            console.log('✅ Telegram 通知已成功发送。');
        }
    }).on('error', (e) => {
        console.error('❌ 发送 Telegram 通知时发生网络错误:', e.message);
    });
}

async function runSyncAndRestartOperations(triggerSource) {
    if (isSyncing) {
        console.warn('⚠️  当前已有同步任务正在进行中，本次触发被跳过。');
        return;
    }
    console.log(`\n🚀 由 [${triggerSource}] 触发，开始执行自动化同步与重启流程...`);
    isSyncing = true;
    let notificationMessage = '';
    const serverList = REMOTE_SERVERS.map(s => s.alias).join(', ');

    try {
        console.log(`⏳ 步骤 A: 重启本地的 ${SERVICE_TO_RESTART}...`);
        await executeCommand(`systemctl restart ${SERVICE_TO_RESTART}`);
        console.log(`👍 步骤 A: 本地服务重启成功。`);

        console.log(`⏳ 步骤 B: 开始同步并重启所有 ${REMOTE_SERVERS.length} 台远程服务器...`);
        for (const server of REMOTE_SERVERS) {
            console.log(`  -> 正在处理服务器: ${server.alias} (${server.ip})`);
            const remoteServerAddress = `${server.user}@${server.ip}`;
            const rsyncCommand = `rsync -avzP -e "ssh -i ${IDENTITY_FILE_PATH} -o 'StrictHostKeyChecking=no'" --rsync-path="sudo rsync" ${TARGET_FILE_PATH} ${remoteServerAddress}:${server.path}`;
            await executeCommand(rsyncCommand);
            const sshCommand = `ssh -i ${IDENTITY_FILE_PATH} -o 'StrictHostKeyChecking=no' ${remoteServerAddress} "sudo systemctl restart ${SERVICE_TO_RESTART}"`;
            await executeCommand(sshCommand);
            console.log(`     -> ${server.alias} 同步并重启成功。`);
        }
        console.log(`👍 步骤 B: 所有远程服务器均已同步并重启成功。`);

        notificationMessage = `✅ *同步任务成功*\n\n*触发方式*: \`${triggerSource}\`\n\n已成功同步并重启以下服务器的服务：\n\`${serverList}\``;
    } catch (error) {
        console.error('❌ 处理过程中发生严重错误:', error.message);
        notificationMessage = `❌ *同步任务失败*\n\n*触发方式*: \`${triggerSource}\`\n\n*错误详情*: \n\`\`\`\n${error.message}\n\`\`\``;
    } finally {
        isSyncing = false;
        await sendTelegramNotification(notificationMessage);
    }
}

async function handlePostRequest(requestData) {
    let { action = 'update', name, link } = requestData;
    console.log(`- 由POST请求触发的操作: [${action}]，目标: "${name}"`);

    const fileContent = await fs.readFile(TARGET_FILE_PATH, 'utf8');
    const mainObject = JSON.parse(fileContent);
    if (!Array.isArray(mainObject.subs)) { throw new Error(`在 ${TARGET_FILE_PATH} 中未找到 "subs" 数组。`); }

    const itemIndex = mainObject.subs.findIndex(sub => sub.name === name);
    const itemExists = itemIndex !== -1;

    if (action === 'create' && itemExists) {
        console.log(`ℹ️ "create" 请求的目标 "${name}" 已存在，操作自动转为 "update"。`);
        action = 'update';
    }

    if (action === 'create') {
        const newItem = JSON.parse(JSON.stringify(NEW_SUB_TEMPLATE));
        newItem.name = name; newItem.content = link || '';
        mainObject.subs.push(newItem);
    } else if (action === 'append') {
        if (!itemExists) { throw new Error(`追加失败：名为 "${name}" 的订阅不存在。`); }
        const currentContent = mainObject.subs[itemIndex].content;
        mainObject.subs[itemIndex].content = currentContent ? `${currentContent}\n${link}` : link;
    } else {
        if (!itemExists) { throw new Error(`覆盖失败：名为 "${name}" 的订阅不存在。`); }
        mainObject.subs[itemIndex].content = link;
    }

    const updatedJsonContent = JSON.stringify(mainObject, null, 2);

    isInternalUpdate = true;
    await fs.writeFile(TARGET_FILE_PATH, updatedJsonContent, 'utf8');
    setTimeout(() => { isInternalUpdate = false; }, 200);

    console.log('👍 本地文件已通过 POST 请求更新。');
    await runSyncAndRestartOperations(`POST 请求 (${action})`);
}

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
                if (!requestData.name) { throw new Error('请求数据中必须包含 "name" 字段。'); }

                await handlePostRequest(requestData);

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, message: 'POST 请求处理完毕，同步流程已触发！' }));
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

// --- 文件监控主逻辑 (已修改) ---
function startFileWatcher() {
    try {
        console.log(`   同时启动 [文件监控模式]...`);
        fs.watch(TARGET_FILE_PATH, (eventType, filename) => {

            // --- 新增的调试日志 ---
            // 无论发生什么事件，都先打印出来，方便我们观察
            console.log(`[DEBUG] fs.watch event: type=${eventType}, filename=${filename || 'N/A'}`);
            // --- 调试日志结束 ---

            // --- 修改后的条件判断 ---
            // 只要 filename 存在，就认为是一次有效变更，不再严格要求 eventType === 'change'
            if (filename) {
                if (isInternalUpdate) {
                    console.log('ℹ️ 检测到内部文件更新，跳过本次文件监控触发。');
                    return;
                }

                console.log(`\n🔔 检测到外部文件 [${filename}] 发生事件: ${eventType}`);
                clearTimeout(debounceTimeout);
                debounceTimeout = setTimeout(() => {
                    runSyncAndRestartOperations('文件监控');
                }, 2000);
            }
            // --- 条件判断结束 ---
        });
    } catch (error) {
        console.error(`🔴 无法启动文件监控服务: ${error.message}`);
    }
}


server.listen(PORT, () => {
    console.log(`🟢 服务已启动 [混合模式]`);
    console.log(`   正在监听端口 ${PORT} 上的POST请求...`);
    startFileWatcher();
});