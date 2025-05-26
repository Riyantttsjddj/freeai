#!/bin/bash

echo "[*] Membersihkan instalasi sebelumnya..."
systemctl stop chatgpt-mini 2>/dev/null
systemctl disable chatgpt-mini 2>/dev/null
rm -rf /opt/chatgpt-mini
rm -f /etc/systemd/system/chatgpt-mini.service

echo "[*] Update & install dependensi..."
apt update -y
apt install -y nodejs npm curl

echo "[*] Setup folder project..."
mkdir -p /opt/chatgpt-mini
cd /opt/chatgpt-mini

echo "[*] Inisialisasi project Node.js..."
npm init -y
npm install express express-session body-parser

echo "[*] Membuat server Express dengan integrasi Puter.js dan memori JSON..."
cat <<EOF > server.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');

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

// Load users and chats from JSON
const userFile = 'users.json';
if (!fs.existsSync(userFile)) fs.writeFileSync(userFile, '{}');
const users = JSON.parse(fs.readFileSync(userFile));

function saveUsers() {
  fs.writeFileSync(userFile, JSON.stringify(users, null, 2));
}

function auth(req, res, next) {
  if (req.session.user) next();
  else res.redirect('/login.html');
}

app.get('/', auth, (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (users[username] && users[username].password === password) {
    req.session.user = username;
    res.redirect('/');
  } else {
    res.send('Login gagal. <a href="/login.html">Coba lagi</a>');
  }
});

app.post('/register', (req, res) => {
  const { username, password } = req.body;
  if (users[username]) {
    res.send('Username sudah terdaftar. <a href="/login.html">Login</a>');
  } else {
    users[username] = { password, history: [] };
    saveUsers();
    res.send('Pendaftaran berhasil. <a href="/login.html">Login</a>');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login.html');
});

app.post('/chat', auth, async (req, res) => {
  const username = req.session.user;
  const msg = req.body.message;
  const context = users[username].history.map(c => c.q + '\n' + c.a).join('\n');
  const fullPrompt = context + "\nYou: " + msg;

  const reply = await fetch('https://api.puter.com/v2/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt: fullPrompt })
  }).then(r => r.json()).then(j => j.reply || 'AI tidak merespon');

  users[username].history.push({ q: msg, a: reply });
  if (users[username].history.length > 20) users[username].history.shift();
  saveUsers();

  res.json({ reply });
});

app.get('/history', auth, (req, res) => {
  const username = req.session.user;
  res.json(users[username]?.history || []);
});

app.post('/clear', auth, (req, res) => {
  const username = req.session.user;
  users[username].history = [];
  saveUsers();
  res.sendStatus(200);
});

app.listen(PORT, () => {
  console.log("Server berjalan di http://0.0.0.0:" + PORT);
});
EOF

echo "[*] Membuat halaman HTML login, register, dan chat UI..."
cat <<'EOF' > login.html
<!DOCTYPE html>
<html><body>
<h2>Login</h2>
<form action="/login" method="post">
  Username: <input name="username"><br>
  Password: <input name="password" type="password"><br>
  <button type="submit">Login</button>
</form>
<p>Belum punya akun? <a href="/register.html">Daftar</a></p>
</body></html>
EOF

cat <<'EOF' > register.html
<!DOCTYPE html>
<html><body>
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
    .msg { margin-bottom: 15px; }
    .ai { background: #f4f4f4; padding: 10px; border-radius: 6px; white-space: pre-wrap; position: relative; }
    .copy-btn { position: absolute; top: 10px; right: 10px; background: #ccc; border: none; cursor: pointer; padding: 5px; }
  </style>
</head>
<body>
  <h1>ChatGPT Mini</h1>
  <a href="/logout">Logout</a> | 
  <a href="#" onclick="clearChat()">Hapus Chat</a>
  <div id="history"></div>
  <input id="msg" placeholder="Tulis pertanyaan..." style="width: 70%;">
  <button onclick="send()">Kirim</button>
  <script>
    fetch('/history').then(r => r.json()).then(data => {
      data.forEach(x => append(x.q, x.a));
    });

    function send() {
      const msg = document.getElementById('msg').value;
      if (!msg) return;
      fetch('/chat', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ message: msg })
      })
      .then(r => r.json())
      .then(d => append(msg, d.reply));
    }

    function append(q, a) {
      const div = document.getElementById('history');
      let html = `<div class='msg'><b>You:</b> ${q}</div>`;
      html += `<div class='ai'><button class='copy-btn' onclick='copy(this)'>Salin</button>${a}</div>`;
      div.innerHTML += html;
    }

    function copy(btn) {
      const text = btn.parentElement.innerText.replace("Salin", "").trim();
      navigator.clipboard.writeText(text);
      btn.innerText = "Disalin!";
      setTimeout(() => btn.innerText = "Salin", 1000);
    }

    function clearChat() {
      fetch('/clear', { method: 'POST' }).then(() => location.reload());
    }
  </script>
</body>
</html>
EOF

echo "[*] Membuat systemd service..."
cat <<EOF > /etc/systemd/system/chatgpt-mini.service
[Unit]
Description=ChatGPT Mini with Puter.js
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl restart chatgpt-mini

IP=$(curl -s ifconfig.me)
echo "======================================="
echo "ChatGPT Mini aktif!"
echo "Buka di: http://$IP:3000/login.html"
echo "======================================="
