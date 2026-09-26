# -*- coding: utf-8 -*-
"""
محرّك محاكاة الأحداث المتقطعة (Discrete-Event) لنظام مزامنة Firebase.

يحاكي حلقة أحداث Dart لكل جهاز: كل عملية غير متزامنة (async) في Dart
هي هنا مولِّد Python (generator) يتوقف عند كل `await` حقيقي على الشبكة
(`yield CloudCall`) أو عند نقاط تبديل المهام (`yield Tick()`).

المهام المتزامنة على الجهاز الواحد تتشابك تماماً كما في Dart: مستمع
Firestore يطلق معالجاً جديداً لكل لقطة دون انتظار السابقة، والمؤقتات
تعمل بالتوازي مع أفعال المستخدم.
"""
import heapq
import itertools
import random
from collections import defaultdict, Counter


class Sleep:
    __slots__ = ("dt",)

    def __init__(self, dt):
        self.dt = dt


class Tick:
    """نقطة await بلا زمن — تتيح لمهام أخرى جاهزة أن تعمل (تشابك)."""
    __slots__ = ()


class CloudCall:
    """استدعاء شبكي من جهاز إلى Firestore.

    kind: 'write' | 'read'
    fn:   دالة تُنفَّذ لحظة وصول الطلب إلى الخادم وتعيد النتيجة.
    """
    __slots__ = ("kind", "fn", "timeout")

    def __init__(self, kind, fn, timeout=60.0):
        self.kind = kind
        self.fn = fn
        self.timeout = timeout


class CloudTimeout(Exception):
    """TimeoutException / FirebaseException(unavailable) في Dart."""


class Task:
    __slots__ = ("gen", "dev", "epoch", "name", "send_val", "throw_exc")

    def __init__(self, gen, dev, name):
        self.gen = gen
        self.dev = dev
        self.epoch = dev.epoch if dev is not None else None
        self.name = name
        self.send_val = None
        self.throw_exc = None


class Sim:
    def __init__(self, seed=0):
        self.now = 0.0
        self._q = []
        self._c = itertools.count()
        self.rng = random.Random(seed)
        self.task_errors = Counter()
        self.log_enabled = False
        self.logs = []

    # ------------------------------------------------------------------
    def at(self, t, fn):
        heapq.heappush(self._q, (t, self.rng.random(), next(self._c), fn))

    def spawn(self, gen, dev=None, name="task", delay=0.0):
        task = Task(gen, dev, name)
        self.at(self.now + delay, lambda: self._step(task))
        return task

    def log(self, *a):
        if self.log_enabled:
            self.logs.append(f"[{self.now:10.2f}] " + " ".join(str(x) for x in a))

    # ------------------------------------------------------------------
    def _alive(self, task):
        d = task.dev
        return d is None or (task.epoch == d.epoch and d.running)

    def _step(self, task):
        if not self._alive(task):
            try:
                task.gen.close()
            except Exception:
                pass
            return
        try:
            if task.throw_exc is not None:
                exc = task.throw_exc
                task.throw_exc = None
                y = task.gen.throw(exc)
            else:
                v = task.send_val
                task.send_val = None
                y = task.gen.send(v)
        except StopIteration:
            return
        except Exception as e:  # استثناء غير ممسوك في Future غير منتظَر
            self.task_errors[f"{task.name}: {type(e).__name__}: {e}"] += 1
            return
        self._handle(task, y)

    def _handle(self, task, y):
        if isinstance(y, Sleep):
            self.at(self.now + y.dt, lambda: self._step(task))
        elif isinstance(y, Tick) or y is None:
            self.at(self.now, lambda: self._step(task))
        elif isinstance(y, CloudCall):
            task.dev.net.issue(task, y)
        else:
            raise RuntimeError(f"yield غير معروف: {y!r}")

    def resume(self, task, value=None, exc=None, delay=0.0):
        task.send_val = value
        task.throw_exc = exc
        self.at(self.now + delay, lambda: self._step(task))

    # ------------------------------------------------------------------
    def run_until(self, t_end, max_events=50_000_000):
        n = 0
        while self._q and self._q[0][0] <= t_end:
            t, _, _, fn = heapq.heappop(self._q)
            self.now = t
            fn()
            n += 1
            if n > max_events:
                raise RuntimeError("تجاوز الحد الأقصى للأحداث (حلقة لا نهائية؟)")
        self.now = max(self.now, t_end)
        return n

    def run_for(self, dt):
        return self.run_until(self.now + dt)


