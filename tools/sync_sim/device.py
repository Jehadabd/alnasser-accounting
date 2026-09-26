# -*- coding: utf-8 -*-
"""
نموذج جهاز واحد: قاعدة SQLite حقيقية بنفس الجداول والاستعلامات، ونسخة
Python سطرية لمسارات المزامنة في:

  lib/services/firebase_sync/firebase_sync_service.dart
  lib/services/firebase_sync/sync_watchdog.dart
  lib/services/firebase_sync/invoice_sync_service.dart
  lib/services/firebase_sync/armored_reconciliation_service.dart
  lib/services/firebase_sync/match_verdict_service.dart
  lib/services/firebase_sync/live_match_service.dart
  lib/services/firebase_sync/smart_pipe_cleanup_service.dart
  lib/services/firebase_sync/sync_crash_recovery_service.dart
  lib/services/database/dao/{customer,transaction}_dao.dart
  lib/services/database/business/invoice_debt_reconciler.dart
  lib/controllers/invoice_controller.dart (مسار الحفظ)

كل سلوك «حالي» يطابق الكود كما هو الآن. كل إصلاح محاط بـ self.fx('اسم')،
والاسم نفسه مذكور في تعليق التعديل المقابل داخل كود Dart.
"""
import datetime
import hashlib
import hmac
import itertools
import json
import re
import sqlite3
from collections import deque

from engine import Sleep, Tick, CloudCall, CloudTimeout, SERVER_TS

BASE = datetime.datetime(2026, 9, 1)


def iso(t):
    return (BASE + datetime.timedelta(seconds=t)).isoformat(timespec="microseconds")


def parse_iso(s):
    if s is None:
        return None
    try:
        return (datetime.datetime.fromisoformat(str(s)) - BASE).total_seconds()
    except Exception:
        return None


_DIAC = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭ]")


def norm_ar(s):
    if not s:
        return s or ""
    s = _DIAC.sub("", s).replace("ـ", "")
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ؤ", "و"), ("ئ", "ي"), ("ة", "ه"), ("ى", "ي")):
        s = s.replace(a, b)
    return re.sub(r"\s+", " ", s).strip()


SCHEMA = """
CREATE TABLE customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, phone TEXT, address TEXT,
  current_total_debt REAL NOT NULL DEFAULT 0,
  last_modified_at TEXT, sync_uuid TEXT, is_deleted INTEGER DEFAULT 0,
  synced_at TEXT, is_created_by_me INTEGER DEFAULT 1, created_at TEXT,
  general_note TEXT, tombstoned INTEGER DEFAULT 0,
  UNIQUE(name, phone)
);
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL, amount_changed REAL NOT NULL,
  transaction_date TEXT NOT NULL, transaction_note TEXT,
  balance_before_transaction REAL, new_balance_after_transaction REAL,
  invoice_id INTEGER, is_created_by_me INTEGER DEFAULT 1, is_uploaded INTEGER DEFAULT 0,
  transaction_uuid TEXT, sync_uuid TEXT, transaction_type TEXT, description TEXT,
  created_at TEXT NOT NULL, is_deleted INTEGER DEFAULT 0, invoice_sync_uuid TEXT,
  origin_device_id TEXT, remote_ver REAL, last_uploaded_at TEXT, remote_modified_at TEXT,
  restored_mark INTEGER DEFAULT 0
);
CREATE UNIQUE INDEX ux_transactions_uuid ON transactions(transaction_uuid) WHERE transaction_uuid IS NOT NULL;
CREATE TABLE invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_uuid TEXT, customer_id INTEGER,
  customer_name TEXT, total_amount REAL, amount_paid_on_invoice REAL, payment_type TEXT,
  status TEXT, version INTEGER, is_synced INTEGER DEFAULT 0, is_created_by_me INTEGER DEFAULT 1,
  is_locked INTEGER DEFAULT 0, creator_device_id TEXT, invoice_date TEXT,
  last_modified_at TEXT, created_at TEXT, is_deleted INTEGER DEFAULT 0,
  restored_mark INTEGER DEFAULT 0
);
CREATE TABLE sync_coordination (
  id INTEGER PRIMARY KEY AUTOINCREMENT, entity_type TEXT NOT NULL, sync_uuid TEXT NOT NULL,
  firebase_synced INTEGER DEFAULT 0, firebase_synced_at TEXT, UNIQUE(entity_type, sync_uuid)
);
CREATE TABLE sync_retry_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, sync_uuid TEXT NOT NULL UNIQUE,
  data TEXT NOT NULL, retry_count INTEGER DEFAULT 0, next_retry_time TEXT NOT NULL,
  created_at TEXT NOT NULL, last_error TEXT
);
CREATE TABLE sync_orphans (
  id INTEGER PRIMARY KEY AUTOINCREMENT, sync_uuid TEXT NOT NULL UNIQUE,
  customer_sync_uuid TEXT NOT NULL, data TEXT NOT NULL, received_at TEXT NOT NULL
);
CREATE TABLE sync_wal (
  id TEXT PRIMARY KEY, type TEXT, action TEXT, sync_uuid TEXT, data TEXT, status INTEGER,
  created_at TEXT, UNIQUE(sync_uuid, action)
);
CREATE TABLE pending_void_verdicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_uuid TEXT NOT NULL UNIQUE,
  verdict_doc_id TEXT, data TEXT
);
CREATE TABLE voided_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_uuid TEXT UNIQUE, snapshot TEXT, reason TEXT
);
CREATE TABLE sync_state (id INTEGER PRIMARY KEY, last_sync_at TEXT, ledger_marker TEXT);
"""

# WalOperationStatus
W_PENDING, W_WRITING, W_COMMITTED, W_UPLOADING, W_SYNCED, W_FAILED, W_RECOVERED = range(7)

INVOICE_SAVED = "محفوظة"
INVOICE_SUSPENDED = "معلقة"
CREDIT = "دين"
CASH = "نقد"
NON_CONTRIB = ("manual_payment", "return_payment", "correction", "opening_balance")

_uid = itertools.count(1)


def new_uuid(prefix, dev):
    return f"{prefix}_{dev}_{next(_uid):06d}"


def checksum_of(d):
    clean = {k: v for k, v in d.items() if k not in ("uploadedAt", "deviceId", "lastModifiedAt")}
    return hashlib.sha256(json.dumps(clean, sort_keys=True, default=str).encode()).hexdigest()[:16]


class RateLimiter:
    def __init__(self, per_min, per_hour):
        self.per_min = per_min
        self.per_hour = per_hour
        self.m = deque()
        self.h = deque()

    def _prune(self, now):
        while self.m and now - self.m[0] > 60:
            self.m.popleft()
        while self.h and now - self.h[0] > 3600:
            self.h.popleft()

    def can(self, now):
        self._prune(now)
        return len(self.m) < self.per_min and len(self.h) < self.per_hour

    def record(self, now):
        self._prune(now)
        self.m.append(now)
        self.h.append(now)


