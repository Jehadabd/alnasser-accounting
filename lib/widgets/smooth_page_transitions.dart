// lib/widgets/smooth_page_transitions.dart
//
// 🎬 انتقال الصفحات: «تلاشٍ عابر» (Material fade-through) بدل «التكبير» الافتراضي في Windows.
//
// لماذا؟ انتقال Windows الافتراضي (ZoomPageTransitionsBuilder) يُظهر الصفحة الجديدة شفافة
// فوق القديمة ثم يكبّرها من 85%، وتكتمل الشفافية في أول ~40ms. إن تأخر رسم أول إطار
// للشاشة الجديدة (شاشة ثقيلة) ضاعت إطارات التكبير، فتُرى قفزة وصورتان متراكبتان.
//
// هنا:
//   1. الصفحة القديمة تتلاشى إلى لون الخلفية (أول 30% من الوقت) — لا تراكب صورتين.
//   2. الجديدة تظهر تدريجياً مع انزلاق خفيف 12px للأعلى (الـ70% الباقية).
//   3. لا تكبير ولا لقطات (snapshots) للشاشة كاملة — أخف على الرسم.
// تأخر أول إطار هنا يقع أثناء تلاشي القديمة، فلا يُلاحظ.
// الرجوع هو العكس تماماً. النوافذ المنبثقة والحوارات لا تتأثر (ليست صفحات Material).

import 'package:flutter/material.dart';

class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  static const _outEnd = 0.3;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fill = Theme.of(context).scaffoldBackgroundColor;

    // الصفحة التي تختفي (فوقها صفحة جديدة): تتلاشى إلى لون الخلفية
    final outgoing = ReverseAnimation(CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, _outEnd, curve: Curves.easeOut),
      reverseCurve: const Interval(0, _outEnd, curve: Curves.easeIn),
    ));

    // الصفحة التي تظهر: بعد اختفاء القديمة، تلاشٍ + انزلاق خفيف
    final incoming = CurvedAnimation(
      parent: animation,
      curve: const Interval(_outEnd, 1, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(_outEnd, 1, curve: Curves.easeInCubic),
    );

    return FadeTransition(
      opacity: incoming,
      child: AnimatedBuilder(
        animation: incoming,
        builder: (context, c) => Transform.translate(
          offset: Offset(0, 12 * (1 - incoming.value)),
          child: c,
        ),
        // خلفية ثابتة تحت الصفحة: تلاشي القديمة يكشف لوناً هادئاً لا سواداً
        child: ColoredBox(
          color: fill,
          child: FadeTransition(opacity: outgoing, child: child),
        ),
      ),
    );
  }
}

/// كل المنصات بالانتقال نفسه (سطح المكتب والهاتف).
const smoothPageTransitionsTheme = PageTransitionsTheme(builders: {
  TargetPlatform.windows: SmoothPageTransitionsBuilder(),
  TargetPlatform.linux: SmoothPageTransitionsBuilder(),
  TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
  TargetPlatform.android: SmoothPageTransitionsBuilder(),
  TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
  TargetPlatform.fuchsia: SmoothPageTransitionsBuilder(),
});