SERVER_TS = object()  # FieldValue.serverTimestamp()


class Doc:
    __slots__ = ("data", "ver", "t", "writer")

    def __init__(self, data, ver, t, writer):
        self.data = data
        self.ver = ver
        self.t = t
        self.writer = writer


class Listener:
    def __init__(self, cloud, dev, coll, pred, handler, name):
        self.cloud = cloud
        self.dev = dev
        self.epoch = dev.epoch
        self.coll = coll
        self.pred = pred
        self.handler = handler  # generator function(changes)
        self.name = name
        self.view = {}  # doc_id -> ver
        self.dirty = set()
        self.flush_scheduled = False
        self.active = True

    def mark_all(self):
        self.dirty.update(self.cloud.colls[self.coll].keys())
        self.dirty.update(self.view.keys())

    def schedule(self):
        if self.flush_scheduled or not self.active:
            return
        if not self.dev.online or not self.dev.running:
            return
        self.flush_scheduled = True
        self.cloud.sim.at(self.cloud.sim.now + self.dev.net.lat_down(), self.flush)

    def flush(self):
        self.flush_scheduled = False
        if not self.active or self.epoch != self.dev.epoch or not self.dev.running:
            return
        if not self.dev.online:
            return
        coll = self.cloud.colls[self.coll]
        changes = []
        # ترتيب التسليم = ترتيب الالتزام في الخادم
        ids = sorted(self.dirty, key=lambda i: coll[i].ver if i in coll else 1 << 60)
        self.dirty.clear()
        for doc_id in ids:
            doc = coll.get(doc_id)
            matches = doc is not None and self.pred(doc.data)
            in_view = doc_id in self.view
            if matches and not in_view:
                changes.append(("added", doc_id, dict(doc.data)))
                self.view[doc_id] = doc.ver
            elif matches and in_view:
                if self.view[doc_id] != doc.ver:
                    changes.append(("modified", doc_id, dict(doc.data)))
                    self.view[doc_id] = doc.ver
            elif (not matches) and in_view:
                changes.append(("removed", doc_id, dict(doc.data) if doc else {}))
                del self.view[doc_id]
        if changes:
            self.cloud.sim.spawn(self.handler(changes), self.dev, name=f"{self.dev.name}:{self.name}")


class Cloud:
    """نموذج Firestore: مستندات بإصدارات + مستمعون يستلمون docChanges بالترتيب."""

    def __init__(self, sim):
        self.sim = sim
        self.colls = defaultdict(dict)
        self.ver = 0
        self.listeners = []
        self.writes = Counter()  # (device, collection) -> عدد الكتابات
        self.reads = Counter()

    def _resolve(self, data):
        out = {}
        for k, v in data.items():
            out[k] = self.sim.now if v is SERVER_TS else v
        return out

    def _touch(self, coll, doc_id):
        for L in self.listeners:
            if L.active and L.coll == coll:
                L.dirty.add(doc_id)
                L.schedule()

    def set(self, coll, doc_id, data, merge, writer):
        d = self.colls[coll].get(doc_id)
        new = dict(d.data) if (d is not None and merge) else {}
        new.update(self._resolve(data))
        self.ver += 1
        self.colls[coll][doc_id] = Doc(new, self.ver, self.sim.now, writer)
        self.writes[(writer, coll)] += 1
        self._touch(coll, doc_id)

    def update(self, coll, doc_id, data, writer):
        if doc_id not in self.colls[coll]:
            raise KeyError(f"not-found {coll}/{doc_id}")
        self.set(coll, doc_id, data, True, writer)

    def delete(self, coll, doc_id, writer):
        if doc_id in self.colls[coll]:
            del self.colls[coll][doc_id]
            self.ver += 1
            self.writes[(writer, coll)] += 1
            self._touch(coll, doc_id)

    def get(self, coll, doc_id):
        d = self.colls[coll].get(doc_id)
        return dict(d.data) if d else None

    def query(self, coll, pred=lambda d: True):
        return [(k, dict(v.data)) for k, v in sorted(self.colls[coll].items(), key=lambda kv: kv[1].ver)
                if pred(v.data)]

    def listen(self, dev, coll, handler, pred=lambda d: True, name="listener"):
        L = Listener(self, dev, coll, pred, handler, name)
        self.listeners.append(L)
        L.mark_all()
        L.schedule()
        return L

    def total_writes(self, coll=None):
        return sum(v for (w, c), v in self.writes.items() if coll is None or c == coll)


