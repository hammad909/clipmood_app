import 'package:flutter/material.dart';

/// Change only this path if your background image has a different filename.
const String kAppBackgroundAsset =
    'assets/images/app_background_rear.png';

/// Adds one managed background behind the whole application Navigator.
///
/// Because this widget is used in MaterialApp.builder, it also appears
/// behind pushed routes and dialogs.
class AppBackground extends StatelessWidget {
  final Widget child;
  final String assetPath;
  final double imageOpacity;

  const AppBackground({
    super.key,
    required this.child,
    this.assetPath = kAppBackgroundAsset,
    this.imageOpacity = 0.88,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(
          color: Color(0xFF07091D),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: imageOpacity,
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x29000000),
                    Color(0x14000000),
                    Color(0x52000000),
                  ],
                  stops: [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.70, -0.85),
                  radius: 1.25,
                  colors: [
                    Color(0x1F9D68FF),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Makes ordinary Scaffolds and AppBars transparent so that the global
/// background remains visible without modifying every screen.
ThemeData withGlobalAppBackground(ThemeData baseTheme) {
  return baseTheme.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    appBarTheme: baseTheme.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
