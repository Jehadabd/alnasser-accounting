# -*- coding: utf-8 -*-
"""
العالم: مجموعة أجهزة + سحابة + «الحقيقة».

الحقيقة لا تُشتق من أي جهاز. هي سجل نوايا المستخدمين: كل فعل نجح في
الواجهة (إضافة، تعديل، تحويل، حذف عميل، فاتورة...) يُسجَّل هنا بأثره
المالي المقصود. بعد انتهاء السيناريو وعودة الجميع للاتصال، يجب أن يعرض
كل جهاز لكل عميل رصيداً يساوي الحقيقة تماماً.
"""
from collections import Counter, defaultdict

from engine import Sim, Cloud
from device import Device, CREDIT, INVOICE_SAVED

ALL_FIXES = frozenset({
    "fresh", "pending", "edits", "rate", "lock", "tomb", "owner", "identity", "keepowner",
    "oldsafe", "removed", "invoice", "recon", "live", "bootstrap", "ackver", "sign",
    "insertguard", "initfix",
})


class Truth:
    def __init__(self):
        self.customers = {}  # uuid -> {name, tomb}
        self.txs = {}  # uuid -> {cust, amount, owner, deleted, kind}
        self.invoices = {}  # uuid -> {...}
        self.forged = set()
        self.phantoms = set()

    def add_customer(self, uuid, name, creator):
        self.customers.setdefault(uuid, {"name": name, "tomb": False, "creator": creator})

    def rename(self, uuid, name):
        self.customers[uuid]["name"] = name

    def add_tx(self, uuid, cust, amount, owner, kind):
        self.txs[uuid] = {"cust": cust, "amount": amount, "owner": owner, "deleted": False, "kind": kind}

    def edit_tx(self, uuid, amount):
        if uuid in self.txs:
            self.txs[uuid]["amount"] = amount

    def foreign_local_convert(self, uuid):
        if uuid in self.txs:
            self.txs[uuid]["amount"] = -self.txs[uuid]["amount"]

    def delete_customer(self, cust, known_tx, known_inv=()):
        """حذف العميل يُبطل كل ما كان يعرفه الجهاز الحاذف لحظة الحذف (معاملات
        وديون فواتير). ما أُنشئ أوفلاين على جهاز لم يعلم بالحذف يبقى ويُعيد تنشيطه."""
        self.customers[cust]["tomb"] = True
        for u in known_tx:
            if u in self.txs:
                self.txs[u]["deleted"] = True
        for u in known_inv:
            if u in self.invoices:
                self.invoices[u]["voided"] = True

    def owner_accepted_tombstone(self, uuid):
        pass

    def owner_strict_void(self, cust, owner):
        for t in self.txs.values():
            if t["cust"] == cust and t["owner"] == owner:
                t["deleted"] = True

    def set_invoice(self, uuid, cust, creator, total, paid, ptype, status):
        voided = self.invoices.get(uuid, {}).get("voided", False)  # إبطال حذف العميل نهائي
        self.invoices[uuid] = {"cust": cust, "creator": creator, "total": total, "paid": paid,
                               "ptype": ptype, "status": status, "voided": voided}

    def delete_invoice(self, uuid):
        self.invoices[uuid]["voided"] = True

    def contribution(self, inv):
        if inv.get("voided"):
            return 0.0
        if inv["ptype"] != CREDIT or inv["status"] != INVOICE_SAVED:
            return 0.0
        return max(inv["total"] - inv["paid"], 0.0)

    def balance(self, cust):
        s = sum(t["amount"] for t in self.txs.values() if t["cust"] == cust and not t["deleted"])
        s += sum(self.contribution(i) for i in self.invoices.values() if i["cust"] == cust)
        return round(s, 2)

    def has_active(self, cust):
        return any(t["cust"] == cust and not t["deleted"] for t in self.txs.values()) or \
            any(i["cust"] == cust and self.contribution(i) > 0 for i in self.invoices.values())

    def visible(self, cust):
        c = self.customers[cust]
        return (not c["tomb"]) or self.has_active(cust)


