const fs = require('fs');
const https = require('https');
const express = require('express');
const WebSocket = require('ws');
const path = require('path');

const app = express();

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

  // Schick dem neuen Client seine ID
  ws.send(JSON.stringify({ type: "init", id: playerId }));

  console.log(`Player ${playerId} connected. Active players: ${clients.size}`);

  ws.on('message', msg => {
    const data = JSON.parse(msg);

    // Broadcast an alle anderen
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

    // Informiere andere Clients, dass er weg ist
    for (let [client] of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({ type: "remove", id: playerId }));
      }
    }
  });
});

// Server starten
const PORT = 8443;
httpsServer.listen(PORT, () => {
  console.log(`HTTPS Server läuft auf https://localhost:${PORT}`);
});

const shutdown = async () => {
  console.log('🛑 Shutting down API service...');
  process.exit(0);
};
process.on('SIGTERM', shutdown);