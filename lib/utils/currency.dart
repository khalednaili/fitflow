/// Centralized currency handling for the app.
///
/// **Storage unit:** monetary amounts are stored as *whole* integer units of
/// the currency (e.g. `50` means 50 TND), **not** minor units / cents. All
/// formatting and the app-wide default currency live here so that display is
/// consistent across every screen and never hard-codes a symbol or code.
abstract final class Currency {
  /// App-wide default currency (ISO 4217). Used as the fallback whenever a
  /// record has no currency stored. Must match the documented default in
  /// `database_schema.dart`.
  static const String defaultCode = 'TND';

  /// Display symbols for well-known ISO 4217 codes. Codes not listed here
  /// (including `TND`) intentionally fall back to the code itself.
  static const Map<String, String> _symbols = {
    'EUR': '€',
    'USD': '\$',
    'GBP': '£',
  };

  /// Normalizes a possibly-null/empty/whitespace code to a non-empty,
  /// upper-cased ISO 4217 code, defaulting to [defaultCode].
  static String normalize(String? code) {
    final c = (code ?? '').trim().toUpperCase();
    return c.isEmpty ? defaultCode : c;
  }

  /// Returns the display symbol for [code], or the normalized code itself when
  /// no symbol is known (e.g. `"TND"`).
  static String symbol(String? code) {
    final c = normalize(code);
    return _symbols[c] ?? c;
  }

  /// Number of decimal places conventionally shown for [code]. The Tunisian
  /// dinar is divided into 1000 millimes, so it uses 3 decimals; everything
  /// else uses 2.
  static int decimalsFor(String? code) => normalize(code) == 'TND' ? 3 : 2;

  /// Formats [amount] followed by its currency code, e.g.
  /// `format(50, 'TND') == '50 TND'`, `format(50.5, 'TND') == '50.5 TND'`.
  /// Fractional amounts keep up to [decimalsFor] the code's decimals (3 for
  /// TND); whole amounts drop the decimal part.
  static String format(num amount, String? code) =>
      '${formatAmount(amount, maxDecimals: decimalsFor(code))} ${normalize(code)}';

  /// Like [format] but prefixes the currency symbol instead of appending the
  /// code, e.g. `formatSymbol(50, 'EUR') == '€50'`.
  static String formatSymbol(num amount, String? code) =>
      '${symbol(code)}${formatAmount(amount, maxDecimals: decimalsFor(code))}';

  /// Formats just the numeric part: whole numbers render without decimals,
  /// fractional values render with exactly [maxDecimals] decimals (2 by
  /// default, 3 for TND millimes — see [format]).
  static String formatAmount(num amount, {int maxDecimals = 2}) {
    if (amount % 1 == 0) return amount.toInt().toString();
    return amount.toStringAsFixed(maxDecimals);
  }

  /// Parses a user-entered amount, accepting both `.` and `,` as the decimal
  /// separator (Tunisian keyboards often produce `,`). Returns null when
  /// [input] is empty or not a valid number.
  static num? parse(String? input) {
    final t = (input ?? '').trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  /// Rounds [amount] to millime precision (3 decimals) to avoid floating-point
  /// drift after tax/discount arithmetic on fractional dinars.
  static num roundMillimes(num amount) => (amount * 1000).round() / 1000;
}
