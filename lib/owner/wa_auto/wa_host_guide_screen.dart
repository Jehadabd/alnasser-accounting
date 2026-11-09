// lib/owner/wa_auto/wa_host_guide_screen.dart
//
// 📘 الشرح الكامل لتشغيل خادم واتساب — لمن لا يعرف شيئاً في التقنية.
// أربعة أدلة: هذه الحاسبة، Oracle Cloud، Render، Docker (Koyeb).
// أسماء الأزرار في المواقع الخارجية قد تتغيّر قليلاً مع الوقت؛ الفكرة تبقى نفسها.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/settings_kit.dart';

class GuideStep {
  const GuideStep(this.title, this.lines, {this.link, this.linkLabel, this.copy, this.tip});
  final String title;
  final List<String> lines;
  final String? link, linkLabel;

  /// نص يُنسخ بزر (رابط، مسار…)
  final String? copy;

  /// تنبيه مهم يظهر بلون مختلف
  final String? tip;
}

class HostGuide {
  const HostGuide(this.title, this.icon, this.intro, this.needs, this.time, this.steps, this.problems);
  final String title, intro, time;
  final IconData icon;
  final List<String> needs;
  final List<GuideStep> steps;
  final List<(String, String)> problems;
}

// ─────────────── الخطوات المشتركة ───────────────

const _getPackage = GuideStep('نزّل ملفات الخادم وفك ضغطها', [
  'في البرنامج، في شاشة «خادم واتساب»، اضغط زر «تنزيل ملفات الخادم (zip)». يُفتح مجلد التنزيلات وفيه ملف اسمه alnaser-wa-server.zip.',
  'انقر على الملف بزر الفأرة الأيمن ← «استخراج الكل» (Extract All).',
  'في المربع الذي يظهر امسح المسار المكتوب واكتب:  C:\\alnaser-wa  ثم اضغط «استخراج».',
  'افتح المجلد الذي ظهر، وادخل المجلد alnaser-wa-server حتى ترى ملفات مثل server.js وpackage.json وstart-windows.bat. هذا هو «مجلد الخادم» في بقية الشرح.',
], tip: 'إن وجدت مجلداً داخل مجلد بالاسم نفسه فهذا طبيعي — ادخل حتى ترى server.js.', copy: r'C:\alnaser-wa');

const _copyKey = GuideStep('انسخ «مفتاح الخادم»', [
  'في شاشة «خادم واتساب» في البرنامج، في بطاقة «2. الاتصال بالخادم»، اضغط زر النسخ بجانب «مفتاح الخادم».',
  'المفتاح كلمة سر طويلة يولّدها البرنامج. من يملكها يستطيع الإرسال من رقمك — لا ترسلها لأحد ولا تنشرها.',
]);

const _linkPhone = GuideStep('اربط رقم واتساب المحل', [
  'في البرنامج: اكتب رابط الخادم في «رابط الخادم» واضغط «حفظ وفحص الاتصال». يجب أن يظهر: «الخادم يعمل — بقي ربط رقم واتساب».',
  'في بطاقة «3. رقم واتساب المحل» اكتب رقم واتساب المحل (مثل 07701234567) واضغط «اطلب رمز الربط». يظهر رمز من 8 خانات.',
  'في هاتف المحل افتح واتساب:',
  '• أندرويد: النقاط الثلاث أعلى الشاشة ← «الأجهزة المرتبطة» ← «ربط جهاز».',
  '• آيفون: «الإعدادات» أسفل الشاشة ← «الأجهزة المرتبطة» ← «ربط جهاز».',
  'تفتح الكاميرا لمسح رمز — لا تمسح شيئاً، بل اضغط أسفلها «الربط برقم الهاتف بدلاً من ذلك»، واكتب الرمز الظاهر في البرنامج.',
  'خلال ثوانٍ يظهر في البرنامج «تم الربط ✓»، ويظهر في الهاتف جهاز جديد في «الأجهزة المرتبطة».',
], tip: 'للرمز مهلة دقيقتين تقريباً. إن انتهت اضغط «اطلب رمز الربط» مرة أخرى.');

