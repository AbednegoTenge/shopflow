const { getPool } = require('../db.js')
const { getCache } = require('../cache.js')
const { publishOrderCreated } = require('../events.js')

const ORDER_CACHE_TTL_SECONDS = 60
const ORDERS_LIST_CACHE_KEY = 'orders:latest'
const orderCacheKey = (id) => `order:${id}`

async function cacheGet(key) {
    try {
        return await getCache().get(key);
    } catch (err) {
        console.error('Cache read failed, falling back to DB:', err);
        return null;
    }
}

async function cacheSet(key, value) {
    try {
        await getCache().set(key, JSON.stringify(value), { EX: ORDER_CACHE_TTL_SECONDS });
    } catch (err) {
        console.error('Cache write failed:', err);
    }
}

async function cacheDel(...keys) {
    try {
        await getCache().del(keys);
    } catch (err) {
        console.error('Cache invalidation failed:', err);
    }
}

const addOrder = async (req, res) => {
    try {
        const pool = getPool();
        const result = await pool.query(
        'INSERT INTO orders (customer_id, item, quantity) VALUES ($1, $2, $3) RETURNING id',
        [req.body.customer_id, req.body.item, req.body.quantity]
        );
        const orderId = result.rows[0].id;
        await cacheDel(ORDERS_LIST_CACHE_KEY);
        try {
            await publishOrderCreated(orderId);
        } catch (err) {
            console.error('Failed to publish OrderCreated event:', err);
        }
        res.status(201).json({ orderId });
  } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to create order' });
  }
}

const getOrder = async (req, res) => {
    const cacheKey = orderCacheKey(req.params.id);
    const cached = await cacheGet(cacheKey);
    if (cached) {
        return res.status(200).json(JSON.parse(cached));
    }

    try {
        const pool = getPool();
        const result = await pool.query('SELECT * FROM orders WHERE id = $1', [req.params.id]);
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Order not found' });
        }
        const order = result.rows[0];
        await cacheSet(cacheKey, order);
        res.status(200).json(order);
  } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch order' });
  }
}

const getOrders = async (req, res) => {
    const cached = await cacheGet(ORDERS_LIST_CACHE_KEY);
    if (cached) {
        return res.status(200).json(JSON.parse(cached));
    }

    try {
        const pool = getPool();
        const result = await pool.query('SELECT * FROM orders ORDER BY created_at DESC LIMIT 100');
        await cacheSet(ORDERS_LIST_CACHE_KEY, result.rows);
        res.status(200).json(result.rows);
  } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch orders' });
  }
}

const deleteOrder = async (req, res) => {
    try {
        const pool = getPool();
        const result = await pool.query('DELETE FROM orders WHERE id = $1 RETURNING id', [req.params.id]);
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Order not found' });
        }
        await cacheDel(orderCacheKey(req.params.id), ORDERS_LIST_CACHE_KEY);
        res.status(204).send();
  } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to delete order' });
  }
}


module.exports = {
    addOrder,
    getOrder,
    getOrders,
    deleteOrder
}