class Device:
    def __init__(self, world, name, platform="desktop", skew=0.0, shared_secret=None):
        from engine import Net
        self.w = world
        self.sim = world.sim
        self.cloud = world.cloud
        self.name = name
        self.device_id = name
        self.invoice_device_num = "1"  # InvoiceSettingsService.getInvoiceDeviceId() الافتراضي = 1
        self.platform = platform
        self.skew = skew
        self.online = True
        self.running = False
        self.epoch = 0
        self.net = Net(self, self.sim, self.cloud)
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        self.db.execute("INSERT INTO sync_state(id, last_sync_at) VALUES (1, NULL)")
        self.settings = {
            "reject_old": False, "max_age_days": 30,
            "policy": "smartReactivate", "auto_cleanup": False,
            "auto_delete_days": 30, "strict_sig": False,
        }
        # مفتاح المجموعة: عشوائي لكل جهاز ما لم يُدخل المستخدم سراً مشتركاً
        self.secret = shared_secret or f"rand-{name}-{world.sim.rng.random()}"
        self.secret_user_provided = shared_secret is not None
        self.restored_flag = False  # SharedPreferences: تُضبط عند استعادة نسخة احتياطية
        self.events = []  # رسائل مهمة للواجهة/التقرير
        self.local_errors = []  # أخطاء ظهرت للمستخدم (استثناءات أفعال الواجهة)
        self._reset_memory()

    # ------------------------------------------------------------------
    def fx(self, name):
        return name in self.w.fixes

    @property
    def now(self):
        return self.sim.now

    def ts(self):
        return iso(self.sim.now + self.skew)

    def q(self, sql, args=()):
        return [dict(r) for r in self.db.execute(sql, args).fetchall()]

    def q1(self, sql, args=()):
        r = self.db.execute(sql, args).fetchone()
        return dict(r) if r else None

    def ex(self, sql, args=()):
        return self.db.execute(sql, args)

    def _reset_memory(self):
        self.initialized = False
        self.listening = False
        self.status = "idle"
        self.upload_locks = set()
        if self.fx("rate"):
            self.rate = RateLimiter(600, 20000)
        else:
            self.rate = RateLimiter(120, 1000)
        self.retry_timer_active = False
        self.listeners = []
        self.bulk = False
        self.repairing = False
        self.wd_processing = False
        self.wd_paused = False
        self.bootstrap_responding = False
        self._bootstrapping = False
        self.handled_requests = set()
        self.init_retry_scheduled = False
        self.last_cleanup_day = None
        self.expect_ready = False

    # ==================================================================
    # دورة حياة التطبيق
    # ==================================================================
    def boot(self):
        """فتح التطبيق (main.dart → FirebaseSyncService().initialize())."""
        if self.running:
            return
        self.running = True
        self.epoch += 1
        self._reset_memory()
        if self.online and self.net.pending:
            self.net.flush_pending()
        self.sim.spawn(self.initialize(), self, name=f"{self.name}:init")

    def crash(self):
        """إغلاق/قتل التطبيق فجأة: كل المهام تموت، الذاكرة تضيع، SQLite يبقى."""
        self.running = False
        self.epoch += 1
        for L in self.listeners:
            L.active = False
        self.listeners = []
        if self.platform != "mobile":
            self.net.pending = []

    def set_online(self, flag):
        if self.online == flag:
            return
        self.online = flag
        if not self.running:
            return
        if flag:
            self.net.flush_pending()
            for L in self.listeners:
                if L.active:
                    L.mark_all()
                    L.schedule()
            # Connectivity().onConnectivityChanged
            if self.status in ("offline", "error") or not self.initialized:
                self.sim.spawn(self._on_connection_restored(), self, name=f"{self.name}:restore")
        else:
            if self.status != "offline":
                self.status = "offline"

    # ==================================================================
    # الشبكة (Firestore)
    # ==================================================================
    def c_set(self, coll, doc_id, data, merge=True, timeout=60.0):
        cloud = self.cloud
        dev = self.name
        yield CloudCall("write", lambda: cloud.set(coll, doc_id, data, merge, dev), timeout)

    def c_update(self, coll, doc_id, data, timeout=60.0):
        cloud = self.cloud
        dev = self.name
        yield CloudCall("write", lambda: cloud.update(coll, doc_id, data, dev), timeout)

    def c_delete(self, coll, doc_id):
        cloud = self.cloud
        dev = self.name
        yield CloudCall("write", lambda: cloud.delete(coll, doc_id, dev))

    def c_get(self, coll, doc_id):
        cloud = self.cloud
        r = yield CloudCall("read", lambda: cloud.get(coll, doc_id), 20.0)
        return r

    def c_query(self, coll, pred=lambda d: True):
        cloud = self.cloud
        r = yield CloudCall("read", lambda: cloud.query(coll, pred), 60.0)
        return r

    def c_txn(self, fn):
        """runTransaction: fn(cloud) تُنفَّذ ذرياً لحظة الوصول."""
        cloud = self.cloud
        dev = self.name
        r = yield CloudCall("write", lambda: fn(cloud, dev), 30.0)
        return r

    # ==================================================================
    # التهيئة  (firebase_sync_service.dart: initialize)
    # ==================================================================
    def initialize(self):
        if self.initialized:
            return True
        # 🚪 بوابة المصادقة تحتاج شبكة
        if not self.online:
            self.status = "offline"
            self._schedule_init_retry()
            return False
        try:
            yield from self.c_query("devices", lambda d: True)  # _testFirebaseConnectivity
        except CloudTimeout:
            pass  # الاختبار يعيد true حتى عند الفشل
        # ⚖️ مستمع القرارات
        self._start_verdict_listener()
        # 🛡️ WAL: استرداد العمليات المعلقة
        self._wal_recover()
        # 🛡️ Watchdog: دورة فورية ثم كل 30 ثانية
        self._start_watchdog()
        # 👂 المستمعون
        self._start_listening()
        # رفع المعلق (في الكود الحالي: لا يعمل لأن _isInitialized ما زال false)
        yield from self._sync_pending_changes(during_init=True)
        # 🧾 الفواتير
        yield from self._invoice_start_sync()
        # 🔄 السحب الكامل (في الكود الحالي: لا يعمل لنفس السبب)
        yield from self.perform_full_catch_up(during_init=True)
        # طابور الإعادة
        cnt = self.q1("SELECT COUNT(*) c FROM sync_retry_queue")["c"]
        if cnt > 0:
            self._schedule_retry()
        # 📱 تسجيل الجهاز
        self.sim.spawn(self._register_device(), self, name=f"{self.name}:register")
        self._start_bootstrap_responder()
        self.sim.spawn(self.ensure_new_device_bootstrap(), self, name=f"{self.name}:bootstrap")
        self._start_timer(600.0, self._background_sync, "bg")
        self.initialized = True
        self.status = "online"
        if self.fx("initfix"):
            self.sim.spawn(self._post_init_sync(), self, name=f"{self.name}:postinit")
        self._start_timer(300.0, self._auto_audit_tick, "audit")
        self._start_armored_listener()
        return True

    def _post_init_sync(self):
        """initialize (Dart): unawaited(_syncPendingChanges ثم performFullCatchUp) بعد التهيئة."""
        try:
            yield from self._sync_pending_changes()
        except CloudTimeout:
            pass
        try:
            yield from self.perform_full_catch_up()
        except CloudTimeout:
            pass

    def _schedule_init_retry(self):
        if self.initialized or self.init_retry_scheduled:
            return
        self.init_retry_scheduled = True
        ep = self.epoch

        def _fire():
            if ep != self.epoch or not self.running:
                return
            self.init_retry_scheduled = False
            if self.initialized:
                return
            if not self.online:
                self._schedule_init_retry()
                return
            self.sim.spawn(self._init_retry(), self, name=f"{self.name}:initretry")
        self.sim.at(self.sim.now + 30.0, _fire)

    def _init_retry(self):
        ok = yield from self.initialize()
        if not ok:
            self._schedule_init_retry()

    def _start_timer(self, period, genfn, name):
        ep = self.epoch

        def _tick():
            if ep != self.epoch or not self.running:
                return
            self.sim.spawn(genfn(), self, name=f"{self.name}:{name}")
            self.sim.at(self.sim.now + period, _tick)
        self.sim.at(self.sim.now + period, _tick)

    def _on_connection_restored(self):
        self.status = "syncing"
        if not self.initialized:
            ok = yield from self.initialize()
            if not ok:
                self.status = "error"
            return
        try:
            yield from self._sync_pending_changes()
            try:
                yield from self.perform_full_catch_up()
            except CloudTimeout:
                pass
            if not self.listening:
                self._start_listening()
            yield from self._register_device()
            self.status = "online"
        except CloudTimeout:
            self.status = "error"

    def _register_device(self):
        data = {"deviceId": self.device_id, "lastSeen": self.ts(), "isOnline": True,
                "isNewDevice": False, "registeredAt": self.ts()}
        if not self.fx("sign"):
            data["groupSecret"] = self.secret
        else:
            data["membershipProof"] = hmac.new(self.secret.encode(), self.device_id.encode(), "sha256").hexdigest()
            data["secretUserProvided"] = self.secret_user_provided
        try:
            yield from self.c_set("devices", self.device_id, data, True)
        except CloudTimeout:
            pass

    # ==================================================================
    # الاستماع
    # ==================================================================
    def _start_listening(self):
        if self.listening:
            return
        self.merge_duplicate_customers_by_name()
        self.listeners.append(self.cloud.listen(self, "customers", self._on_customers_changed, name="customers"))
        self.listeners.append(self.cloud.listen(self, "transactions", self._on_transactions_changed, name="transactions"))
        self.listening = True

    def _own_customer_doc(self, uuid, data):
        """[tomb/bootstrap] مستند آخر كاتب له هو أنا: قد يحمل شاهد حذف كتبه غيري
        (دُمج في نفس المستند)، أو قد يكون عميلاً فقدتُه باستعادة نسخة قديمة."""
        loc = self.customer_by_uuid(uuid)
        if self.fx("tomb") and data.get("isDeleted") is True and loc is not None and loc["tombstoned"] == 0:
            yield from self._apply_customer_tombstone(uuid, data)
        elif self.fx("bootstrap") and loc is None and (data.get("name") or "").strip():
            try:
                cid = self._insert_received_customer(uuid, data, data["name"].strip())
            except sqlite3.IntegrityError:
                cid = self._insert_received_customer(uuid, data, data["name"].strip(), phone_suffix=True)
            self.ex("UPDATE customers SET is_created_by_me=1 WHERE id=?", (cid,))
            self.coord_register("customer", uuid, "firebase")
            self.coord_mark("customer", uuid)
            yield from self._process_orphans(cid, uuid)

    def _own_tx_doc(self, uuid, data):
        """[tomb/bootstrap] مستند معاملة آخر كاتب له هو أنا:
        - قد يحمل شاهد حذف كتبه غيري قبل رفعي (دُمج في المستند نفسه) → أقبله.
        - أو قد تكون معاملتي المفقودة محلياً (استعادة نسخة قديمة) → أستعيدها."""
        if self.fx("tomb") and (data.get("isDeleted") is True):
            loc = self.q1("SELECT id, customer_id, is_deleted FROM transactions WHERE transaction_uuid=?", (uuid,))
            if loc is not None and not loc["is_deleted"]:
                self.ex("UPDATE transactions SET is_deleted=1, is_uploaded=1 WHERE id=?", (loc["id"],))
                self.rebuild_chain(loc["customer_id"])
                self.recalc_customer(loc["customer_id"])
                self.apply_visibility(loc["customer_id"])
                return
        if not self.fx("bootstrap"):
            return
        loc = self.q1("SELECT * FROM transactions WHERE transaction_uuid=?", (uuid,))
        if loc is not None:
            # 🛡️ وضع الاستعادة: قاعدتي رجعت للخلف، والسحابة تحمل آخر ما رفعتُه أنا
            if (self.restored_flag and loc["restored_mark"] == 1 and not loc["is_deleted"]
                    and (data.get("lastModifiedAt") or "") > (loc["last_uploaded_at"] or "")):
                # ما رفعتُه بعد أخذ النسخة الاحتياطية يلغي كل ما في النسخة (حتى المعلّق فيها)
                self.ex("UPDATE transactions SET amount_changed=?, transaction_type=?, last_uploaded_at=?, is_uploaded=1 WHERE id=?",
                        (data.get("amountChanged"), data.get("transactionType"), data.get("lastModifiedAt"), loc["id"]))
                self.rebuild_chain(loc["customer_id"])
                self.recalc_customer(loc["customer_id"])
                self.apply_visibility(loc["customer_id"])
            return
        cust = self.customer_by_uuid(data.get("customerSyncUuid") or "")
        if cust is None:
            self._add_to_orphans(uuid, data)
            return
        inv = data.get("invoiceSyncUuid")
        if self.fx("invoice") and inv and self.q1("SELECT 1 x FROM invoices WHERE invoice_uuid=?", (inv,)):
            return
        dele = 1 if data.get("isDeleted") else 0
        self.ex("""INSERT INTO transactions(customer_id, transaction_date, amount_changed, transaction_type, created_at, is_created_by_me, is_uploaded,
                   sync_uuid, transaction_uuid, invoice_sync_uuid, is_deleted, origin_device_id, last_uploaded_at) VALUES (?,?,?,?,?,1,1,?,?,?,?,?,?)""",
                (cust["id"], data.get("transactionDate") or self.ts(), data.get("amountChanged") or 0.0, data.get("transactionType"),
                 data.get("createdAt") or self.ts(), uuid, uuid, inv, dele, self.device_id, data.get("lastModifiedAt")))
        self.coord_register("transaction", uuid, "local")
        self.coord_mark("transaction", uuid)
        self.rebuild_chain(cust["id"])
        self.recalc_customer(cust["id"])
        if self.fx("tomb"):
            self.apply_visibility(cust["id"])
        return
        yield

    def _on_customers_changed(self, changes):
        for typ, uuid, data in changes:
            if data.get("deviceId") == self.device_id:
                if typ != "removed":
                    try:
                        yield from self._own_customer_doc(uuid, data)
                    except CloudTimeout:
                        pass
                continue
            try:
                if typ in ("added", "modified"):
                    yield from self._apply_customer_change(uuid, data)
                else:
                    if self.fx("removed"):
                        # 🛡️ حذف مستند من السحابة (تنظيف/مسح) ليس أمر حذف
                        continue
                    yield from self._delete_local_customer(uuid)
            except CloudTimeout:
                pass
            except sqlite3.Error as e:
                self.events.append(f"خطأ تطبيق عميل {uuid}: {e}")
        if changes:
            self.merge_duplicate_customers_by_name()
            self.ex("UPDATE sync_state SET last_sync_at=? WHERE id=1", (self.ts(),))

    def _on_transactions_changed(self, changes):
        for typ, uuid, data in changes:
            if data.get("deviceId") == self.device_id:
                if typ != "removed":
                    yield from self._own_tx_doc(uuid, data)
                continue
            try:
                if typ in ("added", "modified"):
                    yield from self._apply_transaction_change(uuid, data)
                else:
                    pass  # _deleteLocalTransaction: تجاهل
            except CloudTimeout:
                pass
            except sqlite3.Error as e:
                self.events.append(f"خطأ تطبيق معاملة {uuid}: {e}")
        if changes:
            self.ex("UPDATE sync_state SET last_sync_at=? WHERE id=1", (self.ts(),))

    # ==================================================================
    # منسق المزامنة
    # ==================================================================
    def coord_register(self, et, uuid, source):
        synced = 1 if source == "firebase" else 0
        self.ex("INSERT OR IGNORE INTO sync_coordination(entity_type, sync_uuid, firebase_synced, firebase_synced_at) VALUES (?,?,?,?)",
                (et, uuid, synced, self.ts() if synced else None))

    def coord_mark(self, et, uuid):
        self.ex("UPDATE sync_coordination SET firebase_synced=1, firebase_synced_at=? WHERE entity_type=? AND sync_uuid=?",
                (self.ts(), et, uuid))

    def coord_is_synced(self, et, uuid):
        r = self.q1("SELECT firebase_synced FROM sync_coordination WHERE entity_type=? AND sync_uuid=?", (et, uuid))
        return bool(r and r["firebase_synced"] == 1)

    def coord_last_sync(self, et, uuid):
        r = self.q1("SELECT firebase_synced_at FROM sync_coordination WHERE entity_type=? AND sync_uuid=?", (et, uuid))
        return r["firebase_synced_at"] if r else None

    # ==================================================================
    # أدوات الأرصدة
    # ==================================================================
    def sum_tx(self, cid):
        return self.q1("SELECT COALESCE(SUM(amount_changed),0) s FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0)", (cid,))["s"]

    def rebuild_chain(self, cid):
        """recalculateCustomerTransactionBalances / rebuildCustomerBalances."""
        running = 0.0
        for t in self.q("SELECT id, amount_changed FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0) ORDER BY transaction_date ASC, id ASC", (cid,)):
            before = running
            running += t["amount_changed"]
            self.ex("UPDATE transactions SET balance_before_transaction=?, new_balance_after_transaction=? WHERE id=?", (before, running, t["id"]))
        return running

    def recalc_customer(self, cid):
        """recalculateAndApplyCustomerDebt."""
        s = self.sum_tx(cid)
        self.ex("UPDATE customers SET current_total_debt=?, last_modified_at=? WHERE id=?", (s, self.ts(), cid))
        return s

    def verify_repair(self, cid):
        """_verifyAndRepairCustomerBalance (بلا تعديل last_modified_at إن كان سليماً)."""
        r = self.q1("SELECT current_total_debt FROM customers WHERE id=?", (cid,))
        if not r:
            return
        s = self.sum_tx(cid)
        if abs(r["current_total_debt"] - s) > 0.01:
            self.ex("UPDATE customers SET current_total_debt=?, last_modified_at=? WHERE id=?", (s, self.ts(), cid))

    def apply_visibility(self, cid):
        """🛡️ [tomb] قاعدة الظهور: العميل مخفي إذا وُسم بالحذف ولا معاملات نشطة له."""
        r = self.q1("SELECT tombstoned, is_deleted FROM customers WHERE id=?", (cid,))
        if not r:
            return
        active = self.q1("SELECT COUNT(*) c FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0)", (cid,))["c"]
        hidden = 1 if (r["tombstoned"] in (1, 2) and active == 0) else 0
        if (r["is_deleted"] or 0) != hidden:
            self.ex("UPDATE customers SET is_deleted=? WHERE id=?", (hidden, cid))

    def customer_by_uuid(self, uuid):
        return self.q1("SELECT * FROM customers WHERE sync_uuid=?", (uuid,))

    # ==================================================================
    # أفعال المستخدم (الواجهة)
    # ==================================================================
    def ui_add_customer(self, name, phone=None, opening=0.0, uuid=None):
        """AppProvider.addCustomer → CustomerDao.insertCustomer → _syncCustomerNow."""
        now = self.ts()
        uuid = uuid or new_uuid("cust", self.name)
        existing = self.q1("SELECT * FROM customers WHERE (name=? OR name=?) AND (phone=? OR (phone IS NULL AND ? IS NULL)) LIMIT 1",
                           (name.strip(), norm_ar(name.strip()), phone, phone))
        if existing and existing["is_deleted"] == 1:
            cid = existing["id"]
            tomb = 3 if (self.fx("tomb") and existing["tombstoned"] in (1, 2)) else 0
            self.ex("UPDATE customers SET is_deleted=0, tombstoned=?, last_modified_at=?, name=?, phone=? WHERE id=?",
                    (tomb, now, name, phone, cid))
            uuid = existing["sync_uuid"] or uuid
            if not existing["sync_uuid"]:
                self.ex("UPDATE customers SET sync_uuid=? WHERE id=?", (uuid, cid))
        else:
            cur = self.ex("INSERT INTO customers(name, phone, current_total_debt, last_modified_at, sync_uuid, is_deleted, is_created_by_me, created_at) VALUES (?,?,?,?,?,0,1,?)",
                          (name, phone, opening, now, uuid, now))
            cid = cur.lastrowid
            if opening > 0:
                tu = new_uuid("tx", self.name)
                self.ex("""INSERT INTO transactions(customer_id, transaction_uuid, sync_uuid, transaction_date, amount_changed,
                           new_balance_after_transaction, transaction_note, transaction_type, created_at, is_deleted, is_created_by_me, is_uploaded)
                           VALUES (?,?,?,?,?,?,?,?,?,0,1,0)""",
                        (cid, tu, tu, now, opening, opening, "الدين المبدئي", "opening_balance", now))
                self.w.truth.add_tx(tu, uuid, opening, self.name, "opening")
        self.sim.spawn(self._app_sync_customer_now(cid), self, name=f"{self.name}:syncNow")
        return cid, uuid

    def ui_add_tx(self, cust_uuid, amount, tx_uuid=None, backdate=0.0):
        """AppProvider.addTransaction → TransactionDao.insertTransaction → _syncCustomerNow."""
        c = self.customer_by_uuid(cust_uuid)
        if not c:
            raise RuntimeError("العميل غير موجود على هذا الجهاز")
        cid = c["id"]
        tx_uuid = tx_uuid or new_uuid("tx", self.name)
        now = self.ts()
        tdate = iso(self.sim.now + self.skew - backdate)
        # TransactionDao.insertTransaction
        if self.fx("insertguard"):
            before = self.sum_tx(cid)
        else:
            before = c["current_total_debt"]
            last = self.q1("SELECT new_balance_after_transaction nb FROM transactions WHERE customer_id=? ORDER BY transaction_date DESC, id DESC LIMIT 1", (cid,))
            if last is not None and abs(before - (last["nb"] or 0)) > 1.0:
                raise RuntimeError(f"خطأ أمني حرج: رصيد العميل ({before}) لا يتطابق مع آخر معاملة ({last['nb']})")
        after = before + amount
        ttype = "manual_debt" if amount >= 0 else "manual_payment"
        self.ex("""INSERT INTO transactions(customer_id, amount_changed, transaction_date, balance_before_transaction, new_balance_after_transaction,
                   is_created_by_me, is_uploaded, transaction_uuid, sync_uuid, transaction_type, created_at, is_deleted)
                   VALUES (?,?,?,?,?,1,0,?,?,?,?,0)""",
                (cid, amount, tdate, before, after, tx_uuid, tx_uuid, ttype, now))
        self.ex("UPDATE customers SET current_total_debt=?, last_modified_at=? WHERE id=?", (after, now, cid))
        if self.fx("tomb"):
            self.apply_visibility(cid)
        self.w.truth.add_tx(tx_uuid, cust_uuid, amount, self.name, "manual")
        self.sim.spawn(self._app_sync_customer_now(cid), self, name=f"{self.name}:syncNow")
        return tx_uuid

    def ui_edit_tx(self, tx_uuid, new_amount):
        """customer_details_screen → DatabaseService.updateTransaction → updateManualTransaction."""
        t = self.q1("SELECT * FROM transactions WHERE transaction_uuid=?", (tx_uuid,))
        if not t or t["is_deleted"] == 1:
            raise RuntimeError("المعاملة غير موجودة")
        if t["invoice_id"] is not None:
            raise RuntimeError("لا يمكن تعديل معاملة مرتبطة بفاتورة من هنا")
        if t["is_created_by_me"] is not None and t["is_created_by_me"] == 0:
            raise RuntimeError("هذه المعاملة أُنشئت على جهاز آخر")
        cid = t["customer_id"]
        ttype = "manual_debt" if new_amount >= 0 else "manual_payment"
        self.ex("UPDATE transactions SET amount_changed=?, transaction_type=?, is_uploaded=0, restored_mark=0 WHERE id=?", (new_amount, ttype, t["id"]))
        self.rebuild_chain(cid)
        self.recalc_customer(cid)
        self.w.truth.edit_tx(tx_uuid, new_amount)
        if self.fx("edits"):
            self.sim.spawn(self._app_sync_customer_now(cid), self, name=f"{self.name}:syncNow")

    def ui_convert_tx(self, tx_uuid):
        """customer_details_screen → DatabaseService.convertTransactionType."""
        t = self.q1("SELECT * FROM transactions WHERE transaction_uuid=?", (tx_uuid,))
        if not t or t["is_deleted"] == 1:
            raise RuntimeError("المعاملة غير موجودة")
        if t["invoice_id"] is not None:
            raise RuntimeError("لا يمكن تحويل نوع معاملة مرتبطة بفاتورة")
        mine = t["is_created_by_me"] is None or t["is_created_by_me"] == 1
        if self.fx("edits") and not mine:
            raise RuntimeError("هذه المعاملة أُنشئت على جهاز آخر")
        cid = t["customer_id"]
        na = -t["amount_changed"]
        ttype = "manual_debt" if na >= 0 else "manual_payment"
        if self.fx("edits"):
            self.ex("UPDATE transactions SET amount_changed=?, transaction_type=?, is_uploaded=0, restored_mark=0 WHERE id=?", (na, ttype, t["id"]))
        else:
            self.ex("UPDATE transactions SET amount_changed=?, transaction_type=? WHERE id=?", (na, ttype, t["id"]))
        self.rebuild_chain(cid)
        self.recalc_customer(cid)
        if mine:
            self.w.truth.edit_tx(tx_uuid, na)
        else:
            self.w.truth.foreign_local_convert(tx_uuid)
        if self.fx("edits"):
            self.sim.spawn(self._app_sync_customer_now(cid), self, name=f"{self.name}:syncNow")

    def ui_edit_customer(self, cust_uuid, new_name):
        """AppProvider.updateCustomer → CustomerDao.updateCustomer → _syncCustomerNow."""
        c = self.customer_by_uuid(cust_uuid)
        self.ex("UPDATE customers SET name=?, last_modified_at=? WHERE id=?", (new_name, self.ts(), c["id"]))
        self.w.truth.rename(cust_uuid, new_name)
        self.sim.spawn(self._app_sync_customer_now(c["id"]), self, name=f"{self.name}:syncNow")

    def ui_delete_customer(self, cust_uuid):
        """AppProvider.deleteCustomer → DatabaseService.deleteCustomer."""
        c = self.customer_by_uuid(cust_uuid)
        cid = c["id"]
        rows = self.q("SELECT transaction_uuid, invoice_sync_uuid FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0)", (cid,))
        known = [r["transaction_uuid"] for r in rows]
        known_inv = {r["invoice_sync_uuid"] for r in rows if r["invoice_sync_uuid"]}
        self.w.truth.delete_customer(cust_uuid, known, known_inv)
        self._dao_delete_customer(cid)
        if self.fx("tomb"):
            self.ex("UPDATE customers SET tombstoned=2 WHERE id=?", (cid,))
            # الحذف يُرفع كشواهد لكل معاملة كانت معروفة + شاهد العميل
            self.sim.spawn(self._upload_customer_tombstone_cascade(cid), self, name=f"{self.name}:delcascade")
        else:
            row = self.q1("SELECT * FROM customers WHERE id=?", (cid,))
            self.sim.spawn(self.upload_customer(row), self, name=f"{self.name}:delupload")

    def _dao_delete_customer(self, cid):
        now = self.ts()
        if self.fx("tomb"):
            # customer_dao.deleteCustomer (المُصلَح): النشطة فقط — صف محذوف مسبقاً ورُفع شاهده لا يعود للطابور
            self.ex("UPDATE transactions SET is_deleted=1, is_uploaded=0, restored_mark=0 WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0)", (cid,))
        else:
            self.ex("UPDATE transactions SET is_deleted=1, is_uploaded=0, restored_mark=0 WHERE customer_id=?", (cid,))
        self.ex("UPDATE customers SET is_deleted=1, current_total_debt=0, last_modified_at=? WHERE id=?", (now, cid))

    # ------------------------------------------------------------------
    def _app_sync_customer_now(self, cid):
        """AppProvider._syncCustomerNow → FirebaseSyncService.syncCustomerNow."""
        try:
            yield from self.sync_customer_now(cid)
        except CloudTimeout:
            pass

    # ==================================================================
    # الرفع
    # ==================================================================
    def _tx_fingerprint(self, row):
        keys = ("amount_changed", "transaction_type", "is_deleted", "customer_id", "transaction_note", "invoice_sync_uuid")
        return tuple(row.get(k) for k in keys)

    def upload_customer(self, data):
        """uploadCustomer."""
        if not self.initialized:
            return True
        if self.fx("pending") and not self.online:
            return False  # 🛡️ لا ننتظر مهلة 60 ثانية ونحن نعلم أننا أوفلاين
        if self.fx("bootstrap") and self.restored_flag:
            return False
        now = self.sim.now
        if not self.rate.can(now):
            return not self.fx("rate")
        uuid = data.get("sync_uuid")
        if not uuid or not data.get("name"):
            return True
        key = "c_" + uuid
        if key in self.upload_locks:
            return True
        if self.fx("fresh"):
            fresh = self.customer_by_uuid(uuid)
            if fresh:
                data = fresh
        pending_tomb = False
        if self.fx("tomb"):
            tr = self.q1("SELECT tombstoned FROM customers WHERE sync_uuid=?", (uuid,))
            pending_tomb = bool(tr and tr["tombstoned"] in (2, 3))
        if self.fx("keepowner"):
            own = self.q1("SELECT is_created_by_me FROM customers WHERE sync_uuid=?", (uuid,))
            if own and own["is_created_by_me"] == 0 and not pending_tomb:
                return True  # uploadCustomer (Dart): وثيقة عميل لا نملكه لا نكتبها
        if self.coord_is_synced("customer", uuid) and not pending_tomb:
            lm, sa = data.get("last_modified_at"), data.get("synced_at")
            need = False
            if lm is not None and sa is not None:
                need = lm > sa
            elif sa is None:
                need = True
            if not need:
                return True
        self.upload_locks.add(key)
        self.rate.record(now)
        is_del = (data.get("is_deleted") or 0) == 1
        exp = self._compute_expectation(uuid)
        doc = {
            "syncUuid": uuid, "name": data.get("name"), "phone": data.get("phone"),
            "currentTotalDebt": 0.0 if is_del else data.get("current_total_debt"),
            "expectedBalance": 0.0 if is_del else exp,
            "lastModifiedAt": data.get("last_modified_at") or self.ts(),
            "createdAt": data.get("created_at"),
            "isDeleted": is_del, "is_deleted": 1 if is_del else 0,
            "deviceId": self.device_id, "originDeviceId": self.device_id,
            "uploadedAt": SERVER_TS,
        }
        tomb_state = None
        if self.fx("tomb"):
            # 🛡️ لا نكتب isDeleted إلا عند حذف أو إعادة تنشيط صريحين، حتى لا
            # يمحو رفعٌ عادي (merge) شاهدَ حذفٍ كتبه جهاز آخر.
            tomb_row = self.q1("SELECT tombstoned FROM customers WHERE sync_uuid=?", (uuid,))
            tomb_state = tomb_row["tombstoned"] if tomb_row else 0
            doc.pop("isDeleted", None)
            doc.pop("is_deleted", None)
            if tomb_state == 2:
                doc["isDeleted"] = True
                doc["is_deleted"] = 1
                doc["deletedAt"] = self.ts()
            elif tomb_state == 3:
                doc["isDeleted"] = False
                doc["is_deleted"] = 0
        self._sign_doc(doc, uuid)
        try:
            yield from self.c_set("customers", uuid, doc, True)
            self.coord_register("customer", uuid, "local")
            self.coord_mark("customer", uuid)
            self.ex("UPDATE customers SET synced_at=? WHERE sync_uuid=?", (iso(now + self.skew), uuid))
            if tomb_state == 2:
                self.ex("UPDATE customers SET tombstoned=1 WHERE sync_uuid=? AND tombstoned=2", (uuid,))
            elif tomb_state == 3:
                self.ex("UPDATE customers SET tombstoned=0 WHERE sync_uuid=? AND tombstoned=3", (uuid,))
            return True
        except CloudTimeout:
            self._add_to_retry("customer", uuid, data)
            return False
        finally:
            self.upload_locks.discard(key)

    def _compute_expectation(self, uuid):
        r = self.q1("""SELECT COALESCE(SUM(t.amount_changed),0) s FROM customers c LEFT JOIN transactions t
                       ON t.customer_id=c.id AND (t.is_deleted IS NULL OR t.is_deleted=0) WHERE c.sync_uuid=?""", (uuid,))
        return r["s"] if r else None

    def _sign_doc(self, doc, uuid):
        if self.fx("sign"):
            canon = f"{uuid}|{doc.get('customerSyncUuid','')}|{doc.get('amountChanged','')}|{doc.get('isDeleted')}|{doc.get('deviceId')}"
            doc["signature"] = hmac.new(self.secret.encode(), canon.encode(), "sha256").hexdigest()
        else:
            doc["groupSecret"] = self.secret  # 🔓 المفتاح نفسه يُكتب نصاً في كل مستند
            doc["signature"] = "sig"

    def upload_transaction(self, tx, cust_uuid, force=False, tombstone_foreign=False):
        """uploadTransaction."""
        if not self.initialized:
            return True
        if self.fx("pending") and not self.online:
            return False  # 🛡️ لا ننتظر مهلة 60 ثانية ونحن نعلم أننا أوفلاين
        if self.fx("bootstrap") and self.restored_flag:
            return False  # 🛡️ وضع الاستعادة: لا نرفع شيئاً من نسخة قديمة قبل مقارنتها بالسحابة
        icm = tx.get("is_created_by_me")
        if icm is not None and icm == 0 and not tombstone_foreign:
            return True
        now = self.sim.now
        if not self.rate.can(now):
            return not self.fx("rate")
        uuid = tx.get("transaction_uuid")
        if not uuid or tx.get("customer_id") is None or tx.get("amount_changed") is None:
            return True
        key = "t_" + uuid
        if key in self.upload_locks:
            return True
        if self.fx("lock"):
            self.upload_locks.add(key)  # 🔒 ذري: قبل أي await
        if self.fx("fresh"):
            fresh = self.q1("SELECT * FROM transactions WHERE transaction_uuid=?", (uuid,))
            if fresh is None:
                self.upload_locks.discard(key)
                return True
            tx = fresh
            cr = self.q1("SELECT sync_uuid FROM customers WHERE id=?", (tx["customer_id"],))
            if cr and cr["sync_uuid"]:
                cust_uuid = cr["sync_uuid"]
            if tx["is_uploaded"] == 1 and not force:
                self.upload_locks.discard(key)
                return True
        else:
            last = self.coord_last_sync("transaction", uuid)
            yield Tick()  # await _coordinator.getLastSyncTime
            if not force and last is not None:
                if tx.get("is_uploaded") == 1:
                    return True
            yield Tick()  # await isDuplicateTransaction
            if key in self.upload_locks and not self.fx("lock"):
                pass  # TOCTOU: مهمة أخرى قد تكون أخذت القفل بين الفحص والتعيين
        if not self.fx("lock"):
            self.upload_locks.add(key)
        self.rate.record(now)
        # 🛡️ WAL
        wal_id = f"transaction_{uuid}_{int(now*1000)}"
        wal_data = dict(tx)
        wal_data["customer_sync_uuid"] = cust_uuid
        self.ex("INSERT OR REPLACE INTO sync_wal(id,type,action,sync_uuid,data,status,created_at) VALUES (?,?,?,?,?,?,?)",
                (wal_id, "transaction", "create", uuid, json.dumps(wal_data, default=str), W_UPLOADING, self.ts()))
        sent_fp = self._tx_fingerprint(tx)
        is_del = (tx.get("is_deleted") or 0) == 1
        doc = {
            "syncUuid": uuid, "customerSyncUuid": cust_uuid,
            "invoiceSyncUuid": tx.get("invoice_sync_uuid"),
            "transactionDate": tx.get("transaction_date"),
            "amountChanged": tx.get("amount_changed"),
            "transactionNote": tx.get("transaction_note"),
            "transactionType": tx.get("transaction_type"),
            "createdAt": tx.get("created_at"),
            "lastModifiedAt": self.ts(),
            "isDeleted": is_del, "is_deleted": 1 if is_del else 0,
            "deviceId": self.device_id, "originDeviceId": self.device_id,
            "uploadedAt": SERVER_TS,
        }
        if tombstone_foreign and icm == 0 and tx.get("origin_device_id"):
            doc["originDeviceId"] = tx.get("origin_device_id")
        if self.fx("tomb") and not is_del:
            # 🛡️ لا نكتب isDeleted=false أبداً: رفعٌ (merge) لتعديل لاحق لا يمحو شاهد
            # حذف كتبه جهاز آخر. الحذف نهائي ولا «إحياء» عبر المزامنة.
            doc.pop("isDeleted", None)
            doc.pop("is_deleted", None)
        doc["checksum"] = checksum_of(tx)
        self._sign_doc(doc, uuid)
        try:
            yield from self.c_set("transactions", uuid, doc, True)
            self.coord_register("transaction", uuid, "local")
            self.coord_mark("transaction", uuid)
            if self.fx("fresh"):
                # 🛡️ CAS: لا نعلّمها مرفوعة إلا إن لم تتغير منذ قراءتها
                cur = self.q1("SELECT * FROM transactions WHERE transaction_uuid=?", (uuid,))
                if cur is not None and self._tx_fingerprint(cur) == sent_fp:
                    self.ex("UPDATE transactions SET is_uploaded=1, last_uploaded_at=? WHERE transaction_uuid=?", (doc["lastModifiedAt"], uuid))
                elif cur is not None:
                    self.ex("UPDATE transactions SET is_uploaded=0 WHERE transaction_uuid=?", (uuid,))
            else:
                self.ex("UPDATE transactions SET is_uploaded=1 WHERE transaction_uuid=?", (uuid,))
            self.ex("UPDATE sync_wal SET status=? WHERE id=?", (W_SYNCED, wal_id))
            return True
        except CloudTimeout:
            self.ex("UPDATE sync_wal SET status=? WHERE id=?", (W_FAILED, wal_id))
            rd = dict(tx)
            rd["customer_sync_uuid"] = cust_uuid
            self._add_to_retry("transaction", uuid, rd)
            return False
        finally:
            self.upload_locks.discard(key)

    # ------------------------------------------------------------------
    def _owned_pending_where(self, alias="t"):
        a = alias
        base = (f"{a}.transaction_uuid IS NOT NULL AND {a}.transaction_uuid != '' "
                f"AND ({a}.is_uploaded = 0 OR {a}.is_uploaded IS NULL) ")
        own = f"({a}.is_created_by_me = 1 OR {a}.is_created_by_me IS NULL)"
        if self.fx("tomb"):
            # شواهد حذف لمعاملات غيري ناتجة عن حذفي أنا للعميل
            own = f"({own} OR ({a}.is_created_by_me = 0 AND {a}.is_deleted = 1))"
        else:
            base += f"AND ({a}.is_deleted IS NULL OR {a}.is_deleted = 0) "
        cond = base + "AND " + own
        if self.fx("invoice"):
            # معاملات الفواتير تسافر داخل حزمة الفاتورة — إلا شاهد الحذف (حذف العميل)
            cond += f" AND ({a}.invoice_sync_uuid IS NULL OR {a}.invoice_sync_uuid = '' OR {a}.is_deleted = 1)"
        return cond

    def sync_customer_now(self, cid):
        """syncCustomerNow."""
        if not self.initialized:
            return
        rows = self.q("SELECT * FROM customers WHERE id=? AND sync_uuid IS NOT NULL AND sync_uuid!='' AND (is_deleted IS NULL OR is_deleted=0) AND (is_created_by_me=1 OR is_created_by_me IS NULL)", (cid,))
        if self.fx("pending"):
            c = self.q1("SELECT * FROM customers WHERE id=?", (cid,))
            if not c or not c["sync_uuid"]:
                return
            if rows:
                ok = yield from self.upload_customer(rows[0])
                if not ok:
                    return
            else:
                # عميل جهاز آخر: لا نرفع وثيقته لكن نرفع معاملاتي المعلّقة عليه
                exists = yield from self._ensure_customer_doc(c)
                if not exists:
                    return
            pend = self.q(f"SELECT * FROM transactions t WHERE t.customer_id=? AND {self._owned_pending_where('t')} ORDER BY transaction_date ASC, id ASC", (cid,))
            for t in pend:
                yield from self.upload_transaction(t, c["sync_uuid"], tombstone_foreign=(t["is_created_by_me"] == 0))
            return
        if not rows:
            return
        cust = rows[0]
        ok = yield from self.upload_customer(cust)
        if not ok:
            return
        pend = self.q("""SELECT * FROM transactions WHERE customer_id=? AND transaction_uuid IS NOT NULL AND transaction_uuid!=''
                         AND (is_deleted IS NULL OR is_deleted=0) AND (is_uploaded=0 OR is_uploaded IS NULL)
                         AND (is_created_by_me=1 OR is_created_by_me IS NULL) ORDER BY transaction_date ASC, id ASC""", (cid,))
        for t in pend:
            yield from self.upload_transaction(t, cust["sync_uuid"])

    def _ensure_customer_doc(self, c):
        """[pending] عميل جهاز آخر: وثيقته في السحابة يرفعها منشئه؛ لكن إن لم تكن
        موجودة (حُذفت بالتنظيف) نحتاجها قبل معاملاتنا وإلا تتيتّم عند الآخرين."""
        return True
        yield  # generator

    def _sync_pending_changes(self, during_init=False):
        """_syncPendingChanges."""
        if not self.initialized and not (during_init and self.fx("initfix")):
            return
        custs = self.q("""SELECT * FROM customers WHERE sync_uuid IS NOT NULL AND sync_uuid!='' AND (is_deleted IS NULL OR is_deleted=0)
                          AND (synced_at IS NULL OR last_modified_at > synced_at) AND (is_created_by_me=1 OR is_created_by_me IS NULL) ORDER BY id""")
        if self.fx("tomb"):
            custs += self.q("""SELECT * FROM customers WHERE sync_uuid IS NOT NULL AND tombstoned IN (2, 3)""")
        done_c = set()
        for c in custs:
            if c["id"] in done_c:
                continue
            done_c.add(c["id"])
            ok = False
            try:
                ok = yield from self.upload_customer(c)
            except CloudTimeout:
                ok = False
            if not ok:
                continue
            if not self.fx("pending"):
                for t in self.q("""SELECT * FROM transactions WHERE customer_id=? AND transaction_uuid IS NOT NULL AND transaction_uuid!=''
                                   AND (is_deleted IS NULL OR is_deleted=0) AND (is_uploaded=0 OR is_uploaded IS NULL)
                                   AND (is_created_by_me=1 OR is_created_by_me IS NULL) ORDER BY transaction_date ASC, id ASC""", (c["id"],)):
                    yield from self.upload_transaction(t, c["sync_uuid"])
        if self.fx("pending"):
            yield from self._upload_all_owned_pending()
        yield from self.sync_pending_invoices()

    def _upload_all_owned_pending(self, limit=None):
        """[pending] كل معاملة أملكها ولم تُرفع — بغض النظر عن مالك العميل أو المنسق."""
        sql = f"""SELECT t.*, c.sync_uuid AS cs FROM transactions t JOIN customers c ON c.id=t.customer_id
                  WHERE c.sync_uuid IS NOT NULL AND {self._owned_pending_where('t')} ORDER BY t.transaction_date ASC, t.id ASC"""
        if limit:
            sql += f" LIMIT {limit}"
        n = 0
        for t in self.q(sql):
            cs = t.pop("cs")
            try:
                ok = yield from self.upload_transaction(t, cs, tombstone_foreign=(t["is_created_by_me"] == 0))
                n += 1 if ok else 0
            except CloudTimeout:
                pass
        return n

    # ------------------------------------------------------------------
    def _add_to_retry(self, typ, uuid, data):
        if self.q1("SELECT 1 x FROM sync_retry_queue WHERE sync_uuid=?", (uuid,)):
            return
        self.ex("INSERT OR IGNORE INTO sync_retry_queue(type, sync_uuid, data, retry_count, next_retry_time, created_at) VALUES (?,?,?,?,?,?)",
                (typ, uuid, json.dumps(data, default=str), 0, iso(self.sim.now + self.skew + 2), self.ts()))
        self._schedule_retry()

    def _schedule_retry(self):
        if self.retry_timer_active:
            return
        self.retry_timer_active = True
        ep = self.epoch

        def _fire():
            if ep != self.epoch or not self.running:
                return
            self.retry_timer_active = False
            self.sim.spawn(self._process_retry_queue(), self, name=f"{self.name}:retry")
        self.sim.at(self.sim.now + 30.0, _fire)

    def _process_retry_queue(self):
        if not self.initialized:
            return
        ready = self.q("SELECT * FROM sync_retry_queue WHERE next_retry_time <= ? ORDER BY next_retry_time ASC LIMIT 10", (self.ts(),))
        for op in ready:
            uuid = op["sync_uuid"]
            data = json.loads(op["data"])
            success = False
            try:
                if op["type"] == "customer":
                    success = yield from self.upload_customer(data)
                else:
                    cs = data.get("customer_sync_uuid")
                    if cs:
                        success = yield from self.upload_transaction(data, cs)
            except CloudTimeout:
                success = False
            if success:
                self.ex("DELETE FROM sync_retry_queue WHERE sync_uuid=?", (uuid,))
                continue
            rc = op["retry_count"] + 1
            mult = min(1 << min(rc, 30), 300)
            self.ex("UPDATE sync_retry_queue SET retry_count=?, next_retry_time=? WHERE sync_uuid=?",
                    (rc, iso(self.sim.now + self.skew + 2 * mult), uuid))
        if self.q1("SELECT COUNT(*) c FROM sync_retry_queue")["c"] > 0:
            self._schedule_retry()

    # ------------------------------------------------------------------
    def _wal_recover(self):
        """SyncCrashRecoveryService._recoverPendingOperations."""
        self.ex("UPDATE sync_wal SET status=? WHERE status < ?", (W_RECOVERED, W_SYNCED))

    def _background_sync(self):
        """_performBackgroundSync (كل 10 دقائق)."""
        if not self.initialized or self.bulk:
            return
        if self.status != "online":
            return
        for op in self.q("SELECT * FROM sync_wal WHERE status IN (?,?) ORDER BY created_at", (W_COMMITTED, W_RECOVERED)):
            data = json.loads(op["data"])
            ok = False
            try:
                if op["type"] == "transaction":
                    cs = data.get("customer_sync_uuid")
                    if cs:
                        ok = yield from self.upload_transaction(data, cs)
                else:
                    ok = yield from self.upload_customer(data)
            except CloudTimeout:
                ok = False
            self.ex("UPDATE sync_wal SET status=? WHERE id=?", (W_SYNCED if ok else W_FAILED, op["id"]))
        yield from self._process_retry_queue()
        yield from self._retry_old_orphans()
        if self.fx("bootstrap") and self.restored_flag:
            yield from self.ensure_new_device_bootstrap()
        if self.fx("pending"):
            yield from self._upload_all_owned_pending()
            yield from self._sync_pending_changes()

    # ------------------------------------------------------------------
    def _start_watchdog(self):
        self.sim.spawn(self._watchdog_cycle(), self, name=f"{self.name}:wd")
        self._start_timer(30.0, self._watchdog_cycle, "wd")

    def _watchdog_cycle(self):
        """SyncWatchdog._runWatchdogCycle."""
        if self.wd_paused or self.bulk or self.wd_processing:
            return
        self.wd_processing = True
        try:
            custs = self.q("""SELECT c.* FROM customers c LEFT JOIN sync_coordination sc ON sc.entity_type='customer' AND sc.sync_uuid=c.sync_uuid
                              WHERE c.sync_uuid IS NOT NULL AND c.sync_uuid!='' AND (sc.id IS NULL OR sc.firebase_synced=0 OR sc.firebase_synced IS NULL)
                              AND (c.is_deleted IS NULL OR c.is_deleted=0) LIMIT 5""")
            if self.fx("keepowner"):
                custs = [c for c in custs if c["is_created_by_me"] in (1, None)]
            for c in custs:
                if self.repairing or self.bulk:
                    return
                try:
                    yield from self.upload_customer(c)
                except CloudTimeout:
                    pass
            if self.fx("pending"):
                yield from self._upload_all_owned_pending(limit=200)
            else:
                txs = self.q("""SELECT t.*, c.sync_uuid AS customer_sync_uuid FROM transactions t INNER JOIN customers c ON t.customer_id=c.id
                                LEFT JOIN sync_coordination sc ON sc.entity_type='transaction' AND sc.sync_uuid=t.transaction_uuid
                                WHERE t.transaction_uuid IS NOT NULL AND t.transaction_uuid!='' AND c.sync_uuid IS NOT NULL
                                AND (t.is_uploaded=0 OR t.is_uploaded IS NULL) AND (t.is_created_by_me=1 OR t.is_created_by_me IS NULL)
                                AND (sc.id IS NULL OR sc.firebase_synced=0 OR sc.firebase_synced IS NULL) LIMIT 10""")
                for t in txs:
                    cs = t.get("customer_sync_uuid")
                    if not cs:
                        continue
                    try:
                        yield from self.upload_transaction(t, cs)
                    except CloudTimeout:
                        pass
            if self.settings["auto_cleanup"]:
                day = int(self.sim.now // 86400)
                if self.last_cleanup_day != day:
                    self.last_cleanup_day = day
                    yield from self.smart_pipe_cleanup()
        finally:
            self.wd_processing = False

    # ==================================================================
    # الاستقبال: العملاء
    # ==================================================================
    def _apply_customer_change(self, uuid, data):
        """_applyCustomerChange."""
        name = (data.get("name") or "").strip()
        if not name and not (self.fx("tomb") and data.get("isDeleted")):
            return
        if not (data.get("syncUuid") or uuid):
            return
        if self.fx("sign") and not self._verify_incoming(uuid, data):
            return
        is_del = data.get("isDeleted") is True or data.get("is_deleted") == 1
        if is_del:
            if self.fx("tomb"):
                yield from self._apply_customer_tombstone(uuid, data)
                return
            if self.settings["policy"] == "smartReactivate":
                own = self.q("""SELECT t.id FROM transactions t JOIN customers c ON c.id=t.customer_id WHERE c.sync_uuid=?
                                AND (t.is_deleted IS NULL OR t.is_deleted=0) AND t.is_created_by_me=1""", (uuid,))
                if own:
                    return
            yield from self._delete_local_customer(uuid)
            return
        existing = self.customer_by_uuid(uuid)
        if existing is None:
            nin = norm_ar(name)
            matched = None
            for c in self.q("SELECT * FROM customers WHERE is_deleted IS NULL OR is_deleted=0"):
                cn = (c["name"] or "").strip()
                if cn == name or (nin and norm_ar(cn) == nin):
                    if self.fx("identity") and c["sync_uuid"]:
                        continue  # 🛡️ هوية مزامنة مستقلة — ليس نفس العميل لمجرد الاسم
                    matched = c
                    break
            if matched is not None:
                mid = matched["id"]
                self.ex("UPDATE customers SET sync_uuid=?, phone=COALESCE(NULLIF(phone,''),?), last_modified_at=?, synced_at=? WHERE id=?",
                        (uuid, data.get("phone"), self.ts(), self.ts(), mid))
                self.coord_register("customer", uuid, "firebase")
                self.coord_mark("customer", uuid)
                yield from self._process_orphans(mid, uuid)
                self.verify_repair(mid)
                return
            try:
                cid = self._insert_received_customer(uuid, data, name)
            except sqlite3.IntegrityError:
                if not self.fx("identity"):
                    raise
                cid = self._insert_received_customer(uuid, data, name, phone_suffix=True)
            self.coord_register("customer", uuid, "firebase")
            self.coord_mark("customer", uuid)
            yield from self._process_orphans(cid, uuid)
            if self.fx("tomb"):
                self.apply_visibility(cid)
        else:
            vals = {
                "name": data.get("name") or existing["name"],
                "phone": data.get("phone") if data.get("phone") is not None else existing["phone"],
                "last_modified_at": data.get("lastModifiedAt") or self.ts(),
                "synced_at": self.ts(),
            }
            if not self.fx("keepowner"):
                vals["is_created_by_me"] = 0
            if self.fx("tomb") and data.get("isDeleted") is False and existing["tombstoned"] in (1,):
                vals["tombstoned"] = 0
            if self.fx("identity") and vals["phone"] != existing["phone"]:
                clash = self.q1("SELECT id FROM customers WHERE name=? AND phone=? AND id!=?", (vals["name"], vals["phone"], existing["id"]))
                if clash:
                    vals["phone"] = (vals["phone"] or "") + "​"
            sets = ", ".join(f"{k}=?" for k in vals)
            try:
                self.ex(f"UPDATE customers SET {sets} WHERE sync_uuid=?", (*vals.values(), uuid))
            except sqlite3.IntegrityError:
                pass
            if self.fx("tomb"):
                self.apply_visibility(existing["id"])
        return
        yield

    def _insert_received_customer(self, uuid, data, name, phone_suffix=False):
        phone = data.get("phone")
        if phone_suffix:
            k = 1
            while True:
                cand = (phone or "") + "​" * k
                if not self.q1("SELECT 1 x FROM customers WHERE name=? AND phone=?", (name, cand)):
                    phone = cand
                    break
                k += 1
        cur = self.ex("""INSERT INTO customers(name, phone, current_total_debt, created_at, last_modified_at, sync_uuid, is_deleted, synced_at, is_created_by_me)
                         VALUES (?,?,0.0,?,?,?,0,?,0)""", (name, phone, data.get("createdAt"), data.get("lastModifiedAt"), uuid, self.ts()))
        return cur.lastrowid

    def _apply_customer_tombstone(self, uuid, data):
        """[tomb] شاهد حذف عميل وارد: لا حذف محلي للمعاملات هنا — المعاملات تُبطَل
        بشواهدها الخاصة (يرفعها الجهاز الذي حذف). نطبّق قاعدة الظهور فقط."""
        c = self.customer_by_uuid(uuid)
        if c is None:
            name = (data.get("name") or "").strip() or "عميل محذوف"
            try:
                cid = self._insert_received_customer(uuid, data, name)
            except sqlite3.IntegrityError:
                cid = self._insert_received_customer(uuid, data, name, phone_suffix=True)
            self.coord_register("customer", uuid, "firebase")
            self.coord_mark("customer", uuid)
        else:
            cid = c["id"]
        self.ex("UPDATE customers SET tombstoned=1, synced_at=? WHERE id=?", (self.ts(), cid))
        if self.settings["policy"] == "strictDelete":
            # المالك يُبطل كل معاملاته هو على العميل ويرفع شواهدها
            self.ex("UPDATE transactions SET is_deleted=1, is_uploaded=0 WHERE customer_id=? AND (is_created_by_me=1 OR is_created_by_me IS NULL) AND (is_deleted IS NULL OR is_deleted=0)", (cid,))
            self.w.truth.owner_strict_void(uuid, self.name)
        self.recalc_customer(cid) if False else self.verify_repair(cid)
        self.apply_visibility(cid)
        return
        yield

    def _delete_local_customer(self, uuid):
        """_deleteLocalCustomer → DatabaseService.deleteCustomer (يرفع العميل من جديد!)."""
        c = self.q1("SELECT id FROM customers WHERE sync_uuid=?", (uuid,))
        if c:
            self._dao_delete_customer(c["id"])
            row = self.q1("SELECT * FROM customers WHERE id=?", (c["id"],))
            # DatabaseService.deleteCustomer: FirebaseSyncService().uploadCustomer(updatedRows.first) (بلا await)
            self.sim.spawn(self.upload_customer(row), self, name=f"{self.name}:delEcho")
        return
        yield

    def merge_duplicate_customers_by_name(self):
        """mergeDuplicateCustomersByName."""
        groups = {}
        for c in self.q("SELECT * FROM customers WHERE is_deleted IS NULL OR is_deleted=0"):
            raw = (c["name"] or "").strip()
            if not raw:
                continue
            key = norm_ar(raw) or raw.lower()
            groups.setdefault(key, []).append(c)
        for lst in groups.values():
            if len(lst) <= 1:
                continue
            if self.fx("identity"):
                # 🛡️ لا ندمج هويتين مزامنتين مختلفتين أبداً؛ ندمج فقط السجلات
                # المحلية القديمة التي لم تُعطَ هوية مزامنة قط.
                lst = [c for c in lst if not c["sync_uuid"]] + [c for c in lst if c["sync_uuid"]][:1]
                if len([c for c in lst if not c["sync_uuid"]]) == 0:
                    continue
            if self.fx("identity"):
                lst.sort(key=lambda c: (0 if c["sync_uuid"] else 1, -(c["is_created_by_me"] or 0), c["id"]))
            else:
                lst.sort(key=lambda c: (-(c["is_created_by_me"] or 0), c["id"]))
            primary = lst[0]
            with_hist = 0
            for c in lst:
                n = self.q1("SELECT COUNT(*) n FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0)", (c["id"],))["n"]
                if n > 0:
                    with_hist += 1
            if with_hist > 1:
                continue
            for c in lst[1:]:
                self.ex("UPDATE transactions SET customer_id=? WHERE customer_id=?", (primary["id"], c["id"]))
                self.ex("UPDATE invoices SET customer_id=? WHERE customer_id=?", (primary["id"], c["id"]))
                self.ex("UPDATE customers SET is_deleted=1, current_total_debt=0, last_modified_at=? WHERE id=?", (self.ts(), c["id"]))
            self.verify_repair(primary["id"])

    # ==================================================================
    # الاستقبال: المعاملات
    # ==================================================================
    def _verify_incoming(self, uuid, data):
        """[sign] رفض المستندات غير الموقّعة بمفتاح المجموعة (الوضع الصارم فقط)."""
        if not (self.settings["strict_sig"] and self.secret_user_provided):
            return True
        dev = data.get("deviceId")
        canon = f"{uuid}|{data.get('customerSyncUuid','')}|{data.get('amountChanged','')}|{data.get('isDeleted')}|{dev}"
        exp = hmac.new(self.secret.encode(), canon.encode(), "sha256").hexdigest()
        ok = hmac.compare_digest(exp, data.get("signature") or "")
        if not ok:
            self.events.append(f"رُفض مستند غير موقّع {uuid} من {dev}")
        return ok

    def _apply_transaction_change(self, uuid, data):
        """_applyTransactionChange."""
        amount = data.get("amountChanged")
        if amount is None or not data.get("customerSyncUuid"):
            return
        if self.fx("sign") and not self._verify_incoming(uuid, data):
            return
        # رفض المعاملات القديمة (مقاساً بوقت الرفع)
        if self.settings["reject_old"] and not self.fx("oldsafe"):
            up = data.get("uploadedAt")
            if isinstance(up, (int, float)):
                if up < self.sim.now - self.settings["max_age_days"] * 86400:
                    return
        cs = data["customerSyncUuid"]
        cust = self.customer_by_uuid(cs)
        if cust is None:
            self._add_to_orphans(uuid, data)
            return
        cid = cust["id"]
        is_tx_del = data.get("isDeleted") is True or data.get("is_deleted") == 1
        if (cust["is_deleted"] == 1) and not is_tx_del and not self.fx("tomb"):
            if self.settings["policy"] == "smartReactivate":
                self.ex("UPDATE customers SET is_deleted=0, last_modified_at=? WHERE id=?", (self.ts(), cid))
            else:
                return
        # [invoice] معاملة فاتورة: حزمة الفاتورة هي المرجع الوحيد
        inv_uuid = data.get("invoiceSyncUuid")
        if self.fx("invoice") and inv_uuid and not is_tx_del:
            if self.q1("SELECT 1 x FROM invoices WHERE invoice_uuid=?", (inv_uuid,)):
                return
        ttype = data.get("transactionType") or ("manual_debt" if amount >= 0 else "manual_payment")
        note = data.get("transactionNote") or ""
        ex = self.q1("SELECT * FROM transactions WHERE transaction_uuid=?", (uuid,))
        up = data.get("uploadedAt") if isinstance(data.get("uploadedAt"), (int, float)) else None
        if self.fx("fresh") and ex is not None and up is not None and ex["remote_ver"] is not None and up < ex["remote_ver"]:
            return  # 🛡️ نسخة أقدم مما طُبّق سابقاً (لقطة سحب كامل/تدقيق تأخر تطبيقها)
        if ex is not None:
            mine = ex["is_created_by_me"] is None or ex["is_created_by_me"] == 1
            if self.fx("owner") and mine:
                # 🛡️ صاحب المعاملة: لا يقبل تعديلاً من غيره إلا شاهد الحذف
                if is_tx_del and not ex["is_deleted"]:
                    self.ex("UPDATE transactions SET is_deleted=1, is_uploaded=1 WHERE id=?", (ex["id"],))
                    self.rebuild_chain(cid)
                    self.recalc_customer(ex["customer_id"])
                    self.apply_visibility(ex["customer_id"])
                    self.w.truth.owner_accepted_tombstone(uuid)
                elif (not is_tx_del) and (not ex["is_deleted"]) and abs(ex["amount_changed"] - amount) > 0.01:
                    self.ex("UPDATE transactions SET is_uploaded=0 WHERE id=?", (ex["id"],))
                return
            if self.fx("tomb") and ex["is_deleted"]:
                return  # 🛡️ الحذف نهائي: لا نُحيي معاملة محذوفة بمستند نشط
            need = abs(ex["amount_changed"] - amount) > 0.01 or ex["transaction_type"] != ttype or (ex["transaction_note"] or "") != note
            if self.fx("tomb"):
                need = need or (bool(ex["is_deleted"]) != is_tx_del)
            if self.fx("fresh") and up is not None and (ex["remote_ver"] is None or up > ex["remote_ver"]):
                # نسجّل أحدث إصدار رأيناه حتى لو تطابق المحتوى، وإلا تسللت نسخة أقدم بعده
                self.ex("UPDATE transactions SET remote_ver=? WHERE id=?", (up, ex["id"]))
            if not need:
                return
            tcs = self.q1("SELECT sync_uuid FROM customers WHERE id=?", (ex["customer_id"],))
            if not tcs or tcs["sync_uuid"] != cs:
                return  # عدم تطابق العميل
            if ex["invoice_id"] is not None:
                self.ex("UPDATE transactions SET amount_changed=?, transaction_note=?, transaction_type=?, is_uploaded=1 WHERE id=?",
                        (amount, note, ttype, ex["id"]))
            else:
                # updateManualTransaction(fromSync: true): النوع يُعاد اشتقاقه من الإشارة
                nt = "manual_debt" if amount >= 0 else "manual_payment"
                self.ex("UPDATE transactions SET amount_changed=?, transaction_note=?, transaction_type=?, is_uploaded=1 WHERE id=?",
                        (amount, note, nt, ex["id"]))
            if self.fx("tomb"):
                self.ex("UPDATE transactions SET is_deleted=? WHERE id=?", (1 if is_tx_del else 0, ex["id"]))
            if self.fx("fresh") and up is not None:
                self.ex("UPDATE transactions SET remote_ver=?, remote_modified_at=? WHERE id=?", (up, data.get("lastModifiedAt"), ex["id"]))
            self.rebuild_chain(ex["customer_id"])
            self.recalc_customer(ex["customer_id"])
            if self.fx("tomb"):
                self.apply_visibility(ex["customer_id"])
            if self.fx("ackver"):
                yield from self._send_ack(uuid, data)
            return
        # 2) تبنّي السجلات التاريخية بلا هوية
        tdate = data.get("transactionDate")
        if tdate:
            om = self.q1("""SELECT id FROM transactions WHERE customer_id=? AND transaction_date=? AND ABS(amount_changed-?)<0.01
                            AND (transaction_uuid IS NULL OR transaction_uuid='') AND (is_deleted IS NULL OR is_deleted=0) LIMIT 1""",
                         (cid, tdate, amount))
            if om:
                self.ex("UPDATE transactions SET sync_uuid=?, transaction_uuid=?, is_uploaded=1 WHERE id=?", (uuid, uuid, om["id"]))
                return
        if abs(amount) > 1e9:
            return
        note2 = note if ("من المزامنة" in note) else (note + "\n🔄 من المزامنة (Firebase)" if note else "🔄 من المزامنة (Firebase)")
        if self.q1("SELECT 1 x FROM transactions WHERE transaction_uuid=? OR sync_uuid=?", (uuid, uuid)):
            return
        before = self.sum_tx(cid)
        dele = 1 if (is_tx_del and self.fx("tomb")) else 0
        self.ex("""INSERT INTO transactions(customer_id, transaction_date, amount_changed, balance_before_transaction, new_balance_after_transaction,
                   transaction_note, transaction_type, created_at, is_created_by_me, is_uploaded, sync_uuid, transaction_uuid, invoice_sync_uuid, is_deleted, origin_device_id, remote_ver, remote_modified_at)
                   VALUES (?,?,?,?,?,?,?,?,0,1,?,?,?,?,?,?,?)""",
                (cid, tdate or self.ts(), amount, before, before + (0 if dele else amount), note2, ttype,
                 data.get("createdAt") or self.ts(), uuid, uuid, inv_uuid, dele, data.get("originDeviceId") or data.get("deviceId"),
                 up if self.fx("fresh") else None, data.get("lastModifiedAt")))
        s = self.sum_tx(cid)
        self.ex("UPDATE customers SET current_total_debt=?, last_modified_at=?, synced_at=? WHERE id=?", (s, self.ts(), self.ts(), cid))
        if self.fx("tomb"):
            self.apply_visibility(cid)
        self.coord_register("transaction", uuid, "firebase")
        self.coord_mark("transaction", uuid)
        yield from self._send_ack(uuid, data)
        if not self.fx("recon"):
            yield from self._apply_pending_verdicts_for(uuid)
        self.verify_repair(cid)

    def _send_ack(self, uuid, data):
        sender = data.get("originDeviceId") or data.get("deviceId")
        if sender is None or sender == self.device_id:
            return
        try:
            yield from self.c_set("transaction_acks", f"{uuid}_{self.device_id}",
                                  {"transactionUuid": uuid, "receiverDeviceId": self.device_id,
                                   "senderDeviceId": sender, "readAt": SERVER_TS}, True)
        except CloudTimeout:
            pass

    def _add_to_orphans(self, uuid, data):
        self.ex("INSERT OR REPLACE INTO sync_orphans(sync_uuid, customer_sync_uuid, data, received_at) VALUES (?,?,?,?)",
                (uuid, data["customerSyncUuid"], json.dumps(data, default=str), self.ts()))

    def _process_orphans(self, cid, cs):
        for o in self.q("SELECT * FROM sync_orphans WHERE customer_sync_uuid=?", (cs,)):
            data = json.loads(o["data"])
            if self.fx("fresh") and self.q1("SELECT 1 x FROM transactions WHERE transaction_uuid=?", (o["sync_uuid"],)):
                # 🛡️ وصلت نسخة أحدث عبر المستمع بعد تخزين اليتيمة — اللقطة المخزنة قديمة
                self.ex("DELETE FROM sync_orphans WHERE sync_uuid=?", (o["sync_uuid"],))
                continue
            try:
                yield from self._apply_transaction_change(o["sync_uuid"], data)
                self.ex("DELETE FROM sync_orphans WHERE sync_uuid=?", (o["sync_uuid"],))
            except CloudTimeout:
                pass

    def _retry_old_orphans(self):
        cutoff = iso(self.sim.now + self.skew - 300)
        for o in self.q("SELECT * FROM sync_orphans WHERE received_at < ? LIMIT 10", (cutoff,)):
            c = self.q1("SELECT id FROM customers WHERE sync_uuid=?", (o["customer_sync_uuid"],))
            if c:
                yield from self._process_orphans(c["id"], o["customer_sync_uuid"])

    # ==================================================================
    # السحب الكامل
    # ==================================================================
    def perform_full_catch_up(self, during_init=False):
        if not self.initialized and not (during_init and self.fx("initfix")):
            return
        try:
            docs = yield from self.c_query("customers")
            for uid, d in docs:
                if d.get("deviceId") == self.device_id:
                    yield from self._own_customer_doc(uid, d)
                    continue
                yield from self._apply_customer_change(uid, d)
        except CloudTimeout:
            pass
        try:
            docs = yield from self.c_query("transactions")
            for uid, d in docs:
                if d.get("deviceId") == self.device_id:
                    yield from self._own_tx_doc(uid, d)
                    continue
                yield from self._apply_transaction_change(uid, d)
        except CloudTimeout:
            pass
        if not self.fx("recon"):
            for p in self.q("SELECT * FROM pending_void_verdicts"):
                if self.q1("SELECT 1 x FROM transactions WHERE transaction_uuid=?", (p["transaction_uuid"],)):
                    yield from self._apply_pending_verdicts_for(p["transaction_uuid"])

    # ==================================================================
    # الفواتير (invoice_controller + invoice_debt_reconciler + invoice_sync_service)
    # ==================================================================
    def recon_uuid(self, inv, cid):
        if self.fx("invoice"):
            cu = self.q1("SELECT sync_uuid FROM customers WHERE id=?", (cid,))
            return f"recon_{inv['invoice_uuid']}_{cu['sync_uuid'] if cu else cid}"
        return f"recon_inv{inv['id']}_cus{cid}"

    def reconcile_invoice(self, invoice_id, create_missing=True, allow_negative=True):
        """InvoiceDebtReconciler.reconcileInvoice."""
        inv = self.q1("SELECT * FROM invoices WHERE id=?", (invoice_id,))
        if not inv:
            return False
        if self.fx("invoice") and inv["is_created_by_me"] == 0:
            return False  # 🛡️ لا يُسوّى على جهاز لا يملك الفاتورة
        expected_cur = 0.0
        if self.fx("invoice") and (inv["is_deleted"] == 1 or inv["status"] != INVOICE_SAVED):
            pass  # فاتورة محذوفة أو مسوّدة: مساهمتها صفر
        elif inv["payment_type"] == CREDIT:
            rem = (inv["total_amount"] or 0) - (inv["amount_paid_on_invoice"] or 0)
            expected_cur = rem if rem > 0 else 0.0
        ph = ",".join("?" * len(NON_CONTRIB))
        recorded = {r["customer_id"]: r["total"] for r in self.q(
            f"""SELECT customer_id, COALESCE(SUM(amount_changed),0) total FROM transactions WHERE invoice_id=? AND (is_deleted IS NULL OR is_deleted=0)
                AND (transaction_type IS NULL OR transaction_type NOT IN ({ph})) GROUP BY customer_id""", (invoice_id, *NON_CONTRIB))}
        affected = set(k for k in recorded if k)
        if inv["customer_id"]:
            affected.add(inv["customer_id"])
        changed = False
        for cid in affected:
            expected = expected_cur if cid == inv["customer_id"] else 0.0
            adj_uuid = self.recon_uuid(inv, cid)
            if self.fx("tomb"):
                gone = self.q1("SELECT 1 x FROM transactions WHERE (transaction_uuid=? OR sync_uuid=?) AND is_deleted=1", (adj_uuid, adj_uuid))
                if gone:
                    continue  # 🛡️ أبطلها حذف العميل — لا نعيد إنشاء الدين
            adj = self.q1("SELECT id, amount_changed FROM transactions WHERE (transaction_uuid=? OR sync_uuid=?) AND (is_deleted IS NULL OR is_deleted=0)", (adj_uuid, adj_uuid))
            if adj is None and self.fx("invoice"):
                legacy = f"recon_inv{invoice_id}_cus{cid}"
                adj = self.q1("SELECT id, amount_changed FROM transactions WHERE transaction_uuid=? AND invoice_id=? AND customer_id=? AND (is_deleted IS NULL OR is_deleted=0)",
                              (legacy, invoice_id, cid))
            adj_amt = adj["amount_changed"] if adj else 0.0
            others = recorded.get(cid, 0.0) - adj_amt
            needed = expected - others
            if adj is None:
                if (not create_missing) and abs(others) <= 0.01:
                    continue
                if abs(needed) <= 0.01:
                    continue
                if not allow_negative and self.sum_tx(cid) + needed - adj_amt < -0.01:
                    continue
                now = self.ts()
                try:
                    self.ex("""INSERT INTO transactions(customer_id, transaction_date, amount_changed, balance_before_transaction, new_balance_after_transaction,
                               transaction_type, invoice_id, invoice_sync_uuid, transaction_uuid, sync_uuid, is_created_by_me, is_uploaded, is_deleted, created_at)
                               VALUES (?,?,?,0,0,'invoice_debt_sync',?,?,?,?,1,0,0,?)""",
                            (cid, now, needed, invoice_id, inv["invoice_uuid"], adj_uuid, adj_uuid, now))
                except sqlite3.IntegrityError:
                    # تصادم المعرّف مع صف قادم من جهاز آخر يحمل نفس recon_inv..._cus...
                    self.local_errors.append(f"تصادم معرّف {adj_uuid}")
                    raise
                changed = True
            else:
                if abs(adj_amt - needed) <= 0.01:
                    continue
                if not allow_negative and self.sum_tx(cid) + needed - adj_amt < -0.01:
                    continue
                self.ex("UPDATE transactions SET amount_changed=?, transaction_date=?, is_uploaded=0, restored_mark=0 WHERE id=?", (needed, self.ts(), adj["id"]))
                changed = True
            self.rebuild_chain(cid)
            self.recalc_customer(cid)
            if self.fx("tomb"):
                self.apply_visibility(cid)
        if changed and self.fx("invoice"):
            # 🛡️ أي تغيير في أثر الفاتورة المالي = نسخة جديدة تُرفع (وإلا تجاهلها المستقبِل)
            if self.fx("bootstrap") and (inv["restored_mark"] or 0) == 1:
                self.ex("UPDATE invoices SET is_synced=0 WHERE id=?", (invoice_id,))
            else:
                self.ex("UPDATE invoices SET version=COALESCE(version,1)+1, is_synced=0 WHERE id=?", (invoice_id,))
        return changed

    def ui_save_invoice(self, cust_uuid, total, paid, ptype, inv_uuid=None):
        """InvoiceController.saveInvoice ثم invoice_actions: syncInvoiceBundleNow + syncCustomer."""
        c = self.customer_by_uuid(cust_uuid)
        cid = c["id"]
        now = self.ts()
        if inv_uuid is None:
            inv_uuid = new_uuid("inv", self.name)
            cur = self.ex("""INSERT INTO invoices(invoice_uuid, customer_id, customer_name, total_amount, amount_paid_on_invoice, payment_type, status,
                             version, is_synced, is_created_by_me, creator_device_id, invoice_date, last_modified_at, created_at)
                             VALUES (?,?,?,?,?,?,?,1,0,1,?,?,?,?)""",
                          (inv_uuid, cid, c["name"], total, paid, ptype, INVOICE_SAVED, self.invoice_device_num, now, now, now))
            iid = cur.lastrowid
        else:
            inv = self.q1("SELECT * FROM invoices WHERE invoice_uuid=?", (inv_uuid,))
            iid = inv["id"]
            self.ex("""UPDATE invoices SET customer_id=?, total_amount=?, amount_paid_on_invoice=?, payment_type=?, status=?, version=?, is_synced=0,
                       last_modified_at=?, restored_mark=0 WHERE id=?""", (cid, total, paid, ptype, INVOICE_SAVED, (inv["version"] or 1) + 1, now, iid))
        self.reconcile_invoice(iid, create_missing=True)
        self.w.truth.set_invoice(inv_uuid, cust_uuid, self.name, total, paid, ptype, INVOICE_SAVED)
        self.sim.spawn(self._after_invoice_save(inv_uuid, cid), self, name=f"{self.name}:invNow")
        return inv_uuid

    def ui_delete_invoice(self, inv_uuid):
        """DatabaseService.deleteInvoice (موجودة في الكود ولا تستدعيها الواجهة حالياً)."""
        inv = self.q1("SELECT * FROM invoices WHERE invoice_uuid=?", (inv_uuid,))
        if inv is None or inv["is_created_by_me"] == 0:
            raise RuntimeError("لا يمكن حذف هذه الفاتورة")
        self.w.truth.delete_invoice(inv_uuid)
        if self.fx("invoice"):
            # 🛡️ حذف منطقي + تسوية المساهمة إلى صفر + نسخة جديدة تنتشر كحزمة
            self.ex("UPDATE invoices SET is_deleted=1, version=COALESCE(version,1)+1, is_synced=0, restored_mark=0, last_modified_at=? WHERE id=?",
                    (self.ts(), inv["id"]))
            self.reconcile_invoice(inv["id"])
            self.sim.spawn(self._after_invoice_save(inv_uuid, inv["customer_id"]), self, name=f"{self.name}:invDel")
            return
        debt = self.q1("SELECT customer_id FROM transactions WHERE invoice_id=? AND amount_changed > 0 ORDER BY created_at LIMIT 1", (inv["id"],))
        # PRAGMA foreign_keys = ON → ON DELETE SET NULL على transactions.invoice_id
        self.ex("UPDATE transactions SET invoice_id=NULL WHERE invoice_id=?", (inv["id"],))
        self.ex("DELETE FROM invoices WHERE id=?", (inv["id"],))
        if debt:
            self.rebuild_chain(debt["customer_id"])
            self.recalc_customer(debt["customer_id"])

    def ui_suspend_invoice(self, cust_uuid, total, paid, ptype):
        """InvoiceSuspendService.suspendInvoice → DatabaseService.insertInvoice (بلا تسوية)."""
        c = self.customer_by_uuid(cust_uuid)
        now = self.ts()
        inv_uuid = new_uuid("inv", self.name)
        self.ex("""INSERT INTO invoices(invoice_uuid, customer_id, customer_name, total_amount, amount_paid_on_invoice, payment_type, status,
                   version, is_synced, is_created_by_me, creator_device_id, invoice_date, last_modified_at, created_at)
                   VALUES (?,?,?,?,?,?,?,1,0,1,?,?,?,?)""",
                (inv_uuid, c["id"], c["name"], total, paid, ptype, INVOICE_SUSPENDED, self.invoice_device_num, now, now, now))
        self.w.truth.set_invoice(inv_uuid, cust_uuid, self.name, total, paid, ptype, INVOICE_SUSPENDED)
        return inv_uuid

    def _after_invoice_save(self, inv_uuid, cid):
        try:
            yield from self.sync_invoice_bundle_now(inv_uuid)
        except CloudTimeout:
            pass
        c = self.q1("SELECT * FROM customers WHERE id=?", (cid,))
        if c and c["sync_uuid"]:
            data = dict(c)
            data.pop("synced_at", None)  # Customer.toMap() لا يحوي synced_at
            if self.fx("keepowner") and not (c["is_created_by_me"] in (1, None)):
                return  # [keepowner] لا نرفع وثيقة عميل لا نملكه
            try:
                yield from self.upload_customer(data)
            except CloudTimeout:
                pass

    def ui_view_customer(self, cust_uuid):
        """getGroupedCustomerTransactions → reconcileCustomerLedger(createMissing: false)."""
        c = self.customer_by_uuid(cust_uuid)
        if not c:
            return
        cid = c["id"]
        for inv in self.q("SELECT * FROM invoices WHERE customer_id=? OR id IN (SELECT DISTINCT invoice_id FROM transactions WHERE customer_id=? AND invoice_id IS NOT NULL)", (cid, cid)):
            exp = 0.0
            if inv["payment_type"] == CREDIT:
                exp = max((inv["total_amount"] or 0) - (inv["amount_paid_on_invoice"] or 0), 0.0)
            ph = ",".join("?" * len(NON_CONTRIB))
            rec = self.q1(f"""SELECT COALESCE(SUM(amount_changed),0) s FROM transactions WHERE invoice_id=? AND customer_id=? AND (is_deleted IS NULL OR is_deleted=0)
                              AND (transaction_type IS NULL OR transaction_type NOT IN ({ph}))""", (inv["id"], cid, *NON_CONTRIB))["s"]
            if abs(exp - rec) <= 0.01:
                continue
            if abs(rec) <= 0.01:
                continue
            try:
                self.reconcile_invoice(inv["id"], create_missing=False, allow_negative=False)
            except sqlite3.IntegrityError:
                pass

    def _invoice_bundle(self, inv):
        txs = self.q("SELECT * FROM transactions WHERE invoice_sync_uuid=?", (inv["invoice_uuid"],))
        if not txs:
            txs = self.q("SELECT * FROM transactions WHERE invoice_id=?", (inv["id"],))
        cu = self.q1("SELECT name, phone, sync_uuid FROM customers WHERE id=?", (inv["customer_id"],)) if inv["customer_id"] else None
        payload = {k: inv[k] for k in ("invoice_uuid", "customer_name", "total_amount", "amount_paid_on_invoice", "payment_type",
                                       "status", "version", "creator_device_id", "invoice_date", "last_modified_at", "created_at")}
        if self.fx("invoice"):
            payload["is_deleted"] = inv["is_deleted"] or 0
        payload["customer_sync_uuid"] = cu["sync_uuid"] if cu else None
        payload["customer"] = cu
        payload["transactions"] = [{k: t[k] for k in ("transaction_date", "amount_changed", "transaction_type", "created_at",
                                                      "transaction_uuid", "sync_uuid", "invoice_sync_uuid", "is_deleted")} for t in txs]
        payload["uploadedAt"] = SERVER_TS
        payload["uploaderDeviceId"] = self.device_id
        return payload

    def sync_pending_invoices(self):
        n = 0
        if self.fx("bootstrap") and self.restored_flag:
            return 0
        for inv in self.q("SELECT * FROM invoices WHERE is_synced=0 AND invoice_uuid IS NOT NULL"):
            payload = self._invoice_bundle(inv)
            try:
                yield from self.c_set("invoices", inv["invoice_uuid"], payload, True)
                self.ex("UPDATE invoices SET is_synced=1 WHERE invoice_uuid=?", (inv["invoice_uuid"],))
                self._mark_bundle_txs_uploaded(payload)
                n += 1
            except CloudTimeout:
                pass
        return n

    def sync_invoice_bundle_now(self, inv_uuid):
        if self.fx("bootstrap") and self.restored_flag:
            return False
        inv = self.q1("SELECT * FROM invoices WHERE invoice_uuid=?", (inv_uuid,))
        if not inv or inv["is_synced"] == 1:
            return True
        payload = self._invoice_bundle(inv)
        yield from self.c_set("invoices", inv_uuid, payload, True)
        self.ex("UPDATE invoices SET is_synced=1 WHERE invoice_uuid=?", (inv_uuid,))
        self._mark_bundle_txs_uploaded(payload)
        return True

    def _mark_bundle_txs_uploaded(self, payload):
        for t in payload["transactions"]:
            if self.fx("tomb") and t.get("is_deleted"):
                continue  # 🛡️ شاهد الحذف يُرفع عبر قناة المعاملات — لا نعلّمه مرفوعاً هنا
            self.ex("UPDATE transactions SET is_uploaded=1 WHERE transaction_uuid=? OR sync_uuid=?", (t["transaction_uuid"], t["transaction_uuid"]))

    def _invoice_start_sync(self):
        try:
            yield from self.sync_pending_invoices()
        except CloudTimeout:
            pass
        self._repair_credit_invoices()
        self.listeners.append(self.cloud.listen(self, "invoices", self._on_invoices_changed, name="invoices"))
        self._start_timer(180.0, self.sync_pending_invoices, "invretry")

    def _on_invoices_changed(self, changes):
        for typ, uuid, data in changes:
            if typ == "removed":
                continue
            try:
                yield from self._process_incoming_invoice(uuid, data)
            except CloudTimeout:
                pass
            except sqlite3.Error as e:
                self.events.append(f"فشل حفظ الفاتورة {uuid}: {e}")

    def _process_incoming_invoice(self, uuid, data):
        """InvoiceSyncService._processIncomingInvoice."""
        creator = str(data.get("creator_device_id") or "unknown")
        if creator == self.device_id:  # مقارنة معرّف Firebase بالرقم «1» — لا تتطابق أبداً
            return
        inc_ver = int(data.get("version") or 1)
        loc = self.q1("SELECT id, version, is_created_by_me, restored_mark FROM invoices WHERE invoice_uuid=?", (uuid,))
        if loc is not None and (loc["version"] or 0) >= inc_ver:
            return
        own_restore = self.fx("bootstrap") and data.get("uploaderDeviceId") == self.device_id and (
            loc is None or loc["is_created_by_me"] == 1)
        if own_restore and loc is not None and (loc["restored_mark"] or 0) == 0:
            # 🛡️ عُدّلت محلياً بعد الاستعادة: تعديل المستخدم هو الأحدث نيةً.
            # نتقدّم على نسخة السحابة كي يحلّ رفعنا محلها بدل أن تمحوه.
            self.ex("UPDATE invoices SET version=?, is_synced=0 WHERE id=?", (inc_ver + 1, loc["id"]))
            return
        if self.fx("invoice") and loc is not None and loc["is_created_by_me"] == 1 and not own_restore:
            return  # 🛡️ فاتورتي أنا: نسختي المحلية هي المرجع دائماً
        cs = data.get("customer_sync_uuid") or ((data.get("customer") or {}).get("sync_uuid"))
        is_credit = data.get("payment_type") == CREDIT
        cid = None
        if is_credit or cs or data.get("customer"):
            cid = self._resolve_or_create_customer(cs, data.get("customer_name"), (data.get("customer") or {}).get("phone"))
        vals = {"customer_name": data.get("customer_name") or "عميل مزامنة", "total_amount": data.get("total_amount") or 0.0,
                "amount_paid_on_invoice": data.get("amount_paid_on_invoice") or 0.0, "payment_type": data.get("payment_type") or CASH,
                "status": data.get("status") or INVOICE_SAVED, "version": inc_ver, "is_synced": 1,
                "is_created_by_me": 1 if own_restore else 0, "is_locked": 0 if own_restore else 1,
                "creator_device_id": creator, "invoice_uuid": uuid, "customer_id": cid, "restored_mark": 0,
                "invoice_date": data.get("invoice_date"), "last_modified_at": data.get("last_modified_at"), "created_at": data.get("created_at")}
        if self.fx("invoice"):
            vals["is_deleted"] = int(data.get("is_deleted") or 0)
        self.ex("BEGIN")
        try:
            row = self.q1("SELECT id, version FROM invoices WHERE invoice_uuid=?", (uuid,))
            if row is not None:
                if (row["version"] or 0) >= inc_ver:
                    self.ex("ROLLBACK")
                    return
                iid = row["id"]
                sets = ", ".join(f"{k}=?" for k in vals)
                self.ex(f"UPDATE invoices SET {sets} WHERE id=?", (*vals.values(), iid))
                is_update = True
            else:
                cols = ", ".join(vals)
                cur = self.ex(f"INSERT INTO invoices({cols}) VALUES ({','.join('?'*len(vals))})", tuple(vals.values()))
                iid = cur.lastrowid
                is_update = False
            deleted_before = set()
            if is_update or self.fx("invoice"):
                if self.fx("invoice"):
                    deleted_before = {r["transaction_uuid"]: r["is_uploaded"] for r in self.q(
                        "SELECT transaction_uuid, is_uploaded FROM transactions WHERE invoice_sync_uuid=? AND is_deleted=1", (uuid,))}
                    if own_restore:
                        self.ex("DELETE FROM transactions WHERE invoice_sync_uuid=? AND (is_deleted IS NULL OR is_deleted=0)", (uuid,))
                    else:
                        self.ex("DELETE FROM transactions WHERE invoice_sync_uuid=? AND (is_created_by_me=0)", (uuid,))
                else:
                    self.ex("DELETE FROM transactions WHERE invoice_sync_uuid=?", (uuid,))
            for t in data.get("transactions") or []:
                if cid is None:
                    continue
                tu = t.get("transaction_uuid") or t.get("sync_uuid")
                m = {"customer_id": cid, "invoice_id": iid, "invoice_sync_uuid": uuid, "is_created_by_me": 1 if own_restore else 0, "is_uploaded": 1,
                     "created_at": t.get("created_at") or self.ts(), "transaction_date": t.get("transaction_date") or t.get("created_at") or self.ts(),
                     "amount_changed": t.get("amount_changed") or 0.0, "transaction_type": t.get("transaction_type") or "invoice_debt",
                     "transaction_uuid": tu, "sync_uuid": tu, "is_deleted": t.get("is_deleted") or 0}
                if tu:
                    exr = self.q1("SELECT id, invoice_sync_uuid, is_created_by_me FROM transactions WHERE transaction_uuid=? OR sync_uuid=?", (tu, tu))
                    if exr:
                        if self.fx("invoice") and (exr["invoice_sync_uuid"] not in (None, "", uuid) or exr["is_created_by_me"] == 1):
                            self.events.append(f"تصادم معرّف معاملة فاتورة {tu} — لم يُكتب فوق صف آخر")
                            continue
                        sets = ", ".join(f"{k}=?" for k in m)
                        self.ex(f"UPDATE transactions SET {sets} WHERE id=?", (*m.values(), exr["id"]))
                        continue
                if tu in deleted_before:
                    m["is_deleted"] = 1  # 🛡️ الحذف نهائي: حزمة أحدث لا تُحيي معاملة محذوفة
                    m["is_uploaded"] = deleted_before[tu]  # شاهد حذف لم يُرفع بعد يبقى في الطابور
                cols = ", ".join(m)
                self.ex(f"INSERT OR REPLACE INTO transactions({cols}) VALUES ({','.join('?'*len(m))})", tuple(m.values()))
            if cid:
                self._ensure_credit_transaction(iid, uuid, cid, vals)
                self.ex("UPDATE customers SET current_total_debt=?, last_modified_at=? WHERE id=?", (self.sum_tx(cid), self.ts(), cid))
                if self.fx("tomb"):
                    self.apply_visibility(cid)
            self.ex("COMMIT")
        except Exception:
            self.ex("ROLLBACK")
            raise
        try:
            yield from self.c_set("invoice_read_acks", f"{uuid}_{self.device_id}",
                                  {"invoiceUuid": uuid, "deviceId": self.device_id, "readAt": SERVER_TS}, True)
        except CloudTimeout:
            pass

    def _resolve_or_create_customer(self, cs, name, phone):
        if cs:
            r = self.customer_by_uuid(cs)
            if r:
                return r["id"]
        name = (name or "").strip()
        if name and not (self.fx("identity") and cs):
            r = self.q1("SELECT id, sync_uuid FROM customers WHERE REPLACE(name,' ','')=? LIMIT 1", (name.replace(" ", ""),))
            if r:
                if not r["sync_uuid"] and cs:
                    self.ex("UPDATE customers SET sync_uuid=? WHERE id=?", (cs, r["id"]))
                return r["id"]
        if not name:
            return None
        uuid = cs or new_uuid("cust_rand", self.name)
        try:
            cur = self.ex("""INSERT INTO customers(name, phone, current_total_debt, sync_uuid, is_created_by_me, is_deleted, created_at, last_modified_at, synced_at)
                             VALUES (?,?,0.0,?,0,0,?,?,?)""", (name, phone, uuid, self.ts(), self.ts(), self.ts()))
            return cur.lastrowid
        except sqlite3.IntegrityError:
            if self.fx("identity"):
                return self._insert_received_customer(uuid, {"phone": phone}, name, phone_suffix=True)
            r = self.q1("SELECT id FROM customers WHERE REPLACE(name,' ','')=? LIMIT 1", (name.replace(" ", ""),))
            return r["id"] if r else None

    def _ensure_credit_transaction(self, iid, inv_uuid, cid, inv):
        if inv["payment_type"] != CREDIT:
            return
        if self.fx("invoice") and (inv["status"] != INVOICE_SAVED or inv.get("is_deleted") == 1):
            return  # 🛡️ الفاتورة المعلّقة مسوّدة (أو محذوفة) لا تُنتج ديناً
        rem = (inv["total_amount"] or 0) - (inv["amount_paid_on_invoice"] or 0)
        if rem <= 0.001:
            return
        if self.q1("SELECT id FROM transactions WHERE (invoice_sync_uuid=? AND invoice_sync_uuid IS NOT NULL AND invoice_sync_uuid!='') OR (invoice_id=? AND invoice_id IS NOT NULL) LIMIT 1", (inv_uuid, iid)):
            return
        if self.fx("invoice"):
            um = None  # 🛡️ لا نختطف معاملة مستقلة لمجرد تطابق المبلغ
        else:
            um = self.q1("""SELECT id FROM transactions WHERE customer_id=? AND ABS(amount_changed-?)<0.01 AND (invoice_sync_uuid IS NULL OR invoice_sync_uuid='')
                            AND (is_deleted IS NULL OR is_deleted=0) LIMIT 1""", (cid, rem))
        if um:
            self.ex("UPDATE transactions SET invoice_id=?, invoice_sync_uuid=? WHERE id=?", (iid, inv_uuid, um["id"]))
            return
        tu = f"tx_debt_{inv_uuid}"
        self.ex("""INSERT INTO transactions(customer_id, transaction_date, amount_changed, transaction_type, invoice_id, transaction_uuid, sync_uuid,
                   invoice_sync_uuid, is_created_by_me, is_uploaded, created_at) VALUES (?,?,?,'invoice_debt',?,?,?,?,0,1,?)""",
                (cid, inv.get("invoice_date") or self.ts(), rem, iid, tu, tu, inv_uuid, self.ts()))

    def _repair_credit_invoices(self):
        for inv in self.q("SELECT * FROM invoices WHERE payment_type=? AND (is_deleted IS NULL OR is_deleted=0) AND (is_created_by_me IS NULL OR is_created_by_me=0)", (CREDIT,)):
            if not inv["customer_id"]:
                continue
            self._ensure_credit_transaction(inv["id"], inv["invoice_uuid"], inv["customer_id"], inv)
            self.ex("UPDATE customers SET current_total_debt=? WHERE id=?", (self.sum_tx(inv["customer_id"]), inv["customer_id"]))

    # ==================================================================
    # الحذف كسلسلة شواهد  [tomb]
    # ==================================================================
    def _upload_customer_tombstone_cascade(self, cid):
        row = self.q1("SELECT * FROM customers WHERE id=?", (cid,))
        try:
            yield from self.upload_customer(row)
        except CloudTimeout:
            pass
        cs = row["sync_uuid"]
        for t in self.q(f"SELECT * FROM transactions t WHERE t.customer_id=? AND {self._owned_pending_where('t')}", (cid,)):
            try:
                yield from self.upload_transaction(t, cs, tombstone_foreign=(t["is_created_by_me"] == 0))
            except CloudTimeout:
                pass

    # ==================================================================
    # القرارات (match_verdicts)
    # ==================================================================
    def _start_verdict_listener(self):
        def handler(changes):
            for typ, doc_id, data in changes:
                if typ != "added":
                    continue
                if data.get("applierDeviceId") == self.device_id:
                    continue
                if self.fx("recon"):
                    continue  # 🛡️ لا أوامر إبطال عن بُعد
                self._apply_verdict(doc_id, data)
            return
            yield
        self.listeners.append(self.cloud.listen(self, "match_verdicts", handler, name="verdicts"))

    def _apply_verdict(self, doc_id, data):
        tu = data.get("transactionUuid")
        if not tu:
            return
        row = self.q1("SELECT * FROM transactions WHERE transaction_uuid=? OR sync_uuid=?", (tu, tu))
        if row is None:
            self.ex("INSERT OR IGNORE INTO pending_void_verdicts(transaction_uuid, verdict_doc_id, data) VALUES (?,?,?)", (tu, doc_id, json.dumps(data, default=str)))
            return
        if row["is_deleted"] == 1:
            return
        self.ex("INSERT OR IGNORE INTO voided_transactions(transaction_uuid, snapshot, reason) VALUES (?,?,?)", (tu, json.dumps(row, default=str), "verdict"))
        self.ex("UPDATE transactions SET is_deleted=1 WHERE id=?", (row["id"],))
        self.ex("UPDATE customers SET current_total_debt=? WHERE id=?", (self.sum_tx(row["customer_id"]), row["customer_id"]))

    def _apply_pending_verdicts_for(self, tu):
        p = self.q1("SELECT * FROM pending_void_verdicts WHERE transaction_uuid=?", (tu,))
        if not p:
            return
        self._apply_verdict(p["verdict_doc_id"], json.loads(p["data"]))
        self.ex("DELETE FROM pending_void_verdicts WHERE id=?", (p["id"],))
        return
        yield

    # ==================================================================
    # المطابقة المحصّنة
    # ==================================================================
    LEDGER_CHUNK = 400

    def _start_armored_listener(self):
        def handler(changes):
            for typ, rid, data in changes:
                if typ == "removed":
                    continue
                if data.get("requesterDeviceId") == self.device_id:
                    continue
                st = data.get("status")
                if self.fx("recon"):
                    if rid in self.handled_requests:
                        continue
                    if st not in ("pending", "completed", "mismatch"):
                        continue
                    self.handled_requests.add(rid)
                elif st != "pending":
                    continue
                try:
                    yield from self._handle_request_as_peer(rid, data)
                except CloudTimeout:
                    pass
        self.listeners.append(self.cloud.listen(self, "reconciliation_requests", handler, name="armored"))

    def _build_ledger(self, cs):
        c = self.customer_by_uuid(cs)
        if not c:
            return None
        txs = self.q("SELECT * FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0) ORDER BY transaction_date, id", (c["id"],))
        out = []
        for t in txs:
            m = {k: t[k] for k in ("amount_changed", "transaction_date", "transaction_type", "transaction_uuid", "sync_uuid", "created_at",
                                   "is_created_by_me", "invoice_sync_uuid", "transaction_note", "description")}
            m["origin"] = self.device_id if (t["is_created_by_me"] in (1, None)) else t["origin_device_id"]
            out.append(m)
        return {"customerSyncUuid": cs, "customerName": c["name"], "referenceBalance": c["current_total_debt"],
                "referenceTxCount": len(out), "transactions": out, "builtAt": SERVER_TS}

    @staticmethod
    def doc_size(d):
        return len(json.dumps(d, default=str, ensure_ascii=False).encode("utf-8"))

    def ui_armored_push(self, cs):
        self.sim.spawn(self.push_my_truth(cs), self, name=f"{self.name}:truthpush")

    def push_my_truth(self, cs):
        if self.fx("recon") and self.restored_flag:
            self.events.append("رُفضت المطابقة: هذا الجهاز في وضع الاستعادة ولم يكمل التمهيد")
            return False
        if self.fx("recon"):
            # 🛡️ اسحب كل ما في السحابة أولاً: لا تعلن «بياناتي صحيحة» وأنت متأخر
            yield from self.perform_full_catch_up()
        led = self._build_ledger(cs)
        if led is None:
            return False
        if self.fx("recon"):
            txs = led.pop("transactions")
            chunks = [txs[i:i + self.LEDGER_CHUNK] for i in range(0, len(txs), self.LEDGER_CHUNK)] or [[]]
            led["chunks"] = len(chunks)
            yield from self.c_set("reconciliation_data", cs, led, False)
            for i, ch in enumerate(chunks):
                part = {"customerSyncUuid": cs, "index": i, "transactions": ch}
                if self.doc_size(part) > 1_048_576:
                    raise RuntimeError("chunk too large")
                yield from self.c_set("reconciliation_data", f"{cs}__p{i}", part, False)
        else:
            if self.doc_size(led) > 1_048_576:
                self.events.append("فشل رفع الكشف: الحجم يتجاوز 1 MiB")
                self.w.metrics["ledger_too_large"] += 1
                return False
            yield from self.c_set("reconciliation_data", cs, led, False)
        rid = f"{cs}_{self.device_id}"
        yield from self.c_set("reconciliation_requests", rid, {"customerSyncUuid": cs, "requesterDeviceId": self.device_id,
                                                              "mode": "truth_push", "status": "pending", "createdAt": SERVER_TS,
                                                              "referenceBalance": led["referenceBalance"]}, False)
        # انتظار أول رد (مهلة 90 ثانية)
        t0 = self.sim.now
        while self.sim.now - t0 < 90:
            yield Sleep(1.0)
            res = [d for _, d in self.cloud.query("reconciliation_results", lambda d: d.get("customerSyncUuid") == cs)]
            if res:
                if not self.fx("recon"):
                    ok = abs(res[0]["balanceAfter"] - led["referenceBalance"]) <= 0.01
                    yield from self.c_set("reconciliation_requests", rid, {"status": "completed" if ok else "mismatch"}, True)
                    if ok:
                        # _cleanupCustomerDocs: حذف الكشف فوراً
                        yield from self.c_delete("reconciliation_data", cs)
                        for k, _ in self.cloud.query("reconciliation_results", lambda d: d.get("customerSyncUuid") == cs):
                            yield from self.c_delete("reconciliation_results", k)
                    return ok
                yield from self.c_set("reconciliation_requests", rid, {"status": "completed"}, True)
                return True
        yield from self.c_set("reconciliation_requests", rid, {"status": "timeout"}, True)
        return False

    def _handle_request_as_peer(self, rid, req):
        cs = req.get("customerSyncUuid")
        led = yield from self.c_get("reconciliation_data", cs)
        if led is None:
            return
        if self.fx("recon"):
            txs = []
            for i in range(int(led.get("chunks") or 0)):
                part = yield from self.c_get("reconciliation_data", f"{cs}__p{i}")
                if part is None:
                    return
                txs.extend(part.get("transactions") or [])
            led = dict(led)
            led["transactions"] = txs
        led["truthDeviceId"] = req.get("requesterDeviceId")
        yield from self._apply_customer_ledger(led)
        bal = self.customer_by_uuid(cs)
        bal = bal["current_total_debt"] if bal else 0.0
        yield from self.c_set("reconciliation_results", f"{cs}_{self.device_id}", {"customerSyncUuid": cs, "applierDeviceId": self.device_id,
                                                                                   "balanceAfter": bal, "respondedAt": SERVER_TS}, False)

    def _apply_customer_ledger(self, led):
        cs = led["customerSyncUuid"]
        c = self.customer_by_uuid(cs)
        if c is None:
            nn = norm_ar(led.get("customerName") or "")
            mb = None
            for r in self.q("SELECT id, name, sync_uuid FROM customers"):
                if norm_ar(r["name"] or "") == nn and not (self.fx("identity") and r["sync_uuid"]):
                    mb = r
                    break
            if mb:
                cid = mb["id"]
                self.ex("UPDATE customers SET sync_uuid=? WHERE id=?", (cs, cid))
            else:
                try:
                    cid = self._insert_received_customer(cs, {}, led.get("customerName") or "عميل مطابقة")
                except sqlite3.IntegrityError:
                    cid = self._insert_received_customer(cs, {}, led.get("customerName") or "عميل مطابقة", phone_suffix=True)
        else:
            cid = c["id"]
        incoming = set()
        for t in led.get("transactions") or []:
            tu = t.get("transaction_uuid") or t.get("sync_uuid")
            if not tu:
                continue
            incoming.add(tu)
            if self.q1("SELECT 1 x FROM transactions WHERE transaction_uuid=? OR sync_uuid=?", (tu, tu)):
                continue
            self.ex("""INSERT INTO transactions(customer_id, amount_changed, transaction_date, transaction_type, transaction_uuid, sync_uuid, created_at,
                       is_created_by_me, is_uploaded, invoice_sync_uuid, origin_device_id) VALUES (?,?,?,?,?,?,?,0,1,?,?)""",
                    (cid, t.get("amount_changed") or 0.0, t.get("transaction_date") or self.ts(), t.get("transaction_type") or "مطابقة",
                     tu, tu, t.get("created_at") or self.ts(), t.get("invoice_sync_uuid"), t.get("origin")))
        excess = self.q("SELECT * FROM transactions WHERE customer_id=? AND (is_deleted IS NULL OR is_deleted=0)", (cid,))
        to_void = []
        for r in excess:
            tu = r["transaction_uuid"] or r["sync_uuid"]
            if tu and tu in incoming:
                continue
            mine = (r["is_created_by_me"] if r["is_created_by_me"] is not None else 1) == 1
            if mine:
                self.ex("UPDATE transactions SET is_uploaded=0 WHERE id=?", (r["id"],))
                continue
            if self.fx("recon"):
                # 🛡️ لا نُبطل معاملة لها في السحابة مستند نشط (المرجع متأخر لا أكثر)
                if r["remote_ver"] is not None:
                    continue  # وصلت من مستند سحابي: غيابه الآن تنظيف لا حذف (_hasEvidenceOfLife)
                if r["invoice_sync_uuid"] and self.q1("SELECT 1 x FROM invoices WHERE invoice_uuid=?", (r["invoice_sync_uuid"],)):
                    continue
                if tu:
                    cd = yield from self.c_get("transactions", tu)
                    if cd is not None and not cd.get("isDeleted"):
                        continue
                    if cd is None:
                        # لا مستند: هل كان في السحابة يوماً ثم نظّفه SmartPipe؟ الإقرارات تشهد
                        acks = yield from self.c_query("transaction_acks", lambda d, u=tu: d.get("transactionUuid") == u)
                        if acks:
                            continue
            to_void.append(r)
        for r in to_void:
            self.ex("INSERT OR IGNORE INTO voided_transactions(transaction_uuid, snapshot, reason) VALUES (?,?,?)",
                    (r["transaction_uuid"], json.dumps(r, default=str), "armored"))
            self.ex("UPDATE transactions SET is_deleted=1 WHERE id=?", (r["id"],))
        self.ex("UPDATE customers SET current_total_debt=? WHERE id=?", (self.sum_tx(cid), cid))
        if to_void and not self.fx("recon"):
            for r in to_void:
                tu = r["transaction_uuid"] or r["sync_uuid"]
                yield from self.c_set("match_verdicts", f"v_{cs}_{tu}", {"transactionUuid": tu, "customerSyncUuid": cs,
                                                                         "voidedAmount": r["amount_changed"], "applierDeviceId": self.device_id,
                                                                         "truthDeviceId": led.get("truthDeviceId")}, False)

    # ==================================================================
    # التدقيق الذاتي مقابل السحابة (ReconciliationService.runSelfAudit)
    # ==================================================================
    def _auto_audit_tick(self):
        if self.status != "online":
            return
        pend = self.q1("SELECT COUNT(*) c FROM transactions WHERE (is_uploaded IS NULL OR is_uploaded=0) AND (is_deleted IS NULL OR is_deleted=0)")["c"]
        if pend > 0:
            return
        yield from self.run_self_audit()

    def run_self_audit(self):
        docs = yield from self.c_query("customers")
        local = {r["sync_uuid"] for r in self.q("SELECT sync_uuid FROM customers WHERE sync_uuid IS NOT NULL")}
        for uid, d in docs:
            if d.get("isDeleted") or uid in local:
                continue
            yield from self._apply_customer_change(uid, d)
        tdocs = yield from self.c_query("transactions")
        by_c = {}
        for uid, d in tdocs:
            by_c.setdefault(d.get("customerSyncUuid"), {})[uid] = d
        for c in self.q("SELECT * FROM customers WHERE sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted=0)"):
            cloud = {u: d for u, d in by_c.get(c["sync_uuid"], {}).items() if not d.get("isDeleted")}
            loc = {r["transaction_uuid"]: r for r in self.q("SELECT * FROM transactions WHERE customer_id=? AND transaction_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted=0)", (c["id"],))}
            for u, d in cloud.items():
                if u not in loc:
                    yield from self._apply_transaction_change(u, d)
            if self.fx("tomb"):
                for u, r in loc.items():
                    d = by_c.get(c["sync_uuid"], {}).get(u)
                    if d is not None and d.get("isDeleted") and r["is_created_by_me"] == 0:
                        yield from self._apply_transaction_change(u, d)

    # ==================================================================
    # المطابقة الحية (LiveMatchService)
    # ==================================================================
    def live_local_state(self):
        rows = self.q("""SELECT c.id, c.name, c.sync_uuid uuid, c.current_total_debt debt, COUNT(t.id) cnt, COALESCE(SUM(t.amount_changed),0) total
                         FROM customers c LEFT JOIN transactions t ON t.customer_id=c.id AND (t.is_deleted IS NULL OR t.is_deleted=0)
                         WHERE c.sync_uuid IS NOT NULL AND (c.is_deleted IS NULL OR c.is_deleted=0) GROUP BY c.id""")
        return {r["uuid"]: {"name": r["name"], "debt": r["debt"], "txCount": r["cnt"], "txSum": r["total"], "id": r["id"]} for r in rows}

    def live_compare(self, peer_state):
        """recompute(): يعيد قائمة صفوف المقارنة كما تُعرض."""
        local = self.live_local_state()
        if self.fx("live"):
            keys = set(local) | set(peer_state)
            out = []
            for k in keys:
                lo, pe = local.get(k), peer_state.get(k)
                out.append({"uuid": k, "localDebt": lo["debt"] if lo else 0.0, "peerDebt": pe["debt"] if pe else 0.0,
                            "localId": lo["id"] if lo else 0})
            return out
        lbn = {}
        for u, c in local.items():
            lbn.setdefault(norm_ar(c["name"]), dict(c, uuid=u))
        pbn = {}
        for u, c in peer_state.items():
            n = norm_ar(c["name"])
            if n not in pbn or abs(c["debt"]) > abs(pbn[n]["debt"]):
                pbn[n] = dict(c, uuid=u)
        out = []
        for n in set(lbn) | set(pbn):
            lo, pe = lbn.get(n), pbn.get(n)
            out.append({"uuid": (lo or pe)["uuid"], "localDebt": lo["debt"] if lo else 0.0, "peerDebt": pe["debt"] if pe else 0.0,
                        "localId": lo["id"] if lo else 0, "name": n})
        return out

    def live_peers_for(self, invited):
        if self.fx("live"):
            return [d for d in invited if d != self.device_id]
        return [next((d for d in invited if d != self.device_id), "")]

    def ui_live_peer_is_correct(self, peer):
        """addCorrectiveTransactionsForPeerTruth."""
        rows = self.live_compare(peer.live_local_state())
        created = 0
        for r in rows:
            if abs(r["peerDebt"] - r["localDebt"]) < 0.01 or r["localId"] <= 0:
                continue
            if self.fx("live"):
                continue
            diff = r["peerDebt"] - r["localDebt"]
            tu = new_uuid("tx_live", self.name)
            self.ex("""INSERT INTO transactions(customer_id, amount_changed, new_balance_after_transaction, transaction_type, transaction_date, created_at,
                       sync_uuid, transaction_uuid, is_created_by_me, is_uploaded, is_deleted) VALUES (?,?,?,'live_match_adjustment',?,?,?,?,1,0,0)""",
                    (r["localId"], diff, r["localDebt"] + diff, self.ts(), self.ts(), tu, tu))
            self.ex("UPDATE customers SET current_total_debt=? WHERE id=?", (r["localDebt"] + diff, r["localId"]))
            created += 1
        if self.fx("live"):
            # 🛡️ «الجهاز الآخر صحيح» = اسحب ما ينقصني من السحابة واطلب منه إعادة رفع ما يملك
            self.sim.spawn(self.run_self_audit(), self, name=f"{self.name}:audit")
            peer.sim.spawn(peer._upload_all_owned_pending(), peer, name=f"{peer.name}:reup") if peer.running else None
        return created

    # ==================================================================
    # التنظيف الذكي (SmartPipe)
    # ==================================================================
    def smart_pipe_cleanup(self):
        devs = yield from self.c_query("devices")
        eligible = {k for k, d in devs if not d.get("isNewDevice") and not d.get("isRetired")}
        if not eligible:
            return 0
        cutoff = self.sim.now - self.settings["auto_delete_days"] * 86400
        docs = yield from self.c_query("transactions")
        acks = yield from self.c_query("transaction_acks")
        by_tx = {}
        for _, a in acks:
            by_tx.setdefault(a.get("transactionUuid"), {})[a.get("receiverDeviceId")] = a.get("readAt")
        deleted = 0
        for uid, d in docs:
            up = d.get("uploadedAt")
            if not isinstance(up, (int, float)) or up > cutoff:
                continue
            sender = d.get("deviceId")
            got = by_tx.get(uid, {})
            ok = True
            for dv in eligible:
                if dv == sender:
                    continue
                if dv not in got:
                    ok = False
                    break
                if self.fx("ackver"):
                    ra = got[dv]
                    if not isinstance(ra, (int, float)) or ra < up:
                        ok = False
                        break
            if ok:
                if self.fx("ackver"):
                    # 🛡️ حذف مشروط داخل معاملة: لا نحذف نسخة أحدث مما فحصناه
                    def cond_delete(cloud, dev, uid=uid, up=up):
                        cur = cloud.get("transactions", uid)
                        if cur is None or cur.get("uploadedAt") != up:
                            return False
                        cloud.delete("transactions", uid, dev)
                        return True
                    r = yield from self.c_txn(cond_delete)
                    deleted += 1 if r else 0
                else:
                    yield from self.c_delete("transactions", uid)
                    deleted += 1
        return deleted

    # ==================================================================
    # مسح السحابة بالكامل (clearCloudDatabase)
    # ==================================================================
    def ui_clear_cloud(self):
        def _run():
            for coll in ("transactions", "customers", "transaction_acks", "sync_operations", "devices", "_time_check"):
                for k, _ in list(self.cloud.query(coll)):
                    yield from self.c_delete(coll, k)
        self.sim.spawn(_run(), self, name=f"{self.name}:clearcloud")

    # ==================================================================
    # التمهيد (Bootstrap) + إعادة البث
    # ==================================================================
    def _start_bootstrap_responder(self):
        def handler(changes):
            for typ, rid, data in changes:
                if typ == "removed":
                    continue
                req = data.get("requestedBy")
                if not req or req == self.device_id or self.bootstrap_responding:
                    continue
                if data.get("status") != "pending":
                    continue
                yield from self._serve_bootstrap(rid, req)
        self.listeners.append(self.cloud.listen(self, "bootstrap_requests", handler, name="bootstrap"))

    def _serve_bootstrap(self, rid, requester):
        def claim(cloud, dev):
            d = cloud.get("bootstrap_requests", rid)
            if d is None or d.get("status") != "pending":
                return False
            cloud.set("bootstrap_requests", rid, {"status": "in_progress", "respondingDevice": dev}, True, dev)
            return True
        try:
            ok = yield from self.c_txn(claim)
        except CloudTimeout:
            return
        if not ok:
            return
        self.bootstrap_responding = True
        try:
            yield from self.rebroadcast_everything()
            yield from self.c_set("bootstrap_requests", rid, {"status": "ready"}, True)
        except CloudTimeout:
            try:
                yield from self.c_set("bootstrap_requests", rid, {"status": "pending"}, True)
            except CloudTimeout:
                pass
        finally:
            self.bootstrap_responding = False

    def rebroadcast_everything(self):
        for c in self.q("SELECT * FROM customers WHERE sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted=0)"):
            if self.fx("bootstrap"):
                # 🛡️ لا نكتب فوق وثيقة موجودة (قد تكون أحدث) ولا نسرق ملكيتها
                exists = yield from self.c_get("customers", c["sync_uuid"])
                if exists is not None:
                    continue
                doc = {"syncUuid": c["sync_uuid"], "name": c["name"], "phone": c["phone"], "isDeleted": False, "is_deleted": 0,
                       "deviceId": "rebroadcast", "lastModifiedAt": c["last_modified_at"], "uploadedAt": SERVER_TS}
                self._sign_doc(doc, c["sync_uuid"])
                yield from self.c_set("customers", c["sync_uuid"], doc, True)
            else:
                # _forceUploadCustomer: deviceId = هذا الجهاز لكل العملاء
                doc = {"syncUuid": c["sync_uuid"], "name": c["name"], "phone": c["phone"], "isDeleted": False, "is_deleted": 0,
                       "deviceId": self.device_id, "lastModifiedAt": c["last_modified_at"], "uploadedAt": SERVER_TS}
                self._sign_doc(doc, c["sync_uuid"])
                yield from self.c_set("customers", c["sync_uuid"], doc, True)
        for t in self.q("""SELECT t.*, c.sync_uuid cs FROM transactions t JOIN customers c ON c.id=t.customer_id
                           WHERE t.transaction_uuid IS NOT NULL AND (t.is_deleted IS NULL OR t.is_deleted=0)"""):
            mine = t["is_created_by_me"] in (1, None)
            if self.fx("invoice") and t["invoice_sync_uuid"]:
                continue  # حزم الفواتير تعاد عبر قناتها
            if not self.fx("bootstrap"):
                if not mine:
                    continue  # _forceUploadTransaction يرفض معاملات غيري
                yield from self._force_upload_tx(t, t["cs"])
            else:
                exists = yield from self.c_get("transactions", t["transaction_uuid"])
                if exists is not None:
                    continue
                doc = {"syncUuid": t["transaction_uuid"], "customerSyncUuid": t["cs"], "amountChanged": t["amount_changed"],
                       "transactionType": t["transaction_type"], "transactionDate": t["transaction_date"], "createdAt": t["created_at"],
                       "isDeleted": False, "is_deleted": 0, "invoiceSyncUuid": t["invoice_sync_uuid"],
                       "deviceId": self.device_id if mine else (t["origin_device_id"] or "rebroadcast"),
                       "originDeviceId": self.device_id if mine else (t["origin_device_id"] or "rebroadcast"),
                       "lastModifiedAt": (t["last_uploaded_at"] if mine else t["remote_modified_at"]) or "",
                       "uploadedAt": SERVER_TS}
                self._sign_doc(doc, t["transaction_uuid"])
                yield from self.c_set("transactions", t["transaction_uuid"], doc, True)
        if self.fx("bootstrap"):
            # InvoiceSyncService.rebroadcastMissingInvoices: إنشاء الغائب فقط داخل معاملة
            for inv in self.q("SELECT * FROM invoices WHERE invoice_uuid IS NOT NULL"):
                payload = self._invoice_bundle(inv)

                def create_if_absent(cloud, dev, u=inv["invoice_uuid"], p=payload):
                    if cloud.get("invoices", u) is not None:
                        return False
                    cloud.set("invoices", u, p, False, dev)
                    return True
                yield from self.c_txn(create_if_absent)
        else:
            self.ex("UPDATE invoices SET is_synced=0 WHERE invoice_uuid IS NOT NULL")
            yield from self.sync_pending_invoices()

    def _force_upload_tx(self, t, cs):
        is_del = (t.get("is_deleted") or 0) == 1
        doc = {"syncUuid": t["transaction_uuid"], "customerSyncUuid": cs, "amountChanged": t["amount_changed"],
               "transactionType": t["transaction_type"], "transactionDate": t["transaction_date"], "createdAt": t["created_at"],
               "isDeleted": is_del, "is_deleted": 1 if is_del else 0, "deviceId": self.device_id, "originDeviceId": self.device_id,
               "uploadedAt": SERVER_TS}
        self._sign_doc(doc, t["transaction_uuid"])
        yield from self.c_set("transactions", t["transaction_uuid"], doc, True)
        self.ex("UPDATE transactions SET is_uploaded=1 WHERE id=?", (t["id"],))

    def ensure_new_device_bootstrap(self):
        """ensureNewDeviceBootstrap."""
        if self.fx("bootstrap"):
            if getattr(self, "_bootstrapping", False):
                return
            self._bootstrapping = True
            try:
                yield from self._ensure_bootstrap_inner()
            except CloudTimeout:
                pass  # يُعاد عند دورة المزامنة الخلفية التالية ما دام الجهاز في وضع الاستعادة
            finally:
                self._bootstrapping = False
            return
        yield from self._ensure_bootstrap_inner()

    def _ensure_bootstrap_inner(self):
        try:
            me = yield from self.c_get("devices", self.device_id)
        except CloudTimeout:
            return
        if self.fx("bootstrap"):
            # 🛡️ جهاز جديد (لم يكمل التمهيد قط) أو قاعدة استُعيدت من نسخة احتياطية
            if me and me.get("bootstrapCompletedAt") and not self.restored_flag:
                return
        else:
            if me and me.get("bootstrapCompletedAt"):
                return
            cnt = self.q1("SELECT COUNT(*) c FROM transactions WHERE is_deleted IS NULL OR is_deleted=0")["c"]
            if cnt > 0:
                yield from self.c_set("devices", self.device_id, {"bootstrapCompletedAt": self.ts()}, True)
                return
        devs = yield from self.c_query("devices")
        others = [k for k, _ in devs if k != self.device_id]
        if not others:
            if self.fx("bootstrap") and self.restored_flag:
                yield from self.perform_full_sync()
            yield from self._finish_bootstrap()
            return
        yield from self.c_set("bootstrap_requests", self.device_id, {"requestedBy": self.device_id, "status": "pending", "requestedAt": SERVER_TS}, False)
        t0 = self.sim.now
        st = "pending"
        while self.sim.now - t0 < 600:
            yield Sleep(10.0)
            try:
                d = yield from self.c_get("bootstrap_requests", self.device_id)
            except CloudTimeout:
                continue
            st = (d or {}).get("status", "pending")
            if st in ("ready", "failed"):
                break
        if st != "ready":
            if self.fx("bootstrap") and self.restored_flag:
                # لا مستجيب: نكمل الاستعادة من السحابة وحدها ثم نفك الحظر
                yield from self.perform_full_sync()
                yield from self._finish_bootstrap()
            return
        yield from self.perform_full_sync()
        yield from self._finish_bootstrap()
        try:
            yield from self.c_delete("bootstrap_requests", self.device_id)
        except CloudTimeout:
            pass

    def _finish_bootstrap(self):
        data = {"bootstrapCompletedAt": self.ts()}
        yield from self.c_set("devices", self.device_id, data, True)
        self.restored_flag = False
        self.ex("UPDATE transactions SET restored_mark=0 WHERE restored_mark=1")
        if self.fx("bootstrap"):
            # فاتورة من النسخة لم تحلّ محلها نسخة سحابية وفيها تغيير معلّق: نسخة جديدة فوق كل ما سبق
            self.ex("UPDATE invoices SET version=COALESCE(version,1)+1 WHERE restored_mark=1 AND is_synced=0")
            self.ex("UPDATE invoices SET restored_mark=0 WHERE restored_mark=1")

    def perform_full_sync(self):
        """performFullSync: تنزيل كل شيء ثم رفع المعلق."""
        if not self.initialized:
            return False
        self.bulk = True
        try:
            docs = yield from self.c_query("customers")
            for uid, d in docs:
                if d.get("deviceId") != self.device_id:
                    yield from self._apply_customer_change(uid, d)
                else:
                    yield from self._own_customer_doc(uid, d)
            docs = yield from self.c_query("transactions")
            for uid, d in docs:
                if d.get("deviceId") != self.device_id:
                    yield from self._apply_transaction_change(uid, d)
                else:
                    yield from self._own_tx_doc(uid, d)
            docs = yield from self.c_query("invoices")
            for uid, d in docs:
                yield from self._process_incoming_invoice(uid, d)
            yield from self._sync_pending_changes()
            return True
        finally:
            self.bulk = False

    # ==================================================================
    # الرفع الشامل (repairAndSyncAllTransactions)
    # ==================================================================
    def ui_repair_all(self):
        def _run():
            self.repairing = True
            try:
                for c in self.q("SELECT * FROM customers WHERE sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted=0) AND (is_created_by_me=1 OR is_created_by_me IS NULL)"):
                    doc = {"syncUuid": c["sync_uuid"], "name": c["name"], "phone": c["phone"], "isDeleted": False, "is_deleted": 0,
                           "deviceId": self.device_id, "uploadedAt": SERVER_TS}
                    self._sign_doc(doc, c["sync_uuid"])
                    yield from self.c_set("customers", c["sync_uuid"], doc, True)
                for t in self.q("""SELECT t.*, c.sync_uuid cs FROM transactions t JOIN customers c ON c.id=t.customer_id WHERE t.transaction_uuid IS NOT NULL
                                   AND (t.is_deleted IS NULL OR t.is_deleted=0) AND (t.is_created_by_me IS NULL OR t.is_created_by_me=1)"""):
                    yield from self._force_upload_tx(t, t["cs"])
            finally:
                self.repairing = False
        self.sim.spawn(_run(), self, name=f"{self.name}:repairall")

    # ==================================================================
    # أدوات الاختبار
    # ==================================================================
    def snapshot_db(self):
        mem = sqlite3.connect(":memory:", isolation_level=None)
        self.db.backup(mem)
        return mem

    def restore_db(self, snap):
        """استعادة نسخة احتياطية قديمة (التطبيق مغلق)."""
        new = sqlite3.connect(":memory:", isolation_level=None)
        snap.backup(new)
        new.row_factory = sqlite3.Row
        self.db = new
        self.restored_flag = True
        # كل صف في النسخة يُوسم «من النسخة»؛ أي تعديل بعد الاستعادة يمحو الوسم
        self.ex("UPDATE transactions SET restored_mark=1")
        if self.fx("bootstrap"):
            self.ex("UPDATE invoices SET restored_mark=1 WHERE is_created_by_me=1 OR is_created_by_me IS NULL")

    def inject_phantom(self, cust_uuid, amount, uuid=None):
        """صف معاملة «شبح» بلا مالك (تلف قديم من إصدار سابق)."""
        c = self.customer_by_uuid(cust_uuid)
        uuid = uuid or new_uuid("tx_phantom", "old")
        self.ex("""INSERT INTO transactions(customer_id, amount_changed, transaction_date, transaction_type, transaction_uuid, sync_uuid, created_at,
                   is_created_by_me, is_uploaded, is_deleted) VALUES (?,?,?,'manual_debt',?,?,?,0,1,0)""",
                (c["id"], amount, self.ts(), uuid, uuid, self.ts()))
        self.ex("UPDATE customers SET current_total_debt=? WHERE id=?", (self.sum_tx(c["id"]), c["id"]))
        return uuid

    # ------------------------------------------------------------------
    def view(self):
        """ما يراه المستخدم: {uuid: (الرصيد المعروض، مجموع المعاملات، مخفي؟)}"""
        out = {}
        for c in self.q("SELECT id, sync_uuid, current_total_debt, is_deleted FROM customers WHERE sync_uuid IS NOT NULL"):
            out[c["sync_uuid"]] = (round(c["current_total_debt"], 2), round(self.sum_tx(c["id"]), 2), bool(c["is_deleted"]))
        return out