const _tryIt = GuideStep('جرّب قبل الاعتماد عليه', [
  'افتح شاشة «تذكير الديون عبر واتساب»، وفي «طريقة الإرسال» اختر «الخادم».',
  'في «رسالة تجربة» اكتب رقماً ثانياً لك (لا رقم زبون) واضغط إرسال. يجب أن تصل الرسالة خلال ثوانٍ.',
  'بعد نجاح التجربة ابدأ بعدد قليل («تجربة على 5 زبائن») قبل الإرسال للجميع.',
]);

// ─────────────── 1) هذه الحاسبة ───────────────

const _local = HostGuide(
  'على هذه الحاسبة',
  Icons.computer_rounded,
  'الأسهل والأسرع للتجربة: الخادم يعمل في نافذة سوداء على حاسبة المحل نفسها. يرسل ما دامت الحاسبة شغّالة والنافذة مفتوحة. لا حسابات ولا بطاقات.',
  ['هذه الحاسبة (ويندوز 10 أو 11) متصلة بالإنترنت', 'هاتف المحل وفيه واتساب'],
  '15 إلى 20 دقيقة أول مرة',
  [
    GuideStep('ثبّت برنامج Node.js', [
      'اضغط الزر أدناه. في الصفحة اختر نسخة «LTS» ثم «Windows Installer (.msi)» وانتظر التنزيل.',
      'افتح الملف الذي نزل (في التنزيلات). اضغط Next ← ضع علامة على «I accept» ← Next ← Next ← Next.',
      'إن ظهرت صفحة فيها «Automatically install the necessary tools» اتركها بلا علامة ← Next ← Install.',
      'إن سألك ويندوز «هل تسمح لهذا التطبيق بإجراء تغييرات» اضغط «نعم». ثم Finish.',
    ], link: 'https://nodejs.org/en/download', linkLabel: 'فتح صفحة تنزيل Node.js'),
    GuideStep('ثبّت برنامج Git', [
      'اضغط الزر أدناه، يبدأ التنزيل وحده (أو اضغط «Click here to download»).',
      'افتح الملف، اضغط «نعم» إن سأل ويندوز، ثم Next في كل الصفحات دون تغيير أي خيار، ثم Install، ثم Finish.',
    ], link: 'https://git-scm.com/download/win', linkLabel: 'فتح صفحة تنزيل Git'),
    GuideStep('أعد تشغيل الحاسبة', [
      'حتى يتعرّف ويندوز على البرنامجين الجديدين. (بعد ذلك لا يلزم ثانية.)',
    ]),
    _getPackage,
    _copyKey,
    GuideStep('شغّل الخادم', [
      'في مجلد الخادم انقر الملف start-windows.bat نقراً مزدوجاً.',
      'إن ظهرت نافذة زرقاء «Windows protected your PC» اضغط «More info» ثم «Run anyway».',
      'تفتح نافذة سوداء تسألك: «الصق مفتاح الخادم». انقر داخلها بزر الفأرة الأيمن (فيُلصق المفتاح) ثم اضغط Enter. يسأل مرة واحدة فقط.',
      'أول مرة ينزّل الملفات اللازمة (1 إلى 3 دقائق، تظهر كتابة كثيرة).',
      'حين تظهر جملة «خادم واتساب الناصر … على المنفذ 8080» فالخادم يعمل. لا تغلق هذه النافذة — يمكنك تصغيرها.',
    ]),
    GuideStep('ضع الرابط في البرنامج', [
      'في شاشة «خادم واتساب»، في «رابط الخادم» اكتب الرابط أدناه (أو انسخه بالزر) ثم «حفظ وفحص الاتصال».',
    ], copy: 'http://127.0.0.1:8080'),
    _linkPhone,
    _tryIt,
    GuideStep('اجعله يعمل وحده عند تشغيل الحاسبة (اختياري)', [
      'انقر start-windows.bat بزر الفأرة الأيمن ← «إنشاء اختصار» (أو «إظهار مزيد من الخيارات» ثم «إنشاء اختصار»).',
      'اضغط على لوحة المفاتيح زر ويندوز + R، واكتب:  shell:startup  ثم Enter. يفتح مجلد «بدء التشغيل».',
      'انقل الاختصار إلى هذا المجلد. من الآن يعمل الخادم كلما شغّلت الحاسبة.',
    ], copy: 'shell:startup'),
  ],
  [
    ('تظهر رسالة «ثبّت Node.js» مع أني ثبّته', 'أعد تشغيل الحاسبة ثم شغّل start-windows.bat مرة أخرى.'),
    ('كتابة حمراء فيها npm ERR أو ENOTFOUND', 'الإنترنت انقطع أثناء التنزيل. تأكد من الإنترنت وشغّل الملف مرة أخرى.'),
    ('البرنامج يقول «مفتاح الخادم غير مطابق»', 'احذف الملف .env من مجلد الخادم، ثم شغّل start-windows.bat والصق المفتاح من جديد.'),
    ('البرنامج يقول «تعذّر الوصول إلى الخادم»', 'النافذة السوداء مغلقة أو الحاسبة أُعيد تشغيلها — شغّل start-windows.bat.'),
  ],
);

