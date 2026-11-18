// lib/widgets/dropbox_troubleshoot.dart
//
// 🩺 حل مشاكل Dropbox — كل مشكلة معروفة: ما الذي تراه، سببه، من يصلحه، وخطوات الحل.
// يُعرض في شاشة Dropbox دائماً، ويفتح وحده المشكلة التي تطابق الخطأ الظاهر
// (ردّ Dropbox، أو رابط صفحة الخطأ إن لُصق في خانة الكود).
//
// عرض فقط — لا يغيّر إعداداً ولا يرسل شيئاً.

import 'package:flutter/material.dart';

import '../services/dropbox_backup_service.dart';
import 'settings_kit.dart';
import 'setup_guide.dart';

/// مشكلة معروفة وحلّها.
class DropboxProblem {
  const DropboxProblem({
    required this.key,
    required this.title,
    required this.symptom,
    required this.who,
    required this.steps,
    this.needles = const [],
  });

  final String key;
  final String title;

  /// ما يراه المستخدم.
  final String symptom;

  /// من يستطيع الإصلاح.
  final String who;
  final List<GuideStep> steps;

  /// نصوص في رسالة الخطأ تدل على هذه المشكلة (بلا حساسية لحالة الأحرف).
  final List<String> needles;
}

class DropboxTroubleshoot {
  DropboxTroubleshoot._();

  static const _connected = 'https://www.dropbox.com/account/connected_apps';

