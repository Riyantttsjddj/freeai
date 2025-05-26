#!/bin/bash

# Update dan install Node.js + npm
apt update -y
apt install -y nodejs npm curl

# Buat direktori project
mkdir -p /opt/chatgpt-mini
cd /opt/chatgpt-mini

# Buat file server.js
cat <<'EOF' > server.js
const http = require('http');
const fs = require('fs');
const path = require('path');

const server = http.createServer((req, res) => {
    let filePath = path.join(__dirname, req.url === '/' ? 'index.html' : req.url);
    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = {
        '.html': 'text/html',
        '.js': 'application/javascript',
        '.css': 'text/css',
    };

    fs.readFile(filePath, (error, content) => {
        if (error) {
            res.writeHead(404);
            res.end('Not found');
        } else {
            res.writeHead(200, { 'Content-Type': mimeTypes[extname] || 'application/octet-stream' });
            res.end(content, 'utf-8');
        }
    });
});

server.listen(3000, () => console.log('ChatGPT Mini berjalan di port 3000'));
EOF

# Buat file index.html
cat <<'EOF' > index.html
<!DOCTYPE html>
<html>
<head>
    <title>ChatGPT Mini</title>
    <style>
        body { font-family: sans-serif; margin: 40px; }
        #chat { max-width: 600px; margin: auto; }
        .msg { margin: 10px 0; }
        .reply pre { background: #f4f4f4; padding: 10px; border-radius: 6px; position: relative; }
        .copy-btn {
            position: absolute;
            top: 10px; right: 10px;
            background: #ddd; border: none;
            padding: 5px; cursor: pointer;
        }
    </style>
</head>
<body>
    <div id="chat">
        <h1>ChatGPT Mini</h1>
        <div id="messages"></div>
        <input id="input" type="text" placeholder="Ask me anything..." style="width: 80%;">
        <button onclick="send()">Send</button>
    </div>

    <script src="https://js.puter.com/v2/"></script>
    <script src="/script.js"></script>
</body>
</html>
EOF

# Buat file script.js
cat <<'EOF' > script.js
function send() {
    const input = document.getElementById('input');
    const msg = input.value;
    if (!msg) return;
    appendMessage("You", msg);
    input.value = "";

    puter.ai.chat(msg).then(reply => {
        appendReply(reply);
    });
}

function appendMessage(sender, text) {
    const div = document.getElementById('messages');
    const msgDiv = document.createElement('div');
    msgDiv.className = 'msg';
    msgDiv.innerHTML = `<strong>${sender}:</strong> ${text}`;
    div.appendChild(msgDiv);
}

function appendReply(text) {
    const div = document.getElementById('messages');
    const msgDiv = document.createElement('div');
    msgDiv.className = 'msg reply';
    const id = Math.random().toString(36).substr(2, 9);
    msgDiv.innerHTML = `
        <pre id="code-${id}">${text}</pre>
        <button class="copy-btn" onclick="copyText('${id}')">Copy</button>
    `;
    div.appendChild(msgDiv);
}

function copyText(id) {
    const text = document.getElementById('code-' + id).innerText;
    navigator.clipboard.writeText(text);
    alert("Copied to clipboard!");
}
EOF

# Buat systemd service
cat <<EOF > /etc/systemd/system/chatgpt-mini.service
[Unit]
Description=ChatGPT Mini
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/chatgpt-mini/server.js
Restart=always
User=root
Environment=NODE_ENV=production
WorkingDirectory=/opt/chatgpt-mini

[Install]
WantedBy=multi-user.target
EOF

# Aktifkan dan jalankan service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl start chatgpt-mini

# Tampilkan IP Publik
IP=$(curl -s ifconfig.me)
echo "ChatGPT Mini siap diakses di: http://$IP:3000"
