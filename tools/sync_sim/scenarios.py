# -*- coding: utf-8 -*-
"""
السيناريوهات. كل سيناريو يأخذ عالماً (World) مهيّأً بوضع «حالي» أو «مُصلَح»،
ينفّذ أفعال المستخدمين وأحداث الشبكة، ثم يعيد (ملاحظات، أخطاء إضافية).
الفحص الأساسي (كل جهاز = الحقيقة) يجريه المشغّل بعد السيناريو.
"""
import random

from world import World, fmt
from device import CREDIT, CASH, INVOICE_SAVED

AR = ["محمد", "علي", "حسن", "حسين", "أحمد", "عمر", "خالد", "يوسف", "كريم", "سعد", "زيد", "ماجد", "نور", "هادي", "سالم"]


def boot(w, names=None, t=90):
    w.boot_all(names)
    w.run(t)


def mk_customers(w, dev, k, prefix="عميل", phone=False):
    out = []
    for i in range(k):
        out.append(w.add_customer(dev, f"{prefix} {i+1}", phone=(f"07{i:08d}" if phone else None)))
    return out


def upload_done(w, uuids, coll="transactions"):
    return all(u in w.cloud.colls[coll] for u in uuids)


def wait_until(w, cond, limit, step=1.0):
    t0 = w.sim.now
    while w.sim.now - t0 < limit:
        if cond():
            return w.sim.now - t0
        w.run(step)
    return None


# ══════════════════════════════════════════════════════════════════════════
SCENARIOS = []


def scenario(num, cat, title, balance_only=False):
    def deco(fn):
        SCENARIOS.append({"num": num, "cat": cat, "title": title, "fn": fn, "balance_only": balance_only})
        return fn
    return deco


@scenario("01", "أساسي", "10 أجهزة متصلة، كل جهاز يسجّل 20 معاملة على نفس العملاء")
def s01(w):
    boot(w)
    cs = mk_customers(w, "D1", 5)
    w.run(60)
    rnd = random.Random(1)
    for dn in w.devices:
        for _ in range(20):
            w.safe(w.d(dn).ui_add_tx, rnd.choice(cs), rnd.choice([100, 250, -50, 1000, -300]))
            w.run(rnd.uniform(0.5, 6))
    w.settle()
    return [], []


@scenario("02", "أساسي", "معاملة تصل قبل عميلها (ترتيب معكوس) → يتيمة ثم تُطبَّق")
def s02(w):
    boot(w)
    d3 = w.d("D3")
    cl = [L for L in d3.listeners if L.name == "customers"][0]
    cl.active = False  # تأخير مستمع العملاء على D3
    c = w.add_customer("D1", "زبون الترتيب")
    w.run(5)
    w.safe(w.d("D1").ui_add_tx, c, 700)
    w.run(40)
    orphan = d3.q1("SELECT COUNT(*) c FROM sync_orphans")["c"]
    cl.active = True
    cl.mark_all()
    cl.schedule()
    w.settle()
    return [f"يتيمة على D3 قبل وصول العميل: {orphan}"], []


@scenario("03", "أساسي", "نفس المعاملة تصل 3 مرات (مستمع + سحب كامل + تدقيق) → لا تكرار")
def s03(w):
    boot(w)
    c = w.add_customer("D1", "زبون التكرار")
    w.run(5)
    w.safe(w.d("D1").ui_add_tx, c, 1200)
    w.run(30)
    d2 = w.d("D2")
    w.sim.spawn(d2.perform_full_catch_up(), d2)
    w.sim.spawn(d2.run_self_audit(), d2)
    w.run(30)
    w.restart("D2")
    w.settle()
    return [], []


@scenario("04", "أساسي", "المالك يعدّل مبلغ معاملته (من شاشة العميل) والكل متصل")
def s04(w):
    boot(w)
    c = w.add_customer("D1", "زبون التعديل")
    w.run(5)
    t = w.d("D1").ui_add_tx(c, 1000)
    w.run(60)
    w.safe(w.d("D1").ui_edit_tx, t, 400)
    w.settle()
    return [], []


@scenario("05", "أساسي", "جهاز مطفأ يعود فيجد تعديلاً على معاملة قديمة")
def s05(w):
    boot(w)
    c = w.add_customer("D1", "زبون قديم")
    w.run(5)
    t = w.d("D1").ui_add_tx(c, 1000)
    w.run(60)
    w.d("D5").crash()
    w.run(60)
    w.safe(w.d("D1").ui_edit_tx, t, 300)
    w.run(600)
    w.d("D5").boot()
    w.settle()
    return [], []