  static List<DropboxProblem> problems({required String appKey, required String appName}) {
    final console = GuideStep(
      'افتح App Console بحساب Dropbox الذي أنشأ التطبيق «$appName»، واضغط على اسمه.',
      links: const [GuideLink('افتح App Console', DropboxBackupService.appConsoleUrl, icon: Icons.open_in_new_rounded)],
    );
    final sameKey = GuideStep(
      'تأكّد أنه التطبيق نفسه: «App key» في صفحته يجب أن يساوي هذا المفتاح. إن اختلف فأنت في تطبيق آخر.',
      copies: [appKey],
      warn: true,
    );
    const relink = GuideStep('ارجع إلى البرنامج واضغط «فتح صفحة Dropbox» من جديد ثم أكمل الربط.');
    return [
      DropboxProblem(
        key: 'user_limit',
        title: 'This app has reached its user limit',
        symptom: 'صفحة Dropbox في المتصفح: «Error connecting app: This app has reached its user limit» '
            '(وفي شريط العنوان check_add_user_increase_limit).',
        who: 'صاحب تطبيق Dropbox (حساب المطوّر) — مرة واحدة. لا يُصلح من البرنامج.',
        needles: const ['check_add_user_increase_limit', 'reached its user limit', 'user limit'],
        steps: [
          const GuideStep(
            'السبب: تطبيق Dropbox جديد في «وضع التطوير» يقبل افتراضياً حساب صاحبه فقط. '
            'أي حساب Dropbox آخر (حساب المحل أو الزبون) يُرفض بهذه الرسالة. حساب صاحب التطبيق نفسه يُربط بلا مشكلة.',
          ),
          console,
          sameKey,
          const GuideStep(
            'في تبويب «Settings» ابحث عن سطر «Development users» (مكتوب بجانبه «Only you»)، '
            'واضغط «Enable additional users». يصبح التطبيق يقبل حسابات أخرى (حتى 500 حساب في وضع التطوير).',
          ),
          relink,
          const GuideStep(
            'إن لم تصل إلى حساب صاحب التطبيق: أنشئ تطبيقاً خاصاً بك في App Console '
            '(Create app ← Scoped access ← App folder)، ثم ضع مفتاحه من بطاقة «تطبيق Dropbox» في هذه الشاشة، '
            'وفعّل أذوناته واضغط «Enable additional users» فيه أيضاً إن كان غيرك سيربط به.',
            note: 'إن امتلأت الـ 500: في تبويب Settings نفسه زر «Apply for production» لطلب رفع الحد من Dropbox.',
          ),
        ],
      ),
      DropboxProblem(
        key: 'bad_app',
        title: 'التطبيق غير موجود أو مفتاحه خطأ',
        symptom: 'صفحة Dropbox: «Invalid client_id» أو «app not found» أو «This app is disabled»، '
            'أو رفض الربط مع ردّ فيه invalid_client.',
        who: 'صاحب تطبيق Dropbox، أو أنت إن كان التطبيق تطبيقك.',
        needles: const ['invalid_client', 'app not found', 'app is disabled', 'disabled app'],
        steps: [
          console,
          sameKey,
          const GuideStep(
            'إن لم تجد تطبيقاً بهذا المفتاح فقد حُذف أو كُتب المفتاح خطأ: انسخ «App key» الصحيح '
            'وضعه من بطاقة «تطبيق Dropbox» أعلى هذه الشاشة (زر «تغيير»).',
          ),
          const GuideStep('إن كان التطبيق موقوفاً (disabled) فلا يُصلح إلا بتطبيق آخر: أنشئ تطبيقاً جديداً وضع مفتاحه.'),
          relink,
        ],
      ),
      DropboxProblem(
        key: 'code',
        title: 'رُفض الكود عند «تأكيد»',
        symptom: 'بعد لصق الكود والضغط على «تأكيد»: «رُفض الكود»، أو ردّ Dropbox فيه invalid_grant أو expired.',
        who: 'أنت — من البرنامج.',
        needles: const ['invalid_grant', 'code doesn', 'رُفض الكود'],
        steps: const [
          GuideStep('الكود صالح دقائق قليلة، ويُستعمل مرة واحدة فقط.'),
          GuideStep(
            'كل ضغطة على «فتح صفحة Dropbox» تُبطل الأكواد السابقة. اضغطه مرة واحدة، ثم استعمل الكود الذي يظهر بعدها فقط.',
            warn: true,
          ),
          GuideStep('اضغط «فتح صفحة Dropbox مجدداً»، ثم «Allow»، وانسخ الكود كاملاً بزر النسخ في صفحة Dropbox.'),
          GuideStep('الصقه فوراً في الخانة واضغط «تأكيد». يقبل البرنامج الكود وحده أو رابط الصفحة كاملاً.'),
        ],
      ),
      DropboxProblem(
        key: 'scope',
        title: 'ينقص تطبيق Dropbox إذن',
        symptom: 'بطاقة «أذونات Dropbox» تُظهر إذناً ناقصاً، أو رسالة «ينقص تطبيق Dropbox إذن»، '
            'أو ردّ فيه missing_scope / required_scope.',
        who: 'صاحب تطبيق Dropbox — مرة واحدة.',
        needles: const ['missing_scope', 'required_scope', 'insufficient_scope', 'ينقص تطبيق Dropbox إذن'],
        steps: [
          console,
          sameKey,
          const GuideStep('افتح تبويب «Permissions» وضع ✔ أمام هذه الأذونات:', copies: DropboxBackupService.requiredScopes),
          const GuideStep('اضغط «Submit» أسفل صفحة Permissions — بدونه لا يُحفظ شيء.', warn: true),
          const GuideStep('في البرنامج: «قطع الاتصال» ثم اربط من جديد — الربط القديم يبقى بأذوناته القديمة.'),
        ],
      ),
      const DropboxProblem(
        key: 'wrong_account',
        title: 'النسخ تذهب إلى حساب Dropbox آخر',
        symptom: 'اسم الحساب الظاهر أعلى الشاشة ليس حسابك، أو لا تجد النسخ في Dropbox الذي تفتحه.',
        who: 'أنت.',
        steps: [
          GuideStep('المتصفح كان مسجّلاً بحساب Dropbox آخر لحظة الربط، فرُبط البرنامج به.'),
          GuideStep('في البرنامج: «قطع الاتصال».'),
          GuideStep(
            'في المتصفح: افتح dropbox.com واخرج من الحساب الآخر (أو استعمل نافذة خاصة InPrivate/Incognito)، ثم سجّل بحسابك.',
            links: [GuideLink('فتح Dropbox', 'https://www.dropbox.com/home', icon: Icons.open_in_new_rounded)],
          ),
          GuideStep('ارجع واضغط «فتح صفحة Dropbox» واربط من جديد، وتأكد من الاسم أعلى الشاشة.'),
        ],
      ),
      const DropboxProblem(
        key: 'expired',
        title: 'انتهى الاتصال — يطلب تسجيل الدخول من جديد',
        symptom: '«انتهى الاتصال — سجّل الدخول من جديد» أو «انتهت صلاحية الاتصال بـ Dropbox».',
        who: 'أنت.',
        needles: ['انتهت صلاحية الاتصال', 'انتهى الاتصال', 'expired_access_token', 'invalid_access_token', 'تغيّر تطبيق Dropbox'],
        steps: [
          GuideStep(
            'السبب غالباً: أُزيل وصول التطبيق من حسابك في Dropbox، أو تغيّر تطبيق Dropbox في البرنامج، '
            'أو غُيّرت كلمة سر الحساب.',
            links: [GuideLink('التطبيقات المرتبطة بحسابك', _connected, icon: Icons.open_in_new_rounded)],
          ),
          GuideStep('اضغط «فتح صفحة Dropbox» واربط من جديد. النسخ الموجودة في Dropbox لا تتأثر.'),
        ],
      ),
      const DropboxProblem(
        key: 'network',
        title: 'لا يصل إلى Dropbox (الإنترنت أو الحجب)',
        symptom: '«تعذّر الوصول إلى Dropbox»، «انقطع الاتصال أثناء الرفع»، «انتهت المهلة»، أو Failed host lookup.',
        who: 'أنت.',
        needles: [
          'تعذّر الوصول',
          'انقطع الاتصال',
          'SocketException',
          'Failed host lookup',
          'TimeoutException',
          'HandshakeException',
          'CERTIFICATE'
        ],
        steps: [
          GuideStep('تأكد أن الإنترنت يعمل، وافتح dropbox.com في المتصفح على الحاسبة نفسها.',
              links: [GuideLink('فتح dropbox.com', 'https://www.dropbox.com', icon: Icons.open_in_new_rounded)]),
          GuideStep(
            'إن فتح الموقع في المتصفح ولم يعمل البرنامج: تأكد من تاريخ الحاسبة وساعتها (خطؤهما يرفض شهادة الأمان)، '
            'ثم أعد المحاولة.',
          ),
          GuideStep('إن لم يفتح الموقع إطلاقاً فقد يكون محجوباً عند مزوّد الإنترنت: جرّب شبكة أخرى أو VPN ثم أعد المحاولة.'),
          GuideStep(
            'إن انقطع الرفع وكان الإنترنت سليماً فالسبب غالباً إذن ناقص: اضغط «فحص الأذونات» في بطاقة «أذونات Dropbox».',
            warn: true,
          ),
        ],
      ),
      const DropboxProblem(
        key: 'space',
        title: 'المساحة في Dropbox لا تكفي',
        symptom: '«المساحة في Dropbox لا تكفي حتى بعد حذف النسخ القديمة» أو insufficient_space.',
        who: 'أنت.',
        needles: ['لا تكفي', 'insufficient_space', 'insufficient space'],
        steps: [
          GuideStep('البرنامج يحذف الأقدم من نسخه هو فقط، ولا يمس ملفاتك الأخرى في Dropbox.'),
          GuideStep('احذف ملفات لا تحتاجها من Dropbox (وأفرغ سلة المحذوفات فيه)، أو قلّل «عدد النسخ المحتفظ بها».',
              links: [GuideLink('فتح Dropbox', 'https://www.dropbox.com/home', icon: Icons.open_in_new_rounded)]),
          GuideStep('أو رقِّ الحساب لمساحة أكبر، ثم أعد «نسخة احتياطية الآن».'),
        ],
      ),
      const DropboxProblem(
        key: 'restore',
        title: 'رُفضت الاستعادة',
        symptom: '«الملف لا يحتوي قاعدة بيانات صالحة» أو «هذه النسخة من برنامج أحدث أو برنامج آخر» أو «فشلت الاستعادة».',
        who: 'أنت.',
        needles: ['قاعدة بيانات صالحة', 'برنامج أحدث', 'فشلت الاستعادة', 'تعذّر تحميل النسخة'],
        steps: [
          GuideStep('عند أي رفض لا يتغيّر شيء في بياناتك: الاستعادة تأخذ نسخة أمان أولاً وتتراجع وحدها إن فشلت.'),
          GuideStep('جرّب نسخة أقدم من القائمة — قد تكون النسخة المختارة ناقصة.'),
          GuideStep('«برنامج أحدث أو آخر»: النسخة من إصدار أحدث من هذا البرنامج أو من برنامج آخر — حدّث البرنامج، '
              'ولا تستعد نسخة برنامج في برنامج آخر.'),
        ],
      ),
    ];
  }

