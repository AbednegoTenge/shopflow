// worker/index.js
const { Client } = require('pg');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const fs = require('fs');
const path = require('path');

const sm = new SecretsManagerClient({ region: process.env.AWS_REGION || 'us-east-1' });
const caBundle = fs.readFileSync(path.join(__dirname, 'global-bundle.pem')).toString();

exports.handler = async (event) => {
  const secret = await sm.send(new GetSecretValueCommand({ SecretId: process.env.SECRET_ARN }));
  const { username, password } = JSON.parse(secret.SecretString);

  const client = new Client({
    host: process.env.DB_HOST,
    port: 5432,
    database: process.env.DB_NAME,
    user: username,
    password,
    ssl: { ca: caBundle }
  });
  await client.connect();

  try {
    for (const record of event.Records) {
      const evt = JSON.parse(record.body);   // the full EventBridge event, not double-wrapped
      const { orderId } = evt.detail;

      console.log(`Order ${orderId}: decrementing inventory (placeholder)`);
      console.log(`Order ${orderId}: sending confirmation email (placeholder)`);

      await client.query('UPDATE orders SET status = $1 WHERE id = $2', ['confirmed', orderId]);
    }
  } finally {
    await client.end();
  }
};