@scenario("06", "انقطاع", "جهازان (D9,D10) بلا إنترنت يسجلان 30 معاملة ثم يعودان")
def s06(w):
    boot(w)
    cs = mk_customers(w, "D1", 4)
    w.run(60)
    for dn in ("D9", "D10"):
        w.d(dn).set_online(False)
    rnd = random.Random(6)
    for i in range(30):
        for dn in ("D9", "D10"):
            w.safe(w.d(dn).ui_add_tx, rnd.choice(cs), rnd.choice([150, 90, -40]))
        w.run(20)
    for dn in ("D9", "D10"):
        w.d(dn).set_online(True)
    w.settle()
    return [], []


@scenario("07", "انقطاع/سرعة", "زمن وصول 30 معاملة أوفلاين بعد عودة الإنترنت (لعملاء أنشأهم جهاز آخر)")
def s07(w):
    boot(w)
    cs = mk_customers(w, "D1", 3)
    w.run(60)
    d9 = w.d("D9")
    d9.set_online(False)
    ids = [w.safe(d9.ui_add_tx, cs[i % 3], 100 + i) for i in range(30)]
    w.run(300)
    d9.set_online(True)
    t = wait_until(w, lambda: upload_done(w, ids), 7200)
    w.settle()
    return [f"زمن الرفع الكامل بعد عودة الاتصال: {int(t) if t is not None else '>7200'} ثانية"], []


@scenario("08", "انقطاع/سرعة", "زمن وصول 1500 معاملة بعد انقطاع طويل (يوم عمل كامل)")
def s08(w):
    boot(w, ["D1", "D2", "D9"])
    cs = mk_customers(w, "D1", 20)
    w.run(90)
    d9 = w.d("D9")
    d9.set_online(False)
    rnd = random.Random(8)
    ids = []
    for i in range(1500):
        ids.append(w.safe(d9.ui_add_tx, rnd.choice(cs), rnd.randint(1, 500)))
        if i % 50 == 0:
            w.run(30)
    w.run(600)
    d9.set_online(True)
    t = wait_until(w, lambda: upload_done(w, ids), 4 * 3600, step=30)
    for dn in w.devices:
        if not w.d(dn).running:
            w.d(dn).boot()
    w.settle()
    return [f"اكتمل الرفع بعد {int(t // 60) if t is not None else '>240'} دقيقة"], []


@scenario("09", "انقطاع", "تعديل معاملة أوفلاين بعد إنشائها أوفلاين (لقطة قديمة في طابور الإعادة)")
def s09(w):
    boot(w)
    c = w.add_customer("D1", "زبون اللقطة")
    w.run(60)
    d5 = w.d("D5")
    d5.set_online(False)
    t = w.safe(d5.ui_add_tx, c, 1000)
    w.run(200)  # محاولة الرفع تنتهي بمهلة → طابور الإعادة يحفظ لقطة 1000
    w.safe(d5.ui_edit_tx, t, 250)
    w.run(60)
    d5.set_online(True)
    w.settle()
    cloud = w.cloud.get("transactions", t) or {}
    row = d5.q1("SELECT amount_changed, is_uploaded FROM transactions WHERE transaction_uuid=?", (t,))
    return [f"السحابة تحمل {fmt(cloud.get('amountChanged', 0))} ، الجهاز D5 يعرض {fmt(row['amount_changed'])} ومعلّمة uploaded={bool(row['is_uploaded'])}"], []


@scenario("10", "انقطاع", "جهاز غاب 40 يوماً و«رفض المعاملات القديمة» مفعّل عليه (30 يوم)")
def s10(w):
    boot(w)
    c = w.add_customer("D1", "زبون الغياب")
    w.run(60)
    d8 = w.d("D8")
    d8.settings["reject_old"] = True
    d8.crash()
    w.d("D1").ui_add_tx(c, 5000)
    w.run(300)
    for dv in w.devices.values():
        dv.crash()
    w.sim.now += 40 * 86400  # قفزة 40 يوماً
    w.settle()
    return [], []


