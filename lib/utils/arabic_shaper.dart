
/// Helper class to handle Arabic text shaping for PDF rendering.
/// This connects isolated Arabic characters into their proper Initial, Medial, Final, or Isolated forms.
/// We rely on the PDF renderer's RTL support for character reordering.
class ArabicShaper {
  static const Map<String, List<String>> _forms = {
    '\u0622': ['\uFE81', '\uFE81', '\uFE82', '\uFE82'], // ALEF WITH MADDA ABOVE
    '\u0623': ['\uFE83', '\uFE83', '\uFE84', '\uFE84'], // ALEF WITH HAMZA ABOVE
    '\u0624': ['\uFE85', '\uFE85', '\uFE86', '\uFE86'], // WAW WITH HAMZA ABOVE
    '\u0625': ['\uFE87', '\uFE87', '\uFE88', '\uFE88'], // ALEF WITH HAMZA BELOW
    '\u0626': ['\uFE89', '\uFE8B', '\uFE8C', '\uFE8A'], // YEH WITH HAMZA ABOVE
    '\u0627': ['\uFE8D', '\uFE8D', '\uFE8E', '\uFE8E'], // ALEF
    '\u0628': ['\uFE8F', '\uFE91', '\uFE92', '\uFE90'], // BEH
    '\u0629': ['\uFE93', '\uFE93', '\uFE94', '\uFE94'], // TEH MARBUTA
    '\u062A': ['\uFE95', '\uFE97', '\uFE98', '\uFE96'], // TEH
    '\u062B': ['\uFE99', '\uFE9B', '\uFE9C', '\uFE9A'], // THEH
    '\u062C': ['\uFE9D', '\uFE9F', '\uFEA0', '\uFE9E'], // JEEM
    '\u062D': ['\uFEA1', '\uFEA3', '\uFEA4', '\uFEA2'], // HAH
    '\u062E': ['\uFEA5', '\uFEA7', '\uFEA8', '\uFEA6'], // KHAH
    '\u062F': ['\uFEA9', '\uFEA9', '\uFEAA', '\uFEAA'], // DAL
    '\u0630': ['\uFEAB', '\uFEAB', '\uFEAC', '\uFEAC'], // THAL
    '\u0631': ['\uFEAD', '\uFEAD', '\uFEAE', '\uFEAE'], // REH
    '\u0632': ['\uFEAF', '\uFEAF', '\uFEB0', '\uFEB0'], // ZAIN
    '\u0633': ['\uFEB1', '\uFEB3', '\uFEB4', '\uFEB2'], // SEEN
    '\u0634': ['\uFEB5', '\uFEB7', '\uFEB8', '\uFEB6'], // SHEEN
    '\u0635': ['\uFEB9', '\uFEBB', '\uFEBC', '\uFEBA'], // SAD
    '\u0636': ['\uFEBD', '\uFEBF', '\uFEC0', '\uFEBE'], // DAD
    '\u0637': ['\uFEC1', '\uFEC3', '\uFEC4', '\uFEC2'], // TAH
    '\u0638': ['\uFEC5', '\uFEC7', '\uFEC8', '\uFEC6'], // ZAH
    '\u0639': ['\uFEC9', '\uFECB', '\uFECC', '\uFECA'], // AIN
    '\u063A': ['\uFECD', '\uFECF', '\uFED0', '\uFECE'], // GHAIN
    '\u0641': ['\uFED1', '\uFED3', '\uFED4', '\uFED2'], // FEH
    '\u0642': ['\uFED5', '\uFED7', '\uFED8', '\uFED6'], // QAF
    '\u0643': ['\uFED9', '\uFEDB', '\uFEDC', '\uFEDA'], // KAF
    '\u0644': ['\uFEDD', '\uFEDF', '\uFEE0', '\uFEDE'], // LAM
    '\u0645': ['\uFEE1', '\uFEE3', '\uFEE4', '\uFEE2'], // MEEM
    '\u0646': ['\uFEE5', '\uFEE7', '\uFEE8', '\uFEE6'], // NOON
    '\u0647': ['\uFEE9', '\uFEEB', '\uFEEC', '\uFEEA'], // HEH
    '\u0648': ['\uFEED', '\uFEED', '\uFEEE', '\uFEEE'], // WAW
    '\u0649': ['\uFEEF', '\uFEEF', '\uFEF0', '\uFEF0'], // ALEF MAKSURA
    '\u064A': ['\uFEF1', '\uFEF3', '\uFEF4', '\uFEF2'], // YEH
    '\u0621': ['\uFE80', '\uFE80', '\uFE80', '\uFE80'], // HAMZA
  };

