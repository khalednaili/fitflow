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

  /// Formats [amount] (in whole currency units) followed by its currency code,
  /// e.g. `format(50, 'TND') == '50 TND'`. Fractional amounts keep up to two
  /// decimals; whole amounts drop the decimal part.
  static String format(num amount, String? code) =>
      '${formatAmount(amount)} ${normalize(code)}';

  /// Like [format] but prefixes the currency symbol instead of appending the
  /// code, e.g. `formatSymbol(50, 'EUR') == '€50'`.
  static String formatSymbol(num amount, String? code) =>
      '${symbol(code)}${formatAmount(amount)}';

  /// Formats just the numeric part: whole numbers render without decimals,
  /// fractional values render with two decimals.
  static String formatAmount(num amount) {
    if (amount % 1 == 0) return amount.toInt().toString();
    return amount.toStringAsFixed(2);
  }
}
