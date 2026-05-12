# models.py — Data models
# FIXME: missing type hints in several methods

from dataclasses import dataclass
from typing import Optional, List


@dataclass
class User:
    id: int
    username: str
    email: str
    is_active: bool = True
    # TODO: add role/permission field


@dataclass
class Product:
    id: int
    name: str
    price: float
    # FIXME: price should use Decimal for currency
    category: str = "uncategorized"


# TODO: add validation methods to all models
class OrderProcessor:
    def __init__(self, db_url: str):
        self.db_url = db_url

    def create_order(self, user: User, products: List[Product]) -> dict:
        # FIXME: no inventory check before creating order
        total = sum(p.price for p in products)
        return {
            "user_id": user.id,
            "products": [p.id for p in products],
            "total": total,
            "status": "pending"
        }

    def cancel_order(self, order_id: int) -> bool:
        # TODO: implement refund logic
        print(f"Cancelling order {order_id}")
        return True