class Net:
    """شبكة جهاز واحد: اتصال/انقطاع، زمن وصول، مهلة 60 ثانية كما في الكود."""

    def __init__(self, dev, sim, cloud):
        self.dev = dev
        self.sim = sim
        self.cloud = cloud
        self.pending = []  # كتابات مخزّنة في SDK (الموبايل مع persistence)

    def lat_up(self):
        return self.sim.rng.uniform(0.05, 0.35)

    def lat_down(self):
        return self.sim.rng.uniform(0.05, 0.35)

    def issue(self, task, call):
        dev = self.dev
        sim = self.sim
        if not dev.online:
            if call.kind == "write" and dev.platform == "mobile":
                # SDK يحتفظ بالكتابة ويرسلها عند عودة الشبكة؛ الـFuture ينتهي بمهلة.
                entry = {"task": task, "call": call, "done": False}
                self.pending.append(entry)

                def _to():
                    if not entry["done"]:
                        entry["done"] = True
                        sim.resume(task, exc=CloudTimeout("timeout (offline, queued)"))
                sim.at(sim.now + call.timeout, _to)
                return
            sim.resume(task, exc=CloudTimeout("offline"), delay=min(call.timeout, 10.0 if call.kind == "read" else call.timeout))
            return

        up = self.lat_up()
        epoch = dev.epoch

        def _arrive():
            # هل انقطع الاتصال والطلب في الطريق؟
            if not dev.online or dev.epoch != epoch:
                lost_but_committed = call.kind == "write" and sim.rng.random() < 0.5 and dev.epoch == epoch
                if lost_but_committed:
                    try:
                        call.fn()
                    except Exception:
                        pass
                if dev.epoch == epoch:
                    sim.resume(task, exc=CloudTimeout("lost in flight"), delay=call.timeout)
                return
            try:
                res = call.fn()
            except Exception as e:
                sim.resume(task, exc=e, delay=self.lat_down())
                return
            if call.kind == "read":
                self.cloud.reads[dev.name] += 1
            # الرد قد يضيع إن انقطع الاتصال بعد الالتزام
            back = self.lat_down()

            def _ret():
                if dev.epoch != epoch:
                    return
                if not dev.online:
                    sim.resume(task, exc=CloudTimeout("ack lost"), delay=call.timeout)
                    return
                sim.resume(task, value=res)
            sim.at(sim.now + back, _ret)

        sim.at(sim.now + up, _arrive)

    def flush_pending(self):
        """عند عودة الاتصال: SDK الموبايل يرسل الكتابات المخزّنة بالترتيب."""
        pend, self.pending = self.pending, []
        for entry in pend:
            try:
                entry["call"].fn()
            except Exception:
                pass
            if not entry["done"]:
                entry["done"] = True
                self.sim.resume(entry["task"], value=None, delay=self.lat_down())
