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

// Wichtig: ein fester Projektname, damit Compose & Labels zusammenpassen
// -> in docker-compose.yml setzen wir COMPOSE_PROJECT_NAME (siehe unten)
const PROJECT_NAME = process.env.COMPOSE_PROJECT_NAME || 'papertim';

// Gemeinsame Labels für ALLE dynamischen Gameserver
const BASE_LABELS = {
  'app': 'gameserver',
  'managed-by': 'masterserver',
  // erlaubt docker compose down --remove-orphans, die Container mitzunehmen
  'com.docker.compose.project': PROJECT_NAME,
};

// Helper: Container anhand Label public_port finden
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

// Helper: sicher stoppen & entfernen
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

// Gameserver starten → dynamischer Host-Port, Container lauscht intern immer 8443
app.post('/servers', async (_req, res) => {
  try {
    const hostPort = String(await getPort());

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
        // mit diesem Label finden/killen wir per Port sehr einfach
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

// *** NEU *** Gameserver per Port beenden & entfernen
app.delete('/servers/:port', async (req, res) => {
  const port = String(req.params.port);
  try {
    const c = await findContainerByPublicPort(port);
    if (!c) return res.status(404).json({ error: `Kein Gameserver mit Port ${port} gefunden.` });

    await stopAndRemoveContainer(c.Id);
    // Redis aufräumen (Key entspricht server:<port>)
    try { await redis.del(`server:${port}`); } catch {}

    res.json({ msg: `Gameserver auf Port ${port} entfernt`, id: c.Id });
  } catch (err) {
    console.error('Fehler beim Stoppen:', err);
    res.status(500).json({ error: err.message });
  }
});

// *** NEU *** Alle dynamischen Gameserver killen
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

app.listen(3000, () => console.log('Master-Server läuft auf http://localhost:3000'));

// --- Compose-Down freundliches Shutdown: alle dynamischen Gameserver wegputzen ---
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