@scenario("11", "انقطاع", "انقطاع أثناء الرفع ثم مزامنة فورية على 9 أجهزة مع جهاز مطفأ")
def s11(w):
    boot(w)
    cs = mk_customers(w, "D1", 3)
    w.run(60)
    w.d("D7").crash()
    d1 = w.d("D1")
    for i in range(10):
        w.safe(d1.ui_add_tx, cs[i % 3], 300 + i)
    w.run(0.2)
    d1.set_online(False)
    w.run(120)
    d1.set_online(True)
    w.run(600)
    w.d("D7").boot()
    w.settle()
    return [], []


@scenario("12", "هوية", "نفس الاسم «محمد علي» أُنشئ على D1 و D2 أوفلاين (شخصان مختلفان)")
def s12(w):
    boot(w)
    for dn in ("D1", "D2"):
        w.d(dn).set_online(False)
    a = w.add_customer("D1", "محمد علي")
    w.d("D1").ui_add_tx(a, 1000)
    b = w.add_customer("D2", "محمد علي")
    w.d("D2").ui_add_tx(b, 300)
    w.run(120)
    for dn in ("D1", "D2"):
        w.d(dn).set_online(True)
    w.settle()
    return [], []


@scenario("13", "هوية", "نفس الاسم أُنشئ مرتين لنفس الشخص (بلا معاملات على أحدهما)", balance_only=True)
def s13(w):
    boot(w)
    w.d("D2").set_online(False)
    a = w.add_customer("D1", "علي حسن")
    w.d("D1").ui_add_tx(a, 500)
    w.add_customer("D2", "علي حسن")
    w.run(120)
    w.d("D2").set_online(True)
    w.settle()
    return [], []


@scenario("14", "هوية", "تعديل اسم نفس العميل على جهازين في نفس اللحظة")
def s14(w):
    boot(w)
    c = w.add_customer("D1", "زبون الاسم")
    w.d("D1").ui_add_tx(c, 800)
    w.run(60)
    w.d("D1").ui_edit_customer(c, "زبون الاسم (أ)")
    w.d("D2").ui_edit_customer(c, "زبون الاسم (ب)")
    w.settle()
    names = {dn: (w.d(dn).customer_by_uuid(c) or {}).get("name") for dn in w.devices}
    distinct = sorted(set(n for n in names.values() if n))
    note = f"أسماء نهائية مختلفة بين الأجهزة: {distinct}" if len(distinct) > 1 else "الاسم موحّد"
    return [note], []


@scenario("15", "حذف", "حذف عميل من D1 (الواجهة) — هل يصل الحذف للأجهزة التسعة؟")
def s15(w):
    boot(w)
    c = w.add_customer("D1", "زبون للحذف")
    w.d("D1").ui_add_tx(c, 1500)
    other = w.add_customer("D1", "زبون آخر")
    w.run(60)
    w0 = w.cloud.total_writes("customers")
    w.d("D1").ui_delete_customer(c)
    w.run(720)
    t = w.d("D5").ui_add_tx(other, 42)
    lag = wait_until(w, lambda: t in w.cloud.colls["transactions"], 3 * 3600, step=10)
    w.settle(hours=2)
    storm = w.cloud.total_writes("customers") - w0
    extra = []
    if storm > 200:
        extra.append(f"عاصفة كتابة: {storm} كتابة لمستند عميل واحد بعد حذفه (ترتد بين الأجهزة حتى يُستنفد حد المعدل)")
    if lag is None or lag > 120:
        extra.append(f"شُلّ رفع المعاملات: معاملة جديدة على D5 وصلت السحابة بعد {int(lag//60) if lag else '>180'} دقيقة")
    return [f"كتابات السحابة لمستند العميل المحذوف: {storm} — زمن وصول معاملة لاحقة: {int(lag) if lag else '∞'} ث"], extra


@scenario("16", "حذف", "حذف عميل من D1 ثم إعادة تشغيل D1 (سحب كامل)")
def s16(w):
    boot(w)
    c = w.add_customer("D1", "خالد")
    w.d("D1").ui_add_tx(c, 1000)
    w.run(30)
    w.d("D2").ui_add_tx(c, -100)
    w.run(60)
    w.d("D1").ui_delete_customer(c)
    w.run(300)
    w.restart("D1")
    w.settle(hours=2)
    v = w.d("D1").view().get(c)
    note = f"D1 بعد إعادة التشغيل: «خالد» {'غير موجود' if (v is None or v[2]) else 'ظاهر برصيد ' + fmt(v[0])}"
    extra = []
    if w.metrics["writes_last_hour"] > 300:
        extra.append(f"عاصفة كتابة: {w.metrics['writes_last_hour']} كتابة في الساعة الأخيرة")
    return [note], extra


