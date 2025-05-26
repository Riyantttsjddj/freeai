#!/bin/bash

echo "[*] Membersihkan instalasi sebelumnya..."
systemctl stop chatgpt-mini 2>/dev/null
systemctl disable chatgpt-mini 2>/dev/null
rm -rf /opt/chatgpt-mini-full
rm -f /etc/systemd/system/chatgpt-mini.service

echo "[*] Update & install dependensi..."
apt update -y
apt install -y nodejs npm curl

echo "[*] Setup folder project..."
mkdir -p /opt/chatgpt-mini-full
cd /opt/chatgpt-mini-full

echo "[*] Inisialisasi project Node.js..."
npm init -y
npm install express express-session body-parser

echo "[*] Membuat penyimpanan memori JSON..."
cat <<EOF > db.js
const fs = require('fs');
const FILE = 'data.json';

let data = { users: [], messages: {} };
if (fs.existsSync(FILE)) {
  try { data = JSON.parse(fs.readFileSync(FILE)); } catch {}
}

function saveData() {
  fs.writeFileSync(FILE, JSON.stringify(data, null, 2));
}

module.exports = { data, saveData };
EOF

echo "[*] Membuat server Express..."
cat <<EOF > server.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const path = require('path');
const { data, saveData } = require('./db');

const app = express();
const PORT = 3000;

app.use(express.static(__dirname));
app.use(bodyParser.urlencoded({ extended: false }));
app.use(bodyParser.json());

app.use(session({
  secret: 'secret123',
  resave: false,
  saveUninitialized: true
}));

function auth(req, res, next) {
  if (req.session.user) next();
  else res.redirect('/login.html');
}

app.get('/', auth, (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  const user = data.users.find(u => u.username === username && u.password === password);
  if (user) {
    req.session.user = username;
    res.redirect('/');
  } else {
    res.send('Login gagal. <a href="/login.html">Coba lagi</a>');
  }
});

app.post('/register', (req, res) => {
  const { username, password } = req.body;
  if (data.users.some(u => u.username === username)) {
    res.send('Username sudah terdaftar. <a href="/login.html">Login</a>');
  } else {
    data.users.push({ username, password });
    saveData();
    res.send('Pendaftaran berhasil. <a href="/login.html">Login</a>');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login.html');
});

app.post('/chat', auth, (req, res) => {
  const user = req.session.user;
  const msg = req.body.message;

  if (!data.messages[user]) data.messages[user] = [];

  // Ambil 3 chat terakhir
  const last = data.messages[user].slice(-3).map(m => \`You: \${m.message}\\nAI: \${m.reply}\`).join('\\n');
  const context = \`\${last}\\nYou: \${msg}\`;

  // Simulasi balasan AI
  const reply = \`\${msg.split('').reverse().join('')} (berdasarkan konteks)\`;

  data.messages[user].push({ message: msg, reply, timestamp: new Date().toISOString() });
  saveData();

  res.json({ reply });
});

app.get('/history', auth, (req, res) => {
  const user = req.session.user;
  res.json((data.messages[user] || []).slice(-20).reverse());
});

app.listen(PORT, () => {
  console.log(\`Server aktif di http://0.0.0.0:\${PORT}\`);
});
EOF

echo "[*] Membuat halaman login dan register..."
cat <<EOF > login.html
<!DOCTYPE html><html><body>
<h2>Login</h2>
<form action="/login" method="post">
  Username: <input name="username"><br>
  Password: <input name="password" type="password"><br>
  <button type="submit">Login</button>
</form>
<p>Belum punya akun? <a href="/register.html">Daftar</a></p>
</body></html>
EOF

cat <<EOF > register.html
<!DOCTYPE html><html><body>
<h2>Daftar</h2>
<form action="/register" method="post">
  Username: <input name="username"><br>
  Password: <input name="password" type="password"><br>
  <button type="submit">Daftar</button>
</form>
</body></html>
EOF

cat <<'EOF' > index.html
<!DOCTYPE html>
<html>
<head>
  <title>ChatGPT Mini</title>
  <style>
    body { font-family: sans-serif; padding: 20px; }
    pre { background: #f0f0f0; padding: 10px; border-radius: 6px; position: relative; }
    .copy-btn { position: absolute; top: 10px; right: 10px; background: #ccc; border: none; cursor: pointer; }
  </style>
</head>
<body>
  <h1>ChatGPT Mini</h1>
  <a href="/logout">Logout</a>
  <div id="history"></div>
  <input id="msg" placeholder="Tulis pertanyaan..." style="width: 70%;">
  <button onclick="send()">Kirim</button>
  <script>
    fetch('/history').then(res => res.json()).then(data => {
      for (const h of data) append(h.message, h.reply);
    });

    function send() {
      const msg = document.getElementById('msg').value;
      if (!msg) return;
      fetch('/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: msg })
      })
      .then(res => res.json())
      .then(data => append(msg, data.reply));
    }

    function append(q, a) {
      const div = document.getElementById('history');
      div.innerHTML += `<p><b>You:</b> ${q}</p><pre>${a}</pre>`;
    }
  </script>
</body>
</html>
EOF

echo "[*] Membuat systemd service..."
cat <<EOF > /etc/systemd/system/chatgpt-mini.service
[Unit]
Description=ChatGPT Mini JSON Mode
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/chatgpt-mini-full/server.js
Restart=always
User=root
Environment=NODE_ENV=production
WorkingDirectory=/opt/chatgpt-mini-full

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl start chatgpt-mini

IP=$(curl -s ifconfig.me)
echo "========================================="
echo "ChatGPT Mini dengan memori aktif!"
echo "Akses di: http://$IP:3000/login.html"
echo "========================================="
