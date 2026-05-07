import 'package:flutter/services.dart';

/// Formats input as "+7 (XXX) XXX-XX-XX". Accepts pasted +7/8 prefixes.
/// Preserves the cursor position based on how many digits sit to the left
/// of it — so editing in the middle stops jumping to the end.
class RuPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Count digits before the new cursor position in the raw input — this
    // is the anchor that survives reformatting.
    final caretRaw = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCaret = _countDigits(newValue.text.substring(0, caretRaw));

    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('8')) digits = '7${digits.substring(1)}';
    if (!digits.startsWith('7')) digits = '7$digits';
    digits = digits.substring(0, digits.length.clamp(0, 11));

    final formatted = _format(digits);
    // Find the offset in [formatted] that corresponds to [digitsBeforeCaret].
    final newOffset = _offsetForDigit(formatted, digitsBeforeCaret);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  static String _format(String digits) {
    final buf = StringBuffer('+7');
    if (digits.length > 1) {
      buf.write(' (${digits.substring(1, digits.length.clamp(1, 4))}');
    }
    if (digits.length >= 4) {
      buf.write(') ${digits.substring(4, digits.length.clamp(4, 7))}');
    }
    if (digits.length >= 7) {
      buf.write('-${digits.substring(7, digits.length.clamp(7, 9))}');
    }
    if (digits.length >= 9) {
      buf.write('-${digits.substring(9, digits.length.clamp(9, 11))}');
    }
    return buf.toString();
  }

  static int _countDigits(String s) =>
      s.replaceAll(RegExp(r'\D'), '').length;

  /// Walk through [formatted] until we've passed [digitCount] digits.
  static int _offsetForDigit(String formatted, int digitCount) {
    if (digitCount <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) seen++;
      if (seen >= digitCount) return i + 1;
    }
    return formatted.length;
  }

  static String? extractE164(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return null;
    return '+$digits';
  }
}
