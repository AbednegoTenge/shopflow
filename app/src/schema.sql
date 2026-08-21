-- schema.sql
CREATE TABLE orders (
  id          SERIAL PRIMARY KEY,
  customer_id VARCHAR(64) NOT NULL,
  item        VARCHAR(255) NOT NULL,
  quantity    INTEGER NOT NULL CHECK (quantity > 0),
  status      VARCHAR(32) NOT NULL DEFAULT 'pending',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);