@scenario("17", "حذف", "زر «حذف قاعدة البيانات السحابية بالكامل» والأجهزة التسعة متصلة")
def s17(w):
    boot(w)
    cs = mk_customers(w, "D1", 2)
    w.run(60)
    w.d("D2").ui_add_tx(cs[0], 1000)
    w.d("D3").ui_add_tx(cs[1], 400)
    w.run(90)
    w.d("D1").ui_clear_cloud()
    w.settle(hours=1)
    lost = [dn for dn in w.devices if any(v[2] for u, v in w.d(dn).view().items() if u in cs)]
    return [f"أجهزة فقدت العميل ومعاملاته محلياً: {lost}"], []


@scenario("18", "فواتير", "فاتورة دين 5000 (حُفظت أوفلاين) ثم تحويلها إلى نقد على الجهاز المنشئ ثم إعادة التشغيل")
def s18(w):
    boot(w)
    c = w.add_customer("D2", "زبون الفاتورة")
    w.run(60)
    d2 = w.d("D2")
    d2.set_online(False)
    inv = d2.ui_save_invoice(c, 5000, 0, CREDIT)
    w.run(120)
    d2.set_online(True)
    w.run(400)
    d2.ui_save_invoice(c, 5000, 5000, CASH, inv_uuid=inv)
    w.run(600)
    before = len(w.check())
    w.restart_all()
    w.settle(hours=1)
    after = len(w.check())
    return [f"قبل إعادة التشغيل: {before} خلل — بعدها: {after} خلل (الدين الوهمي يعود)"], []


@scenario("19", "فواتير", "تعديل مبلغ فاتورة الدين (نفس المعاملة) من 5000 إلى 4200")
def s19(w):
    boot(w)
    c = w.add_customer("D2", "زبون التعديل")
    w.run(60)
    inv = w.d("D2").ui_save_invoice(c, 5000, 0, CREDIT)
    w.run(300)
    w.d("D2").ui_save_invoice(c, 4200, 0, CREDIT, inv_uuid=inv)
    w.settle()
    return [], []


@scenario("20", "فواتير", "حذف فاتورة دين من الجهاز المنشئ (DatabaseService.deleteInvoice — لا تستدعيه الواجهة حالياً)")
def s20(w):
    boot(w)
    c = w.add_customer("D2", "زبون الحذف")
    w.run(60)
    d2 = w.d("D2")
    inv = d2.ui_save_invoice(c, 3000, 0, CREDIT)
    w.run(300)
    d2.ui_delete_invoice(inv)
    w.settle()
    return [], []


@scenario("21", "مطابقة", "«بياناتي صحيحة» من D1 مع 10 أجهزة متصلة — تلف قديم (999) على بقية الأجهزة")
def s21(w):
    boot(w)
    c = w.add_customer("D1", "زبون المطابقة")
    w.run(60)
    for dn in list(w.devices)[1:]:
        u = w.d(dn).inject_phantom(c, 999, uuid="tx_phantom_legacy_999")
    w.truth.phantoms.add("tx_phantom_legacy_999")
    w.d("D1").ui_armored_push(c)
    w.settle()
    applied = [dn for dn in w.devices if w.d(dn).q1("SELECT COUNT(*) c FROM transactions WHERE transaction_uuid='tx_phantom_legacy_999' AND is_deleted=0")["c"] == 0]
    return [f"الأجهزة التي طبّقت الكشف: {applied}"], []


@scenario("22", "مطابقة", "«بياناتي صحيحة» والجهاز المرجعي لم يستلم بعد تسديداً حقيقياً من D3")
def s22(w):
    boot(w)
    c = w.add_customer("D1", "زبون التسديد")
    w.run(60)
    d1 = w.d("D1")
    tl = [L for L in d1.listeners if L.name == "transactions"][0]
    tl.active = False  # D1 متأخر في الاستلام
    p = w.d("D3").ui_add_tx(c, -2000)
    w.run(60)
    d1.ui_armored_push(c)
    w.run(200)
    tl.active = True
    tl.mark_all()
    tl.schedule()
    w.settle()
    lost = [dn for dn in w.devices if (w.d(dn).q1("SELECT is_deleted FROM transactions WHERE transaction_uuid=?", (p,)) or {}).get("is_deleted") == 1]
    return [f"أُبطل التسديد الحقيقي على: {lost}"], []


