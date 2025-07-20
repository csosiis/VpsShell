const http = require('http');
const fs = require('fs').promises;

const PORT = 8443;
const TARGET_FILE_PATH = '/root/sub-store/sub-store.json';
const SECRET_TOKEN = 'sanjose';

const NEW_SUB_TEMPLATE = {
    "name": "Test", "displayName": "", "form": "", "remark": "", "mergeSources": "",
    "ignoreFailedRemoteSub": false, "passThroughUA": false,
    "icon": "https://raw.githubusercontent.com/cc63/ICON/main/icons/Stash.png",
    "isIconColor": true,
    "process": [{"type": "Quick Setting Operator", "args": { "useless": "DISABLED", "udp": "DEFAULT", "scert": "DEFAULT", "tfo": "DEFAULT", "vmess aead": "DEFAULT" }}],
    "source": "local", "url": "", "content": "test", "ua": "", "tag": [], "subscriptionTags": [], "display-name": ""
};

const server = http.createServer(async (req, res) => {
    if (req.method === 'POST' && req.url === '/') {
        let body = '';
        req.on('data', chunk => { body += chunk.toString(); });
        req.on('end', async () => {
            try {
                const requestData = JSON.parse(body);
                if (requestData.token !== SECRET_TOKEN) {
                    res.writeHead(401, { 'Content-Type': 'application/json' });
                    return res.end(JSON.stringify({ success: false, message: 'Invalid Token' }));
                }
                if (!requestData.name) { throw new Error('Request must include "name" field.'); }

                let { action = 'update', name, link } = requestData;

                const fileContent = await fs.readFile(TARGET_FILE_PATH, 'utf8');
                const mainObject = JSON.parse(fileContent);
                if (!Array.isArray(mainObject.subs)) { throw new Error(`"subs" array not found in ${TARGET_FILE_PATH}`); }

                const itemIndex = mainObject.subs.findIndex(sub => sub.name === name);
                const itemExists = itemIndex !== -1;

                if (action === 'create' && itemExists) {
                    action = 'update';
                }

                if (action === 'create') {
                    const newItem = JSON.parse(JSON.stringify(NEW_SUB_TEMPLATE));
                    newItem.name = name; newItem.content = link || '';
                    mainObject.subs.push(newItem);
                } else if (action === 'append') {
                    if (!itemExists) { throw new Error(`Append failed: item "${name}" not found.`); }
                    const currentContent = mainObject.subs[itemIndex].content;
                    mainObject.subs[itemIndex].content = currentContent ? `${currentContent}\n${link}` : link;
                } else { // update
                    if (!itemExists) { throw new Error(`Update failed: item "${name}" not found.`); }
                    mainObject.subs[itemIndex].content = link;
                }

                await fs.writeFile(TARGET_FILE_PATH, JSON.stringify(mainObject, null, 2), 'utf8');

                console.log(`[API] Successfully processed action "${action}" for item "${name}". File updated.`);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, message: `Action "${action}" was successful. File updated.` }));

            } catch (error) {
                console.error('[API] Error processing request:', error.message);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: error.message }));
            }
        });
    } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: false, message: 'Not Found' }));
    }
});

server.listen(PORT, () => {
    console.log(`🟢 API Server started. Listening on port ${PORT}.`);
});