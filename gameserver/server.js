const express = require('express');
const WebSocket = require('ws');
const path = require('path');
const Redis = require('ioredis');

const app = express();

// Redis konfigurieren
const redis = new Redis({
  host: process.env.REDIS_HOST || 'redis', // Docker-Service Name oder Hostname
  port: parseInt(process.env.REDIS_PORT) || 6379
});

// Game HTML benutzen
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, './client/Game/game.html'));
});

app.use('/', express.static(path.join(__dirname, './client/Game')));

// HTTP Server erstellen
const PORT = process.env.PORT || 8443;
const server = app.listen(PORT, async () => {
  console.log(`HTTP Server läuft auf http://localhost:${PORT}`);

  // Server in Redis registrieren
  const serverKey = `server:${PORT}`;
  await redis.hset(serverKey, {
    host: 'gameserver', // oder der Container-Hostname falls Remote-Zugriff
    port: PORT,
    players: 0
  });
  await redis.expire(serverKey, 3600); // 1 Stunde
  console.log(`Server registriert in Redis unter Key ${serverKey}`);
});

// WebSocket Server auf HTTP-Server aufsetzen
const ws = new WebSocket.Server({ server });

let nextId = 1;
const clients = new Map(); // ws -> {id}
ws.on('connection', async ws => {
  if (clients.size >= 10) {
    ws.close(1000, "Max players reached");
    return;
  }

  const playerId = nextId++;
  clients.set(ws, { id: playerId });

  ws.send(JSON.stringify({ type: "init", id: playerId }));
  console.log(`Player ${playerId} connected. Active players: ${clients.size}`);

  // Redis: Spielerzahl hochzählen
  const PUBLIC_PORT = process.env.PUBLIC_PORT || PORT;
  const serverKey = `server:${PUBLIC_PORT}`;
  const newCount = await redis.hincrby(serverKey, "players", 1);
  console.log(`Redis players count is now: ${newCount}`);


  ws.on('message', msg => {
    const data = JSON.parse(msg);
    for (let [client, info] of clients) {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({
          type: "update",
          id: playerId,
          x: data.x,
          y: data.y
        }));
      }
    }
  });

  ws.on('close', async () => {
    clients.delete(ws);
    console.log(`Player ${playerId} disconnected. Active clients: ${clients.size}`);

    // Redis: Spielerzahl runterzählen
    const newCount = await redis.hincrby(serverKey, "players", -1);
    console.log(`Redis players count after disconnect: ${newCount}`);

    for (let [client] of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({ type: "remove", id: playerId }));
      }
    }
  })
});


// Clean shutdown
const shutdown = async () => {
  const serverKey = `server:${PORT}`;
  await redis.del(serverKey);
  console.log('🛑 Shutting down API service...');
  await redis.quit();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
