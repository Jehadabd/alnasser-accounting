#!/usr/bin/env python3
"""
تحقق من محرك الترحيل على نسخة من القاعدة الحقيقية (بدون Flutter).

  python3 tool/verify_posting.py <نسخة debt_book.db>

يقرأ أوامر المخطط من lib/accounting/accounting_schema.dart نفسه، وينفذ
منطق الترحيل نفسه (منقول سطراً بسطر من posting_engine.dart)، ثم يتحقق:
  1) كل قيد متوازن، وميزان المراجعة متوازن.
  2) رصيد «ذمم العملاء» = مجموع أرصدة العملاء في سجل الديون.
  3) رصيد كل عميل في الدفتر = رصيده في جدول customers.
  4) التشغيل الثاني لا يغيّر شيئاً (إدمبوتنت).
  5) حذف معاملة وتعديل فاتورة ينعكسان في الدفتر.
"""
import json, re, sqlite3, sys, os, shutil, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCHEMA_DART = os.path.join(ROOT, 'lib', 'accounting', 'accounting_schema.dart')
EPS = 0.005


def dart_list(src, name):
    i = src.index(name)
    i = src.index('[', i)
    depth, j = 0, i
    in_str = None
    while True:
        ch = src[j]
        if in_str:
            if src.startswith(in_str, j) and src[j - 1] != '\\':
                j += len(in_str) - 1
                in_str = None
        elif src.startswith("'''", j):
            in_str = "'''"; j += 2
        elif ch == "'":
            in_str = "'"
        elif ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = src[i:j + 1]
    body = re.sub(r'^\s*//.*$', '', body, flags=re.M)
    body = body.replace('null', 'None')
    return eval(body)


def load_schema():
    src = open(SCHEMA_DART, encoding='utf-8').read()
    return dart_list(src, 'createStatements ='), dart_list(src, 'addedColumns ='), dart_list(src, 'defaultChart =')


def ensure(c, stmts, cols, chart):
    for s in stmts:
        c.execute(s)
    for t, col, d in cols:
        if not c.execute("select 1 from sqlite_master where type='table' and name=?", (t,)).fetchone():
            continue
        if col not in [r[1] for r in c.execute(f'pragma table_info({t})')]:
            c.execute(f'alter table {t} add column {col} {d}')
    now = datetime.datetime.now().isoformat()
    if c.execute('select count(*) from branches').fetchone()[0] == 0:
        c.execute("insert into branches(id,code,name,is_active,is_current,created_at) values(1,'B1','الفرع الرئيسي',1,1,?)", (now,))
    if c.execute('select count(*) from warehouses').fetchone()[0] == 0:
        c.execute("insert into warehouses(id,branch_id,code,name,is_default,is_active,created_at) values(1,1,'W1','المخزن الرئيسي',1,1,?)", (now,))
    ids = dict(c.execute('select code,id from accounts'))
    for code, name, parent, typ, grp, ctl, key in chart:
        if code in ids:
            continue
        cur = c.execute("insert into accounts(code,name,parent_id,type,is_group,is_control,system_key,currency,created_at) values(?,?,?,?,?,?,?,?,?)",
                        (code, name, ids.get(parent) if parent else None, typ, grp, ctl, key, 'USD' if key == 'ap_usd' else 'IQD', now))
        ids[code] = cur.lastrowid
    if c.execute('select count(*) from cash_boxes').fetchone()[0] == 0:
        c.execute("insert into cash_boxes(name,account_id,branch_id,kind,is_default,created_at) values('الصندوق الرئيسي',(select id from accounts where system_key='cash_main'),1,'cash',1,?)", (now,))
    c.execute("insert or ignore into accounting_settings(key,value) values('usd_rate','1310')")


def sysacc(c, key):
    return c.execute('select id from accounts where system_key=?', (key,)).fetchone()[0]


