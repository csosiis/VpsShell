// 文件名: handler-watcher.js
const fs = require('fs');
const https = require('https');
const { exec } = require('child_process');

// --- 配置区 ---
const TARGET_FILE_PATH = '/root/sub-store/sub-store.json';
const SERVICE_TO_RESTART = 'sub-store.service';
const IDENTITY_FILE_PATH = '/root/.ssh/server';

const REMOTE_SERVERS = [
    { ip: '137.131.41.2', user: 'ubuntu', path: '/root/sub-store/', alias: 'Oracle-Phoenix(凤凰城)' }
];

const ENABLE_TELEGRAM_NOTIFICATIONS = true;
const TELEGRAM_BOT_TOKEN = '**********';
const TELEGRAM_CHAT_ID = '**********';
// --- 配置区结束 ---

let debounceTimeout = null;
let isSyncing = false;

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
      res.on('end', () => console.error(`❌ 发送 Telegram 通知失败，状态码: ${res.statusCode}`, data));
    } else {
      console.log('✅ Telegram 通知已成功发送。');
    }
  }).on('error', (e) => console.error('❌ 发送 Telegram 通知时发生网络错误:', e.message));
}

async function runSyncAndRestartOperations() {
  if (isSyncing) {
    console.warn('⚠️  当前已有同步任务正在进行中，本次触发被跳过。');
    return;
  }
  console.log('\n🚀 文件变更被检测到，开始执行自动化同步与重启流程...');
  isSyncing = true;
  let notificationMessage = '';
  const serverList = REMOTE_SERVERS.map(s => s.alias).join(', ');

  try {
    console.log(`⏳ 步骤 1/2: 正在重启本地的 ${SERVICE_TO_RESTART}...`);
    await executeCommand(`systemctl restart ${SERVICE_TO_RESTART}`);
    console.log(`👍 步骤 1/2: 本地服务重启成功。`);
    console.log(`⏳ 步骤 2/2: 开始同步并重启所有 ${REMOTE_SERVERS.length} 台远程服务器...`);
    for (const server of REMOTE_SERVERS) {
        console.log(`  -> 正在处理服务器: ${server.alias} (${server.ip})`);
        const remoteServerAddress = `${server.user}@${server.ip}`;
        const rsyncCommand = `rsync -avzP -e "ssh -i ${IDENTITY_FILE_PATH} -o 'StrictHostKeyChecking=no'" --rsync-path="sudo rsync" ${TARGET_FILE_PATH} ${remoteServerAddress}:${server.path}`;
        await executeCommand(rsyncCommand);
        const sshCommand = `ssh -i ${IDENTITY_FILE_PATH} -o 'StrictHostKeyChecking=no' ${remoteServerAddress} "sudo systemctl restart ${SERVICE_TO_RESTART}"`;
        await executeCommand(sshCommand);
        console.log(`     -> ${server.alias} 同步并重启成功。`);
    }
    console.log(`👍 步骤 2/2: 所有远程服务器均已同步并重启成功。`);
    notificationMessage = `✅ *文件自动同步成功*\n\n*监控文件*: \`${TARGET_FILE_PATH}\`\n\n已成功同步并重启以下服务器的服务：\n\`${serverList}\``;
  } catch (error) {
    console.error('❌ 处理过程中发生严重错误:', error.message);
    notificationMessage = `❌ *文件自动同步失败*\n\n*监控文件*: \`${TARGET_FILE_PATH}\`\n\n*错误详情*: \n\`\`\`\n${error.message}\n\`\`\``;
  } finally {
    isSyncing = false;
    await sendTelegramNotification(notificationMessage);
  }
}

try {
  console.log(`🟢 Watcher Service started. Monitoring file: ${TARGET_FILE_PATH}`);
  fs.watch(TARGET_FILE_PATH, (eventType, filename) => {
    if (filename && eventType === 'change') {
      console.log(`\n🔔 File [${filename}] changed.`);
      clearTimeout(debounceTimeout);
      debounceTimeout = setTimeout(() => {
        runSyncAndRestartOperations();
      }, 2000);
    }
  });
} catch (error) {
  console.error(`🔴 Failed to start watcher service: ${error.message}`);
  process.exit(1);
}