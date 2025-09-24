import express from 'express';
import WebSocket, { WebSocketServer } from 'ws';
import path from 'path';
import Redis from 'ioredis';
import { fileURLToPath } from 'url';
import { report } from 'process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const redis = new Redis({ host: REDIS_HOST, port: REDIS_PORT });
redis.on('error', (e) => console.error('[Redis] error:', e.message));

// Container lauscht auf 8443
const INTERNAL_PORT = Number(process.env.INTERNAL_PORT) || 8443;

const PUBLIC_PORT = Number(process.env.PUBLIC_PORT) || INTERNAL_PORT;
const SERVER_KEY = `server:${PUBLIC_PORT}`;

app.use((req, res, next) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  next();
});

app.get('/config', (req, res) => {
  const hostHeader = req.headers['host'];
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

// WebSocket an HTTP-Server hängen
const wss = new WebSocketServer({ server });
let nextId = 1;

// globaler Überblick (für Redis-Zähler etc.)
const clients = new Map();

const rooms = new Map(); 

function getOrCreateRoom(roomId) {
  if (!rooms.has(roomId)) rooms.set(roomId, new Set());
  return rooms.get(roomId);
}

function broadcastToRoom(roomId, msgObj, excludeWs = null) {
  const set = rooms.get(roomId);
  if (!set) return;
  const data = JSON.stringify(msgObj);
  for (const ws of set) {
    if (ws !== excludeWs && ws.readyState === WebSocket.OPEN) {
      ws.send(data);
    }
  }
}

function getRoomFromReq(req) {
  try {
    const url = new URL(req.url, 'http://localhost');
    const r = url.searchParams.get('room');
    return (r && String(r)) || 'default';
  } catch {
    return 'default';
  }
}

wss.on('connection', async (ws, req) => {
  if (clients.size >= 4) { ws.close(1000, 'Max players reached'); return; }
  // reportWinner(1); // TESTING
  const playerId = nextId++;
  const roomId = getRoomFromReq(req);
  const playerName = getNameFromReq(req) || `Player ${playerId}`;
  const set = getOrCreateRoom(roomId);

  // Roster für neuen Client
  const existingIds = [];
  const readyIds = [];
  const names = {}; 
  for (const sock of set) {
    const meta = clients.get(sock);
    if (!meta) continue;
    existingIds.push(meta.id);
    if (meta.ready) readyIds.push(meta.id);
    names[meta.id] = meta.name || '';
  }

  // init + roster nur an neuen Client
  ws.send(JSON.stringify({ type: 'init', id: playerId }));
  ws.send(JSON.stringify({ type: 'roster', ids: existingIds }));
  ws.send(JSON.stringify({ type: 'ready_state', ids: readyIds }));
  ws.send(JSON.stringify({ type: 'names', names}));

  // registrieren & allen anderen "join"
  clients.set(ws, { id: playerId, roomId, ready: false, name: playerName});
  set.add(ws);
  try { await redis.hincrby(SERVER_KEY, 'players', +1); } catch {}
  broadcastToRoom(roomId, { type: 'join', id: playerId }, ws);
  broadcastToRoom(roomId, { type: 'name', id: playerId, name: playerName }, ws);

  ws.on('message', (msg) => {
    let data; try { data = JSON.parse(msg); } catch { return; }

    if (data.type === 'ready') {
      const meta = clients.get(ws);
      if (meta) meta.ready = !!data.ready;
    //  broadcastToRoom(roomId, { type: 'ready', id: playerId, ready: !!data.ready }, ws);
      broadcastToRoom(roomId, { type: 'ready', id: playerId, ready: !!data.ready });
      return;
    }
  
  if (data.type === 'name') {
    const meta = clients.get(ws);
    if (meta) meta.name = String(data.name || '');
    broadcastToRoom(roomId, { type: 'name', id: playerId, name: meta?.name || '' }, ws);
    return;
  }

  if (data.type === 'name') {
    const meta = clients.get(ws);
    if (meta) meta.name = String(data.name || '');
    broadcastToRoom(roomId, { type: 'name', id: playerId, name: meta?.name || '' }, ws);
    return;
  }
    if (data.type === 'input') {
      broadcastToRoom(roomId, { type: 'input', id: playerId, left: !!data.left, right: !!data.right });
      return;
    }
    if (data.type === 'round_start') {
      broadcastToRoom(roomId, data);
      return;
    }
    if (data.type === 'round_over') {
      broadcastToRoom(roomId, { type: 'round_over', winner_pid: data.winner_pid, draw: !!data.draw });
      return;
    }


    if (data.x !== undefined && data.y !== undefined) {
      broadcastToRoom(roomId, { type: 'update', id: playerId, x: data.x, y: data.y }, ws);
      return;
    }
  });

  ws.on('close', async () => {
    const meta = clients.get(ws);
    clients.delete(ws);
    if (meta) {
      const roomSet = rooms.get(meta.roomId);
      if (roomSet) { roomSet.delete(ws); if (roomSet.size === 0) rooms.delete(meta.roomId); }
      broadcastToRoom(meta.roomId, { type: 'remove', id: meta.id });
    }
    try { await redis.hincrby(SERVER_KEY, 'players', -1); } catch {}
  });
});

/*async function reportWinner(winnerId) {
  try {
    await fetch('http://masterserver:3000/internal/report', {
      method: 'POST',
      headers: { 'Content-Type':'application/json', 'x-api-key': process.env.MASTER_API_KEY },
      body: JSON.stringify({ user_id: winnerId, trophies: 1, games: 1 })
    });
  } catch (err) {
    console.error('Report failed:', err.message);
  }
} */
function getNameFromReq(req) {
  try {
    const url = new URL(req.url, 'http://localhost');
    const n = url.searchParams.get('name');
    return (n && String(n)) || '';
  } catch {
    return '';
  }
}

// Clean shutdown
const shutdown = async () => {
  try { await redis.del(SERVER_KEY); } catch {}
  console.log('🛑 Shutting down gameserver...');
  try { await redis.quit(); } catch {}
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
