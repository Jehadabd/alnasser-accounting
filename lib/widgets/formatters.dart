// widgets/formatters.dart
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ThousandSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,##0', 'en_US');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow empty
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Keep only digits
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Parse to int and format
    final int value = int.parse(digitsOnly);
    final String newText = _formatter.format(value);

    // Calculate new cursor position from the right end
    final int selectionFromRight = newValue.text.length - newValue.selection.end;
    final int newSelectionIndex = newText.length - selectionFromRight;
    final int clampedSelectionIndex = newSelectionIndex.clamp(0, newText.length);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: clampedSelectionIndex),
    );
  }
}

class ThousandSeparatorDecimalInputFormatter extends TextInputFormatter {
  final NumberFormat _intFormatter = NumberFormat('#,##0', 'en_US');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // 1. Remove all non-numeric characters except one dot
    // Allows digits (0-9) and one decimal point
    String sanitized = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    
    // Handle multiple dots: keep only the first one
    if (sanitized.indexOf('.') != sanitized.lastIndexOf('.')) {
      final firstDotIndex = sanitized.indexOf('.');
      sanitized = sanitized.substring(0, firstDotIndex + 1) + 
                  sanitized.substring(firstDotIndex + 1).replaceAll('.', '');
    }

    // If input was just invalid chars (e.g. '*'), return oldValue or empty
    if (sanitized.isEmpty && newValue.text.isNotEmpty) {
      return oldValue; 
    }
    
    // Special case: just "." -> "0."
    if (sanitized == '.') {
      return const TextEditingValue(
        text: '0.',
        selection: TextSelection.collapsed(offset: 2),
      );
    }

    // Split integer and decimal parts
    final parts = sanitized.split('.');
    String intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : null;

    // Handle leading zeros for integer part
    if (intPart.isEmpty) {
      intPart = '0';
    } else if (intPart.length > 1 && intPart.startsWith('0')) {
      intPart = int.parse(intPart).toString();
    }

    String formatted;
    try {
      formatted = _intFormatter.format(int.parse(intPart));
    } catch (e) {
      // Fallback if parsing fails (shouldn't happen with sanitized input but safe to have)
      return oldValue;
    }

    if (decPart != null) {
      formatted += '.$decPart';
    }

    // Calculate selection position relative to the end to maintain position
    final int selectionIndexFromRight = newValue.text.length - newValue.selection.end;
    final int newSelectionIndex = formatted.length - selectionIndexFromRight;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: newSelectionIndex.clamp(0, formatted.length),
      ),
    );
  }
}


