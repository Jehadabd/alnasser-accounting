// lib/widgets/error_dialog_observer.dart
//
// 🩺 يراقب كل شاشة ونافذة تُفتح (navigatorObservers في main.dart) لأداة «تشخيص الأخطاء»:
//   • النافذة (حوار/لوحة سفلية) التي عنوانها فشل — «لم يكتمل رفع البيانات»، «تعذّر حفظ النسخة
//     الاحتياطية»… — أو فيها أيقونة خطأ: يقرأ نصها بعد رسمها ويسجّلها.
//   • الشاشة المفتوحة: اسمها يُرفق بكل خطأ («الشاشات الأخيرة: …») ليُعرف أين وقع.
// يقرأ فقط ولا يغيّر أي نافذة. أسئلة التأكيد (تنتهي بـ «؟») لا تُعدّ أخطاء.

import 'package:flutter/material.dart';

import '../services/diagnostics/error_journal.dart';
import 'error_capture_messenger.dart';

class ErrorDialogObserver extends NavigatorObserver {
  static final _failure = RegExp(r'فشل|تعذّر|تعذر|خطأ|لم يكتمل|لم ينجح|لم يُحفظ|توقف|\bError\b|\bException\b|\bfailed\b',
      caseSensitive: false);

  /// نوافذ أداة التشخيص نفسها لا تُسجَّل.
  static const _own = {
    'ارفع قاعدة البيانات أولاً',
    'مسح سجل الأخطاء؟',
    'أبلغ عن مشكلة',
    'لا يوجد خطأ يحتاج هذا الإصلاح',
    'إغلاق كل الأخطاء المفتوحة؟',
  };

  /// نفي الخطأ («لا يوجد خطأ»، «بلا أخطاء») ليس خطأ.
  static final _negated = RegExp(r'(لا|بلا|دون|ليس هناك) (يوجد |توجد )?(أي )?(خطأ|أخطاء)');

  /// رمز أيقونة (حرف واحد من منطقة الاستخدام الخاص في الخطوط) ليس نصاً.
  static bool _isGlyph(String t) {
    final r = t.runes.toList();
    if (r.length != 1) return false;
    final c = r.first;
    return (c >= 0xE000 && c <= 0xF8FF) || c >= 0xF0000;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _seen(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _seen(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute is PageRoute) _nameScreen(previousRoute);
  }

  void _seen(Route<dynamic> route) {
    // المحتوى يُبنى في الإطار التالي
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (route is PopupRoute) {
          _inspectDialog(route);
        } else if (route is PageRoute) {
          _nameScreen(route);
        }
      } catch (_) {
        // المراقبة لا تُسقط البرنامج أبداً
      }
    });
  }

  void _nameScreen(PageRoute<dynamic> route) {
    final name = route.settings.name;
    final found = _screenWidget(route);
    final label = found ?? (name != null && name != '/' ? name : null);
    if (label != null) ErrorJournal.screenOpened(label);
  }

  /// أول عنصر اسمه «…Screen» أو «…Page» تحت الشاشة.
  static String? _screenWidget(ModalRoute<dynamic> route) {
    final ctx = route.subtreeContext;
    if (ctx is! Element) return null;
    String? found;
    var seen = 0;
    void visit(Element e) {
      if (found != null || seen++ > 400) return;
      final n = e.widget.runtimeType.toString();
      if (n.endsWith('Screen') || n.endsWith('Page')) {
        found = n;
        return;
      }
      e.visitChildren(visit);
    }

    ctx.visitChildren(visit);
    return found;
  }

  void _inspectDialog(PopupRoute<dynamic> route) {
    final ctx = route.subtreeContext;
    if (ctx is! Element) return;
    final texts = <String>[];
    var errorIcon = false;
    var seen = 0;
    void visit(Element e) {
      if (seen++ > 3000) return;
      final w = e.widget;
      if (w is RichText) {
        final t = w.text.toPlainText().trim();
        if (t.isNotEmpty && (texts.isEmpty || texts.last != t)) texts.add(t);
        return; // Text يبني RichText: لا نكرر
      }
      if (w is Icon) {
        // الأيقونة تُرسم RichText برمزها: لا ندخلها حتى لا يُقرأ الرمز نصاً
        if (w.icon != null && ErrorCaptureMessenger.isErrorIcon(w.icon!)) errorIcon = true;
        return;
      }
      if (w is EditableText) return; // حقول الإدخال ليست رسالة
      e.visitChildren(visit);
    }

    ctx.visitChildren(visit);
    final hit = classify(texts, errorIcon: errorIcon);
    if (hit == null) return;
    ErrorJournal.recordText(ErrorSource.dialog, hit);
  }

  /// نص التسجيل إن كانت النافذة نافذة خطأ، وإلا null.
  /// خطأ إن كان عنوانها (أول نصين) فشلاً ولا ينتهي بـ «؟»، أو فيها أيقونة خطأ ونص فشل.
  @visibleForTesting
  static String? classify(List<String> raw, {bool errorIcon = false}) {
    final texts = [for (final t in raw) if (!_isGlyph(t)) t];
    if (texts.isEmpty) return null;
    final title = texts.first;
    if (_own.contains(title) || _negated.hasMatch(title)) return null;
    bool failing(String t) => _failure.hasMatch(t) && !_negated.hasMatch(t);
    final head = texts.take(2).toList();
    final titled = head.any((t) => failing(t) && !t.trimRight().endsWith('؟') && !t.trimRight().endsWith('?'));
    final iconed = errorIcon && texts.any(failing);
    if (!titled && !iconed) return null;
    // السطر الأول: العنوان؛ ثم نص النافذة (بلا أزرارها القصيرة)
    final body = texts.skip(1).where((t) => t.length > 12).take(6).join('\n');
    return body.isEmpty ? title : '$title\n$body';
  }
}
