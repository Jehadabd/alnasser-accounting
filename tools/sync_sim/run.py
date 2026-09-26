# -*- coding: utf-8 -*-
"""
مشغّل المحاكاة.

    python run.py                 # كل السيناريوهات: الحالي مقابل المُصلَح
    python run.py --only 09 18    # سيناريوهات محددة
    python run.py --chaos 50      # عدد تشغيلات الفوضى لكل وضع
    python run.py --mode fixed    # وضع واحد فقط
    python run.py --ablate        # أي إصلاح يحل أي سيناريو
    python run.py --only 31 --mode fixed --chaos 100 --seed0 10000 --profile harsh
                                  # فوضى فقط، بذور جديدة، شبكة قاسية
"""
import argparse
import json
import random
import sys
import time
import traceback

from world import World, ALL_FIXES, fmt
from scenarios import SCENARIOS, mk_customers
from device import CREDIT, CASH

MODES = {"الحالي": frozenset(), "المُصلَح": ALL_FIXES}


def run_scenario(sc, fixes, seed=0):
    w = World(fixes=fixes, seed=seed)
    if sc["num"] == "28" and "sign" in fixes:
        # الإصلاح يتطلب سراً مشتركاً مُدخلاً على كل الأجهزة + الوضع الصارم
        w = World(fixes=fixes, seed=seed, shared_secret="shop-group-secret")
        for dv in w.devices.values():
            dv.settings["strict_sig"] = True
    try:
        notes, extra = sc["fn"](w)
    except Exception as e:
        return {"errors": [f"استثناء في المحاكاة: {type(e).__name__}: {e}"], "notes": [traceback.format_exc()[-400:]], "w": w}
    if sc["num"] == "30":
        errs = list(extra)
    else:
        errs = w.check()
        if sc.get("balance_only"):
            errs = [e for e in errs if "مفقود (الصحيح 0)" not in e]
        errs += extra
    return {"errors": errs, "notes": notes, "w": w}


# ══════════════════════════════════════════════════════════════════════════
# الفوضى
# ══════════════════════════════════════════════════════════════════════════
def _pending_own(dv):
    a = dv.q1("SELECT COUNT(*) c FROM transactions WHERE (is_created_by_me=1 OR is_created_by_me IS NULL) AND is_uploaded=0")["c"]
    b = dv.q1("SELECT COUNT(*) c FROM invoices WHERE is_created_by_me=1 AND is_synced=0")["c"]
    c = dv.q1("SELECT COUNT(*) c FROM transactions WHERE is_created_by_me=0 AND is_deleted=1 AND is_uploaded=0")["c"]
    d = dv.q1("SELECT COUNT(*) c FROM customers WHERE tombstoned IN (2,3) OR (is_created_by_me=1 AND (synced_at IS NULL OR last_modified_at > synced_at))")["c"]
    return a + b + c + d


