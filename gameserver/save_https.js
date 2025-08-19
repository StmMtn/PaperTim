const fs = require('fs');
const https = require('https');
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

// HTTPS Zertifikate laden
const serverOptions = {
  key: fs.readFileSync('localhost-key.pem'),
  cert: fs.readFileSync('localhost.pem')
};

// Game HTML benutzen
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, './client/Game/game.html'));
});

app.use('/', express.static(path.join(__dirname, './client/Game')));

// HTTPS Server erstellen
const httpsServer = https.createServer(serverOptions, app);

// WebSocket Server auf HTTPS-Server aufsetzen
const wss = new WebSocket.Server({ server: httpsServer });

let nextId = 1;
const clients = new Map(); // ws -> {id}

wss.on('connection', ws => {
  if (clients.size >= 10) {
    ws.close(1000, "Max players reached");
    return;
  }

  const playerId = nextId++;
  clients.set(ws, { id: playerId });

  ws.send(JSON.stringify({ type: "init", id: playerId }));
  console.log(`Player ${playerId} connected. Active players: ${clients.size}`);

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

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`Player ${playerId} disconnected. Active clients: ${clients.size}`);
    for (let [client] of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({ type: "remove", id: playerId }));
      }
    }
  });
});

// Server starten
const PORT = process.env.PORT || 8443;
httpsServer.listen(PORT, async () => {
  console.log(`HTTPS Server läuft auf https://localhost:${PORT}`);

  // Server in Redis registrieren
  const serverKey = `server:${PORT}`;
  await redis.hset(serverKey, {
    host: 'gameserver', // oder der Container-Hostname falls Remote-Zugriff
    port: PORT,
    players: 0
  });
  // Optional: Ablaufzeit setzen, falls Container abstürzt
  await redis.expire(serverKey, 3600); // 1 Stunde

  console.log(`Server registriert in Redis unter Key ${serverKey}`);
});

// Clean shutdown
const shutdown = async () => {
  await redis.del(serverKey);
  console.log('🛑 Shutting down API service...');
  await redis.quit();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
