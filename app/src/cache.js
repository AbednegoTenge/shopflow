// src/cache.js
const { createClient } = require('redis');

let client;

async function initCache() {
  client = createClient({
    socket: {
      host: process.env.REDIS_HOST,
      port: Number(process.env.REDIS_PORT) || 6379,
    },
  });

  client.on('error', (err) => console.error('Redis client error:', err));

  await client.connect();
  await client.ping();
  console.log('Redis client ready');
}

function getCache() {
  if (!client) throw new Error('Redis client not initialized yet');
  return client;
}

module.exports = { initCache, getCache };
