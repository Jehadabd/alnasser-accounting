// widgets/line_item_focus_nodes.dart
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