  static const Map<String, List<String>> _ligatures = {
    '\u0644\u0622': ['\uFEF5', '\uFEF5', '\uFEF6', '\uFEF6'], // LAM WITH ALEF MADDA
    '\u0644\u0623': ['\uFEF7', '\uFEF7', '\uFEF8', '\uFEF8'], // LAM WITH ALEF HAMZA ABOVE
    '\u0644\u0625': ['\uFEF9', '\uFEF9', '\uFEFA', '\uFEFA'], // LAM WITH ALEF HAMZA BELOW
    '\u0644\u0627': ['\uFEFB', '\uFEFB', '\uFEFC', '\uFEFC'], // LAM WITH ALEF
  };

  static bool _isConnectableAfter(String char) {
    // Non-connecting following characters: Alef, Dal, Thal, Reh, Zain, Waw, etc.
    final nonConnectingAfter = [
      '\u0622', '\u0623', '\u0624', '\u0625', '\u0627',
      '\u062F', '\u0630', '\u0631', '\u0632', '\u0648', '\u0649', '\u0629', '\u0621'
    ];
    return _forms.containsKey(char) && !nonConnectingAfter.contains(char);
  }

  static bool _isConnectableBefore(String char) {
    // Hamza doesn't connect before.
    if (char == '\u0621') return false;
    return _forms.containsKey(char);
  }

  /// Shapes Arabic text. Returns shaped characters in logical order.
  /// Use this with Arabic-capable renderers (set to RTL).
  static String shape(String text) {
    if (text.isEmpty) return text;

    List<String> result = [];
    List<String> chars = text.split('');

    for (int i = 0; i < chars.length; i++) {
      String current = chars[i];
      
      // Handle Lam-Alef Ligature
      if (current == '\u0644' && i < chars.length - 1) {
        String next = chars[i + 1];
        String combined = current + next;
        if (_ligatures.containsKey(combined)) {
          bool prevConnects = false;
          if (i > 0) {
            String prev = chars[i - 1];
            if (_isConnectableAfter(prev)) prevConnects = true;
          }
          
          int formIdx = prevConnects ? 2 : 0; 
          result.add(_ligatures[combined]![formIdx]);
          i++; 
          continue;
        }
      }

      if (!_forms.containsKey(current)) {
        result.add(current);
        continue;
      }

      bool prevConnects = false;
      if (i > 0) {
        String prev = chars[i - 1];
        if (_isConnectableAfter(prev)) prevConnects = true;
      }

      bool nextConnects = false;
      if (i < chars.length - 1) {
        String next = chars[i + 1];
        if (_isConnectableBefore(next) && _isConnectableAfter(current)) {
          nextConnects = true;
        }
      }

      int formIdx = 0;
      if (!prevConnects && !nextConnects) formIdx = 0; // Isolated
      else if (!prevConnects && nextConnects) formIdx = 1; // Initial
      else if (prevConnects && nextConnects) formIdx = 2; // Medial
      else if (prevConnects && !nextConnects) formIdx = 3; // Final

      result.add(_forms[current]![formIdx]);
    }

    // Return in LOGICAL order. The PDF renderer will handle RTL reversal.
    return result.join('');
  }
}