def write_entry(c, stype, sid, shash, date, desc, lines):
    lines = [l for l in lines if abs(l[1]) > EPS or abs(l[2]) > EPS]
    dr = sum(l[1] for l in lines); cr = sum(l[2] for l in lines)
    assert abs(dr - cr) < EPS, f'unbalanced {stype} {sid}: {dr} {cr}'
    ex = c.execute('select id from journal_entries where source_type=? and source_id=?', (stype, sid)).fetchone()
    if ex:
        eid = ex[0]
        c.execute('delete from journal_lines where entry_id=?', (eid,))
        c.execute('update journal_entries set entry_date=?,description=?,source_hash=? where id=?', (date, desc, shash, eid))
    else:
        n = c.execute('select coalesce(max(entry_number),0)+1 from journal_entries').fetchone()[0]
        eid = c.execute("insert into journal_entries(entry_number,entry_date,description,source_type,source_id,source_hash,branch_id,created_at) values(?,?,?,?,?,?,1,?)",
                        (n, date, desc, stype, sid, shash, datetime.datetime.now().isoformat())).lastrowid
    for acc, d, cr_, pt, pid in lines:
        c.execute('insert into journal_lines(entry_id,account_id,debit,credit,party_type,party_id) values(?,?,?,?,?,?)',
                  (eid, acc, round(d, 2), round(cr_, 2), pt, pid))


def delete_source(c, stype, sid):
    for (eid,) in c.execute('select id from journal_entries where source_type=? and source_id=?', (stype, sid)).fetchall():
        c.execute('delete from journal_lines where entry_id=?', (eid,))
        c.execute('delete from journal_entries where id=?', (eid,))


def reconcile(c, stype, sources, post, stats):
    existing = dict(c.execute('select source_id, source_hash from journal_entries where source_type=?', (stype,)).fetchall())
    for sid, h, row in sources:
        had = sid in existing
        old = existing.pop(sid, None)
        if had and old == h:
            stats['unchanged'] += 1
            continue
        post(sid, h, row)
        stats['updated' if had else 'created'] += 1
    for sid in existing:
        delete_source(c, stype, sid)
        stats['deleted'] += 1


def f(v):
    return float(v or 0)


def invoice_cost(c, iid, margin):
    tot = 0.0
    for qi, ql, uilu, actual, selling, sale_type, pcost, unit, lpu, ucj in c.execute('''
        SELECT ii.quantity_individual, ii.quantity_large_unit, ii.units_in_large_unit, ii.actual_cost_price,
               ii.applied_price, ii.sale_type, p.cost_price, p.unit, p.length_per_unit, p.unit_costs
        FROM invoice_items ii LEFT JOIN products p ON p.name = ii.product_name WHERE ii.invoice_id = ?''', (iid,)).fetchall():
        qi, ql, pcost, selling = f(qi), f(ql), f(pcost), f(selling)
        uilu = 1.0 if uilu is None else float(uilu)
        uc = {}
        if ucj and ucj.strip():
            try: uc = json.loads(ucj)
            except Exception: pass
        large = ql > 0
        cnt = ql if large else qi
        if actual is not None and actual > 0:
            cc = actual
        elif large:
            st = uc.get(sale_type or '')
            if isinstance(st, (int, float)) and st > 0:
                cc = float(st)
            else:
                cc = pcost * lpu if (unit == 'meter' and lpu is not None and sale_type == 'لفة') else pcost * uilu
        else:
            cc = pcost
        if cc <= 0 and selling > 0:
            cc = selling * (1.0 - margin)
        tot += cc * cnt
    return round(tot, 2)


