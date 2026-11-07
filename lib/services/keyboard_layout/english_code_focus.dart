// lib/services/keyboard_layout/english_code_focus.dart
//
// ⌨️ يربط أي خانة «رمز مادة» بالتحويل التلقائي إلى الإنجليزية (إعداد «لغة الكتابة في
// رمز المادة»): عند دخول الخانة تتحول لوحة المفاتيح للإنجليزية، وعند الخروج تعود اللغة
// التي كانت. الإعداد مطفأ ⇒ لا شيء.

import 'package:flutter/widgets.dart';

import '../product_codes.dart' show ItemCodeKeyboard;
import 'keyboard_layout.dart';

class EnglishCodeFocus {
  EnglishCodeFocus(this.node) {
    node.addListener(_onFocus);
  }

  final FocusNode node;
  int? _prev;
  bool _switched = false;

  void _onFocus() {
    if (node.hasFocus) {
      if (_switched || !ItemCodeKeyboard.forceEnglish) return;
      _prev = KeyboardLayoutSwitcher.switchToEnglish();
      _switched = true;
    } else {
      _leave();
    }
  }

  void _leave() {
    if (!_switched) return;
    _switched = false;
    KeyboardLayoutSwitcher.restore(_prev); // null = كانت إنجليزية أصلاً ⇒ لا شيء
    _prev = null;
  }

  /// قبل التخلص من الخانة: تُرجع اللغة إن كانت محوّلة
  void dispose() {
    _leave();
    node.removeListener(_onFocus);
  }
}
