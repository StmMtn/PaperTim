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

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../client/Game/game.html'));
});

// Game HTML benutzen
app.use('/', express.static(path.join(__dirname, '../client/Game')));

// HTTPS Server erstellen
const httpsServer = https.createServer(serverOptions, app);

// WebSocket Server auf HTTPS-Server aufsetzen
const wss = new WebSocket.Server({ server: httpsServer });

const clients = new Set();

wss.on('connection', ws => {
  if (clients.size >= 10) {
    ws.close(1000, "Max players reached");
    return;
  }

  clients.add(ws);
  console.log("Client connected:", clients.size);

  ws.on('message', message => {
    // Broadcast an alle außer Sender
    for (let client of clients) {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(message);
      }
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
    console.log("Client disconnected:", clients.size);
  });
});

// Server starten
const PORT = 8443;
httpsServer.listen(PORT, () => {
  console.log(`HTTPS Server läuft auf https://localhost:${PORT}`);
});