@scenario("23", "مطابقة", "مطابقة حية بين 10 أجهزة — مع مَن يقارن كل جهاز؟")
def s23(w):
    boot(w, t=30)
    invited = list(w.devices)
    pairs = set()
    per = {}
    for dn in invited:
        peers = w.d(dn).live_peers_for(invited)
        per[dn] = peers
        for p in peers:
            if p:
                pairs.add(tuple(sorted((dn, p))))
    extra = []
    if len(pairs) < 45:
        extra.append(f"أزواج مُقارنة {len(pairs)} من 45 — D3..D10 تقارن مع D1 فقط، ولا أحد يقارن D5 بـ D7")
    return [f"D1↔{per['D1'][:3]}…  D7↔{per['D7'][:3]}…"], extra


@scenario("24", "مطابقة", "مطابقة حية: «الجهاز الآخر صحيح» → معاملة تصحيحية على D2")
def s24(w):
    boot(w)
    c = w.add_customer("D1", "زبون التصحيح")
    w.run(60)
    d2 = w.d("D2")
    tl = [L for L in d2.listeners if L.name == "transactions"][0]
    tl.active = False
    w.d("D1").ui_add_tx(c, 1500)
    w.run(60)
    d2.ui_live_peer_is_correct(w.d("D1"))
    w.run(60)
    tl.active = True
    tl.mark_all()
    tl.schedule()
    w.settle()
    return [], []


@scenario("25", "مطابقة", "مطابقة حية مع عميلين مختلفين يحملان نفس الاسم")
def s25(w):
    boot(w)
    a = w.add_customer("D1", "سالم", phone="0770")
    b = w.add_customer("D1", "سالم", phone="0780")
    w.d("D1").ui_add_tx(b, 200)
    w.run(90)
    rows = w.d("D2").live_compare(w.d("D1").live_local_state())
    seen = {r["uuid"] for r in rows}
    extra = []
    if not ({a, b} <= seen):
        extra.append("عميلان صارا صفاً واحداً في شاشة المطابقة؛ دين 200 لـ C2 غير مرئي")
    w.settle(hours=1)
    return [], extra


@scenario("26", "تنظيف", "تنظيف السحابة (SmartPipe) ثم استعادة نسخة احتياطية قديمة على D6")
def s26(w):
    boot(w)
    cs = mk_customers(w, "D1", 2)
    w.run(120)
    snap = w.d("D6").snapshot_db()
    w.run(60)
    w.d("D2").ui_add_tx(cs[0], 700)
    w.d("D2").ui_add_tx(cs[1], 900)
    w.run(300)
    for dv in w.devices.values():
        dv.settings["auto_delete_days"] = 0
    w.sim.spawn(w.d("D1").smart_pipe_cleanup(), w.d("D1"))
    w.run(300)
    d6 = w.d("D6")
    d6.crash()
    d6.restore_db(snap)
    w.run(10)
    d6.boot()
    w.settle()
    return [f"مستندات معاملات متبقية في السحابة بعد التنظيف: {len(w.cloud.colls['transactions'])}"], []


@scenario("27", "تنظيف", "جهاز جديد ينضم بعد التنظيف ولديه معاملة محلية واحدة سابقة")
def s27(w):
    names = [f"D{i}" for i in range(1, 10)]
    boot(w, names)
    cs = mk_customers(w, "D1", 2)
    w.run(60)
    w.d("D2").ui_add_tx(cs[0], 900)
    w.run(300)
    for dv in w.devices.values():
        dv.settings["auto_delete_days"] = 0
    w.sim.spawn(w.d("D1").smart_pipe_cleanup(), w.d("D1"))
    w.run(300)
    d10 = w.d("D10")
    # استُخدم التطبيق محلياً قبل تفعيل المزامنة
    cid, u = d10.ui_add_customer("زبون محلي قديم")
    w.truth.add_customer(u, "زبون محلي قديم", "D10")
    d10.ex("UPDATE transactions SET is_uploaded=0")
    tu = "tx_local_before_join"
    d10.ex("""INSERT INTO transactions(customer_id, amount_changed, transaction_date, transaction_type, transaction_uuid, sync_uuid, created_at,
              is_created_by_me, is_uploaded, is_deleted) VALUES (?,?,?,?,?,?,?,1,0,0)""", (cid, 250, d10.ts(), "manual_debt", tu, tu, d10.ts()))
    d10.ex("UPDATE customers SET current_total_debt=250 WHERE id=?", (cid,))
    w.truth.add_tx(tu, u, 250, "D10", "manual")
    d10.boot()
    w.settle()
    return [], []


