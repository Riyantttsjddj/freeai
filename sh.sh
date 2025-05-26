#!/bin/bash

# Instalasi dependensi
apt update -y
apt install -y nodejs npm curl

# Buat direktori untuk project
mkdir -p /opt/chatgpt-mini
cd /opt/chatgpt-mini

# Buat file server.js
cat <<'EOF' > server.js
const http = require('http');
const fs = require('fs');
const path = require('path');

const chatHistory = [];

const server = http.createServer((req, res) => {
    if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        return res.end(fs.readFileSync(path.join(__dirname, 'index.html')));
    } else if (req.url === '/script.js') {
        res.writeHead(200, { 'Content-Type': 'application/javascript' });
        return res.end(fs.readFileSync(path.join(__dirname, 'script.js')));
    } else if (req.url === '/history') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify(chatHistory));
    } else if (req.method === 'POST' && req.url === '/chat') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            const { message } = JSON.parse(body);
            global.puter.ai.chat(message).then(reply => {
                chatHistory.push({ prompt: message, reply });
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ reply }));
            });
        });
    } else {
        res.writeHead(404);
        res.end('Not found');
    }
});

server.listen(3000, () => console.log('Server berjalan di port 3000'));

global.puter = require('puter-ai');
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
    <script src="script.js"></script>
</body>
</html>
EOF

# Buat file script.js
cat <<'EOF' > script.js
async function send() {
    const input = document.getElementById('input');
    const msg = input.value;
    if (!msg) return;
    appendMessage("You", msg);
    input.value = "";

    const res = await fetch('/chat', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ message: msg })
    });
    const data = await res.json();
    appendReply(data.reply);
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

# Instalasi modul
npm install puter-ai

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

# Reload systemd dan jalankan service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl start chatgpt-mini

# Tampilkan IP publik
IP=$(curl -s ifconfig.me)
echo "Akses ChatGPT Mini melalui: http://$IP:3000"
