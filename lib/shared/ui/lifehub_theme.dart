import 'package:flutter/material.dart';

abstract final class LifeHubTheme {
  static const seed = Color(0xFF8B79C6);

  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final light = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: light ? const Color(0xFFF8F5FF) : const Color(0xFF171420),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: colors.onSurface,
      ),
      cardTheme: CardThemeData(
        color: light
            ? const Color(0xEFFFFFFF)
            : colors.surfaceContainer.withValues(alpha: .88),
        surfaceTintColor: Colors.transparent,
        elevation: light ? 1.5 : 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: light
            ? Colors.white.withValues(alpha: .78)
            : colors.surfaceContainerHighest.withValues(alpha: .72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: light
            ? const Color(0xF5F6F1FB)
            : colors.surfaceContainer.withValues(alpha: .96),
        indicatorColor:
            light ? const Color(0xFFE6DEFF) : colors.primaryContainer,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: light ? const Color(0xFFFFFBFF) : colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

class LifeHubBackground extends StatelessWidget {
  const LifeHubBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF17131F), Color(0xFF211A31), Color(0xFF14242B)]
              : const [Color(0xFFFBF9FF), Color(0xFFF2ECFF), Color(0xFFEDF7FA)],
          stops: const [0, .56, 1],
        ),
      ),
      child: child,
    );
  }
}
