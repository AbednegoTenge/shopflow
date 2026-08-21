const express = require('express');
const router = express.Router();
const { addOrder, getOrder, getOrders, deleteOrder } = require("../controllers/orderController.js")

router.post('/orders', addOrder);
router.get('/orders/:id', getOrder);
router.get('/orders', getOrders);
router.delete('/orders/:id', deleteOrder);

module.exports = router;