@scenario("28", "أمان", "مستخدم مجهول يملك إعدادات Firebase يكتب معاملة مزوّرة")
def s28(w):
    boot(w)
    c = w.add_customer("D1", "زبون الأمان")
    w.d("D1").ui_add_tx(c, 100)
    w.run(90)
    # المهاجم: يقرأ groupSecret من أي مستند (الحالي يكتبه نصاً) ثم يكتب معاملة
    leaked = (w.cloud.get("transactions", next(iter(w.cloud.colls["transactions"]))) or {}).get("groupSecret")
    w.cloud.set("transactions", "tx_forged_attack", {"syncUuid": "tx_forged_attack", "customerSyncUuid": c, "amountChanged": 10000,
                                                     "transactionType": "manual_debt", "isDeleted": False, "deviceId": "EVIL",
                                                     "groupSecret": leaked, "signature": "forged", "uploadedAt": w.sim.now}, True, "EVIL")
    w.truth.forged.add("tx_forged_attack")
    w.settle(hours=1)
    acc = [dn for dn in w.devices if w.d(dn).q1("SELECT COUNT(*) c FROM transactions WHERE transaction_uuid='tx_forged_attack' AND is_deleted=0")["c"]]
    extra = []
    if acc:
        extra.append(f"قُبلت على {len(acc)} أجهزة" + (" (التوقيع تحذير فقط، والمفتاح مكشوف في كل مستند)" if leaked else ""))
    return [], extra


@scenario("29", "أمان", "قرار إبطال مزوّر في match_verdicts يمسح تسديداً حقيقياً")
def s29(w):
    boot(w)
    c = w.add_customer("D1", "زبون القرار")
    w.run(30)
    p = w.d("D3").ui_add_tx(c, -4000)
    w.run(90)
    w.cloud.set("match_verdicts", f"v_{c}_{p}", {"transactionUuid": p, "customerSyncUuid": c, "voidedAmount": -4000,
                                                "applierDeviceId": "EVIL", "truthDeviceId": "EVIL"}, False, "EVIL")
    w.settle(hours=1)
    return [], []


@scenario("30", "حجم", "كشف مطابقة لعميل عنده 6000 معاملة (حد Firestore = 1 MiB للمستند)")
def s30(w):
    boot(w, ["D1", "D2"])
    c = w.add_customer("D1", "زبون كبير")
    w.run(60)
    d1, d2 = w.d("D1"), w.d("D2")
    cid1 = d1.customer_by_uuid(c)["id"]
    cid2 = d2.customer_by_uuid(c)["id"]
    rows = []
    for i in range(6000):
        u = f"tx_big_{i:05d}"
        rows.append(u)
        for dv, cid, own in ((d1, cid1, 1), (d2, cid2, 0)):
            dv.ex("""INSERT INTO transactions(customer_id, amount_changed, transaction_date, transaction_type, transaction_uuid, sync_uuid, created_at,
                     is_created_by_me, is_uploaded, is_deleted, transaction_note, description) VALUES (?,?,?,?,?,?,?,?,1,0,?,?)""",
                  (cid, 10, dv.ts(), "manual_debt", u, u, dv.ts(), own, "ملاحظة معاملة طويلة نسبياً للعميل", "وصف المعاملة"))
        w.truth.add_tx(u, c, 10, "D1", "manual")
    for dv, cid in ((d1, cid1), (d2, cid2)):
        dv.recalc_customer(cid)
    size = d1.doc_size(d1._build_ledger(c))
    res = {}

    def _push():
        r = yield from d1.push_my_truth(c)
        res["ok"] = r
    w.sim.spawn(_push(), d1)
    w.run(200)
    extra = []
    if not res.get("ok"):
        extra.append(f"حجم الكشف ≈ {size/1048576:.1f} MiB > 1 MiB → set() يفشل والمطابقة مستحيلة")
    for dn in list(w.devices)[2:]:
        w.devices[dn].running = True  # لا نفحص الأجهزة غير المشاركة
    return [f"حجم الكشف ≈ {size/1048576:.1f} MiB"], extra


