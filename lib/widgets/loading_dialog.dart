// lib/widgets/loading_dialog.dart
// ⏳ مؤشر تحميل يُغلق نفسه بعينه.
//
// النمط القديم: showDialog(مؤشر) ثم Navigator.pop(context). المؤشر يُعرض في
// الملاح الرئيسي، لكن Navigator.pop(context) يغلق أقرب ملاح للشاشة — وفي
// النوافذ المنبثقة (سجل الديون، الإعدادات…) لكل نافذة ملاحها الخاص، فكان يُغلق
// الشاشة داخل النافذة بدل المؤشر، ويبقى المؤشر معلقاً فوق البرنامج.
// وفي catch كان يُستدعى الإغلاق مرة ثانية فيُغلق شيئاً آخر غير المؤشر.
//
// هنا يُحفظ مسار المؤشر نفسه، و[hide] يزيله هو وحده أينما كان، ولا يفعل شيئاً
// إن لم يكن هناك مؤشر مفتوح (فاستدعاؤه مرتين آمن).

import 'package:flutter/material.dart';

class LoadingDialog {
  LoadingDialog._();

  static final List<(NavigatorState, Route<void>)> _open = [];

  /// يعرض مؤشر التحميل. [builder] اختياري لشكل مخصص (بطاقة مع نص…).
  static void show(BuildContext context, {WidgetBuilder? builder}) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: builder ?? (_) => const Center(child: CircularProgressIndicator()),
    );
    _open.add((navigator, route));
    navigator.push(route);
  }

  /// يغلق آخر مؤشر تحميل ما زال مفتوحاً، ولا شيء غيره.
  static void hide() {
    while (_open.isNotEmpty) {
      final (navigator, route) = _open.removeLast();
      if (route.isActive) {
        navigator.removeRoute(route);
        return;
      }
    }
  }
}