  /// المشكلة التي يطابقها [text] (رسالة خطأ أو رابط صفحة الخطأ)، أو null.
  static DropboxProblem? match(String? text, {required String appKey, required String appName}) {
    final t = (text ?? '').toLowerCase();
    if (t.trim().isEmpty) return null;
    for (final p in problems(appKey: appKey, appName: appName)) {
      for (final n in p.needles) {
        if (t.contains(n.toLowerCase())) return p;
      }
    }
    return null;
  }

  /// هل [input] رابط صفحة خطأ من Dropbox (لا كود)؟
  static bool isErrorPage(String input) {
    final s = input.toLowerCase();
    return s.contains('authorize_error') || s.contains('error_name=') || (s.contains('error=') && !s.contains('code='));
  }
}

/// 🩺 بطاقة «حل مشاكل Dropbox».
class DropboxTroubleshootCard extends StatelessWidget {
  const DropboxTroubleshootCard({super.key, required this.appKey, required this.appName, this.openKey});

  final String appKey;
  final String appName;

  /// المشكلة المفتوحة تلقائياً (المطابقة للخطأ الظاهر).
  final String? openKey;

  static const _c = Color(0xFF0061FE);

  @override
  Widget build(BuildContext context) {
    final list = DropboxTroubleshoot.problems(appKey: appKey, appName: appName);
    return SetCard(
      title: 'حل مشاكل Dropbox',
      subtitle: 'كل رسالة خطأ معروفة: سببها ومن يصلحها وخطوات الحل',
      icon: Icons.healing_rounded,
      color: _c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        const SetBanner(
          'ظهرت لك صفحة خطأ في المتصفح بدل صفحة «Allow»؟ انسخ رابطها من شريط العنوان والصقه في خانة الكود ثم «تأكيد»: '
          'يتعرّف البرنامج على المشكلة ويفتح حلّها هنا.',
        ),
        const SizedBox(height: 6),
        for (final p in list)
          GuideToggle(
            // المفتاح يتغيّر حين تتغيّر المشكلة المطابقة، فتُفتح وحدها
            key: ValueKey('${p.key}|${p.key == openKey}'),
            label: p.title,
            color: _c,
            initiallyOpen: p.key == openKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('ما تراه: ${p.symptom}', style: const TextStyle(fontSize: 12.5, color: kSetText, height: 1.6)),
              const SizedBox(height: 4),
              Text('من يصلحها: ${p.who}',
                  style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.6, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SetupGuide(color: _c, steps: p.steps),
            ]),
          ),
      ]),
    );
  }
}
