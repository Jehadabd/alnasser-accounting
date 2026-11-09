// assets/wa_server/boot_android.mjs
//
// 📱 تشغيل خادم واتساب داخل تطبيق أندرويد (nodejs-mobile = Node 18، والخادم كُتب لـ Node 20):
//   • مكتبة واتساب تقرأ globalThis.crypto عند التحميل، وهو غير مكشوف افتراضياً في Node 18
//     ⇒ يُعرَّف من node:crypto قبل تحميل الخادم.
//   • أي فشل في تحميل الخادم أو مكتباته يُكتب في LOG_FILE (يظهر في «السجل» داخل البرنامج).
// المتغيرات (API_KEY، PORT، HOST، STATE_DIR، LOG_FILE) يضعها التطبيق في بيئة العملية.

import fs from 'node:fs';
import { webcrypto } from 'node:crypto';

const log = (m) => {
  try {
    if (process.env.LOG_FILE) fs.appendFileSync(process.env.LOG_FILE, `${new Date().toISOString()} ${m}\n`);
  } catch {
    // السجل إضافي
  }
};

if (!globalThis.crypto) {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true, writable: true });
}

log(`تشغيل الخادم على الهاتف — Node ${process.version} (${process.arch})`);
try {
  await import('./server.js');
} catch (e) {
  log(`فشل تحميل الخادم: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
}