// ─────────────── 2) Oracle Cloud ───────────────

const _oracle = HostGuide(
  'Oracle Cloud (مجاني دائماً)',
  Icons.cloud_rounded,
  'حاسبة صغيرة عند Oracle في الإنترنت تعمل ليلاً ونهاراً مجاناً (Always Free) — حتى وحاسبة المحل مطفأة. الإعداد أطول قليلاً، ومرة واحدة فقط.',
  [
    'بريد إلكتروني ورقم هاتف',
    'بطاقة مصرفية (Visa أو Mastercard) — للتحقق من الهوية فقط؛ قد يُحجز مبلغ صغير مؤقتاً ثم يعود',
    'حاسبة المحل (ويندوز 10 أو 11) لرفع الخادم منها',
  ],
  '30 إلى 60 دقيقة أول مرة (وقد يتأخر تفعيل حساب Oracle بضع ساعات)',
  [
    GuideStep('أنشئ حساب Oracle Cloud', [
      'اضغط الزر أدناه. اختر البلد، واكتب اسمك وبريدك، ثم «Verify my email». افتح بريدك واضغط الرابط الذي وصلك.',
      'اكتب كلمة سر. في «Cloud Account Name» اكتب اسماً بالإنجليزية بلا مسافات (مثل alnaserwa) — احفظه، تحتاجه للدخول.',
      'في «Home Region» اختر الأقرب لك. انتبه: لا يمكن تغييرها بعد ذلك.',
      'أكمل العنوان ورقم الهاتف، ثم أدخل البطاقة للتحقق، ووافق على الشروط ← «Start my free trial».',
      'انتظر رسالة في بريدك بأن الحساب جاهز (دقائق، وأحياناً ساعات).',
    ], link: 'https://signup.cloud.oracle.com', linkLabel: 'فتح صفحة إنشاء الحساب',
        tip: 'احفظ «Cloud Account Name» والبريد وكلمة السر في مكان آمن.'),
    GuideStep('ادخل لوحة التحكم', [
      'اضغط الزر أدناه، واكتب «Cloud Account Name» ثم Next، ثم البريد وكلمة السر.',
    ], link: 'https://cloud.oracle.com', linkLabel: 'فتح لوحة Oracle'),
    GuideStep('أنشئ الخادم (Instance)', [
      'اضغط زر القائمة ☰ أعلى اليسار ← «Compute» ← «Instances» ← زر «Create instance».',
      'Name: اكتب alnaser-wa.',
      'في «Image and shape» اضغط «Edit» أو «Change image» ← اختر «Ubuntu» ← «Select image».',
      'اضغط «Change shape» ← «Ampere» ← VM.Standard.A1.Flex واجعل OCPUs = 1 وMemory = 6 ← «Select shape». (بجانبه كلمة «Always Free-eligible».)',
      'في «Networking» اترك الاختيارات كما هي (إنشاء شبكة جديدة، وAssign a public IPv4 address = نعم).',
      'في «Add SSH keys» اختر «Generate a key pair for me» واضغط «Save private key». ينزل ملف ينتهي بـ .key — انقله إلى C:\\alnaser-wa ولا تحذفه أبداً.',
      'اضغط «Create». انتظر حتى تصبح الحالة «Running» باللون الأخضر (دقيقة أو دقيقتان).',
      'في صفحة الخادم انسخ «Public IP address» (أرقام مثل 129.151.10.20).',
    ], tip: 'إن ظهر «Out of capacity» مع Ampere: ارجع واختر Shape من «Specialty and previous generation»: VM.Standard.E2.1.Micro (مجاني أيضاً).'),
    GuideStep('افتح المنفذين 80 و443', [
      'في صفحة الخادم، في قسم «Primary VNIC»، اضغط الرابط بجانب «Subnet».',
      'اضغط «Security Lists» ← «Default Security List for …» ← «Add Ingress Rules».',
      'Source CIDR: اكتب 0.0.0.0/0   •   IP Protocol: TCP   •   Destination Port Range: اكتب 80,443',
      'اضغط «Add Ingress Rules».',
    ], copy: '0.0.0.0/0'),
    _getPackage,
    _copyKey,
    GuideStep('ارفع الخادم بضغطة واحدة', [
      'في مجلد الخادم انقر deploy-oracle.bat نقراً مزدوجاً (وإن ظهرت «Windows protected your PC»: More info ← Run anyway).',
      'يسأل أسئلة، أجب عنها واضغط Enter بعد كل واحدة:',
      '• عنوان IP: الصق «Public IP address».',
      '• مسار ملف المفتاح: انقر ملف .key بزر الفأرة الأيمن مع الضغط على Shift ← «نسخ كمسار» (Copy as path) ثم الصقه.',
      '• اسم المستخدم: اضغط Enter فقط (ubuntu).',
      '• مفتاح الخادم: انقر بزر الفأرة الأيمن للصق.',
      'انتظر 3 إلى 8 دقائق (كتابة كثيرة طبيعية). في النهاية يظهر: «✅ تم. رابط الخادم: https://…sslip.io».',
      'حدّد الرابط بالفأرة وانقر بالزر الأيمن لنسخه.',
    ]),
    GuideStep('ضع الرابط في البرنامج', [
      'في «رابط الخادم» الصق الرابط (يبدأ بـ https وينتهي بـ sslip.io) واضغط «حفظ وفحص الاتصال». إن لم ينجح فوراً انتظر دقيقة وأعد (الشهادة تُنشأ أول مرة).',
    ]),
    _linkPhone,
    _tryIt,
  ],
  [
    ('«Permission denied» أو «UNPROTECTED PRIVATE KEY FILE»', 'ملف المفتاح غير صحيح أو في مكان مشترك. تأكد أنه ملف .key الذي نزل عند إنشاء الخادم، وأن الاسم بلا أخطاء. الملف deploy-oracle.bat يضبط صلاحياته وحده.'),
    ('«Connection timed out» عند الرفع', 'الخادم ليس «Running» أو الـ IP خطأ. انسخ «Public IP address» من صفحة الخادم مرة أخرى.'),
    ('الرابط https://…sslip.io لا يفتح', 'تأكد من خطوة فتح المنفذين 80 و443، ثم انتظر دقيقتين وأعد «فحص الاتصال».'),
    ('«Out of capacity»', 'اختر VM.Standard.E2.1.Micro، أو جرّب لاحقاً.'),
  ],
);

