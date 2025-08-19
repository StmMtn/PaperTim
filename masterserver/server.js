const express = require('express');
const Redis = require('ioredis');
const { exec } = require('child_process');
const Docker = require('dockerode');
const docker = new Docker({ socketPath: '/var/run/docker.sock' });

const app = express();
const redis = new Redis({
  host: 'redis',
  port: 6379
});

app.use(express.json());

// Alle aktiven Gameserver
app.get('/servers', async (req, res) => {
  try {
    console.log("Request GET /servers");
    const keys = await redis.keys('server:*');
    console.log("Redis keys:", keys);

    const servers = [];
    for (const key of keys) {
      const data = await redis.hgetall(key);
      console.log(`Redis data for ${key}:`, data);
      servers.push({ id: key, ...data });
    }
    res.json(servers);
  } catch (err) {
    console.error("Error in /servers:", err);
    res.status(500).json({ error: err.message });
  }
});

// Gameserver starten
app.post('/servers', async (req, res) => {
  try {
    const container = await docker.createContainer({
      Image: 'gameserver', // dein Image-Name
      name: `gameserver_${Date.now()}`,
      Tty: true,
      ExposedPorts: { "8443/tcp": {} },
      HostConfig: {
        PortBindings: { "8443/tcp": [{ HostPort: "8443" }] }
      }
    });

    await container.start();
    res.json({ msg: "Server gestartet", id: container.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => console.log('Master-Server läuft auf http://localhost:3000'));
const shutdown = async () => {
  console.log('🛑 Shutting down API service...');
  process.exit(0);
};
process.on('SIGTERM', shutdown);