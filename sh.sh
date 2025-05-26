#!/bin/bash

echo "[*] Membersihkan instalasi sebelumnya..."
systemctl stop chatgpt-mini 2>/dev/null
systemctl disable chatgpt-mini 2>/dev/null
rm -rf /opt/chatgpt-mini-full
rm -f /etc/systemd/system/chatgpt-mini.service

echo "[*] Update & install dependensi..."
apt update -y
apt install -y nodejs npm sqlite3 curl

echo "[*] Setup folder project..."
mkdir -p /opt/chatgpt-mini-full
cd /opt/chatgpt-mini-full

echo "[*] Inisialisasi project Node.js..."
npm init -y
npm install express express-session better-sqlite3 body-parser

echo "[*] Membuat database dan file schema..."
cat <<EOF > db.js
const Database = require('better-sqlite3');
const db = new Database('chat.db');

// Membuat tabel jika belum ada
db.prepare(\`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE,
  password TEXT
);
\`).run();

db.prepare(\`
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user TEXT,
  message TEXT,
  reply TEXT,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
\`).run();

module.exports = db;
EOF

echo "[*] Membuat server Express..."
cat <<EOF > server.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const db = require('./db');
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

function auth(req, res, next) {
  if (req.session.user) next();
  else res.redirect('/login.html');
}

app.get('/', auth, (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  const user = db.prepare('SELECT * FROM users WHERE username=? AND password=?').get(username, password);
  if (user) {
    req.session.user = user.username;
    res.redirect('/');
  } else {
    res.send('Login gagal. <a href="/login.html">Coba lagi</a>');
  }
});

app.post('/register', (req, res) => {
  const { username, password } = req.body;
  try {
    db.prepare('INSERT INTO users (username, password) VALUES (?, ?)').run(username, password);
    res.send('Pendaftaran berhasil. <a href="/login.html">Login</a>');
  } catch (e) {
    res.send('Username sudah terdaftar. <a href="/login.html">Login</a>');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login.html');
});

app.post('/chat', auth, async (req, res) => {
  const msg = req.body.message;
  const reply = `AI: ${msg.split('').reverse().join('')} (simulasi)`; // simulasi
  db.prepare('INSERT INTO messages (user, message, reply) VALUES (?, ?, ?)').run(req.session.user, msg, reply);
  res.json({ reply });
});

app.get('/history', auth, (req, res) => {
  const rows = db.prepare('SELECT message, reply, timestamp FROM messages WHERE user=? ORDER BY timestamp DESC LIMIT 20').all(req.session.user);
  res.json(rows);
});

app.listen(PORT, () => {
  console.log(`Server berjalan di http://0.0.0.0:${PORT}`);
});
EOF

echo "[*] Membuat halaman login dan chat..."
cat <<EOF > login.html
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

cat <<EOF > register.html
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
  <title>ChatGPT Mini Full</title>
  <style>
    body { font-family: sans-serif; padding: 20px; }
    pre { background: #f0f0f0; padding: 10px; border-radius: 6px; position: relative; }
    .copy-btn { position: absolute; top: 10px; right: 10px; background: #ccc; border: none; cursor: pointer; padding: 5px; }
  </style>
</head>
<body>
  <h1>ChatGPT Mini Full</h1>
  <a href="/logout">Logout</a>
  <div id="history"></div>
  <input id="msg" placeholder="Tulis pertanyaan..." style="width: 70%;">
  <button onclick="send()">Kirim</button>
  <script>
    fetch('/history').then(res => res.json()).then(data => {
      for (const h of data.reverse()) {
        append(h.message, h.reply);
      }
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
Description=ChatGPT Mini Full
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable chatgpt-mini
systemctl start chatgpt-mini

IP=$(curl -s ifconfig.me)
echo "========================================="
echo "ChatGPT Mini Full aktif!"
echo "Akses di: http://$IP:3000/login.html"
echo "========================================="
