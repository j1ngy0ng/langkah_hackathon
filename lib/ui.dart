import 'dart:math' as math;
import 'package:flutter/material.dart';

const navy = Color(0xFF20352F),
    green = Color(0xFF17624B),
    cream = Color(0xFFF7F8F2),
    lime = Color(0xFFD9EF9C),
    muted = Color(0xFF68766D),
    line = Color(0xFFE5EADF),
    orange = Color(0xFFF3B37A);

ThemeData langkahTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: cream,
  colorScheme: ColorScheme.fromSeed(
    seedColor: green,
    primary: green,
    secondary: navy,
    surface: Colors.white,
  ),
  textTheme: ThemeData().textTheme.apply(bodyColor: navy, displayColor: navy),
  appBarTheme: const AppBarTheme(
    backgroundColor: cream,
    foregroundColor: navy,
    centerTitle: false,
    scrolledUnderElevation: 0,
    elevation: 0,
    titleTextStyle: TextStyle(
      fontFamily: 'Roboto',
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: navy,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: cream,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    labelStyle: const TextStyle(color: muted, fontSize: 14),
    prefixIconColor: muted,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: green, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      disabledBackgroundColor: line,
      disabledForegroundColor: muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: line),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    titleTextStyle: TextStyle(
      fontFamily: 'Roboto',
      color: navy,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
    subtitleTextStyle: TextStyle(
      fontFamily: 'Roboto',
      color: muted,
      fontSize: 13,
      height: 1.5,
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: lime,
    height: 76,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? green : muted,
      ),
    ),
  ),
  dividerTheme: const DividerThemeData(color: line, space: 24),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: navy,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: green,
      borderRadius: BorderRadius.circular(size * .34),
    ),
    child: Icon(Icons.directions_walk_rounded, color: lime, size: size * .66),
  );
}

Widget iconBadge(
  IconData icon, {
  Color color = green,
  Color background = cream,
  double size = 48,
}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Icon(icon, color: color, size: size * .48),
);

Widget sectionTitle(String title, {String? detail}) => Padding(
  padding: const EdgeInsets.only(top: 10, bottom: 14),
  child: Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 4,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
      if (detail != null)
        Text(detail, style: const TextStyle(color: muted, fontSize: 12)),
    ],
  ),
);

IconData shopIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('coffee') || lower.contains('matcha')) {
    return Icons.local_cafe_outlined;
  }
  if (lower.contains('scoop')) return Icons.icecream_outlined;
  if (lower.contains('decathlon')) return Icons.sports_outlined;
  if (lower.contains('grocer')) return Icons.shopping_basket_outlined;
  if (lower.contains('huckleberry')) return Icons.bakery_dining_outlined;
  return Icons.storefront_outlined;
}

class WalkIllustration extends StatelessWidget {
  const WalkIllustration({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 138,
      height: 145,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _WalkPathPainter())),
          Positioned(
            top: 18,
            left: 6,
            child: iconBadge(
              Icons.storefront_outlined,
              color: navy,
              background: orange,
              size: 42,
            ),
          ),
          Positioned(
            bottom: 5,
            right: 5,
            child: iconBadge(
              Icons.local_offer_outlined,
              color: navy,
              background: lime,
              size: 42,
            ),
          ),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: lime,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: green, width: 5),
            ),
            child: const Icon(
              Icons.directions_walk_rounded,
              color: green,
              size: 42,
            ),
          ),
        ],
      ),
    ),
  );
}

class _WalkPathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * .43,
      paint,
    );
    final path = Path()
      ..moveTo(25, 45)
      ..cubicTo(130, -10, 10, 155, 118, 111);
    final metric = path.computeMetrics().first;
    paint
      ..color = lime.withValues(alpha: .65)
      ..strokeWidth = 3;
    for (double d = 0; d < metric.length; d += 10) {
      canvas.drawPath(
        metric.extractPath(d, math.min(d + 4, metric.length)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WalkPathPainter oldDelegate) => false;
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Container(
            width: 94,
            height: 94,
            decoration: const BoxDecoration(
              color: cream,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 42, color: green),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.6, fontSize: 14),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}

class StatTile extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: green, size: 24),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: muted, fontSize: 13)),
        ],
      ),
    ),
  );
}

class TicketCard extends StatelessWidget {
  final String title, merchant, footer, status;
  final VoidCallback onTap;
  const TicketCard({
    super.key,
    required this.title,
    required this.merchant,
    required this.footer,
    required this.status,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconBadge(
                    shopIcon(merchant),
                    background: lime.withValues(alpha: .4),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: green,
                  ),
                ],
              ),
            ),
            CustomPaint(
              painter: _TicketDivider(),
              child: const SizedBox(width: double.infinity, height: 12),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'Available'
                          ? lime.withValues(alpha: .4)
                          : cream,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: status == 'Available' ? green : muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    footer,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TicketDivider extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double x = 14; x < size.width - 14; x += 8) {
      canvas.drawLine(Offset(x, 6), Offset(x + 4, 6), paint);
    }
    paint.color = cream;
    canvas.drawCircle(const Offset(0, 6), 7, paint);
    canvas.drawCircle(Offset(size.width, 6), 7, paint);
  }

  @override
  bool shouldRepaint(_TicketDivider oldDelegate) => false;
}
