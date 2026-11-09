// خادم تذكير الديون عبر واتساب — برنامج الناصر للمحاسبة
//
// يرتبط برقم واتساب كـ«جهاز مرتبط» (رمز ربط من 8 خانات) ثم يرسل رسائل
// التذكير التي يطلبها البرنامج فقط.
//   • لا يقرأ الرسائل الواردة ولا يخزّنها، ولا يزامن سجل المحادثات.
//   • كل طلب يحمل مفتاحاً سرياً (API_KEY) يولّده البرنامج.
//   • جلسة الربط محفوظة مشفّرة (AES-256-GCM بمفتاح مشتق من API_KEY) في
//     STATE_DIR، ونسخة منها عند البرنامج: إن أُعيد تشغيل الخادم على منصة تمسح
//     الملفات (Render المجاني) يعيدها البرنامج فلا يلزم ربط جديد.
//   • حد أقصى للرسائل في الساعة (MAX_PER_HOUR) حماية للرقم.
//
// المتغيرات: API_KEY (إلزامي، 24+ حرفاً)، PORT (8080)، STATE_DIR (./data)، MAX_PER_HOUR (60)

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import pino from 'pino';
import makeWASocket, {
  BufferJSON,
  DisconnectReason,
  fetchLatestBaileysVersion,
  initAuthCreds,
  proto,
} from 'baileys';

// ملف .env بجانب الخادم (الحاسبة المحلية / Oracle): KEY=VALUE في كل سطر
try {
  for (const line of fs.readFileSync(new URL('./.env', import.meta.url), 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
} catch {
  // لا ملف .env — المتغيرات من المنصة
}

const VERSION = '1.0.0';
const API_KEY = (process.env.API_KEY || '').trim();
const PORT = Number(process.env.PORT || 8080);
const STATE_DIR = process.env.STATE_DIR || path.join(process.cwd(), 'data');
const STATE_FILE = path.join(STATE_DIR, 'wa_state.enc');
const MAX_PER_HOUR = Math.max(1, Number(process.env.MAX_PER_HOUR || 60));

if (API_KEY.length < 24) {
  console.error('API_KEY مطلوب (24 حرفاً على الأقل) — انسخه من شاشة «خادم واتساب» في البرنامج');
  process.exit(1);
}
fs.mkdirSync(STATE_DIR, { recursive: true });

// ─────────────── التشفير ───────────────
const encKey = crypto.createHash('sha256').update(`alnaser-wa:${API_KEY}`).digest();

function encrypt(obj) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', encKey, iv);
  const data = Buffer.concat([c.update(JSON.stringify(obj, BufferJSON.replacer), 'utf8'), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), data]).toString('base64');
}

function decrypt(b64) {
  const buf = Buffer.from(b64, 'base64');
  const d = crypto.createDecipheriv('aes-256-gcm', encKey, buf.subarray(0, 12));
  d.setAuthTag(buf.subarray(12, 28));
  const text = Buffer.concat([d.update(buf.subarray(28)), d.final()]).toString('utf8');
  return JSON.parse(text, BufferJSON.reviver);
}

// ─────────────── الحالة ───────────────
let store = null; // { creds, keys: { [type]: { [id]: value } } }
let rev = 0; // يزيد مع كل تغيّر في الجلسة — البرنامج يأخذ النسخة الأحدث
let sock = null;
let connected = false;
let qrSeen = false;
let lastError = null;
let saveTimer = null;
const sentTimes = [];

const linked = () => !!store?.creds?.me;
const myNumber = () => (store?.creds?.me?.id || '').split(':')[0].split('@')[0] || null;

function persist() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try {
      if (store) fs.writeFileSync(STATE_FILE, encrypt({ rev, store }));
      else fs.rmSync(STATE_FILE, { force: true });
    } catch (e) {
      console.error('تعذّر حفظ الجلسة:', e.message);
    }
  }, 300);
}

function changed() {
  rev++;
  persist();
}

function authState() {
  return {
    creds: store.creds,
    keys: {
      get: async (type, ids) => {
        const bucket = store.keys[type] || {};
        const out = {};
        for (const id of ids) {
          let v = bucket[id];
          if (type === 'app-state-sync-key' && v) v = proto.Message.AppStateSyncKeyData.fromObject(v);
          out[id] = v;
        }
        return out;
      },
      set: async (data) => {
        for (const type in data) {
          store.keys[type] = store.keys[type] || {};
          for (const id in data[type]) {
            const v = data[type][id];
            if (v) store.keys[type][id] = v;
            else delete store.keys[type][id];
          }
        }
        changed();
      },
    },
  };
}

// ─────────────── الاتصال بواتساب ───────────────
let reconnectTimer = null;

async function connect() {
  if (!store || sock) return;
  qrSeen = false;
  let version;
  try {
    ({ version } = await fetchLatestBaileysVersion());
  } catch {
    // يكمل بالإصدار المضمّن
  }
  const s = makeWASocket({
    auth: authState(),
    version,
    logger: pino({ level: 'silent' }),
    printQRInTerminal: false,
    markOnlineOnConnect: false,
    syncFullHistory: false,
    shouldSyncHistoryMessage: () => false,
    generateHighQualityLinkPreview: false,
  });
  sock = s;
  s.ev.on('creds.update', () => changed());
  s.ev.on('connection.update', (u) => {
    if (sock !== s) return;
    if (u.qr) qrSeen = true;
    if (u.connection === 'open') {
      connected = true;
      lastError = null;
      console.log(`متصل بواتساب: ${myNumber()}`);
    }
    if (u.connection === 'close') {
      connected = false;
      sock = null;
      const code = u.lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        console.log('فُكّ الربط من الهاتف — الجلسة حُذفت');
        store = null;
        lastError = 'logged_out';
        changed();
      } else if (linked()) {
        lastError = `closed_${code ?? 'unknown'}`;
        clearTimeout(reconnectTimer);
        reconnectTimer = setTimeout(() => connect().catch(() => {}), 3000);
      } else {
        lastError = 'pair_timeout';
      }
    }
  });
  // messages.upsert غير مُعالَج عمداً: لا شيء يُقرأ أو يُحفظ.
}

