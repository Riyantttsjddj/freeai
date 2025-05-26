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

echo "[*] Membuat server Express..."
cat <<EOF > server.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;
const DATA_FILE = 'data.json';

// Inisialisasi file jika belum ada
if (!fs.existsSync(DATA_FILE)) fs.writeFileSync(DATA_FILE, '{}');

function loadData() {
  return JSON.parse(fs.readFileSync(DATA_FILE));
}

function saveData(data) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
}

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
  const db = loadData();
  if (db[username] && db[username].password === password) {
    req.session.user = username;
    res.redirect('/');
  } else {
    res.send('Login gagal. <a href="/login.html">Coba lagi</a>');
  }
});

app.post('/register', (req, res) => {
  const { username, password } = req.body;
  const db = loadData();
  if (db[username]) {
    res.send('Username sudah terdaftar. <a href="/login.html">Login</a>');
  } else {
    db[username] = { password, chats: [] };
    saveData(db);
    res.send('Pendaftaran berhasil. <a href="/login.html">Login</a>');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login.html');
});

app.post('/chat', auth, async (req, res) => {
  const msg = req.body.message;
  const db = loadData();
  const user = req.session.user;

  // Ambil 5 histori terakhir
  const history = db[user].chats.slice(-5);
  let prompt = "";
  for (const h of history) {
    prompt += \`You: \${h.q}\nAI: \${h.a}\n\`;
  }
  prompt += \`You: \${msg}\nAI:\`;

  // Kirim ke Puter.js (via browser nanti)
  const reply = '(jawaban AI akan muncul di frontend menggunakan Puter.js)';

  db[user].chats.push({ q: msg, a: reply });
  saveData(db);
  res.json({ prompt }); // Kirim prompt ke frontend untuk digunakan oleh puter.ai.chat()
});

app.get('/history', auth, (req, res) => {
  const db = loadData();
  const user = req.session.user;
  res.json(db[user]?.chats.slice(-20).reverse() || []);
});

app.listen(PORT, () => {
  console.log(\`Server berjalan di http://0.0.0.0:\${PORT}\`);
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
  <script src="https://js.puter.com/v2/"></script>
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
      for (const h of data.reverse()) append(h.q, h.a);
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
      .then(data => {
        puter.ai.chat(data.prompt).then(reply => {
          append(msg, reply);
          // Kirim update ke server (update jawaban)
          fetch('/chat', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: msg, reply })
          });
        });
      });
    }

    function append(q, a) {
      const div = document.getElementById('history');
      const pre = document.createElement('pre');
      pre.innerHTML = a;
      const copyBtn = document.createElement('button');
      copyBtn.className = 'copy-btn';
      copyBtn.innerText = 'Salin';
      copyBtn.onclick = () => navigator.clipboard.writeText(a);
      pre.appendChild(copyBtn);
      div.innerHTML += \`<p><b>You:</b> \${q}</p>\`;
      div.appendChild(pre);
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
systemctl restart chatgpt-mini

IP=$(curl -s ifconfig.me)
echo "=========================================="
echo "ChatGPT Mini (dengan memori & Puter.js)"
echo "Akses di: http://$IP:3000/login.html"
echo "=========================================="
