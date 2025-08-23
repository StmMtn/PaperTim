// server.js
import express from 'express';
import Redis from 'ioredis';
import Docker from 'dockerode';
import getPort from 'get-port';
import cors from 'cors';

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const app = express();

const redis = new Redis({ host: 'redis', port: 6379 });

app.use(cors({ origin: 'http://localhost:8081', credentials: true }));
app.use(express.json());

const DOCKER_NETWORK = process.env.DOCKER_NETWORK || 'gamenet';

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
    // 1) freien Hostport reservieren
    const hostPort = String(await getPort());

    // 2) Container mit ENV erstellen
    const container = await docker.createContainer({
      Image: 'gameserver:latest',
      name: `gameserver_${Date.now()}`,
      Tty: false,
      Env: [
        `PUBLIC_PORT=${hostPort}`,
        `REDIS_HOST=redis`,
        `REDIS_PORT=6379`,
      ],
      ExposedPorts: { '8443/tcp': {} },
      HostConfig: {
        PortBindings: { '8443/tcp': [{ HostPort: hostPort }] },
        NetworkMode: DOCKER_NETWORK,
      },
      NetworkingConfig: {
        EndpointsConfig: { [DOCKER_NETWORK]: {} },
      },
    });

    await container.start();

    // 3) In Redis registrieren
    const serverKey = `server:${hostPort}`;
    await redis.hset(serverKey, { host: 'localhost', port: hostPort, players: 0 });
    await redis.expire(serverKey, 3600);

    res.json({ msg: 'Server gestartet', id: container.id, port: hostPort });
  } catch (err) {
    console.error('Fehler beim Starten:', err);
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => console.log('Master-Server läuft auf http://localhost:3000'));

const shutdown = async () => {
  console.log('🛑 Shutting down API service...');
  process.exit(0);
};
process.on('SIGTERM', shutdown);