async function waitFor(check, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (check()) return true;
    await new Promise((r) => setTimeout(r, 250));
  }
  return check();
}

async function closeSocket() {
  const s = sock;
  sock = null;
  connected = false;
  clearTimeout(reconnectTimer);
  if (s) {
    try {
      s.end(undefined);
    } catch {
      // مغلق أصلاً
    }
  }
}

async function pair(phone) {
  await closeSocket();
  store = { creds: initAuthCreds(), keys: {} };
  lastError = null;
  changed();
  await connect();
  await waitFor(() => qrSeen, 8000);
  if (!sock) throw new Error(lastError || 'socket_closed');
  return sock.requestPairingCode(phone);
}

async function logout() {
  const s = sock;
  if (s && linked()) {
    try {
      await s.logout('alnaser');
    } catch {
      // نحذف الجلسة محلياً على أي حال
    }
  }
  await closeSocket();
  store = null;
  lastError = null;
  changed();
}

function hourCount() {
  const hourAgo = Date.now() - 3600 * 1000;
  while (sentTimes.length && sentTimes[0] < hourAgo) sentTimes.shift();
  return sentTimes.length;
}

async function sendText(to, text) {
  const digits = to.replace(/\D/g, '');
  if (digits.length < 10 || digits.length > 15) return { ok: false, error: 'bad_number' };
  if (!text.trim() || text.length > 4000) return { ok: false, error: 'bad_text' };
  if (!linked()) return { ok: false, error: 'not_linked' };
  if (hourCount() >= MAX_PER_HOUR) return { ok: false, error: 'hour_limit' };
  if (!sock) await connect();
  if (!(await waitFor(() => connected, 45000))) return { ok: false, error: 'not_connected' };
  const [hit] = (await sock.onWhatsApp(`${digits}@s.whatsapp.net`)) || [];
  if (!hit?.exists) return { ok: false, error: 'not_on_whatsapp' };
  const m = await sock.sendMessage(hit.jid, { text });
  sentTimes.push(Date.now());
  return { ok: true, id: m?.key?.id || null };
}

function status() {
  return {
    ok: true,
    app: 'alnaser-wa',
    v: VERSION,
    linked: linked(),
    connected,
    me: myNumber(),
    rev,
    error: lastError,
    sentLastHour: hourCount(),
    maxPerHour: MAX_PER_HOUR,
  };
}

// ─────────────── HTTP ───────────────
function reply(res, code, obj) {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(obj));
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > 30 * 1024 * 1024) throw new Error('too_large');
    chunks.push(c);
  }
  const t = Buffer.concat(chunks).toString('utf8');
  return t ? JSON.parse(t) : {};
}

function authorized(req) {
  const a = Buffer.from(String(req.headers['x-key'] || ''));
  const b = Buffer.from(API_KEY);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/ping')) {
      return reply(res, 200, { ok: true, app: 'alnaser-wa', v: VERSION });
    }
    if (!authorized(req)) return reply(res, 401, { ok: false, error: 'bad_key' });

    switch (`${req.method} ${url.pathname}`) {
      case 'GET /status':
        return reply(res, 200, status());

      case 'POST /pair': {
        const b = await readBody(req);
        const phone = String(b.phone || '').replace(/\D/g, '');
        if (phone.length < 10 || phone.length > 15) return reply(res, 400, { ok: false, error: 'bad_phone' });
        const code = await pair(phone);
        return reply(res, 200, { ok: true, code });
      }

      case 'GET /state':
        return reply(res, 200, { ok: true, rev, blob: store ? encrypt({ rev, store }) : null });

      case 'POST /state': {
        const b = await readBody(req);
        if (linked() && !b.force) return reply(res, 409, { ok: false, error: 'already_linked', rev });
        let d;
        try {
          d = decrypt(String(b.blob || ''));
        } catch {
          return reply(res, 400, { ok: false, error: 'bad_blob' });
        }
        await closeSocket();
        store = d.store;
        rev = Math.max(rev, Number(d.rev || 0));
        persist();
        await connect();
        await waitFor(() => connected, 30000);
        return reply(res, 200, status());
      }

      case 'POST /send': {
        const b = await readBody(req);
        return reply(res, 200, await sendText(String(b.to || ''), String(b.text || '')));
      }

      case 'POST /logout':
        await logout();
        return reply(res, 200, { ok: true });

      default:
        return reply(res, 404, { ok: false, error: 'not_found' });
    }
  } catch (e) {
    return reply(res, 500, { ok: false, error: String(e?.message || e) });
  }
});

// ─────────────── الإقلاع ───────────────
try {
  if (fs.existsSync(STATE_FILE)) {
    const d = decrypt(fs.readFileSync(STATE_FILE, 'utf8'));
    store = d.store;
    rev = Number(d.rev || 0);
    console.log('جلسة محفوظة — إعادة الاتصال');
    connect().catch((e) => console.error(e.message));
  }
} catch (e) {
  console.error('تعذّر قراءة الجلسة المحفوظة (مفتاح مختلف؟):', e.message);
}

if (process.env.NO_LISTEN !== '1') {
  server.listen(PORT, '0.0.0.0', () => console.log(`خادم واتساب الناصر ${VERSION} على المنفذ ${PORT}`));
}
