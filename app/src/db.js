// src/db.js
const { Pool } = require('pg');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const path = require('path');
const fs = require('fs');

let pool;

async function initDb() {
  const sm = new SecretsManagerClient({ region: process.env.AWS_REGION || 'us-east-1' });
  const sec = await sm.send(new GetSecretValueCommand({ SecretId: process.env.SECRET_ARN }));
  const { password, username } = JSON.parse(sec.SecretString);

  pool = new Pool({
    host: process.env.DB_HOST,
    port: 5432,
    database: process.env.DB_NAME,
    user: username,
    password,
    ssl: { ca: fs.readFileSync(path.join(__dirname, '..', 'global-bundle.pem')).toString() },
    max: 10,
    idleTimeoutMillis: 30000,
  });

  await pool.query('SELECT 1');
  console.log('Database pool ready');
}

function getPool() {
  if (!pool) throw new Error('Database pool not initialized yet');
  return pool;
}

module.exports = { initDb, getPool };