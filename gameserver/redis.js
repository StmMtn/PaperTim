const Redis = require('ioredis');
const redis = new Redis(); // Standard localhost:6379

const serverId = `server:${Date.now()}`;

// beim Start registrieren
async function registerServer(port) {
  await redis.hset(serverId, {
    port,
    players: 0,
    status: 'running'
  });
  // optional: automatisch nach 60s verfallen lassen
  await redis.expire(serverId, 60*60);
}

// beim Stop deregistrieren
async function unregisterServer() {
  await redis.del(serverId);
}

httpsServer.listen(PORT, async () => {
  console.log(`HTTPS Server läuft auf https://localhost:${PORT}`);
  await registerServer(PORT);
});

process.on('SIGTERM', async () => {
  await unregisterServer();
  process.exit(0);
});
const shutdown = async () => {
  console.log('🛑 Shutting down API service...');
  process.exit(0);
};
process.on('SIGTERM', shutdown);