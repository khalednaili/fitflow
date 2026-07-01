import 'package:flutter_test/flutter_test.dart';

import 'package:fit_flow/utils/currency.dart';

void main() {
  group('Currency.defaultCode', () {
    test('is TND (matches the documented schema default)', () {
      expect(Currency.defaultCode, 'TND');
    });
  });

  group('Currency.normalize', () {
    test('returns the default for null', () {
      expect(Currency.normalize(null), 'TND');
    });

    test('returns the default for empty or whitespace', () {
      expect(Currency.normalize(''), 'TND');
      expect(Currency.normalize('   '), 'TND');
    });

    test('upper-cases and trims a provided code', () {
      expect(Currency.normalize('  eur '), 'EUR');
    });

    test('leaves a valid code untouched', () {
      expect(Currency.normalize('USD'), 'USD');
    });
  });

  group('Currency.symbol', () {
    test('maps known codes to their symbol', () {
      expect(Currency.symbol('EUR'), '€');
      expect(Currency.symbol('USD'), '\$');
      expect(Currency.symbol('GBP'), '£');
    });

    test('falls back to the code for unknown currencies', () {
      expect(Currency.symbol('TND'), 'TND');
      expect(Currency.symbol('JPY'), 'JPY');
    });

    test('falls back to the default code for empty input', () {
      expect(Currency.symbol(''), 'TND');
      expect(Currency.symbol(null), 'TND');
    });
  });

  group('Currency.formatAmount', () {
    test('drops decimals for whole numbers', () {
      expect(Currency.formatAmount(50), '50');
      expect(Currency.formatAmount(50.0), '50');
    });

    test('keeps two decimals for fractional values', () {
      expect(Currency.formatAmount(50.5), '50.50');
      expect(Currency.formatAmount(29.99), '29.99');
    });

    test('handles zero', () {
      expect(Currency.formatAmount(0), '0');
    });

    test('formats negative amounts (e.g. overpaid balances)', () {
      expect(Currency.formatAmount(-400), '-400');
      expect(Currency.formatAmount(-12.5), '-12.50');
    });
  });

  group('Currency.format', () {
    test('appends the code, amount first', () {
      expect(Currency.format(50, 'TND'), '50 TND');
      expect(Currency.format(50, 'EUR'), '50 EUR');
    });

    test('uses the default code when none is given', () {
      expect(Currency.format(50, null), '50 TND');
      expect(Currency.format(50, ''), '50 TND');
    });

    test('formats fractional amounts', () {
      expect(Currency.format(12.5, 'USD'), '12.50 USD');
    });

    test('formats a negative balance with its code', () {
      expect(Currency.format(-400, 'TND'), '-400 TND');
    });
  });

  group('Currency.formatSymbol', () {
    test('prefixes a known symbol', () {
      expect(Currency.formatSymbol(50, 'EUR'), '€50');
      expect(Currency.formatSymbol(12.5, 'USD'), '\$12.50');
    });

    test('prefixes the code when no symbol is known', () {
      expect(Currency.formatSymbol(50, 'TND'), 'TND50');
    });

    test('uses the default for empty input', () {
      expect(Currency.formatSymbol(50, null), 'TND50');
    });
  });

  group('Currency.decimalsFor', () {
    test('TND uses 3 decimals (millimes)', () {
      expect(Currency.decimalsFor('TND'), 3);
    });

    test('other currencies use 2 decimals', () {
      expect(Currency.decimalsFor('EUR'), 2);
      expect(Currency.decimalsFor('USD'), 2);
    });

    test('null/empty resolves to TND → 3 decimals', () {
      expect(Currency.decimalsFor(null), 3);
      expect(Currency.decimalsFor(''), 3);
    });
  });

  group('Currency.format — TND millimes', () {
    test('fractional TND renders 3 decimals', () {
      expect(Currency.format(50.5, 'TND'), '50.500 TND');
      expect(Currency.format(9.876, 'TND'), '9.876 TND');
    });

    test('whole TND still drops decimals', () {
      expect(Currency.format(50, 'TND'), '50 TND');
    });

    test('non-TND currencies keep 2 decimals', () {
      expect(Currency.format(50.5, 'EUR'), '50.50 EUR');
    });
  });

  group('Currency.parse', () {
    test('parses a plain decimal', () {
      expect(Currency.parse('50.5'), 50.5);
      expect(Currency.parse('50'), 50);
    });

    test('accepts a comma as decimal separator', () {
      expect(Currency.parse('50,500'), 50.5);
      expect(Currency.parse('  12,25 '), 12.25);
    });

    test('returns null for empty or invalid input', () {
      expect(Currency.parse(''), isNull);
      expect(Currency.parse('   '), isNull);
      expect(Currency.parse('abc'), isNull);
      expect(Currency.parse(null), isNull);
    });
  });

  group('Currency.roundMillimes', () {
    test('rounds to 3 decimals', () {
      expect(Currency.roundMillimes(9.4051), 9.405);
      expect(Currency.roundMillimes(6.3327), 6.333);
    });

    test('leaves millime-precise values unchanged', () {
      expect(Currency.roundMillimes(19), 19);
      expect(Currency.roundMillimes(50.5), 50.5);
    });
  });
}
