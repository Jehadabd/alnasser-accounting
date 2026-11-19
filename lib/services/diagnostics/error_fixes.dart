// lib/services/diagnostics/error_fixes.dart
//
// 🧰 دليل حلول الأخطاء لأداة «تشخيص الأخطاء»: لكل نوع خطأ شرح بلغة بسيطة، والسبب
// المرجح، وخطوات الحل مرقّمة، ومن يستطيع حلّه (أنت أو المطوّر).
//
// المطابقة: نصوص (تعابير منتظمة بلا حساسية لحالة الأحرف) تُبحث في رسالة الخطأ وتفاصيله.
// الترتيب مهم: الأدق أولاً (مثلاً «قاعدة تالفة» قبل «خطأ قرص» العام). ما لا يطابق شيئاً
// يأخذ الحل العام: خلل برمجي إن كان استثناءً تقنياً، وإلا «خطأ غير معروف».
//
// ⚠️ أسماء القوائم في الخطوات هي أسماؤها الحقيقية في البرنامج — عند تغيير اسم قائمة غيّره هنا.

import 'package:flutter/material.dart';

import '../../widgets/setup_guide.dart' show GuideStep, GuideLink;

enum FixSeverity { critical, error, warning, info }

enum FixWho { you, developer, both }

class ErrorCategory {
  const ErrorCategory(this.key, this.label, this.icon, this.color);
  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

class ErrorFix {
  const ErrorFix({
    required this.key,
    required this.title,
    required this.category,
    required this.severity,
    required this.what,
    required this.cause,
    required this.steps,
    this.needles = const [],
    this.who = FixWho.you,
    this.harmless = false,
    this.actions = const [],
  });

  final String key;

  /// اسم المشكلة بلغة صاحب المحل.
  final String title;
  final String category;
  final FixSeverity severity;

  /// ما الذي حدث.
  final String what;

  /// السبب المرجح.
  final String cause;
  final List<GuideStep> steps;

  /// تعابير منتظمة تدل على المشكلة في نص الخطأ.
  final List<String> needles;
  final FixWho who;

  /// تنبيه لا يضر البيانات (مثل حماية تعمل كما يجب).
  final bool harmless;

  /// أزرار إصلاح تنفّذ الحل (مفاتيح FixActions) — ما يكتب منها لا يعمل قبل رفع القاعدة.
  final List<String> actions;
}

class ErrorFixes {
  ErrorFixes._();

  static const categories = <ErrorCategory>[
    ErrorCategory('crash', 'خروج مفاجئ', Icons.power_settings_new_rounded, Color(0xFFB91C1C)),
    ErrorCategory('db', 'قاعدة البيانات', Icons.storage_rounded, Color(0xFF7C3AED)),
    ErrorCategory('disk', 'الملفات والقرص', Icons.folder_off_rounded, Color(0xFFC2410C)),
    ErrorCategory('net', 'الإنترنت والاتصال', Icons.wifi_off_rounded, Color(0xFF2563EB)),
    ErrorCategory('sync', 'المزامنة', Icons.sync_problem_rounded, Color(0xFF0891B2)),
    ErrorCategory('lan', 'الشبكة المحلية', Icons.lan_rounded, Color(0xFF0D9488)),
    ErrorCategory('backup', 'النسخ الاحتياطي', Icons.cloud_off_rounded, Color(0xFF4F46E5)),
    ErrorCategory('print', 'الطباعة', Icons.print_disabled_rounded, Color(0xFF0F766E)),
    ErrorCategory('money', 'حماية الحسابات', Icons.shield_rounded, Color(0xFF047857)),
    ErrorCategory('ui', 'الشاشة والعرض', Icons.web_asset_off_rounded, Color(0xFF64748B)),
    ErrorCategory('code', 'خلل في البرنامج', Icons.bug_report_rounded, Color(0xFFBE123C)),
    ErrorCategory('other', 'أخرى', Icons.help_outline_rounded, Color(0xFF475569)),
  ];

  static ErrorCategory category(String key) =>
      categories.firstWhere((c) => c.key == key, orElse: () => categories.last);

  static const _report = GuideStep(
    'اضغط «نسخ التقرير» أسفل هذه الصفحة وأرسله للمطوّر مع جملة عمّا كنت تفعله لحظة الخطأ.',
    note: 'التقرير لا يحوي كلمات مرور ولا رموزاً سرية — تُمحى قبل الحفظ.',
  );

