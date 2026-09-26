# -*- coding: utf-8 -*-
"""تتبّع معاملة واحدة على جهاز واحد خلال تشغيلة فوضى (أداة تشخيص)."""
import sys

import device as devmod
from run import chaos_run
from world import ALL_FIXES

seed, dev, tx = int(sys.argv[1]), sys.argv[2], sys.argv[3]
fx = ALL_FIXES if (len(sys.argv) < 5 or sys.argv[4] == "fixed") else frozenset()
LOG = []

orig_apply = devmod.Device._apply_transaction_change
orig_up = devmod.Device.upload_transaction
orig_edit = devmod.Device.ui_edit_tx
orig_orph = devmod.Device._add_to_orphans


def apply_wrap(self, uuid, data):
    if uuid == tx and self.name == dev:
        row = self.q1("SELECT amount_changed, is_deleted FROM transactions WHERE transaction_uuid=?", (uuid,))
        LOG.append(f"{self.sim.now:9.1f} {self.name} APPLY amount={data.get('amountChanged')} del={data.get('isDeleted')} by={data.get('deviceId')} local={row} online={self.online}")
    r = yield from orig_apply(self, uuid, data)
    if uuid == tx and self.name == dev:
        row = self.q1("SELECT amount_changed, is_deleted FROM transactions WHERE transaction_uuid=?", (uuid,))
        LOG.append(f"{self.sim.now:9.1f} {self.name}   -> local={row}")
    return r


def up_wrap(self, t, cs, force=False, tombstone_foreign=False):
    if t.get("transaction_uuid") == tx:
        LOG.append(f"{self.sim.now:9.1f} {self.name} UPLOAD start amount={t.get('amount_changed')} online={self.online}")
    r = yield from orig_up(self, t, cs, force, tombstone_foreign)
    if t.get("transaction_uuid") == tx:
        c = self.cloud.get("transactions", tx) or {}
        LOG.append(f"{self.sim.now:9.1f} {self.name} UPLOAD done ok={r} cloud={c.get('amountChanged')}")
    return r


def edit_wrap(self, u, a):
    if u == tx:
        LOG.append(f"{self.sim.now:9.1f} {self.name} EDIT -> {a}")
    return orig_edit(self, u, a)


def orph_wrap(self, u, data):
    if u == tx and self.name == dev:
        LOG.append(f"{self.sim.now:9.1f} {self.name} ORPHAN amount={data.get('amountChanged')}")
    return orig_orph(self, u, data)


devmod.Device._apply_transaction_change = apply_wrap
devmod.Device.upload_transaction = up_wrap
devmod.Device.ui_edit_tx = edit_wrap
devmod.Device._add_to_orphans = orph_wrap

w, e1, e2 = chaos_run(fx, seed, restart=False)
for l in LOG:
    print(l)
d = w.d(dev)
print("final local:", d.q1("SELECT amount_changed, is_deleted FROM transactions WHERE transaction_uuid=?", (tx,)))
print("cloud:", (w.cloud.get("transactions", tx) or {}).get("amountChanged"))
L = [x for x in d.listeners if x.name == "transactions"]
print("listener view ver:", [x.view.get(tx) for x in L], "doc ver:", w.cloud.colls["transactions"][tx].ver if tx in w.cloud.colls["transactions"] else None, "active:", [x.active for x in L])
