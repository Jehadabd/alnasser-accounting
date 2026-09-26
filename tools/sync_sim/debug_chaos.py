# -*- coding: utf-8 -*-
"""أداة تشخيص: تشغيل فوضى واحدة وطباعة تفاصيل أول عميل مختلف."""
import sys
from collections import defaultdict

from run import chaos_run
from world import ALL_FIXES

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 0
mode = sys.argv[2] if len(sys.argv) > 2 else "fixed"
fx = ALL_FIXES if mode == "fixed" else frozenset()
if len(sys.argv) > 3:
    fx = ALL_FIXES - set(sys.argv[3].split(","))
idx = int(sys.argv[5]) if len(sys.argv) > 5 else 0
w, e1, e2 = chaos_run(fx, seed, ops=int(sys.argv[4]) if len(sys.argv) > 4 else 400, restart=False, profile=(sys.argv[6] if len(sys.argv) > 6 else "normal"))
print(len(e1), "errors after settle;", len(e2), "after restart")
for e in e1[:12]:
    print("  ", e)
if not e1:
    sys.exit(0)
e = e1[idx]
cu = e.split("رصيد ")[1].split(" ")[0] if "رصيد " in e else e.split("العميل ")[1].split(" ")[0]
print("\nالعميل:", cu, "الحقيقة:", w.truth.balance(cu), w.truth.customers[cu])
print("معاملات الحقيقة:")
for u, t in w.truth.txs.items():
    if t["cust"] == cu:
        print("   ", u, t)
for u, i in w.truth.invoices.items():
    if i["cust"] == cu:
        print("    INV", u, i, "contrib", w.truth.contribution(i))
print("السحابة:")
for u, d in w.cloud.colls["transactions"].items():
    if d.data.get("customerSyncUuid") == cu:
        print("   ", u, d.data.get("amountChanged"), "del=", d.data.get("isDeleted"), "by", d.data.get("deviceId"), "inv", d.data.get("invoiceSyncUuid"))
for u, d in w.cloud.colls["invoices"].items():
    if d.data.get("customer_sync_uuid") == cu:
        print("    INV", u, d.data.get("payment_type"), d.data.get("status"), d.data.get("total_amount"), d.data.get("amount_paid_on_invoice"), "v", d.data.get("version"), [(t["transaction_uuid"], t["amount_changed"], t["is_deleted"]) for t in d.data.get("transactions")])
for name, dv in w.devices.items():
    c = dv.customer_by_uuid(cu)
    if not c:
        print(name, "— لا يوجد")
        continue
    rows = dv.q("SELECT transaction_uuid, amount_changed, is_deleted, is_created_by_me, is_uploaded, invoice_sync_uuid FROM transactions WHERE customer_id=? ORDER BY id", (c["id"],))
    act = sum(r["amount_changed"] for r in rows if not r["is_deleted"])
    print(f"{name}: shown={c['current_total_debt']} sum={act} del={c['is_deleted']} tomb={c['tombstoned']} own={c['is_created_by_me']}")
    for r in rows:
        tr = w.truth.txs.get(r["transaction_uuid"])
        mark = "" if (tr and (tr["amount"] == r["amount_changed"]) and (tr["deleted"] == bool(r["is_deleted"]))) else "   <<<"
        print("     ", r, mark)
print("\nأخطاء مهام:", w.sim.task_errors.most_common(5))
print("metrics:", dict(w.metrics))