def chaos_run(fixes, seed, ops=400, n=10, horizon=7200.0, features="all", restart=True, profile="normal"):
    rnd = random.Random(seed)
    plats = {f"D{i}": ("mobile" if rnd.random() < 0.3 else "desktop") for i in range(1, n + 1)}
    w = World(fixes=fixes, seed=seed, n=n, platforms=plats)
    w.boot_all()
    w.run(60)
    for i in range(4):
        w.add_customer("D1", f"عميل {i+1}", phone=None)
    w.run(60)
    names = list(w.devices)
    snaps = {}
    counters = {"ops": 0}
    for k in range(ops):
        w.run(rnd.expovariate(ops / horizon))
        dn = rnd.choice(names)
        dv = w.d(dn)
        r = rnd.random()
        counters["ops"] += 1
        try:
            if profile == "harsh":
                h = rnd.random()
                if h < 0.02:
                    # انقطاع طويل (1-6 ساعات)
                    dv.set_online(False)
                    back = rnd.uniform(3600, 6 * 3600)
                    w.sim.at(w.sim.now + back, (lambda d=dv: d.set_online(True)))
                    continue
                if h < 0.03 and dv.running:
                    for x in w.devices.values():
                        x.settings["auto_delete_days"] = 0
                    w.sim.spawn(dv.smart_pipe_cleanup(), dv)
                    continue
                if h < 0.04 and dv.running and dn in snaps and _pending_own(dv) == 0:
                    # استعادة نسخة احتياطية قديمة (مسموحة فقط إن لم يبقَ عمل غير مرفوع)
                    dv.crash()
                    dv.restore_db(snaps.pop(dn))
                    w.run(5)
                    dv.boot()
                    continue
                if h < 0.05 and dv.running:
                    vis = [u for u, (_, _, hh) in dv.view().items() if not hh and u in w.truth.customers]
                    if vis:
                        dv.ui_armored_push(rnd.choice(vis))
                    continue
                if h < 0.06 and dv.running:
                    peer = w.d(rnd.choice([x for x in names if x != dn]))
                    if peer.running:
                        dv.ui_live_peer_is_correct(peer)
                    continue
                if h < 0.09 and dv.running and dn not in snaps:
                    snaps[dn] = dv.snapshot_db()
            if r < 0.10:
                dv.set_online(not dv.online)
            elif r < 0.14:
                if dv.running:
                    if rnd.random() < 0.3:
                        snaps[dn] = dv.snapshot_db()
                    dv.crash()
                else:
                    dv.boot()
            elif not dv.running:
                continue
            elif r < 0.50:
                vis = [u for u, (_, _, h) in dv.view().items() if not h and u in w.truth.customers]
                if not vis:
                    continue
                w.safe(dv.ui_add_tx, rnd.choice(vis), rnd.choice([50, 100, 250, 400, 1000, -60, -150, -500]))
            elif r < 0.60:
                own = dv.q("""SELECT transaction_uuid FROM transactions WHERE is_created_by_me=1 AND invoice_id IS NULL AND is_deleted=0
                              AND transaction_uuid LIKE 'tx_%' AND transaction_type IN ('manual_debt','manual_payment')""")
                if own:
                    w.safe(dv.ui_edit_tx, rnd.choice(own)["transaction_uuid"], rnd.choice([10, 75, 300, 900, -80, -400]))
            elif r < 0.64:
                own = dv.q("""SELECT transaction_uuid FROM transactions WHERE is_created_by_me=1 AND invoice_id IS NULL AND is_deleted=0
                              AND transaction_type IN ('manual_debt','manual_payment')""")
                if own:
                    w.safe(dv.ui_convert_tx, rnd.choice(own)["transaction_uuid"])
            elif r < 0.68:
                w.add_customer(dn, f"{rnd.choice(['سعد','رامي','ليث','أنس','باسم'])} {rnd.randint(1, 60)}")
            elif r < 0.78 and features in ("all", "invoices"):
                vis = [u for u, (_, _, h) in dv.view().items() if not h and u in w.truth.customers]
                if vis:
                    total = rnd.choice([500, 1200, 3000, 750])
                    ptype = rnd.choice([CREDIT, CREDIT, CASH])
                    paid = 0 if ptype == CREDIT else total
                    if ptype == CREDIT and rnd.random() < 0.3:
                        paid = rnd.choice([100, 200])
                    w.safe(dv.ui_save_invoice, rnd.choice(vis), total, paid, ptype)
            elif r < 0.84 and features in ("all", "invoices"):
                inv = dv.q("SELECT i.invoice_uuid, c.sync_uuid cs FROM invoices i JOIN customers c ON c.id=i.customer_id WHERE i.is_created_by_me=1 AND i.status='محفوظة' AND (i.is_deleted IS NULL OR i.is_deleted=0)")
                if inv:
                    x = rnd.choice(inv)
                    total = rnd.choice([400, 900, 2600])
                    ptype = rnd.choice([CREDIT, CASH])
                    w.safe(dv.ui_save_invoice, x["cs"], total, 0 if ptype == CREDIT else total, ptype, inv_uuid=x["invoice_uuid"])
            elif r < 0.86 and features in ("all", "invoices"):
                vis = [u for u, (_, _, h) in dv.view().items() if not h and u in w.truth.customers]
                if vis:
                    w.safe(dv.ui_suspend_invoice, rnd.choice(vis), rnd.choice([300, 800]), 0, CREDIT)
            elif r < 0.92:
                vis = [u for u, (_, _, h) in dv.view().items() if u in w.truth.customers]
                if vis:
                    dv.ui_view_customer(rnd.choice(vis))
            elif r < 0.935 and features == "all":
                vis = [u for u, (_, _, h) in dv.view().items() if not h and u in w.truth.customers]
                if vis:
                    w.safe(dv.ui_delete_customer, rnd.choice(vis))
            elif r < 0.95:
                # نظام تعديل على جهاز كان أوفلاين ثم عاد (يولّد تواريخ قديمة وطوابير إعادة)
                dv.set_online(False)
            elif r < 0.96 and features == "all":
                w.restart(dn)
            else:
                dv.set_online(True)
        except Exception as e:  # noqa
            w.metrics["driver_exc"] += 1
    w.settle(hours=3)
    errs = w.check()
    if not restart:
        return w, errs, []
    # إعادة تشغيل الجميع ثم الفحص مرة أخرى (السحب الكامل يجب ألا يُفسد شيئاً)
    w.restart_all()
    w.settle(hours=1)
    errs2 = w.check()
    return w, errs, errs2