def sync_all(c, margin=0.10):
    stats = dict(created=0, updated=0, deleted=0, unchanged=0)
    cols = [r[1] for r in c.execute('pragma table_info(invoices)')]
    has_del = 'is_deleted' in cols
    has_adj = c.execute("select 1 from sqlite_master where name='invoice_adjustments'").fetchone() is not None
    cash = c.execute('select account_id from cash_boxes where is_default=1 and is_active=1 order by id limit 1').fetchone()[0]
    sales, cogs, inv = sysacc(c, 'sales'), sysacc(c, 'cogs'), sysacc(c, 'inventory')
    rows = c.execute(f'''
      SELECT i.id, i.invoice_date, i.payment_type, i.total_amount, i.amount_paid_on_invoice, i.customer_name,
             {"COALESCE((SELECT SUM(a.amount_delta) FROM invoice_adjustments a WHERE a.invoice_id = i.id AND a.settlement_payment_type = 'نقد'), 0)" if has_adj else '0'},
             (SELECT COUNT(*) || ':' || ROUND(COALESCE(SUM(ii.item_total), 0), 2) || ':' ||
                     ROUND(COALESCE(SUM(COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)), 0), 3) || ':' ||
                     ROUND(COALESCE(SUM(COALESCE(ii.actual_cost_price, 0)), 0), 2)
              FROM invoice_items ii WHERE ii.invoice_id = i.id)
      FROM invoices i WHERE i.status = 'محفوظة' {"AND COALESCE(i.is_deleted,0)=0" if has_del else ''}''').fetchall()
    src = []
    for r in rows:
        h = '|'.join(str(x) for x in [r[1], r[2], f'{f(r[3]):.2f}', f'{f(r[4]):.2f}', f'{f(r[6]):.2f}', r[7]])
        src.append((r[0], h, r))

    def post_inv(sid, h, r):
        total = f(r[3])
        cp = total if r[2] == 'نقد' else f(r[4])
        cp = max(0, min(cp, total)) + f(r[6])
        cost = invoice_cost(c, sid, margin)
        lines = []
        if cp > 0: lines += [(cash, cp, 0, None, None), (sales, 0, cp, None, None)]
        if cost > 0: lines += [(cogs, cost, 0, None, None), (inv, 0, cost, None, None)]
        if not lines:
            delete_source(c, 'invoice', sid)
            c.execute("insert into journal_entries(entry_number,entry_date,description,source_type,source_id,source_hash,branch_id,created_at) values(0,?,?,?,?,?,1,?)",
                      (r[1], 'placeholder', 'invoice', sid, h, datetime.datetime.now().isoformat()))
            return
        write_entry(c, 'invoice', sid, h, r[1], f'فاتورة {sid}', lines)
    reconcile(c, 'invoice', src, post_inv, stats)

    tcols = [r[1] for r in c.execute('pragma table_info(transactions)')]
    rows = c.execute(f'''SELECT id, customer_id, transaction_date, amount_changed, transaction_type, invoice_id FROM transactions
                        {"WHERE COALESCE(is_deleted,0)=0" if 'is_deleted' in tcols else ''}''').fetchall()
    src = []
    for r in rows:
        a = f(r[3])
        if abs(a) < EPS: continue
        src.append((r[0], '|'.join(str(x) for x in [r[1], r[2], f'{a:.2f}', r[4], r[5]]), r))
    ar, sm, op = sysacc(c, 'ar_customers'), sysacc(c, 'sales_manual'), sysacc(c, 'opening_equity')

    def post_tx(sid, h, r):
        a = f(r[3]); t = r[4] or ''
        if r[5] is not None: cnt = sales
        elif t == 'opening_balance': cnt = op
        elif t == 'manual_payment' or (t == '' and a < 0): cnt = cash
        else: cnt = sm
        lines = [(ar, a, 0, 'customer', r[1]), (cnt, 0, a, None, None)] if a > 0 else [(cnt, -a, 0, None, None), (ar, 0, -a, 'customer', r[1])]
        write_entry(c, 'customer_tx', sid, h, r[2], 'tx', lines)
    reconcile(c, 'customer_tx', src, post_tx, stats)
    return stats


