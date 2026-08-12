// models/line_item_focus_nodes.dart
// إدارة FocusNode لكل صف
import 'package:flutter/material.dart';

class LineItemFocusNodes {
  FocusNode details = FocusNode();
  FocusNode quantity = FocusNode();
  FocusNode price = FocusNode();
  void dispose() {
    details.dispose();
    quantity.dispose();
    price.dispose();
  }
} 