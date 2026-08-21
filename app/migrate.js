const fs = require('fs');
const path = require('path');
const { initDb, getPool } = require('./src/db');

(async () => {
  await initDb();
  const schema = fs.readFileSync(path.join(__dirname, 'src', 'schema.sql'), 'utf8');
  await getPool().query(schema);
  console.log('Migration applied successfully');
  await getPool().end();
  process.exit(0);
})().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
