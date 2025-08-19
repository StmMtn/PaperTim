const express = require('express');
const Redis = require('ioredis');
const { exec } = require('child_process');

const app = express();
const redis = new Redis();

app.use(express.json());

// Alle aktiven Gameserver
app.get('/servers', async (req, res) => {
  const keys = await redis.keys('server:*');
  const servers = [];
  for (const key of keys) {
    const data = await redis.hgetall(key);
    servers.push({ id: key, ...data });
  }
  res.json(servers);
});

// Gameserver starten
app.post('/servers', (req, res) => {
  // Docker Compose nutzt den Service "gameserver"
  exec('docker compose run -d gameserver', (err, stdout, stderr) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ msg: 'Server gestartet', containerId: stdout.trim() });
  });
});

app.listen(3000, () => console.log('Master-Server läuft auf http://localhost:3000'));
const shutdown = async () => {
  console.log('🛑 Shutting down API service...');
  process.exit(0);
};
process.on('SIGTERM', shutdown);