// ─────────────── 3) Render ───────────────

const _render = HostGuide(
  'Render (مجاني — قد يطلب بطاقة)',
  Icons.rocket_launch_rounded,
  'موقع يشغّل الخادم لك من ملفات ترفعها إلى GitHub. الخطة المجانية «تنام» بعد 15 دقيقة بلا طلبات وتستيقظ خلال دقيقة عند الإرسال — البرنامج يتعامل مع هذا وحده.\n'
      'تنبيه: Render يطلب بطاقة مع «Blueprint» دائماً، وقد يطلبها لبعض الحسابات حتى مع «Web Service» المجاني للتحقق. '
      'هذا الدليل يستعمل «Web Service» (بلا Blueprint). إن طلب بطاقة ولا تملكها فاستعمل «هذه الحاسبة» — الخيار الوحيد المضمون بلا بطاقة.',
  ['بريد إلكتروني', 'حساب GitHub (مجاني)', 'متصفح على هذه الحاسبة'],
  '20 إلى 30 دقيقة أول مرة',
  [
    GuideStep('أنشئ حساب GitHub', [
      'اضغط الزر أدناه. اكتب بريدك وكلمة سر واسم مستخدم بالإنجليزية، وأكمل التحقق، ثم أدخل الرمز الذي يصل إلى بريدك.',
    ], link: 'https://github.com/signup', linkLabel: 'فتح صفحة إنشاء حساب GitHub'),
    GuideStep('أنشئ مستودعاً خاصاً (مكان الملفات)', [
      'اضغط الزر أدناه (وأنت داخل حساب GitHub).',
      'Repository name: اكتب alnaser-wa.',
      'اختر «Private» — مهم جداً حتى لا يرى أحد ملفاتك.',
      'لا تضع علامة على أي خيار آخر ← اضغط «Create repository».',
    ], link: 'https://github.com/new', linkLabel: 'فتح «مستودع جديد»', copy: 'alnaser-wa'),
    _getPackage,
    GuideStep('ارفع ملفات الخادم إلى المستودع', [
      'في صفحة المستودع الفارغة اضغط الرابط الأزرق «uploading an existing file».',
      'افتح مجلد الخادم في ويندوز، واضغط Ctrl+A لتحديد كل ما بداخله.',
      'اسحب الملفات المحددة بالفأرة وأفلتها داخل صفحة GitHub — الملفات لا المجلد نفسه.',
      'انتظر حتى تظهر أسماء الملفات، ثم اضغط الزر الأخضر «Commit changes» أسفل الصفحة.',
      'تأكد: في الصفحة الرئيسية للمستودع يجب أن ترى package.json وserver.js وrender.yaml مباشرة (لا داخل مجلد).',
    ], tip: 'إن ظهر ملف .env في المجلد فلا ترفعه — فيه المفتاح.'),
    _copyKey,
    GuideStep('ادخل Render بحساب GitHub', [
      'اضغط الزر أدناه، ثم اختر زر «GitHub» (لا تكتب بريداً) ووافق على «Authorize Render».',
      'إن سألك أسئلة تعريفية (ماذا تبني…) اختر أي جواب أو تخطَّها.',
    ], link: 'https://dashboard.render.com/register', linkLabel: 'فتح Render (الدخول بـ GitHub)'),
    GuideStep('أنشئ «Web Service» — لا Blueprint', [
      'اضغط الزر أدناه: يفتح مباشرة صفحة «New Web Service». (أو من الأعلى: + New ← «Web Service»؛ لا تختر «Blueprint» لأنه يطلب بطاقة.)',
      'في أعلى الصفحة قسم «Source Code» وفيه تبويب «Git Provider» وتحته زر «GitHub». اضغطه.',
      'تفتح صفحة GitHub: اختر «Only select repositories» ← اختر alnaser-wa ← «Install» (أو «Save»). ترجع إلى Render.',
      'يظهر المستودع alnaser-wa في القائمة: اضغط عليه (أو «Connect» بجانبه).',
    ], link: 'https://dashboard.render.com/web/new', linkLabel: 'فتح «New Web Service»',
        tip: 'إن لم يظهر زر GitHub: اضغط «Git Provider» في أعلى الصفحة، أو «Configure account» بجانب GitHub.'),
    GuideStep('املأ الإعدادات (انسخ كل قيمة بزرها)', [
      'Name: alnaser-wa',
      'Language (أو Runtime): Node',
      'Branch: main   •   Region: أي منطقة   •   Root Directory: اتركه فارغاً',
      'Build Command: امسح ما فيه واكتب:  npm install --omit=dev',
      'Start Command: امسح ما فيه واكتب:  node server.js',
      'Instance Type: اختر «Free» (0 دولار) — مهم.',
      'انزل إلى «Environment Variables» ← «Add Environment Variable»: في NAME اكتب API_KEY، وفي VALUE الصق «مفتاح الخادم».',
      'اضغط «Deploy Web Service» أسفل الصفحة.',
    ], copy: 'npm install --omit=dev',
        tip: 'إن طلب Render بطاقة عند الضغط على Deploy مع أنك اخترت Free، فحسابك يحتاج تحققاً ببطاقة — توقف هنا واستعمل «هذه الحاسبة».'),
    GuideStep('أمر التشغيل', [
      'هذا ما يوضع في «Start Command» (انسخه بالزر):',
    ], copy: 'node server.js'),
    GuideStep('انتظر البناء وانسخ الرابط', [
      'افتح «Dashboard» ← الخدمة alnaser-wa. البناء يأخذ 3 إلى 6 دقائق.',
      'حين تظهر كلمة «Live» باللون الأخضر، انسخ الرابط في أعلى الصفحة (مثل https://alnaser-wa-ab12.onrender.com).',
      'في البرنامج الصقه في «رابط الخادم» واضغط «حفظ وفحص الاتصال» (أول مرة قد يأخذ دقيقة).',
    ]),
    _linkPhone,
    _tryIt,
  ],
  [
    ('Render يطلب بطاقة (credit card)', 'لا تستعمل «Blueprint». استعمل «New Web Service» بنوع «Free». إن طلبها حتى هناك فحسابك يحتاج تحققاً ببطاقة — استعمل «هذه الحاسبة» فهي بلا بطاقة.'),
    ('لا أرى مكاناً لاختيار GitHub', 'افتح الرابط https://dashboard.render.com/web/new مباشرة (زر «فتح New Web Service» في الخطوة). زر GitHub داخل قسم «Source Code» في تلك الصفحة، لا في قائمة + New.'),
    ('البناء فشل (Build failed)', 'غالباً رُفعت الملفات داخل مجلد. افتح المستودع: يجب أن يكون package.json في الصفحة الرئيسية. إن كان داخل مجلد فاحذف المستودع وأعد الرفع بالملفات نفسها.'),
    ('في Logs: «API_KEY مطلوب»', 'افتح الخدمة ← Environment ← أضف API_KEY والصق المفتاح ← Save. يعيد Render التشغيل وحده.'),
    ('«مفتاح الخادم غير مطابق»', 'المفتاح في Render غير المفتاح في البرنامج: انسخه من البرنامج وضعه في Environment ← API_KEY.'),
    ('الإرسال بطيء في أول رسالة', 'طبيعي: Render كان نائماً ويستيقظ خلال دقيقة.'),
  ],
);