class World:
    def __init__(self, fixes=frozenset(), seed=0, n=10, platforms=None, shared_secret=None):
        self.fixes = set(fixes)
        self.sim = Sim(seed)
        self.cloud = Cloud(self.sim)
        self.truth = Truth()
        self.metrics = Counter()
        self.devices = {}
        for i in range(1, n + 1):
            name = f"D{i}"
            plat = (platforms or {}).get(name, "desktop")
            self.devices[name] = Device(self, name, platform=plat, shared_secret=shared_secret)

    def d(self, name):
        return self.devices[name]

    # ------------------------------------------------------------------
    def boot_all(self, names=None):
        for n in names or self.devices:
            self.devices[n].boot()

    def run(self, seconds):
        self.sim.run_for(seconds)

    def everyone_online(self):
        for dv in self.devices.values():
            dv.set_online(True)
            if not dv.running:
                dv.boot()

    def restart(self, name, gap=5.0):
        dv = self.devices[name]
        dv.crash()
        self.run(gap)
        dv.boot()

    def restart_all(self):
        for dv in self.devices.values():
            dv.crash()
        self.run(5)
        for dv in self.devices.values():
            dv.boot()

    # UI helpers that also register customers in the truth
    def add_customer(self, dev, name, phone=None, opening=0.0):
        cid, uuid = self.devices[dev].ui_add_customer(name, phone, opening)
        if uuid in self.truth.customers:
            self.truth.customers[uuid]["tomb"] = False  # إعادة تنشيط عميل محذوف
        self.truth.add_customer(uuid, name, dev)
        return uuid

    def safe(self, fn, *a, **k):
        """فعل واجهة قد يرفض (يرمي استثناء) — يُسجَّل خطأً للمستخدم ولا يغير الحقيقة."""
        try:
            return fn(*a, **k)
        except Exception as e:  # noqa
            self.metrics["ui_rejected"] += 1
            return e

    # ------------------------------------------------------------------
    def settle(self, hours=3.0, restart=False):
        """الجميع متصل ثم تشغيل ساعات حتى يهدأ النظام."""
        self.everyone_online()
        w0 = self.cloud.total_writes()
        self.run(hours * 3600 - 3600)
        w1 = self.cloud.total_writes()
        self.run(3600)
        w2 = self.cloud.total_writes()
        self.metrics["writes_last_hour"] = w2 - w1
        self.metrics["writes_settle"] = w2 - w0
        if restart:
            self.restart_all()
            self.run(3600)

    # ------------------------------------------------------------------
    def check(self, devices=None, max_list=None):
        """يعيد قائمة الخلل: كل جهاز مقابل الحقيقة."""
        errs = []
        names = devices or list(self.devices)
        for name in names:
            dv = self.devices[name]
            view = dv.view()
            for cu, info in self.truth.customers.items():
                tb = self.truth.balance(cu)
                vis = self.truth.visible(cu)
                if cu not in view:
                    if vis or abs(tb) > 0.01:
                        errs.append(f"{name}: العميل {self.label(cu)} مفقود (الصحيح {fmt(tb)})")
                    continue
                shown, summ, hidden = view[cu]
                if abs(summ - shown) > 0.01:
                    errs.append(f"{name}: رصيد {self.label(cu)} المعروض {fmt(shown)} ≠ مجموع معاملاته {fmt(summ)}")
                if hidden and abs(tb) > 0.01:
                    errs.append(f"{name}: العميل {self.label(cu)} مخفي (محذوف) والصحيح {fmt(tb)}")
                    continue
                if not hidden and not vis and abs(shown) > 0.01:
                    errs.append(f"{name}: العميل {self.label(cu)} محذوف فعلاً لكنه ظاهر برصيد {fmt(shown)}")
                    continue
                if abs(shown - tb) > 0.01 and not (hidden and not vis):
                    errs.append(f"{name}: رصيد {self.label(cu)} = {fmt(shown)} والصحيح {fmt(tb)} (فرق {fmt(shown - tb)})")
            for cu, (shown, summ, hidden) in view.items():
                if cu not in self.truth.customers and not hidden and abs(shown) > 0.01:
                    errs.append(f"{name}: هوية عميل زائفة {cu} برصيد {fmt(shown)}")
        return errs

    def label(self, cu):
        return cu

    def cloud_writes_per_hour(self):
        return self.metrics.get("writes_last_hour", 0)


def fmt(x):
    if abs(x - round(x)) < 1e-9:
        return str(int(round(x)))
    return f"{x:.2f}"
