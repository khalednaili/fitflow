import 'package:flutter/material.dart';

const Color _seed = Color(0xFF0F766E);
const Color _secondarySeed = Color(0xFFF97316);
const Color _tertiarySeed = Color(0xFFEAB308);

ThemeData buildAppTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: _seed,
    secondary: _secondarySeed,
    tertiary: _tertiarySeed,
  );
  final colorScheme = base.copyWith(
    primary: const Color(0xFF0F766E),
    onPrimary: Colors.white,
    secondary: const Color(0xFFF97316),
    onSecondary: Colors.white,
    tertiary: const Color(0xFFEAB308),
    onTertiary: const Color(0xFF1F2937),
    surface: const Color(0xFFF8FAFC),
    surfaceContainerLowest: Colors.white,
    outline: const Color(0xFFCBD5E1),
  );

  const radius = BorderRadius.all(Radius.circular(12));

  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colorScheme.outline),
  );

  final focusedBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colorScheme.primary, width: 2),
  );

  final errorBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colorScheme.error, width: 1.5),
  );

  final focusedErrorBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colorScheme.error, width: 2),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: colorScheme.surfaceContainerLowest,
      foregroundColor: colorScheme.onSurface,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainerLowest,
      height: 72,
      elevation: 2,
      indicatorColor: colorScheme.primary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: colorScheme.primary);
        }
        return IconThemeData(color: colorScheme.onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      margin: const EdgeInsets.all(0),
      color: colorScheme.surfaceContainerLowest,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      surfaceTintColor: colorScheme.primary.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: colorScheme.primary, width: 3),
      ),
      dividerColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.secondary,
      foregroundColor: colorScheme.onSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 1,
      backgroundColor: const Color(0xFF111827),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.4)),
      backgroundColor: colorScheme.surfaceContainerLowest,
      selectedColor: colorScheme.primary.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outline.withValues(alpha: 0.28),
      thickness: 1,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.outline.withValues(alpha: 0.3),
        disabledForegroundColor: colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      iconColor: colorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: focusedErrorBorder,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle:
          TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w500),
      hintStyle:
          TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      prefixIconColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