// ─────────────── 4) Docker (Koyeb مثالاً) ───────────────

const _docker = HostGuide(
  'Docker (Koyeb وغيرها)',
  Icons.inventory_2_rounded,
  'لأي منصة تشغّل الخوادم بـ Docker (Koyeb، Fly.io، Railway، أي خادم). الشرح هنا على Koyeb. بعض هذه المنصات تطلب بطاقة أو اشتراكاً — تأكد من صفحة الأسعار فيها.',
  ['حساب GitHub ومستودع خاص فيه ملفات الخادم (الخطوات 1 إلى 4 في دليل Render)', 'حساب في المنصة'],
  '20 إلى 30 دقيقة',
  [
    GuideStep('جهّز المستودع', [
      'نفّذ من دليل Render الخطوات: إنشاء حساب GitHub، مستودع خاص alnaser-wa، ورفع ملفات الخادم (لا المجلد).',
    ]),
    _copyKey,
    GuideStep('أنشئ الخدمة في Koyeb', [
      'اضغط الزر أدناه وأنشئ حساباً (يمكن بحساب GitHub).',
      '«Create Service» ← «Web Service» ← «GitHub» ← اسمح لـKoyeb بالمستودع alnaser-wa واختره.',
      'Builder: اختر «Dockerfile».',
      'Environment variables: اضغط «Add variable»: الاسم API_KEY والقيمة «مفتاح الخادم».',
      'Exposed ports: 8080 (HTTP).',
      'Instance: اختر الخطة المجانية إن وُجدت ← «Deploy».',
    ], link: 'https://app.koyeb.com', linkLabel: 'فتح Koyeb', copy: 'API_KEY'),
    GuideStep('انسخ الرابط', [
      'حين تصبح الخدمة «Healthy»، انسخ رابطها العام (ينتهي بـ koyeb.app) والصقه في البرنامج ← «حفظ وفحص الاتصال».',
    ]),
    _linkPhone,
    _tryIt,
  ],
  [
    ('البناء فشل', 'تأكد أن Dockerfile وpackage.json في الصفحة الرئيسية للمستودع لا داخل مجلد.'),
    ('«مفتاح الخادم غير مطابق»', 'ضع المفتاح نفسه من البرنامج في متغير API_KEY في المنصة.'),
  ],
);

