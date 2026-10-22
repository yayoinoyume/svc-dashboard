import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// 深色底色固定为博客同款深蓝黑；壁纸动态色只参与强调色，
/// 避免系统壁纸把整页底色带偏。
class AppColors {
  static const surface = Color(0xFF0F111A);
  static const surfaceLow = Color(0xFF141824);
  static const surfaceContainer = Color(0xFF191E2C);
  static const surfaceHigh = Color(0xFF202737);
  static const onSurface = Color(0xFFE8EAF6);
  static const onSurfaceVariant = Color(0xFFA9B0C6);
  static const outline = Color(0xFF2A3346);
  static const seed = Color(0xFF9B7BB8);

  static const success = Color(0xFF7BC9A6);
  static const warning = Color(0xFFD9B36C);
  static const error = Color(0xFFE57373);
}

ThemeData buildTheme(ColorScheme? dynamicDark) {
  final base = dynamicDark ??
      ColorScheme.fromSeed(
        seedColor: AppColors.seed,
        brightness: Brightness.dark,
      );

  final scheme = base.copyWith(
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: const Color(0x1FA9B0C6),
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surfaceLow,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHigh,
    error: AppColors.error,
  );

  final textTheme = ThemeData.dark().textTheme.apply(
        bodyColor: AppColors.onSurface,
        displayColor: AppColors.onSurface,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: textTheme.copyWith(
      displaySmall: textTheme.displaySmall?.copyWith(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14),
      labelSmall: textTheme.labelSmall?.copyWith(
        fontSize: 11,
        color: AppColors.onSurfaceVariant,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.outline, width: 0.8),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 0.8,
      space: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 10,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? scheme.primary : AppColors.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 21,
          color: selected ? scheme.primary : AppColors.onSurfaceVariant,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
        side: WidgetStateProperty.all(
          const BorderSide(color: AppColors.outline, width: 0.8),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.16);
          }
          return AppColors.surfaceLow;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return AppColors.onSurfaceVariant;
        }),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: scheme.primary, width: 1.2),
      ),
      labelStyle: const TextStyle(color: AppColors.onSurfaceVariant),
      hintStyle: const TextStyle(color: Color(0xFF6E778F)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// 动态色优先，取不到时回退到博客主色。
class AppThemeBuilder extends StatelessWidget {
  final Widget Function(ThemeData theme) builder;

  const AppThemeBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return builder(buildTheme(darkDynamic));
      },
    );
  }
}
