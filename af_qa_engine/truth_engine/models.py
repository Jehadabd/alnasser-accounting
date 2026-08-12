# af_qa_engine/truth_engine/models.py
from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Optional

@dataclass
class InvoiceItem:
    product_name: str
    quantity: float
    price: float
    item_total: float
    sale_type: str  # 'قطعة', 'كرتون', etc.
    cost_price: float = 0.0

@dataclass
class Invoice:
    id: Optional[int]
    customer_name: str
    total_amount: float
    discount: float
    paid_amount: float
    payment_type: str  # 'نقد' or 'دين'
    status: str
    date: datetime
    items: List[InvoiceItem] = field(default_factory=list)
    loading_fee: float = 0.0
    return_amount: float = 0.0

    @property
    def net_total(self) -> float:
        return (self.total_amount + self.loading_fee) - self.discount

    @property
    def remaining_debt(self) -> float:
        if self.payment_type == 'نقد':
            return 0.0
        return self.net_total - self.paid_amount

@dataclass
class Customer:
    id: int
    name: str
    current_debt: float
    last_transaction_date: Optional[datetime]

@dataclass
class Transaction:
    id: int
    customer_id: int
    amount_changed: float
    balance_before: float
    balance_after: float
    type: str
    date: datetime
    invoice_id: Optional[int] = None