def check(c, label):
    ok = True
    bad = c.execute('''select e.id, sum(l.debit)-sum(l.credit) d from journal_entries e join journal_lines l on l.entry_id=e.id
                       group by e.id having abs(d) > 0.01''').fetchall()
    tb = c.execute('select round(sum(debit),2), round(sum(credit),2) from journal_lines').fetchone()
    ar = sysacc(c, 'ar_customers')
    ar_bal = c.execute('select coalesce(sum(debit-credit),0) from journal_lines where account_id=?', (ar,)).fetchone()[0]
    cust_total = c.execute('select coalesce(sum(current_total_debt),0) from customers where coalesce(is_deleted,0)=0').fetchone()[0]
    ledger_by_c = dict(c.execute('select party_id, sum(debit-credit) from journal_lines where account_id=? group by party_id', (ar,)).fetchall())
    mism = [(cid, name, bal, ledger_by_c.get(cid, 0)) for cid, name, bal in
            c.execute('select id,name,current_total_debt from customers where coalesce(is_deleted,0)=0').fetchall()
            if abs((bal or 0) - (ledger_by_c.get(cid) or 0)) > 1]
    print(f'— {label}')
    print(f'  قيود غير متوازنة: {len(bad)}')
    print(f'  ميزان المراجعة: مدين {tb[0]:,.2f}  دائن {tb[1]:,.2f}')
    print(f'  ذمم العملاء في الدفتر {ar_bal:,.2f}  ↔ مجموع أرصدة العملاء {cust_total:,.2f}')
    print(f'  عملاء يختلف رصيدهم: {len(mism)}  {mism[:3]}')
    for code, name, bal in c.execute('''select a.code, a.name, round(sum(l.debit-l.credit),2) from journal_lines l join accounts a on a.id=l.account_id
                                        group by a.id order by a.code''').fetchall():
        print(f'    {code:6} {name:35} {bal:>18,.2f}')
    ok = not bad and abs(tb[0] - tb[1]) < 0.05 and not mism and abs(ar_bal - cust_total) < 1
    return ok


def main():
    src = sys.argv[1]
    work = src + '.verify.db'
    shutil.copy(src, work)
    c = sqlite3.connect(work)
    stmts, cols, chart = load_schema()
    # الأعمدة التي يضيفها ensureSchema في البرنامج ولا توجد في القواعد القديمة
    for t, col, d in [('invoices', 'is_deleted', 'INTEGER DEFAULT 0')]:
        if col not in [r[1] for r in c.execute(f'pragma table_info({t})')]:
            c.execute(f'alter table {t} add column {col} {d}')
    ensure(c, stmts, cols, chart)
    ensure(c, stmts, cols, chart)  # مرة ثانية: يجب ألا يكرر شيئاً
    n_acc = c.execute('select count(*) from accounts').fetchone()[0]
    assert n_acc == len(chart), f'الشجرة تكررت: {n_acc} != {len(chart)}'

    s1 = sync_all(c); c.commit(); print('التشغيل الأول:', s1)
    ok1 = check(c, 'بعد الترحيل الأول')
    s2 = sync_all(c); c.commit(); print('التشغيل الثاني:', s2)
    ok2 = s2['created'] == 0 and s2['updated'] == 0 and s2['deleted'] == 0

    # سيناريو: حذف معاملة + تعديل مبلغ فاتورة نقدية
    tid, cid, amt = c.execute("select id, customer_id, amount_changed from transactions where transaction_type='manual_payment' and coalesce(is_deleted,0)=0 limit 1").fetchone()
    c.execute('update transactions set is_deleted=1 where id=?', (tid,))
    c.execute('update customers set current_total_debt = current_total_debt - ? where id=?', (amt, cid))
    iid = c.execute("select id from invoices where payment_type='نقد' and status='محفوظة' limit 1").fetchone()[0]
    c.execute('update invoices set total_amount = total_amount + 1000 where id=?', (iid,))
    s3 = sync_all(c); c.commit(); print('بعد حذف تسديد وتعديل فاتورة:', s3)
    ok3 = s3['deleted'] == 1 and s3['updated'] == 1
    ok4 = check(c, 'بعد السيناريو')
    c.close()
    os.remove(work)
    print('\nالنتيجة:', 'ناجح ✅' if (ok1 and ok2 and ok3 and ok4) else 'فشل ❌', (ok1, ok2, ok3, ok4))
    sys.exit(0 if (ok1 and ok2 and ok3 and ok4) else 1)


if __name__ == '__main__':
    main()
