// gameserver/server.js
const express = require('express');
const WebSocket = require('ws');
const path = require('path');
const Redis = require('ioredis');

const app = express();

const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const redis = new Redis({ host: REDIS_HOST, port: REDIS_PORT });
redis.on('error', (e) => console.error('[Redis] error:', e.message));

// WICHTIG: IMMER im Container auf 8443 lauschen
const INTERNAL_PORT = Number(process.env.INTERNAL_PORT) || 8443;

// Dieser Wert beschreibt den "öffentlichen" Host-Port (vom Master vergeben)
const PUBLIC_PORT = Number(process.env.PUBLIC_PORT) || INTERNAL_PORT;
const SERVER_KEY = `server:${PUBLIC_PORT}`;

// --- Sicherheits-/Kompat-Header (schaden nie, helfen Godot Web) ---
app.use((req, res, next) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  next();
});

// --- Runtime-Config für Godot: nimmt den Host-Header (host:publicPort) ---
app.get('/config', (req, res) => {
  const hostHeader = req.headers['host']; // z.B. "localhost:43943"
  const isHttps = (req.headers['x-forwarded-proto'] || req.protocol) === 'https';
  const wsScheme = isHttps ? 'wss' : 'ws';
  res.setHeader('Cache-Control', 'no-store');
  res.json({ ws_url: `${wsScheme}://${hostHeader}`, port: PUBLIC_PORT });
});

// Health
app.get('/healthz', (_req, res) => res.status(200).send('ok'));

// Static: liefert game.html + Assets
app.use(
  '/',
  express.static(path.join(__dirname, './client/Game'), {
    index: 'game.html',
    setHeaders: (res, filePath) => {
      if (filePath.endsWith('.wasm')) {
        res.setHeader('Content-Type', 'application/wasm');
      }
    },
  })
);

console.log(`Starte Gameserver (container) auf 0.0.0.0:${INTERNAL_PORT} | public http://localhost:${PUBLIC_PORT}`);
const server = app.listen(INTERNAL_PORT, async () => {
  console.log(`HTTP bereit (container:${INTERNAL_PORT}) → erreichbar als http://localhost:${PUBLIC_PORT}`);
  try {
    await redis.hset(SERVER_KEY, { host: 'localhost', port: PUBLIC_PORT, players: 0 });
    await redis.expire(SERVER_KEY, 3600);
    console.log(`Server registriert in Redis unter Key ${SERVER_KEY}`);
  } catch (e) {
    console.error('Registrierung in Redis fehlgeschlagen:', e.message);
  }
});

// WebSocket an denselben HTTP-Server hängen
const wss = new WebSocket.Server({ server });
let nextId = 1;
const clients = new Map();

wss.on('connection', async (ws) => {
  if (clients.size >= 10) {
    ws.close(1000, 'Max players reached');
    return;
  }

  const playerId = nextId++;
  clients.set(ws, { id: playerId });
  ws.send(JSON.stringify({ type: 'init', id: playerId }));
  console.log(`Player ${playerId} connected. Active players: ${clients.size}`);

  try {
    const newCount = await redis.hincrby(SERVER_KEY, 'players', 1);
    console.log(`Players jetzt: ${newCount} @ public:${PUBLIC_PORT}`);
  } catch (e) {
    console.error('Redis hincrby +1 failed:', e.message);
  }

  ws.on('message', (msg) => {
    const data = JSON.parse(msg);
    for (const [client] of clients) {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({ type: 'update', id: playerId, x: data.x, y: data.y }));
      }
    }
  });

  ws.on('close', async () => {
    clients.delete(ws);
    console.log(`Player ${playerId} disconnected. Active clients: ${clients.size}`);
    try {
      const newCount = await redis.hincrby(SERVER_KEY, 'players', -1);
      console.log(`Players jetzt: ${newCount} @ public:${PUBLIC_PORT}`);
    } catch (e) {
      console.error('Redis hincrby -1 failed:', e.message);
    }
  });
});

// Clean shutdown
const shutdown = async () => {
  try { await redis.del(SERVER_KEY); } catch {}
  console.log('🛑 Shutting down gameserver...');
  try { await redis.quit(); } catch {}
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
