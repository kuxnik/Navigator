import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF12161A);
  static const card = Color(0xFF1A1F24);
  static const cardBorder = Color(0xFF252C32);
  static const panel = Color(0xEB0E1114); // полупрозрачная панель поверх карты
  static const panelBorder = Color(0xFF2B3238);
  static const button = Color(0xFF232A30);
  static const text = Color(0xFFF1F3F5);
  static const text2 = Color(0xFFA9B1BA);
  static const accent = Color(0xFFFFB020); // цель
  static const blue = Color(0xFF4DA3FF); // я, мой трек
  static const blueActive = Color(0xFF1E4E80);
  static const green = Color(0xFF5FD38D);
  static const red = Color(0xFFFF5C4D);
  static const grey = Color(0xFF8A939C);
  static const purple = Color(0xFFC38BFF);
  static const halo = Color(0xFF0B0E10);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.blue,
    brightness: Brightness.dark,
  ).copyWith(surface: C.bg, primary: C.blue, secondary: C.accent);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.text),
    ),
    dividerColor: C.cardBorder,
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: C.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      labelStyle: TextStyle(color: C.text2),
    ),
  );
}

/// Квадратная кнопка поверх карты.
class MapButton extends StatelessWidget {
  const MapButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
    this.borderColor,
    this.size = 52,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;
  final Color? borderColor;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? C.blueActive : C.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor ?? (active ? C.blue : C.panelBorder)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: child ?? Icon(icon, color: C.text, size: 26)),
          ),
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.border});

  final Widget child;
  final EdgeInsets padding;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: C.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? C.panelBorder, width: border == null ? 1 : 1.5),
      ),
      child: child,
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: C.text2)),
        ],
      ),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}
