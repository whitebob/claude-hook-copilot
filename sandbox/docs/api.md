# API Reference

## GET /api/users
Returns list of users.
- **200**: `[{ "id": 1, "username": "alice" }]`
- **500**: `{ "error": "database unavailable" }`

## POST /api/auth/login
Authenticate user.
- Body: `{ "username": "alice", "password": "secret" }`
- **200**: `{ "token": "abc123" }`
- **401**: `{ "error": "invalid credentials" }`

## GET /api/products
Returns product catalog.
- **200**: `[{ "id": 101, "name": "Widget", "price": 9.99 }]`

## POST /api/orders
Create new order.
- Body: `{ "user_id": 1, "product_ids": [101, 102] }`
- **201**: `{ "order_id": 1004, "total": 34.98 }`
- **400**: `{ "error": "product out of stock" }`
