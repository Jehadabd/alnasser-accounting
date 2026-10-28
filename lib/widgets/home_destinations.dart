// lib/widgets/home_destinations.dart
//
// 🧭 أزرار الرئيسية في مكان واحد: الاسم والأيقونة واللون والشرح والاختصار.
// تستعملها الشاشة الرئيسية وشريط التنقل الجانبي معاً، فيبقى لكل قسم لون
// وأيقونة واحدة في كل مكان (كانت تختلف بين الشاشتين).

import 'package:flutter/material.dart';

class HomeDest {
  const HomeDest(this.title, this.icon, this.color, {this.subtitle, this.shortcut, this.route});
  final String title;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final String? shortcut;
  final String? route;
}

class HomeDests {
  HomeDests._();

  // ── العمل اليومي ──
  static const pos = HomeDest('الكاشير', Icons.point_of_sale_rounded, Color(0xFFEA580C),
      subtitle: 'بيع سريع بالباركود', shortcut: 'F1', route: '/pos');
  static const createInvoice = HomeDest('إنشاء فاتورة', Icons.receipt_long_rounded, Color(0xFF2563EB),
      subtitle: 'فاتورة بيع نقد أو دين', shortcut: 'F2', route: '/create_invoice');
  static const debtRegister = HomeDest('سجل الديون', Icons.menu_book_rounded, Color(0xFF7C3AED),
      subtitle: 'العملاء وأرصدتهم وتسديداتهم', shortcut: 'F3', route: '/debt_register');
  static const editInvoices = HomeDest('تعديل الفواتير', Icons.edit_note_rounded, Color(0xFF9A6B4F),
      subtitle: 'بحث وتعديل وإرجاع', shortcut: 'F5', route: '/edit_invoices');
  static const productEntry = HomeDest('إدخال بضاعة', Icons.add_box_rounded, Color(0xFF16A34A),
      subtitle: 'مواد جديدة وكميات وأسعار', shortcut: 'F6', route: '/product_entry');
  static const suppliers = HomeDest('الموردون', Icons.local_shipping_rounded, Color(0xFF0E7490),
      subtitle: 'فواتير الشراء والدفعات', shortcut: 'F8', route: '/suppliers');

  // ── الأقسام ──
  static const sales = HomeDest('المبيعات', Icons.storefront_rounded, Color(0xFF0E7C61),
      subtitle: 'مرتجعات، عروض أسعار، طلبات', route: '/sales_hub');
  static const inventory = HomeDest('المخزون', Icons.warehouse_rounded, Color(0xFF5B3CC4),
      subtitle: 'بطاقات المواد، الجرد، التقارير', route: '/inventory_hub');
  static const accounting = HomeDest('المحاسبة', Icons.account_balance_rounded, Color(0xFF0F3460),
      subtitle: 'السندات، الصناديق، الدفاتر', shortcut: 'F4', route: '/accounting');
  static const reports = HomeDest('التقارير', Icons.insights_rounded, Color(0xFFD97706),
      subtitle: 'يومية، شهرية، أرباح، قوائم مالية', route: '/reports');
  static const settings = HomeDest('الإعدادات', Icons.settings_rounded, Color(0xFF64748B),
      subtitle: 'الطابعات، الموظفون، النسخ الاحتياطي', route: '/general_settings');
}
