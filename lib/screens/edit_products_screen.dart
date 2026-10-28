// lib/screens/edit_products_screen.dart
//
// «تعديل المواد وحذفها» صارت جزءاً من قائمة المواد الموحّدة (بطاقات المواد):
// نفس البحث والفلاتر، والتعديل بشاشة الإدخال نفسها، والحذف من السطر.
// يبقى هذا الملف ليعمل المسار القديم '/edit_products' كما هو.

import 'package:flutter/material.dart';

import '../inventory/item_card_screen.dart';

export '../inventory/product_delete.dart';

class EditProductsScreen extends StatelessWidget {
  static const routeName = '/edit-products';

  const EditProductsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ItemCardsListScreen();
}
