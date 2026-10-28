// lib/theme/numeric_date_localizations.dart
//
// 📅 الأشهر بالأرقام في كل نوافذ اختيار التاريخ.
//
// نافذة التاريخ في Flutter تكتب الشهر باسمه («أكتوبر ٢٠٢٦»)، وأغلب الناس هنا
// يحفظون الأشهر بأرقامها. هذا المندوب يبني ترجمة الواجهة العربية نفسها لكن
// بتنسيقات تاريخ رقمية وأرقام لاتينية (مثل بقية البرنامج):
//   • رأس الشهر في التقويم:  شهر 10 - 2026
//   • التاريخ المختار:       2026/10/13
//   • حقل الكتابة اليدوية:   2026/10/13  (يطابق تلميح «yyyy/mm/dd» العربي)
// أسماء أيام الأسبوع وبداية الأسبوع (السبت) تبقى عربية كما هي.
//
// يُسجَّل في main.dart قبل GlobalMaterialLocalizations.delegate؛ Flutter يأخذ
// أول مندوب يدعم اللغة، فيصبح هذا هو المعتمد للعربية فقط.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

class NumericMonthsLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const NumericMonthsLocalizationsDelegate();

  static final Map<Locale, Future<MaterialLocalizations>> _cache = {};

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ar';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // الترجمة الافتراضية تُحمَّل أولاً (تهيّئ بيانات التواريخ) وتبقى احتياطاً.
    // SynchronousFuture.then تعيد SynchronousFuture فلا تتأخر أول شاشة.
    return _cache.putIfAbsent(
      locale,
      () => GlobalMaterialLocalizations.delegate.load(locale).then<MaterialLocalizations>((fallback) {
        try {
          // أسماء الأيام وبداية الأسبوع تُقرأ من التنسيق الطويل، فيبقى عربياً
          final long = intl.DateFormat('EEEE yyyy/MM/dd', 'ar')..useNativeDigits = false;
          final numeric = intl.DateFormat('yyyy/MM/dd', 'en');
          final loc = getMaterialTranslation(
            locale,
            intl.DateFormat('y', 'en'), // السنة
            numeric, // حقل الكتابة اليدوية
            numeric, // التاريخ المختصر (نطاق تواريخ)
            numeric, // رأس النافذة (مساحته ضيقة: بلا اسم اليوم)
            long, // قراءة الشاشة + أسماء الأيام
            intl.DateFormat("'شهر' M  -  y", 'en'), // عنوان الشهر في التقويم
            intl.DateFormat('MM/dd', 'en'), // يوم/شهر مختصر
            intl.NumberFormat.decimalPattern('en'),
            intl.NumberFormat('00', 'en'),
          );
          return loc ?? fallback;
        } catch (_) {
          return fallback;
        }
      }),
    );
  }

  @override
  bool shouldReload(NumericMonthsLocalizationsDelegate old) => false;
}