# ══════════════════════════════════════════════════════════════════════════
def print_block(sc, res_by_mode):
    print(f"\n[{sc['num']}] ({sc['cat']}) {sc['title']}")
    for mode, res in res_by_mode.items():
        errs = res["errors"]
        tag = f"{mode:8s}"
        runs = res.get("runs", 1)
        failed = res.get("failed_runs", 1 if errs else 0)
        rate = f" — فشل في {failed}/{runs} تشغيلة بتوقيتات مختلفة" if runs > 1 and failed else (f" (في {runs}/{runs} تشغيلة)" if runs > 1 else "")
        if not errs:
            print(f"   {tag}: ✅ متطابق: كل الأجهزة = الحقيقة{rate}")
        else:
            print(f"   {tag}: ❌ {len(errs)} خلل{rate}")
            for e in errs[:4]:
                print(f"      - {e}")
            if len(errs) > 4:
                print(f"      ... و{len(errs) - 4} غيرها")
        for n in res["notes"]:
            if n.strip():
                print(f"            ↳ {n}")
        te = res["w"].sim.task_errors
        if te:
            top = te.most_common(2)
            print(f"            ↳ أخطاء مهام غير ممسوكة: {sum(te.values())} — مثال: {top[0][0][:120]}")


def main():
    # طرفية ويندوز الافتراضية (cp1252) لا تطبع العربية
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--chaos", type=int, default=20)
    ap.add_argument("--ops", type=int, default=400)
    ap.add_argument("--mode", choices=["both", "current", "fixed"], default="both")
    ap.add_argument("--json", default=None)
    ap.add_argument("--ablate", action="store_true")
    ap.add_argument("--seed0", type=int, default=0)
    ap.add_argument("--seeds", type=int, default=5, help="تشغيلات لكل سيناريو بتوقيتات عشوائية مختلفة")
    ap.add_argument("--profile", choices=["normal", "harsh"], default="normal")
    args = ap.parse_args()

    modes = dict(MODES)
    if args.mode == "current":
        modes.pop("المُصلَح")
    elif args.mode == "fixed":
        modes.pop("الحالي")

    summary = {m: 0 for m in modes}
    total = 0
    out = {}
    t0 = time.time()
    for sc in SCENARIOS:
        if args.only and sc["num"] not in args.only:
            continue
        if sc["num"] == "31":
            continue
        total += 1
        res = {}
        for m, fx in modes.items():
            best = None
            failed = 0
            for seed in range(args.seeds):
                r = run_scenario(sc, fx, seed=seed)
                if r["errors"]:
                    failed += 1
                    if best is None or not best["errors"]:
                        best = r
                elif best is None:
                    best = r
            best["runs"] = args.seeds
            best["failed_runs"] = failed
            res[m] = best
            if failed:
                summary[m] += 1
        print_block(sc, res)
        out[sc["num"]] = {m: {"errors": r["errors"], "notes": r["notes"]} for m, r in res.items()}
        sys.stdout.flush()

    if args.chaos and (not args.only or "31" in args.only):
        total += 1
        print(f"\n[31] (فوضى) {args.chaos} تشغيلة عشوائية × {args.ops} عملية لكل وضع (10 أجهزة، 30% موبايل)")
        for m, fx in modes.items():
            bad = 0
            bad_after_restart = 0
            example = None
            wmax = 0
            for s in range(args.seed0, args.seed0 + args.chaos):
                w, e1, e2 = chaos_run(fx, s, ops=args.ops, profile=args.profile)
                wmax = max(wmax, w.metrics["writes_last_hour"])
                if e1:
                    bad += 1
                    example = example or (s, e1[:2])
                if e2:
                    bad_after_restart += 1
                    example = example or (s, e2[:2])
            if bad or bad_after_restart:
                summary[m] += 1
                print(f"   {m:8s}: ❌ {bad}/{args.chaos} تشغيلة بأرصدة مختلفة بعد 3 ساعات، {bad_after_restart}/{args.chaos} بعد إعادة تشغيل الجميع")
                print(f"      - مثال seed={example[0]}: {example[1]}")
            else:
                print(f"   {m:8s}: ✅ {args.chaos}/{args.chaos} تشغيلة: كل الأجهزة = الحقيقة (وبعد إعادة التشغيل أيضاً)")
            print(f"            ↳ أعلى معدل كتابة سحابية في الساعة الأخيرة: {wmax}")
            sys.stdout.flush()

    line = " — ".join(f"{m} {summary[m]}/{total} سيناريو فاشل" for m in modes)
    print(f"\n══ الخلاصة: {line}   (زمن التشغيل {time.time()-t0:.0f} ث)")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
