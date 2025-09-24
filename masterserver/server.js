import express from 'express';
import Redis from 'ioredis';
import Docker from 'dockerode';
//import getPort from 'get-port'; //wenn keine range benötigt wird, ersetze: allocatePort() mit getPort()
import cors from 'cors';
import authRoutes from './auth.js';
import statsRoutes from './stats.js';

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const app = express();
const PORT_RANGE_START = 30000;
const PORT_RANGE_END = 31000;
const redis = new Redis({ host: 'redis', port: 6379 });
const DOCKER_NETWORK = process.env.DOCKER_NETWORK || 'gamenet';
const PROJECT_NAME = process.env.COMPOSE_PROJECT_NAME || 'papertim';

app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

app.use('/auth', authRoutes);
app.use('/', statsRoutes);

// Gemeinsame Labels für ALLE dynamischen Gameserver
const BASE_LABELS = {
  'app': 'gameserver',
  'managed-by': 'masterserver',
  // erlaubt docker compose down --remove-orphans, die Container mitzunehmen
  'com.docker.compose.project': PROJECT_NAME,
};

// Container anhand Label public_port finden
async function findContainerByPublicPort(port) {
  const list = await docker.listContainers({
    all: true,
    filters: {
      label: [
        'app=gameserver',
        'managed-by=masterserver',
        `public_port=${String(port)}`,
      ],
    },
  });
  return list[0] || null;
}

// sicher stoppen & entfernen
async function stopAndRemoveContainer(id) {
  const c = docker.getContainer(id);
  try { await c.stop({ t: 5 }); } catch { /* already stopped */ }
  try { await c.remove({ force: true }); } catch { /* ignore */ }
}

// --- API ---

// Alle aktiven Gameserver (aus Redis)
app.get('/servers', async (_req, res) => {
  try {
    const keys = await redis.keys('server:*');
    const servers = [];
    for (const key of keys) {
      const data = await redis.hgetall(key);
      servers.push({ id: key, ...data });
    }
    res.json(servers);
  } catch (err) {
    console.error('Error in /servers:', err);
    res.status(500).json({ error: err.message });
  }
});

// Gameserver starten → dynamischer Host-Port, Container lauscht intern immer auf 8443
app.post('/servers', async (_req, res) => {
  try {
    const hostPort = await allocatePort(); // Ports dynamisch holen 
    const container = await docker.createContainer({
      Image: 'gameserver:latest',
      name: `gameserver_${Date.now()}`,
      Tty: false,
      Env: [
        `PUBLIC_PORT=${hostPort}`,
        `REDIS_HOST=redis`,
        `REDIS_PORT=6379`,
        `INTERNAL_PORT=8443`,
      ],
      ExposedPorts: { '8443/tcp': {} },
      HostConfig: {
        PortBindings: { '8443/tcp': [{ HostPort: hostPort }] },
        NetworkMode: DOCKER_NETWORK,
      },
      NetworkingConfig: {
        EndpointsConfig: { [DOCKER_NETWORK]: {} },
      },
      Labels: {
        ...BASE_LABELS,
        'public_port': hostPort,
      },
    });
    await container.start();
    res.json({ msg: 'Server gestartet', id: container.id, port: hostPort });
  } catch (err) {
    console.error('Fehler beim Starten:', err);
    res.status(500).json({ error: err.message });
  }
});

// Gameserver per Port beenden & entfernen
app.delete('/servers/:port', async (req, res) => {
  const port = String(req.params.port);
  try {
    const c = await findContainerByPublicPort(port);
    if (!c) return res.status(404).json({ error: `Kein Gameserver mit Port ${port} gefunden.` });
    await stopAndRemoveContainer(c.Id);
    // Redis aufräumen (Key entspricht server:<port>)
    try { await redis.del(`server:${port}`); } catch {}
    await releasePort(port);
    res.json({ msg: `Gameserver auf Port ${port} entfernt`, id: c.Id });
  } catch (err) {
    console.error('Fehler beim Stoppen:', err);
    res.status(500).json({ error: err.message });
  }
});

// Alle dynamischen Gameserver killen
app.delete('/servers', async (_req, res) => {
  try {
    const list = await docker.listContainers({
      all: true,
      filters: { label: ['app=gameserver', 'managed-by=masterserver'] },
    });
    const removed = [];
    for (const c of list) {
      const port = c.Labels?.public_port;
      await stopAndRemoveContainer(c.Id);
      if (port) { try { await redis.del(`server:${port}`); } catch {} }
      removed.push({ id: c.Id, port });
    }
    res.json({ msg: 'Alle dynamischen Gameserver entfernt', removed });
  } catch (err) {
    console.error('Fehler beim Massen-Stoppen:', err);
    res.status(500).json({ error: err.message });
  }
});

async function allocatePort() {
  for (let port = PORT_RANGE_START; port <= PORT_RANGE_END; port++) {
    const inUse = await redis.exists(`server:${port}`);
    if (!inUse) {
      // reservieren
      await redis.hset(`server:${port}`, { status: 'allocating' });
      return String(port);
    }
  }
  throw new Error('Kein freier Port verfügbar!');
}

// Port wieder freigeben
async function releasePort(port) {
  await redis.del(`server:${port}`);
}

app.listen(3000, () => console.log('Master-Server läuft auf http://213.153.88.123:3000'));

const shutdown = async () => {
  console.log('🛑 Shutting down Master... entferne dynamische Gameserver');
  try {
    const list = await docker.listContainers({
      all: true,
      filters: { label: ['app=gameserver', 'managed-by=masterserver'] },
    });
    for (const c of list) {
      const port = c.Labels?.public_port;
      await stopAndRemoveContainer(c.Id);
      if (port) { try { await redis.del(`server:${port}`); } catch {} }
      console.log(`✓ removed ${c.Id} (port ${port || 'n/a'})`);
    }
  } catch (e) {
    console.error('Cleanup beim Shutdown fehlgeschlagen:', e.message);
  } finally {
    process.exit(0);
  }
};


process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