const hostGuides = [_local, _oracle, _render, _docker];

class WaHostGuideScreen extends StatelessWidget {
  const WaHostGuideScreen({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final g = hostGuides[index];
    return SettingsScaffold(
      title: 'الشرح الكامل: ${g.title}',
      icon: g.icon,
      subtitle: 'المدة التقريبية: ${g.time}',
      children: [
        SetBanner(g.intro),
        const SizedBox(height: 12),
        SetCard(
          title: 'ماذا تحتاج',
          icon: Icons.checklist_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final n in g.needs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF047857)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(n, style: const TextStyle(height: 1.5))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < g.steps.length; i++) ...[
          _StepCard(n: i + 1, step: g.steps[i]),
          const SizedBox(height: 10),
        ],
        SetCard(
          title: 'إن ظهرت مشكلة',
          icon: Icons.build_circle_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (q, a) in g.problems)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                childrenPadding: const EdgeInsets.only(bottom: 10),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(a, style: const TextStyle(height: 1.6))],
              ),
          ]),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.n, required this.step});
  final int n;
  final GuideStep step;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: kSetNavy,
                child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(step.title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: kSetNavy)),
              ),
            ]),
            const SizedBox(height: 8),
            for (final l in step.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(l, style: const TextStyle(height: 1.65, fontSize: 13.5)),
              ),
            if (step.tip != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Text('💡 ${step.tip}', style: const TextStyle(height: 1.5, fontSize: 13)),
              ),
            if (step.link != null || step.copy != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (step.link != null)
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse(step.link!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(step.linkLabel ?? 'فتح الموقع'),
                  ),
                if (step.copy != null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: step.copy!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نُسخ: ${step.copy}')));
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text('نسخ ${step.copy}', textDirection: TextDirection.ltr),
                  ),
              ]),
            ],
          ]),
        ),
      );
}