@scenario("31", "فوضى", "اختبار فوضى: تشغيلات عشوائية × 400 عملية (اتصال/انقطاع/إضافة/تعديل/فواتير/إعادة تشغيل)")
def s31(w):
    return [], []  # يُدار من run.py (chaos)


# ══════════════════════════════════════════════════════════════════════════
# سيناريوهات جديدة اكتُشفت من قراءة الكود (غير موجودة في تقريرك)
# ══════════════════════════════════════════════════════════════════════════

@scenario("32", "تعديل", "تحويل نوع معاملة (دين↔تسديد) على الجهاز المالك")
def s32(w):
    boot(w)
    c = w.add_customer("D1", "زبون التحويل")
    t = w.d("D1").ui_add_tx(c, 1000)
    w.run(90)
    w.safe(w.d("D1").ui_convert_tx, t)
    w.settle()
    return [], []


@scenario("33", "تعديل", "تعديل معاملة D2 على عميل أنشأه D1 (ثم انقطاع/عودة شبكة وإعادة تشغيل)")
def s33(w):
    boot(w)
    c = w.add_customer("D1", "زبون مشترك")
    w.run(60)
    t = w.d("D2").ui_add_tx(c, 600)
    w.run(90)
    w.safe(w.d("D2").ui_edit_tx, t, 150)
    w.run(60)
    w.d("D2").set_online(False)
    w.run(30)
    w.d("D2").set_online(True)
    w.restart_all()
    w.settle()
    return [], []


@scenario("34", "تعديل", "تحويل نوع معاملة وصلت من جهاز آخر (الواجهة تسمح!)")
def s34(w):
    boot(w)
    c = w.add_customer("D1", "زبون التحويل الأجنبي")
    t = w.d("D1").ui_add_tx(c, 700)
    w.run(90)
    w.safe(w.d("D4").ui_convert_tx, t)
    w.settle()
    return [], []


@scenario("35", "فواتير", "فاتورة دين «معلّقة» (مسوّدة) على D1 — ماذا ترى بقية الأجهزة؟")
def s35(w):
    boot(w)
    c = w.add_customer("D1", "زبون المسوّدة")
    w.run(60)
    w.d("D1").ui_suspend_invoice(c, 2500, 0, CREDIT)
    w.settle()
    return [], []


@scenario("36", "فواتير", "جهازان يبدآن من قاعدة فارغة: أول فاتورة دين لأول عميل على كلٍ منهما")
def s36(w):
    boot(w)
    for dn in ("D1", "D2"):
        w.d(dn).set_online(False)
    a = w.add_customer("D1", "زبون الأول")
    w.d("D1").ui_save_invoice(a, 1200, 0, CREDIT)
    b = w.add_customer("D2", "زبون الثاني")
    w.d("D2").ui_save_invoice(b, 800, 0, CREDIT)
    w.run(120)
    for dn in ("D1", "D2"):
        w.d(dn).set_online(True)
    w.run(600)
    for dn in w.devices:
        w.d(dn).ui_view_customer(a)
        w.d(dn).ui_view_customer(b)
    w.settle()
    return [], []


@scenario("37", "ملكية", "D2 يحرّر فاتورة لعميل أنشأه D1 → هل يفقد D1 ملكية عميله؟ ثم D1 يعدّل اسمه")
def s37(w):
    boot(w)
    c = w.add_customer("D1", "زبون الملكية")
    w.run(60)
    w.d("D2").ui_save_invoice(c, 900, 900, CASH)
    w.run(120)
    own = w.d("D1").customer_by_uuid(c)["is_created_by_me"]
    w.d("D1").ui_edit_customer(c, "زبون الملكية (معدّل)")
    w.settle()
    names = sorted({(w.d(dn).customer_by_uuid(c) or {}).get("name") for dn in w.devices})
    extra = []
    if own == 0:
        extra.append("D1 فقد ملكية عميله (is_created_by_me=0) بعد فاتورة من D2")
    if len(names) > 1:
        extra.append(f"تعديل اسم المالك لم يصل: {names}")
    return [], extra


