// lib/widgets/error_capture_messenger.dart
//
// 🩺 يلتقط كل رسالة خطأ حمراء تظهر للمستخدم (الشريط أسفل الشاشة) ويسجّلها في «تشخيص الأخطاء».
//
// لماذا هنا: في البرنامج أكثر من 270 موضعاً يُظهر رسالة خطأ بطرق مختلفة (showError، setToast،
// SnackBar مباشر…). كلها تمر بـ ScaffoldMessenger الأقرب — هذا الغلاف (حول كل الشاشات في
// main.dart) هو الأقرب، فيرى كل رسالة قبل عرضها ثم يعرضها كما هي تماماً.
//
// الرسالة «خطأ» إن كان لونها أحمر أو فيها أيقونة خطأ. أخطاء الإدخال (اكتب، اختر، أدخل…) ورسائل
// الصلاحية لا تُسجَّل: أخطاء المستخدم لا البرنامج.
//
// ⚠️ توقيع showSnackBar منسوخ من Flutter المثبّت (scaffold.dart). إن غيّره تحديث Flutter فعدّله هنا.

import 'package:flutter/material.dart';

import '../services/diagnostics/error_journal.dart';

class ErrorCaptureMessenger extends ScaffoldMessenger {
  const ErrorCaptureMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _ErrorCaptureMessengerState();

  static final _input = RegExp(r'^\s*(اكتب|أدخل|ادخل|اختر|أضف|حدّد|حدد|يرجى|الرجاء|يجب|ليس لديك صلاحية|لا تملك صلاحية)');

  static const _errorIcons = <IconData>{
    Icons.error,
    Icons.error_outline,
    Icons.error_rounded,
    Icons.error_outline_rounded,
    Icons.error_outlined,
    Icons.report_rounded,
    Icons.dangerous_rounded,
  };

  /// هل هذه الرسالة رسالة خطأ؟ (لون أحمر أو أيقونة خطأ)
  static bool isError(SnackBar s) {
    final bg = s.backgroundColor;
    if (bg != null && _reddish(bg)) return true;
    return _hasErrorIcon(s.content);
  }

  static bool _reddish(Color c) {
    final hsv = HSVColor.fromColor(c);
    return (hsv.hue >= 345 || hsv.hue <= 15) && hsv.saturation >= 0.45 && hsv.value >= 0.35;
  }

  static bool _hasErrorIcon(Widget w) {
    var found = false;
    _walk(w, (x) {
      if (x is Icon) {
        final i = x.icon;
        if (i != null && _errorIcons.contains(i)) {
          found = true;
        }
      }
    });
    return found;
  }

  /// النص الظاهر في الرسالة.
  static String textOf(Widget w) {
    final parts = <String>[];
    _walk(w, (x) {
      if (x is Text) {
        final t = x.data ?? x.textSpan?.toPlainText();
        if (t != null && t.trim().isNotEmpty) parts.add(t.trim());
      } else if (x is RichText) {
        final t = x.text.toPlainText();
        if (t.trim().isNotEmpty) parts.add(t.trim());
      }
    });
    return parts.join(' — ');
  }

  /// يمشي على شجرة الرسالة (ما يمكن الوصول إليه دون بنائها).
  static void _walk(Widget w, void Function(Widget) visit, [int depth = 0]) {
    if (depth > 40) return;
    visit(w);
    if (w is Text || w is RichText) return;
    if (w is MultiChildRenderObjectWidget) {
      for (final c in w.children) {
        _walk(c, visit, depth + 1);
      }
    } else if (w is SingleChildRenderObjectWidget) {
      final c = w.child;
      if (c != null) _walk(c, visit, depth + 1);
    } else if (w is ProxyWidget) {
      _walk(w.child, visit, depth + 1);
    } else if (w is Container) {
      final c = w.child;
      if (c != null) _walk(c, visit, depth + 1);
    } else if (w is Card) {
      final c = w.child;
      if (c != null) _walk(c, visit, depth + 1);
    } else if (w is ListTile) {
      for (final c in [w.leading, w.title, w.subtitle, w.trailing]) {
        if (c != null) _walk(c, visit, depth + 1);
      }
    }
  }

  /// يسجّل الرسالة إن كانت خطأ برنامج (لا خطأ إدخال).
  static void capture(SnackBar s) {
    try {
      if (!isError(s)) return;
      final text = textOf(s.content);
      if (text.isEmpty || _input.hasMatch(text)) return;
      ErrorJournal.recordText(ErrorSource.shown, text);
    } catch (_) {
      // الالتقاط لا يمنع عرض الرسالة أبداً
    }
  }
}

class _ErrorCaptureMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    ErrorCaptureMessenger.capture(snackBar);
    return super.showSnackBar(snackBar, snackBarAnimationStyle: snackBarAnimationStyle);
  }
}
