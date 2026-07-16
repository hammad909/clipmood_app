import 'dart:ui';

import 'package:flutter/material.dart';

/// Main five-tab application shell.
///
/// Page order:
/// 0 Home
/// 1 AI Clips
/// 2 Create
/// 3 Saved
/// 4 Settings
class MainNavigationShell extends StatefulWidget {
  final List<Widget> pages;
  final int initialIndex;

  /// When provided, the center plus button runs this callback rather than
  /// switching to page index 2.
  final VoidCallback? onCreatePressed;

  const MainNavigationShell({
    super.key,
    required this.pages,
    this.initialIndex = 0,
    this.onCreatePressed,
  }) : assert(
          pages.length == 5,
          'MainNavigationShell requires exactly five pages.',
        );

  @override
  State<MainNavigationShell> createState() =>
      _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;

  static const List<_MainNavItem> _items = [
    _MainNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _MainNavItem(
      label: 'AI Clips',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
    _MainNavItem(
      label: 'Create',
      icon: Icons.add,
      selectedIcon: Icons.add,
      isCenterAction: true,
    ),
    _MainNavItem(
      label: 'Saved',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
    ),
    _MainNavItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
  }

  void _handleTap(int index) {
    if (index == 2 && widget.onCreatePressed != null) {
      widget.onCreatePressed!();
      return;
    }

    if (_currentIndex == index) return;

    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: _currentIndex,
        children: widget.pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: AppGlassBottomNavigationBar(
          items: _items,
          currentIndex: _currentIndex,
          onTap: _handleTap,
        ),
      ),
    );
  }
}

class AppGlassBottomNavigationBar extends StatelessWidget {
  final List<_MainNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppGlassBottomNavigationBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final secondary = colorScheme.secondary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xD8151738),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withAlpha(38),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(70),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: primary.withAlpha(35),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = currentIndex == index;

              if (item.isCenterAction) {
                return Expanded(
                  child: _CenterCreateButton(
                    selected: selected,
                    primary: primary,
                    secondary: secondary,
                    onTap: () => onTap(index),
                  ),
                );
              }

              return Expanded(
                child: _NavigationItemButton(
                  item: item,
                  selected: selected,
                  activeColor: primary,
                  onTap: () => onTap(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavigationItemButton extends StatelessWidget {
  final _MainNavItem item;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  const _NavigationItemButton({
    required this.item,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Colors.white.withAlpha(145);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withAlpha(28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 220),
                scale: selected ? 1.08 : 1,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 23,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: selected ? activeColor : inactiveColor,
                  fontSize: 10,
                  height: 1,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterCreateButton extends StatelessWidget {
  final bool selected;
  final Color primary;
  final Color secondary;
  final VoidCallback onTap;

  const _CenterCreateButton({
    required this.selected,
    required this.primary,
    required this.secondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Create',
      child: Center(
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary,
                  secondary,
                ],
              ),
              border: Border.all(
                color: Colors.white.withAlpha(selected ? 110 : 65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withAlpha(105),
                  blurRadius: selected ? 24 : 18,
                  spreadRadius: selected ? 2 : 0,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
        ),
      ),
    );
  }
}

class _MainNavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isCenterAction;

  const _MainNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.isCenterAction = false,
  });
}