@scenario("38", "هوية", "نفس الاسم ونفس الهاتف أُنشئ على جهازين أوفلاين (قيد UNIQUE(name, phone))")
def s38(w):
    boot(w)
    for dn in ("D1", "D2"):
        w.d(dn).set_online(False)
    a = w.add_customer("D1", "رعد", phone="07711112222")
    w.d("D1").ui_add_tx(a, 400)
    b = w.add_customer("D2", "رعد", phone="07711112222")
    w.d("D2").ui_add_tx(b, 600)
    w.run(120)
    for dn in ("D1", "D2"):
        w.d(dn).set_online(True)
    w.settle()
    return [], []


@scenario("39", "حذف", "عميل محذوف (اسم+هاتف) ثم جهاز لم يره قط ينشئ عميلاً جديداً بنفس الاسم والهاتف")
def s39(w):
    boot(w)
    w.d("D3").set_online(False)
    a = w.add_customer("D1", "بشار", phone="07900000001")
    w.d("D1").ui_add_tx(a, 300)
    w.run(90)
    w.d("D1").ui_delete_customer(a)
    w.run(300)
    b = w.add_customer("D3", "بشار", phone="07900000001")
    w.safe(w.d("D3").ui_add_tx, b, 700)
    w.run(60)
    w.d("D3").set_online(True)
    w.settle()
    return [], []


@scenario("40", "إدخال", "معاملة قديمة التاريخ تصل من جهاز كان أوفلاين → هل يستطيع D1 إضافة معاملة جديدة؟")
def s40(w):
    boot(w)
    c = w.add_customer("D1", "زبون التاريخ")
    w.d("D1").ui_add_tx(c, 100)
    w.run(60)
    w.d("D5").set_online(False)
    w.d("D5").ui_add_tx(c, 50)
    w.run(600)
    w.d("D1").ui_add_tx(c, 200)
    w.run(60)
    w.d("D5").set_online(True)
    w.run(300)
    r = w.safe(w.d("D1").ui_add_tx, c, 30)
    extra = []
    if isinstance(r, Exception):
        extra.append(f"D1 لا يستطيع إضافة معاملة: «{str(r)[:60]}…»")
    w.settle()
    return [], extra


@scenario("41", "حذف", "حذف عميل على D1 بينما D4 أوفلاين يسجل عليه بيعاً جديداً (إعادة تنشيط ذكي)")
def s41(w):
    boot(w)
    c = w.add_customer("D1", "زبون التنشيط")
    w.d("D1").ui_add_tx(c, 1000)
    w.d("D2").ui_add_tx(c, 200) if False else None
    w.run(90)
    w.d("D4").set_online(False)
    w.run(10)
    w.d("D1").ui_delete_customer(c)
    w.d("D4").ui_add_tx(c, 350)
    w.run(300)
    w.d("D4").set_online(True)
    w.settle(hours=2)
    return [], []


@scenario("42", "انقطاع", "موبايل (persistence) أوفلاين: إنشاء ثم تعديل ثم عودة — كتابات SDK المخزّنة + طابور الإعادة")
def s42(w):
    w.d("D6").platform = "mobile"
    boot(w)
    c = w.add_customer("D1", "زبون الموبايل")
    w.run(60)
    d6 = w.d("D6")
    d6.set_online(False)
    t = d6.ui_add_tx(c, 900)
    w.run(120)
    w.safe(d6.ui_edit_tx, t, 450)
    w.run(120)
    d6.set_online(True)
    w.settle()
    return [], []


@scenario("43", "انقطاع", "تطبيق يُقتل أثناء الرفع ثم يُعدَّل قبل مرور المزامنة الخلفية (سجل WAL قديم)")
def s43(w):
    boot(w)
    c = w.add_customer("D2", "زبون WAL")
    w.run(60)
    d2 = w.d("D2")
    t = d2.ui_add_tx(c, 1000)
    w.run(0.01)
    d2.crash()  # قُتل والرفع في الطريق
    w.run(30)
    d2.boot()
    w.run(60)
    w.safe(d2.ui_edit_tx, t, 100)
    w.run(60)
    w.safe(d2.ui_add_tx, c, 1)  # يطلق syncCustomerNow فيرفع التعديل
    w.settle()
    return [], []
