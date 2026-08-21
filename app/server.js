// index.js — your file, trimmed down
const express = require('express');
const { initDb, getPool } = require('./src/db');
const { initCache, getCache } = require('./src/cache');
const routes = require('./src/routes/orderRoutes.js');

const app = express();
const PORT = 3000;

app.use(express.json());
app.get('/health', (req, res) => res.status(200).send('OK'));
app.use(routes);

Promise.all([initDb(), initCache()])
  .then(() => app.listen(PORT, () => console.log(`Server running on ${PORT}`)))
  .catch(err => {
    console.error('Startup failed:', err);
    process.exit(1);
  });

process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing pool and cache client');
  try { await getPool().end(); } catch { /* pool may not exist yet */ }
  try { await getCache().quit(); } catch { /* client may not exist yet */ }
  process.exit(0);
});