  static const all = <ErrorFix>[
    // ───────────── خروج مفاجئ (ويندوز) ─────────────
    ErrorFix(
      key: 'crash_tdlib',
      title: 'أُغلق البرنامج بسبب مكتبة تيليجرام (MTProto)',
      category: 'crash',
      severity: FixSeverity.critical,
      what: 'البرنامج أُغلق فجأة، والعطل وقع داخل مكتبة تيليجرام tdjson التي تعمل عند تفعيل «MTProto».',
      cause: 'ملف المكتبة ناقص أو لا يناسب هذا الجهاز، أو برنامج حماية يعبث به.',
      needles: [r'tdjson', r'libtdjson', r'tdlib'],
      who: FixWho.both,
      steps: [
        GuideStep('افتح البرنامج من جديد. بياناتك المحفوظة قبل الإغلاق سليمة.'),
        GuideStep('من «إعدادات تيليجرام» ← «عند حظر تيليجرام» أطفئ «MTProto» مؤقتاً، وارفع بالطريقة العادية أو عبر Tor.'),
        GuideStep('إن تكرّر: احذف المكتبة من «عند حظر تيليجرام» ونزّلها من جديد، واستثنِ مجلد البرنامج من برنامج الحماية.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'crash_gpu',
      title: 'أُغلق البرنامج بسبب تعريف كرت الشاشة',
      category: 'crash',
      severity: FixSeverity.critical,
      what: 'العطل وقع داخل تعريف كرت الشاشة (Intel/NVIDIA/AMD) لا داخل البرنامج.',
      cause: 'تعريف شاشة قديم أو تالف.',
      needles: [r'nvoglv', r'nvwgf', r'atig6', r'atio6', r'amdxx', r'ig\d+icd', r'igxelp', r'd3d1[01]\.dll', r'dxgi\.dll', r'opengl32'],
      steps: [
        GuideStep('افتح البرنامج من جديد. بياناتك المحفوظة سليمة.'),
        GuideStep('حدّث تعريف كرت الشاشة: من «Windows Update» ← «تحديثات اختيارية»، أو من موقع الشركة المصنعة.'),
        GuideStep('أعد تشغيل الحاسبة بعد التحديث.'),
      ],
    ),
    ErrorFix(
      key: 'crash_printer',
      title: 'أُغلق البرنامج أثناء الطباعة',
      category: 'crash',
      severity: FixSeverity.critical,
      what: 'العطل وقع داخل مكتبة الطباعة أو تعريف الطابعة.',
      cause: 'تعريف طابعة تالف، أو طابعة مفصولة وويندوز ما زال ينتظرها.',
      needles: [r'printing_plugin', r'pdfium', r'winspool', r'spool', r'\bprint\w*\.dll'],
      steps: [
        GuideStep('افتح البرنامج من جديد وتأكد أن الفاتورة محفوظة قبل إعادة الطباعة.'),
        GuideStep('من إعدادات ويندوز ← «الطابعات والماسحات الضوئية»: احذف المهام العالقة، وتأكد أن الطابعة متصلة.'),
        GuideStep('أعد تثبيت تعريف الطابعة من موقع الشركة المصنعة إن تكرّر.'),
      ],
    ),
    ErrorFix(
      key: 'crash_memory',
      actions: ['integrity'],
      title: 'أُغلق البرنامج: نفدت الذاكرة أو تلفت',
      category: 'crash',
      severity: FixSeverity.critical,
      what: 'البرنامج أُغلق لأن ذاكرة الحاسبة امتلأت أو أصابها تلف.',
      cause: 'برامج كثيرة مفتوحة، أو تقرير/طباعة ضخمة جداً، أو ذاكرة RAM فيها عطل.',
      needles: [r'0xC0000374', r'0xC00000FD', r'Out of Memory', r'OutOfMemory', r'Exhausted heap', r'bad_alloc'],
      who: FixWho.both,
      steps: [
        GuideStep('أغلق البرامج الأخرى المفتوحة ثم افتح البرنامج.'),
        GuideStep('إن كنت تفتح تقريراً لفترة طويلة جداً، قسّمه على فترات أقصر.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'crash_generic',
      actions: ['integrity', 'checkpoint', 'deep_check'],
      title: 'أُغلق البرنامج فجأة',
      category: 'crash',
      severity: FixSeverity.critical,
      what: 'البرنامج أُغلق دون أن تطلب ذلك.',
      cause: 'عطل داخل البرنامج أو إحدى مكتباته؛ مكانه في «التفاصيل التقنية».',
      needles: [r'خروج البرنامج', r'عطل خطير', r'0xC0000005', r'access violation', r'abort\(\)'],
      who: FixWho.developer,
      steps: [
        GuideStep('افتح البرنامج من جديد. ما حُفظ قبل الإغلاق سليم؛ ما كان مكتوباً ولم يُحفظ يُعاد إدخاله.'),
        GuideStep('افتح «الفحص العميق (قراءة فقط)» من «أدوات الحماية والتدقيق المالي» للتأكد من سلامة الحسابات.'),
        _report,
      ],
    ),

    // ───────────── قاعدة البيانات ─────────────
    ErrorFix(
      key: 'db_corrupt',
      actions: ['integrity', 'reindex', 'checkpoint'],
      title: 'قاعدة البيانات تالفة',
      category: 'db',
      severity: FixSeverity.critical,
      what: 'ملف قاعدة البيانات فيه تلف، فلا يُقرأ بعضه أو كله.',
      cause: 'انقطاع الكهرباء أثناء الحفظ، أو قرص فيه قطاعات تالفة، أو نسخ الملف والبرنامج مفتوح.',
      needles: [r'malformed', r'SQLITE_CORRUPT', r'file is not a database', r'SQLITE_NOTADB', r'database disk image', r'تالف أو غير صالح'],
      who: FixWho.both,
      steps: [
        GuideStep('توقف عن إدخال بيانات جديدة الآن.', warn: true),
        GuideStep('أغلق البرنامج، وانسخ مجلد بيانات البرنامج كاملاً إلى فلاشة أو مكان آخر قبل أي محاولة.'),
        GuideStep('من الإعدادات ← «استعادة قاعدة البيانات من ملف (.db)» استعد آخر نسخة احتياطية سليمة (تيليجرام أو Dropbox أو نسخة الخروج).'),
        GuideStep('بعد الاستعادة شغّل «الفحص العميق (قراءة فقط)»، وأعد إدخال ما بعد تاريخ النسخة.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'db_locked',
      actions: ['checkpoint'],
      title: 'قاعدة البيانات مشغولة',
      category: 'db',
      severity: FixSeverity.error,
      what: 'عملية لم تكتمل لأن قاعدة البيانات كانت مشغولة بعملية أخرى في اللحظة نفسها.',
      cause: 'نسختان من البرنامج مفتوحتان، أو نسخ احتياطي/مزامنة تعمل، أو برنامج حماية يفحص الملف.',
      needles: [r'database is locked', r'SQLITE_BUSY', r'database table is locked', r'SQLITE_LOCKED', r'فشل الحصول على قفل'],
      steps: [
        GuideStep('انتظر ثواني وأعد المحاولة — غالباً تنجح.'),
        GuideStep('تأكد أن البرنامج مفتوح مرة واحدة فقط: من «مدير المهام» لا يوجد أكثر من debt_book.exe.'),
        GuideStep('إن تكرّر كثيراً: استثنِ مجلد بيانات البرنامج من فحص برنامج الحماية.'),
      ],
    ),
    ErrorFix(
      key: 'db_schema',
      actions: ['integrity'],
      title: 'قاعدة البيانات من إصدار مختلف',
      category: 'db',
      severity: FixSeverity.error,
      what: 'البرنامج طلب جدولاً أو عموداً غير موجود في قاعدة البيانات.',
      cause: 'قاعدة من إصدار أقدم أو أحدث من البرنامج، أو تحديث لم يكتمل.',
      needles: [r'no such table', r'no such column', r'has no column named', r'برنامج أحدث'],
      who: FixWho.both,
      steps: [
        GuideStep('حدّث البرنامج لآخر إصدار، ثم أغلقه وافتحه مرة واحدة ليكمل تحديث القاعدة.'),
        GuideStep('إن استعدت نسخة من جهاز آخر: تأكد أن الجهازين على الإصدار نفسه.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'db_unique',
      title: 'سجل مكرر',
      category: 'db',
      severity: FixSeverity.warning,
      what: 'رُفض حفظ سجل لأن مثله موجود مسبقاً (رقم أو اسم أو معرّف).',
      cause: 'حفظ مرتين بسرعة، أو اسم/رقم مستعمل، أو بيانات وصلت من جهاز آخر في اللحظة نفسها.',
      needles: [r'UNIQUE constraint failed', r'SQLITE_CONSTRAINT_UNIQUE', r'موجود مسبقاً', r'Duplicate'],
      steps: [
        GuideStep('أعد فتح الشاشة لترى آخر البيانات، وتأكد أن السجل لم يُحفظ فعلاً قبل إعادته.'),
        GuideStep('إن كان اسماً مكرراً: غيّر الاسم أو استعمل السجل الموجود.'),
      ],
    ),
    ErrorFix(
      key: 'db_fk',
      actions: ['integrity', 'deep_check'],
      title: 'سجل مرتبط بسجل غير موجود',
      category: 'db',
      severity: FixSeverity.error,
      what: 'رُفض حفظ أو حذف لأن السجل مرتبط بسجل آخر محذوف أو غير موجود.',
      cause: 'حُذف عميل أو مادة أو فاتورة من شاشة أخرى أثناء العمل.',
      needles: [r'FOREIGN KEY constraint failed'],
      who: FixWho.both,
      steps: [
        GuideStep('أعد فتح الشاشة وأعد المحاولة.'),
        GuideStep('شغّل «الفحص العميق (قراءة فقط)» للتأكد.'),
        _report,
      ],
    ),

    // ───────────── الملفات والقرص ─────────────
    ErrorFix(
      key: 'disk_full',
      actions: ['checkpoint'],
      title: 'القرص ممتلئ',
      category: 'disk',
      severity: FixSeverity.critical,
      what: 'لم يُكتب ملف لأن مساحة القرص نفدت.',
      cause: 'القرص C (أو قرص البيانات) ممتلئ.',
      needles: [r'No space left', r'ENOSPC', r'errno = 112', r'SQLITE_FULL', r'database or disk is full', r'not enough space', r'المساحة.*لا تكفي'],
      steps: [
        GuideStep('أفرغ مساحة: سلة المحذوفات، مجلد التنزيلات، الملفات المؤقتة (اكتب «تنظيف القرص» في بحث ويندوز).', warn: true),
        GuideStep('اترك على الأقل 2 غيغابايت فارغة دائماً.'),
        GuideStep('أعد المحاولة. ما لم يُحفظ يُعاد إدخاله.'),
      ],
    ),
    ErrorFix(
      key: 'disk_access',
      title: 'لا صلاحية للكتابة على الملف',
      category: 'disk',
      severity: FixSeverity.error,
      what: 'ويندوز منع البرنامج من فتح ملف أو الكتابة عليه.',
      cause: 'الملف «للقراءة فقط»، أو برنامج حماية يحجزه، أو مجلد محمي (OneDrive/المجلدات المحمية)، أو الملف مفتوح في برنامج آخر.',
      needles: [r'Access is denied', r'Permission denied', r'errno = 13\b', r'errno = 5\b', r'EACCES', r'PathAccessException', r'being used by another process', r'errno = 32\b'],
      steps: [
        GuideStep('أغلق أي برنامج آخر فتح الملف (Excel، عارض PDF…).'),
        GuideStep('إن كان الملف «للقراءة فقط»: زر الفأرة الأيمن عليه ← خصائص ← أزل علامة «للقراءة فقط».'),
        GuideStep('أضف مجلد البرنامج إلى استثناءات برنامج الحماية، وإن كان «الوصول المتحكَّم به للمجلدات» مفعّلاً في Windows Security فاسمح للبرنامج.'),
      ],
    ),
    ErrorFix(
      key: 'disk_missing',
      title: 'ملف أو مجلد غير موجود',
      category: 'disk',
      severity: FixSeverity.warning,
      what: 'البرنامج بحث عن ملف أو مجلد ولم يجده.',
      cause: 'الملف نُقل أو حُذف (صورة شعار، نسخة احتياطية، فلاشة مفصولة).',
      needles: [r'PathNotFoundException', r'No such file or directory', r'errno = 2\b', r'cannot find the (file|path)', r'errno = 3\b'],
      steps: [
        GuideStep('إن كان ملفاً اخترته سابقاً (شعار، مجلد نسخ): اختره من جديد من الإعدادات.'),
        GuideStep('إن كان على فلاشة أو قرص خارجي: أعد توصيله.'),
      ],
    ),
    ErrorFix(
      key: 'disk_io',
      actions: ['integrity'],
      title: 'خطأ في قراءة القرص',
      category: 'disk',
      severity: FixSeverity.critical,
      what: 'فشلت قراءة أو كتابة على القرص نفسه.',
      cause: 'قرص يتعطل، أو فلاشة/قرص خارجي فُصل أثناء العمل.',
      needles: [r'disk I/O error', r'SQLITE_IOERR', r'FileSystemException', r'errno = 23\b', r'errno = 1117\b'],
      who: FixWho.both,
      steps: [
        GuideStep('خذ نسخة احتياطية الآن (تيليجرام أو Dropbox) قبل أي شيء.', warn: true),
        GuideStep('افحص القرص: زر أيمن على القرص ← خصائص ← أدوات ← «تدقيق».'),
        GuideStep('إن تكرّر فالقرص قد يتعطل قريباً — انقل البرنامج وبياناته إلى قرص سليم.'),
        _report,
      ],
    ),

    // ───────────── النسخ الاحتياطي ─────────────
    ErrorFix(
      key: 'tg_token',
      title: 'رمز بوت تيليجرام غير صحيح',
      category: 'backup',
      severity: FixSeverity.error,
      what: 'تيليجرام رفض الرفع: رمز البوت غير صالح.',
      cause: 'الرمز كُتب خطأ، أو أُلغي من BotFather، أو أُنشئ رمز جديد.',
      needles: [r'(telegram|bot).{0,80}(401|Unauthorized)', r'(401|Unauthorized).{0,80}(telegram|bot)', r'Not Found: method'],
      steps: [
        GuideStep('افتح BotFather في تيليجرام ← /mybots ← اختر البوت ← «API Token» وانسخ الرمز.',
            links: [GuideLink('فتح BotFather', 'https://t.me/BotFather')]),
        GuideStep('الصقه في «إعدادات تيليجرام» واضغط «تحقق» ثم احفظ.'),
      ],
    ),
    ErrorFix(
      key: 'tg_chat',
      title: 'قناة تيليجرام غير صحيحة أو البوت ليس مشرفاً',
      category: 'backup',
      severity: FixSeverity.error,
      what: 'تيليجرام رفض الإرسال إلى القناة.',
      cause: 'معرّف القناة خطأ، أو البوت ليس مشرفاً فيها، أو ليست له صلاحية النشر.',
      needles: [r'chat not found', r'bot is not a member', r'not enough rights', r'CHAT_ADMIN_REQUIRED', r'bot was kicked', r'have no rights to send'],
      steps: [
        GuideStep('افتح القناة ← المشرفون ← أضف البوت مشرفاً مع صلاحية «نشر الرسائل».'),
        GuideStep('في «إعدادات تيليجرام» اضغط «اكتشاف القناة» بعد إرسال رسالة في القناة، ثم «رسالة تجربة».'),
      ],
    ),
    ErrorFix(
      key: 'tg_limit',
      title: 'تيليجرام طلب الانتظار',
      category: 'backup',
      severity: FixSeverity.warning,
      what: 'تيليجرام أوقف الإرسال مؤقتاً لكثرة الطلبات.',
      cause: 'رفع متكرر في وقت قصير.',
      needles: [r'Too Many Requests', r'\b429\b', r'retry after', r'FLOOD_WAIT'],
      harmless: true,
      steps: [
        GuideStep('لا تفعل شيئاً: البرنامج يعيد المحاولة لاحقاً تلقائياً.'),
        GuideStep('إن كنت ترفع يدوياً: انتظر بضع دقائق بين كل رفع وآخر.'),
      ],
    ),
    ErrorFix(
      key: 'tg_size',
      title: 'ملف النسخة أكبر مما يقبله تيليجرام',
      category: 'backup',
      severity: FixSeverity.error,
      what: 'رُفض رفع النسخة لأن حجمها كبير.',
      cause: 'حد البوت العادي 50 ميغابايت للملف.',
      needles: [r'Request Entity Too Large', r'\b413\b', r'file is too big'],
      steps: [
        GuideStep('فعّل «MTProto» من «عند حظر تيليجرام»: يرفع ملفات حتى 2 غيغابايت.'),
        GuideStep('أو استعمل Dropbox للنسخ الكبيرة.'),
      ],
    ),
    ErrorFix(
      key: 'tg_blocked',
      title: 'تيليجرام محجوب على هذا الاتصال',
      category: 'backup',
      severity: FixSeverity.error,
      what: 'لم يصل البرنامج إلى خوادم تيليجرام.',
      cause: 'مزود الإنترنت يحجب تيليجرام.',
      needles: [r'api\.telegram\.org.{0,120}(SocketException|Connection|timed out|HandshakeException|Failed host lookup)', r'تيليجرام محجوب', r'حظر تيليجرام'],
      steps: [
        GuideStep('من «إعدادات تيليجرام» ← «عند حظر تيليجرام» فعّل Tor أو MTProto أو بروكسي.'),
        GuideStep('اضغط «اختبار الاتصال» — يمر عبر الطريقة المفعّلة.'),
      ],
    ),
    ErrorFix(
      key: 'tor',
      title: 'مشكلة في Tor',
      category: 'backup',
      severity: FixSeverity.warning,
      what: 'تعذّر تنزيل Tor أو تشغيله.',
      cause: 'برنامج الحماية حذف tor.exe، أو موقع التنزيل محجوب، أو المنفذ مشغول.',
      needles: [r'tor\.exe', r'TorEngine', r'torproject', r'\bTor\b'],
      steps: [
        GuideStep('من «عند حظر تيليجرام» اضغط «تثبيت Tor» مرة أخرى.'),
        GuideStep('إن اختفى tor.exe بعد التنزيل: استثنِ مجلد البرنامج من برنامج الحماية ثم أعد التثبيت.'),
        GuideStep('بديل: فعّل MTProto أو بروكسي بدل Tor.'),
      ],
    ),
    ErrorFix(
      key: 'tdlib',
      title: 'مشكلة في MTProto (مكتبة تيليجرام)',
      category: 'backup',
      severity: FixSeverity.warning,
      what: 'تعذّر تشغيل طريقة MTProto.',
      cause: 'ملف الإعداد tg_api.json غير موجود، أو المكتبة لم تُنزَّل.',
      needles: [r'TdError', r'tg_api\.json', r'MTProto'],
      steps: [
        GuideStep('افتح «عند حظر تيليجرام» واتبع خطوات إعداد MTProto كاملة.'),
        GuideStep('إن لم تكن تحتاجه: أطفئه وارفع بالطريقة العادية أو Tor.'),
      ],
    ),
    ErrorFix(
      key: 'dropbox',
      title: 'مشكلة في Dropbox',
      category: 'backup',
      severity: FixSeverity.error,
      what: 'تعذّر الرفع إلى Dropbox أو الربط به.',
      cause: 'انظر «حل مشاكل Dropbox» في شاشة Dropbox — تتعرّف على نوع المشكلة من الرسالة.',
      needles: [r'dropbox'],
      steps: [
        GuideStep('افتح الإعدادات ← «النسخ الاحتياطي السحابي (Dropbox)» وانزل إلى «حل مشاكل Dropbox».'),
        GuideStep('الصق رسالة الخطأ هناك أو اختر نوع المشكلة واتبع خطواتها.'),
      ],
    ),

    // ───────────── المزامنة ─────────────
    ErrorFix(
      key: 'fb_rules',
      title: 'Firebase يرفض البيانات (القواعد)',
      category: 'sync',
      severity: FixSeverity.error,
      what: 'خادم Firebase رفض القراءة أو الكتابة.',
      cause: 'قواعد Firestore في مشروعك لا تسمح، أو المصادقة المجهولة غير مفعّلة.',
      needles: [r'permission-denied', r'PERMISSION_DENIED', r'Missing or insufficient permissions', r'Firestore Rules'],
      steps: [
        GuideStep('افتح «إعداد Firebase الخاص» من الإعدادات واتبع خطوة «القواعد»: انسخ القواعد كما هي والصقها في Firebase Console ← Firestore ← Rules ← Publish.',
            links: [GuideLink('Firebase Console', 'https://console.firebase.google.com')]),
        GuideStep('تأكد من تفعيل Authentication ← Sign-in method ← Anonymous.'),
        GuideStep('أغلق البرنامج وافتحه، ثم «مزامنة الآن».'),
      ],
    ),
    ErrorFix(
      key: 'fb_auth',
      title: 'تسجيل الدخول إلى Firebase فشل',
      category: 'sync',
      severity: FixSeverity.error,
      what: 'البرنامج لم يستطع الدخول إلى مشروع Firebase.',
      cause: 'المصادقة المجهولة غير مفعّلة، أو مفاتيح المشروع خطأ.',
      needles: [r'unauthenticated', r'admin-restricted-operation', r'operation-not-allowed', r'تسجيل الدخول المجهول', r'invalid-api-key', r'API key not valid'],
      steps: [
        GuideStep('Firebase Console ← Authentication ← Sign-in method ← فعّل Anonymous.',
            links: [GuideLink('Firebase Console', 'https://console.firebase.google.com')]),
        GuideStep('من «إعداد Firebase الخاص» الصق المفاتيح من جديد واضغط «اختبار».'),
      ],
    ),
    ErrorFix(
      key: 'fb_quota',
      title: 'تجاوزت حصة Firebase المجانية',
      category: 'sync',
      severity: FixSeverity.warning,
      what: 'Firebase أوقف القراءة أو الكتابة مؤقتاً.',
      cause: 'تجاوز الحد اليومي المجاني للعمليات.',
      needles: [r'resource-exhausted', r'RESOURCE_EXHAUSTED', r'quota'],
      steps: [
        GuideStep('انتظر حتى اليوم التالي (الحصة تتجدد يومياً) — المزامنة تكمل تلقائياً.'),
        GuideStep('إن تكرّر يومياً: فعّل خطة Blaze في Firebase (تدفع حسب الاستهلاك فقط).'),
      ],
    ),
    ErrorFix(
      key: 'sync_state',
      title: 'المزامنة غير جاهزة',
      category: 'sync',
      severity: FixSeverity.warning,
      what: 'عملية مزامنة لم تبدأ لأن المزامنة غير مفعّلة أو لم تكتمل تهيئتها.',
      cause: 'المزامنة مطفأة، أو لا إنترنت لحظة التشغيل، أو استعادة نسخة ما زالت تقارن البيانات.',
      needles: [r'المزامنة غير (مفعّلة|مُهيّأة)', r'مجموعة المزامنة غير معرفة', r'فشلت تهيئة المزامنة', r'وضع الاستعادة'],
      harmless: true,
      steps: [
        GuideStep('تأكد من الإنترنت، ثم من «إعدادات المزامنة» اضغط «مزامنة الآن».'),
        GuideStep('بعد استعادة نسخة: انتظر دقائق حتى تكتمل المقارنة — البيع والتسديد الجديد مسموحان.'),
      ],
    ),

    // ───────────── الشبكة المحلية ─────────────
    ErrorFix(
      key: 'lan',
      title: 'الشبكة المحلية لا تعمل',
      category: 'lan',
      severity: FixSeverity.error,
      what: 'الطرفية لم تتصل بحاسبة السيرفر، أو السيرفر لم يبدأ.',
      cause: 'حاسبة السيرفر مطفأة أو برنامجها مغلق، أو جدار حماية ويندوز يمنع المنفذ 47800، أو المنفذ مشغول ببرنامج آخر.',
      needles: [r'47800', r'errno = 10048', r'Address already in use', r'LanClient', r'LanServer', r'الشبكة المحلية', r'\blan\b'],
      steps: [
        GuideStep('تأكد أن حاسبة السيرفر مشغّلة والبرنامج مفتوح عليها.'),
        GuideStep('على حاسبة السيرفر: اسمح للبرنامج في «جدار حماية ويندوز» على الشبكات الخاصة.'),
        GuideStep('من «الشبكة المحلية» في الإعدادات اضغط «اختبار الاتصال» على الطرفية.'),
        GuideStep('إن ظهر «المنفذ مشغول»: أغلق نسخة البرنامج الثانية على حاسبة السيرفر أو أعد تشغيلها.'),
      ],
    ),

    // ───────────── الإنترنت ─────────────
    ErrorFix(
      key: 'net_tls',
      title: 'فشل الاتصال الآمن (شهادة الموقع)',
      category: 'net',
      severity: FixSeverity.error,
      what: 'الاتصال بالخادم بدأ لكن التحقق من شهادته الأمنية فشل.',
      cause: 'تاريخ ووقت الحاسبة خطأ (السبب الأشهر)، أو برنامج حماية يفحص الاتصالات الآمنة، أو شبكة تعترض الاتصال.',
      needles: [r'HandshakeException', r'CERTIFICATE_VERIFY_FAILED', r'certificate', r'TlsException'],
      steps: [
        GuideStep('صحّح تاريخ ووقت الحاسبة: إعدادات ويندوز ← الوقت واللغة ← «ضبط الوقت تلقائياً».', warn: true),
        GuideStep('إن بقي: أطفئ «فحص HTTPS/SSL» في برنامج الحماية مؤقتاً وجرّب.'),
      ],
    ),
    ErrorFix(
      key: 'net_timeout',
      title: 'انتهت مهلة الاتصال',
      category: 'net',
      severity: FixSeverity.warning,
      what: 'الخادم لم يردّ في الوقت المحدد.',
      cause: 'إنترنت ضعيف أو متقطع، أو الخادم بطيء أو محجوب.',
      needles: [r'TimeoutException', r'timed out', r'انتهت المهلة', r'Future not completed'],
      harmless: true,
      steps: [
        GuideStep('تأكد من الإنترنت وأعد المحاولة. أغلب العمليات تعيد المحاولة تلقائياً.'),
        GuideStep('إن كانت لتيليجرام: جرّب «عند حظر تيليجرام».'),
      ],
    ),
    ErrorFix(
      key: 'net_offline',
      title: 'لا يوجد اتصال بالإنترنت',
      category: 'net',
      severity: FixSeverity.warning,
      what: 'البرنامج لم يصل إلى الخادم.',
      cause: 'الإنترنت مقطوع، أو اسم الخادم لم يُحلّ (DNS)، أو الاتصال قُطع أثناء العملية.',
      needles: [
        r'SocketException', r'Failed host lookup', r'Network is unreachable', r'errno = 1100\d', r'errno = 7\b',
        r'Connection (refused|reset|closed|abort)', r'errno = 1006\d', r'errno = 1005\d', r'لا يوجد اتصال', r'ClientException'
      ],
      harmless: true,
      steps: [
        GuideStep('تأكد من الإنترنت (افتح أي موقع).'),
        GuideStep('ما لم يُرفع يُرفع تلقائياً عند عودة الاتصال — لا حاجة لإعادة الإدخال.'),
        GuideStep('إن كان الإنترنت يعمل والخطأ يتكرر: أعد تشغيل الراوتر، أو غيّر DNS إلى 1.1.1.1.'),
      ],
    ),

    // ───────────── فشل الرفع أو النسخ (بعد أسباب الشبكة: السبب الأدق يُعرض أولاً) ─────────────
    ErrorFix(
      key: 'backup_failed',
      title: 'لم يكتمل رفع البيانات أو حفظ النسخة',
      category: 'backup',
      severity: FixSeverity.critical,
      what: 'النسخة الاحتياطية لم تصل إلى وجهة أو أكثر (تيليجرام، Dropbox، Google Drive) أو لم تُحفظ على الحاسبة.',
      cause: 'السبب مكتوب تحت اسم كل وجهة في «التفاصيل التقنية»: اتصال، رمز بوت، صلاحية مجلد، مساحة…',
      needles: [r'لم يكتمل رفع البيانات', r'تعذّر حفظ النسخة', r'فشل الرفع', r'فشل رفع', r'Backup error', r'النسخة المحفوظة ناقصة'],
      steps: [
        GuideStep('اقرأ سطر كل وجهة في «التفاصيل التقنية» — ما نجح منها نجح، والفاشل وحده يحتاج إصلاحاً.', warn: true),
        GuideStep('تأكد من الإنترنت ثم اضغط «رفع البيانات» مرة أخرى من الشاشة الرئيسية.'),
        GuideStep('تيليجرام: «إعدادات تيليجرام» ← «اختبار الاتصال». Dropbox: شاشة Dropbox ← «حل مشاكل Dropbox».'),
        GuideStep('إن كانت نسخة الخروج: اختر مجلداً آخر للنسخة، أو أفرغ مساحة في القرص.'),
      ],
    ),

    // ───────────── الطباعة ─────────────
    ErrorFix(
      key: 'print',
      title: 'تعذّرت الطباعة',
      category: 'print',
      severity: FixSeverity.error,
      what: 'الفاتورة أو السند لم يُطبع.',
      cause: 'الطابعة مطفأة أو مفصولة، أو ليست الطابعة الافتراضية، أو حجم الورق في الإعدادات لا يناسبها.',
      needles: [r'Printer', r'PrinterException', r'printing', r'Bluetooth', r'طابعة', r'الطباعة', r'print job', r'Spooler'],
      steps: [
        GuideStep('تأكد أن الطابعة مشغّلة ومتصلة، وأن فيها ورقاً.'),
        GuideStep('من «إعدادات الطباعة والمخزون» اختر الطابعة وحجم الورق الصحيح (A4 أو 80 أو 58 ملم) واطبع صفحة تجربة.'),
        GuideStep('إن علقت مهام: إعدادات ويندوز ← الطابعات ← افتح قائمة الانتظار واحذف المهام العالقة.'),
      ],
    ),

    // ───────────── حماية الحسابات (رفض صحيح) ─────────────
    ErrorFix(
      key: 'money_negative',
      title: 'رُفض تعديل يجعل رصيد العميل سالباً',
      category: 'money',
      severity: FixSeverity.info,
      what: 'البرنامج منع حفظاً كان سيجعل الزبون دائناً للمحل بمبلغ لم يدفعه.',
      cause: 'تسديد أكبر من الدين، أو تعديل فاتورة/معاملة يُنقص الدين تحت الصفر.',
      needles: [r'سالباً', r'سيصبح.*سالب', r'لا يمكن إتمام هذا التعديل'],
      harmless: true,
      steps: [
        GuideStep('هذه حماية تعمل كما يجب — لا شيء تالف.'),
        GuideStep('راجع المبلغ: إن كان الزبون دفع أكثر فعلاً، سجّل الفرق كمعاملة منفصلة بعد التأكد.'),
      ],
    ),
    ErrorFix(
      key: 'money_half',
      title: 'مبلغ أقل من نصف دينار',
      category: 'money',
      severity: FixSeverity.info,
      what: 'رُفض مبلغ صار صفراً بعد التقريب لدينار صحيح.',
      cause: 'البرنامج يحفظ الدينار الصحيح فقط.',
      needles: [r'أقل من نصف دينار'],
      harmless: true,
      steps: [GuideStep('اكتب مبلغاً بالدينار الصحيح (1 فأكثر).')],
    ),
    ErrorFix(
      key: 'money_period',
      title: 'الفترة مثبّتة',
      category: 'money',
      severity: FixSeverity.info,
      what: 'رُفض إضافة أو تعديل مستند بتاريخ داخل فترة مُقفلة.',
      cause: 'المدير ثبّت الإدخالات حتى تاريخ معيّن حتى لا تتغير الحسابات المغلقة.',
      needles: [r'الفترة مثبّتة', r'تثبيت الإدخالات'],
      harmless: true,
      steps: [
        GuideStep('استعمل تاريخاً بعد تاريخ التثبيت.'),
        GuideStep('إن كان التعديل ضرورياً فعلاً: المدير يفتح «تثبيت الإدخالات» ويضغط «إلغاء تثبيت الإدخالات»، ثم يثبّتها بعد التعديل.'),
      ],
    ),
    ErrorFix(
      key: 'money_other_device',
      title: 'المعاملة من جهاز آخر',
      category: 'money',
      severity: FixSeverity.info,
      what: 'لا تُعدَّل معاملة إلا من الجهاز الذي أنشأها.',
      cause: 'حتى لا يعدّل جهازان المعاملة نفسها فتتعارض الأرقام.',
      needles: [r'أُنشئت على جهاز آخر'],
      harmless: true,
      steps: [GuideStep('عدّلها من الجهاز الذي أنشأها، أو سجّل معاملة تصحيح جديدة من هنا.')],
    ),
    ErrorFix(
      key: 'money_restored',
      title: 'سجل من نسخة مستعادة لم يكتمل',
      category: 'money',
      severity: FixSeverity.info,
      what: 'منع تعديل سجل قيمته قد تكون قديمة بعد استعادة نسخة احتياطية.',
      cause: 'الجهاز لم يلحق بعد بآخر بيانات الأجهزة الأخرى.',
      needles: [r'نسخة احتياطية مستعادة', r'RestoredRecordLocked'],
      harmless: true,
      steps: [GuideStep('اتصل بالإنترنت وانتظر دقائق حتى تكتمل الاستعادة ثم عدّل.')],
    ),
    ErrorFix(
      key: 'money_invoice_link',
      title: 'المعاملة تابعة لفاتورة',
      category: 'money',
      severity: FixSeverity.info,
      what: 'معاملة الفاتورة لا تُعدَّل من كشف العميل.',
      cause: 'مبلغها يتبع الفاتورة نفسها.',
      needles: [r'مرتبطة بفاتورة'],
      harmless: true,
      steps: [GuideStep('افتح الفاتورة نفسها وعدّلها؛ المعاملة تتعدّل معها.')],
    ),
    ErrorFix(
      key: 'perm',
      title: 'لا صلاحية لهذه العملية',
      category: 'money',
      severity: FixSeverity.info,
      what: 'المستخدم الحالي لا يملك صلاحية هذه العملية.',
      cause: 'الصلاحيات تُحدَّد لكل مستخدم.',
      needles: [r'ليس لديك صلاحية', r'لا تملك صلاحية'],
      harmless: true,
      steps: [GuideStep('اطلب من المدير منحك الصلاحية من «إدارة المستخدمين»، أو ادخل بحساب المدير.')],
    ),

    // ───────────── الشاشة ─────────────
    ErrorFix(
      key: 'ui_freeze',
      title: 'البرنامج تجمّد ولم يستجب',
      category: 'ui',
      severity: FixSeverity.warning,
      what: 'البرنامج توقف عن الاستجابة للضغط وعن الرسم بضع ثوانٍ ثم عاد.',
      cause: 'عملية ثقيلة على الخيط الرئيسي (تقرير كبير، نسخ أو استعادة، فحص)، أو قرص بطيء/ممتلئ، أو برنامج حماية يفحص الملفات.',
      needles: [r'تجمّد البرنامج'],
      who: FixWho.both,
      steps: [
        GuideStep('إن تجمّد أثناء ضغط زر: لا تضغطه مرة ثانية — انتظر حتى يستجيب، فقد تكون العملية تعمل.'),
        GuideStep('انظر «الشاشات الأخيرة» في التفاصيل التقنية لتعرف أين حدث.'),
        GuideStep('إن تكرّر في الشاشة نفسها: استثنِ مجلد البرنامج من برنامج الحماية، وتأكد أن في القرص مساحة.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'ui_overflow',
      title: 'محتوى لا يتسع في الشاشة',
      category: 'ui',
      severity: FixSeverity.info,
      what: 'جزء من الشاشة أكبر من المساحة المتاحة فقُصّ.',
      cause: 'نافذة صغيرة، أو تكبير ويندوز (125% أو 150%)، أو نص طويل جداً.',
      needles: [r'overflowed by', r'RenderFlex overflowed', r'A RenderFlex overflowed'],
      harmless: true,
      who: FixWho.both,
      steps: [
        GuideStep('كبّر نافذة البرنامج أو اجعلها ملء الشاشة.'),
        GuideStep('إن بقي: إعدادات ويندوز ← العرض ← «المقياس» إلى 100%.'),
        GuideStep('أرسل صورة للشاشة للمطوّر مع «نسخ التقرير» ليصلحها.'),
      ],
    ),
    ErrorFix(
      key: 'ui_disposed',
      title: 'شاشة أُغلقت قبل أن تكمل التحميل',
      category: 'ui',
      severity: FixSeverity.info,
      what: 'عملية انتهت بعد إغلاق الشاشة التي طلبتها، فلم تُعرض نتيجتها.',
      cause: 'إغلاق شاشة أو الرجوع منها بسرعة أثناء التحميل.',
      needles: [r'setState\(\) called after dispose', r'deactivated widget', r'unmounted', r'أُغلقت الشاشة', r'Looking up a deactivated'],
      harmless: true,
      who: FixWho.developer,
      steps: [GuideStep('لا شيء تفعله: لا يضر البيانات. إن تكرّر كثيراً في شاشة بعينها أرسل التقرير للمطوّر.')],
    ),
    ErrorFix(
      key: 'ui_image',
      title: 'صورة لا تُقرأ',
      category: 'ui',
      severity: FixSeverity.warning,
      what: 'البرنامج لم يستطع فتح صورة (شعار أو صورة مادة).',
      cause: 'الملف تالف أو بصيغة غير مدعومة (HEIC، WebP قديم…).',
      needles: [r'Invalid image data', r'ImageCodecException', r'Codec failed', r'instantiateImageCodec', r'image decode'],
      steps: [
        GuideStep('افتح الصورة واحفظها بصيغة PNG أو JPG، ثم اخترها من جديد في البرنامج.'),
      ],
    ),

    // ───────────── خلل في البرنامج ─────────────
    ErrorFix(
      key: 'code_null',
      actions: ['deep_check'],
      title: 'خلل في البرنامج: قيمة ناقصة',
      category: 'code',
      severity: FixSeverity.error,
      what: 'البرنامج توقع بيانات ولم يجدها.',
      cause: 'خلل في الكود نفسه (لا في بياناتك غالباً): حالة لم يحسب لها المطوّر حساباً.',
      needles: [r'Null check operator', r'Unexpected null value', r'NoSuchMethodError', r'LateInitializationError', r"Null is not a subtype"],
      who: FixWho.developer,
      steps: [
        GuideStep('أغلق الشاشة وافتحها من جديد وأعد العملية.'),
        GuideStep('تأكد أن ما حفظته موجود (افتح الفاتورة أو كشف العميل).'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'code_range',
      actions: ['deep_check'],
      title: 'خلل في البرنامج: عنصر غير موجود في القائمة',
      category: 'code',
      severity: FixSeverity.error,
      what: 'البرنامج طلب عنصراً خارج حدود قائمة.',
      cause: 'خلل في الكود، غالباً قائمة تغيّرت أثناء عرضها (حذف سطر، تحديث من المزامنة).',
      needles: [r'RangeError', r'Index out of range', r'IndexError', r'Bad state: No element', r'Too many elements'],
      who: FixWho.developer,
      steps: [
        GuideStep('أعد فتح الشاشة وأعد العملية.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'code_type',
      actions: ['deep_check'],
      title: 'خلل في البرنامج: نوع بيانات غير متوقع',
      category: 'code',
      severity: FixSeverity.error,
      what: 'البرنامج قرأ قيمة بنوع غير الذي توقعه (نص بدل رقم مثلاً).',
      cause: 'خلل في الكود، أو بيانات قديمة/مستوردة بصيغة مختلفة.',
      needles: [r"is not a subtype of type", r'_CastError', r'TypeError', r'type cast'],
      who: FixWho.developer,
      steps: [
        GuideStep('إن حدث بعد استيراد ملف: راجع أعمدة الملف (أرقام في أعمدة الأرقام).'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'code_format',
      title: 'قيمة مكتوبة بصيغة خاطئة',
      category: 'code',
      severity: FixSeverity.warning,
      what: 'البرنامج لم يفهم رقماً أو تاريخاً أو ملفاً.',
      cause: 'حرف داخل رقم، أو تاريخ بصيغة غير مفهومة، أو ملف استيراد/إعداد تالف.',
      needles: [r'FormatException', r'Invalid date', r'Invalid number', r'Unexpected character', r'Invalid radix'],
      who: FixWho.both,
      steps: [
        GuideStep('تأكد من القيمة المكتوبة (أرقام فقط في حقول المبالغ والكميات).'),
        GuideStep('إن كان من ملف استيراد: افتح الملف وصحّح الخلية.'),
        _report,
      ],
    ),
    ErrorFix(
      key: 'code_plugin',
      title: 'ميزة غير متاحة على هذا الجهاز',
      category: 'code',
      severity: FixSeverity.warning,
      what: 'البرنامج طلب ميزة من النظام (كاميرا، طابعة بلوتوث، ملفات…) ولم تتوفر.',
      cause: 'الميزة غير مدعومة على هذا النظام، أو تحتاج إذناً، أو تثبيت البرنامج ناقص.',
      needles: [r'MissingPluginException', r'PlatformException'],
      who: FixWho.both,
      steps: [
        GuideStep('أغلق البرنامج وافتحه من جديد.'),
        GuideStep('إن كانت الكاميرا أو الملفات: اسمح للبرنامج بالإذن من إعدادات الجهاز.'),
        GuideStep('إن بقي: أعد تثبيت البرنامج (بياناتك لا تُحذف بإعادة التثبيت).'),
        _report,
      ],
    ),
  ];

  /// بلاغ كتبه المستخدم (Ctrl+Shift+E أو «أبلغ عن مشكلة»).
  static const userReport = ErrorFix(
    key: 'user_report',
    title: 'بلاغ من المستخدم',
    category: 'other',
    severity: FixSeverity.warning,
    what: 'المستخدم أبلغ عن مشكلة لم يرافقها خطأ يلتقطه البرنامج (زر لم يعمل، رقم غير متوقع…).',
    cause: 'غير معروف — الوصف وصورة الشاشة واسمها في الأسفل.',
    who: FixWho.both,
    actions: ['integrity', 'chain_check', 'deep_check'],
    steps: [
      GuideStep('انظر هل ظهر خطأ آخر في الوقت نفسه في قائمة «تشخيص الأخطاء» — غالباً هو السبب.'),
      GuideStep('أعد ما فعلته مرة واحدة. إن تكرّر فسجّل بلاغاً جديداً فور حدوثه (Ctrl+Shift+E).'),
      _report,
    ],
  );

  /// حل عام لاستثناء تقني لم يطابق شيئاً.
  static const genericCode = ErrorFix(
    key: 'generic_code',
      actions: ['deep_check'],
    title: 'خطأ تقني في البرنامج',
    category: 'code',
    severity: FixSeverity.error,
    what: 'حدث خطأ لم يتوقعه البرنامج.',
    cause: 'غير معروف بعد — التفاصيل التقنية أسفل الصفحة تدل المطوّر على مكانه.',
    who: FixWho.developer,
    steps: [
      GuideStep('أعد العملية مرة واحدة. إن نجحت فقد كان عارضاً.'),
      GuideStep('تأكد أن ما حفظته موجود فعلاً قبل إعادة إدخاله.'),
      _report,
    ],
  );

  /// حل عام لرسالة لم تطابق شيئاً.
  static const genericOther = ErrorFix(
    key: 'generic_other',
    title: 'مشكلة لم يتعرّف عليها الدليل',
    category: 'other',
    severity: FixSeverity.warning,
    what: 'البرنامج سجّل مشكلة لا يعرف الدليل نوعها بعد.',
    cause: 'انظر نص الرسالة — غالباً تشرح نفسها.',
    who: FixWho.both,
    steps: [
      GuideStep('اقرأ الرسالة في «التفاصيل التقنية» وأعد العملية.'),
      _report,
    ],
  );

  static final Map<String, List<RegExp>> _compiled = {};

  static List<RegExp> _res(ErrorFix f) =>
      _compiled.putIfAbsent(f.key, () => [for (final n in f.needles) RegExp(n, caseSensitive: false)]);

  static final _technical = RegExp(r'\b\w*(Exception|Error)\b|#\d+\s+\S+\s+\(|package:');

  /// الحل المناسب لنص الخطأ. [source] مصدر الخطأ (الخروج المفاجئ يُطابَق في قسمه فقط).
  static ErrorFix match(String text, {String? source}) {
    if (source == 'report') return userReport;
    final native = source == 'native';
    for (final f in all) {
      if (native != (f.category == 'crash')) continue;
      for (final re in _res(f)) {
        if (re.hasMatch(text)) return f;
      }
    }
    if (native) return all.firstWhere((f) => f.key == 'crash_generic');
    return _technical.hasMatch(text) ? genericCode : genericOther;
  }

  /// للفحص: كل التعابير تُبنى بلا خطأ.
  static void validate() {
    for (final f in all) {
      _res(f);
    }
  }
}
