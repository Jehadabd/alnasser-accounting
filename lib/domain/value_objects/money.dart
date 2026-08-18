// lib/domain/value_objects/money.dart
import 'package:flutter/foundation.dart';

/// كائن قيمة خالي من التغيير (Immutable Value Object) يمثل المبالغ المالية
/// يمنع تماماً أخطاء التقريب الناتجة عن أرقام النقطة العائمة (Floating-Point REAL).
@immutable
class Money {
  /// المبلغ مقدراً بالوحدة المالية الصغرى (مثلاً بالفلس أو السنت - Integer)
  final int amountInCents;

  /// اسم العملة (افتراضياً IQD)
  final String currency;

  /// معامل التحويل بين الوحدة الأساسية والوحدة الصغرى (افتراضياً 1000 للدينار العراقي)
  static const int defaultScale = 1000;

  const Money._(this.amountInCents, {this.currency = 'IQD'});

  /// إنشاء مبلغ مالى من القيمة الصغرى (Integer)
  factory Money.fromCents(int cents, {String currency = 'IQD'}) {
    return Money._(cents, currency: currency);
  }

  /// إنشاء مبلغ مالي من قيمة الوحدة الرئيسية (Double/Num) بتحويل آمن لـ Integer
  factory Money.fromMajor(num amount, {String currency = 'IQD', int scale = defaultScale}) {
    final cents = (amount * scale).round();
    return Money._(cents, currency: currency);
  }

  /// القيمة بالوحدة الرئيسية كـ double للعرض فقط (Display Only)
  double get toMajor => amountInCents / defaultScale;

  /// القيمة المالية الصحيحة كـ int لاستخدامها في قاعدة البيانات
  int get toCents => amountInCents;

  // -------------------------------------------------------------
  // العمليات الحسابية الآمنة (Pure Integer Arithmetic)
  // -------------------------------------------------------------

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money._(amountInCents + other.amountInCents, currency: currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money._(amountInCents - other.amountInCents, currency: currency);
  }

  Money operator *(num multiplier) {
    final newCents = (amountInCents * multiplier).round();
    return Money._(newCents, currency: currency);
  }

  Money operator /(num divisor) {
    if (divisor == 0) throw ArgumentError('القسمة على صفر غير مسموحة في الحسابات المالية');
    final newCents = (amountInCents / divisor).round();
    return Money._(newCents, currency: currency);
  }

  bool operator >(Money other) {
    _assertSameCurrency(other);
    return amountInCents > other.amountInCents;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return amountInCents >= other.amountInCents;
  }

  bool operator <(Money other) {
    _assertSameCurrency(other);
    return amountInCents < other.amountInCents;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return amountInCents <= other.amountInCents;
  }

  void _assertSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('لا يمكن إجراء عمليات حسابية بين عملتين مختلفين: $currency و ${other.currency}');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          runtimeType == other.runtimeType &&
          amountInCents == other.amountInCents &&
          currency == other.currency;

  @override
  int get hashCode => amountInCents.hashCode ^ currency.hashCode;

  @override
  String toString() => '${toMajor.toStringAsFixed(2)} $currency';

  /// صفر للعملة
  static Money zero({String currency = 'IQD'}) => Money._(0, currency: currency);
}
