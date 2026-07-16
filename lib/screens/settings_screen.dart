import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final bool backgroundEnabled;
  final double backgroundOpacity;
  final ValueChanged<bool> onBackgroundEnabledChanged;
  final ValueChanged<double> onBackgroundOpacityChanged;
  final VoidCallback onResetAppearance;
  final VoidCallback onOpenSavedClips;
  final VoidCallback onOpenPremium;

  const SettingsScreen({
    super.key,
    required this.backgroundEnabled,
    required this.backgroundOpacity,
    required this.onBackgroundEnabledChanged,
    required this.onBackgroundOpacityChanged,
    required this.onResetAppearance,
    required this.onOpenSavedClips,
    required this.onOpenPremium,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _backgroundEnabled;
  late double _backgroundOpacity;

  @override
  void initState() {
    super.initState();
    _backgroundEnabled = widget.backgroundEnabled;
    _backgroundOpacity = widget.backgroundOpacity;
  }

  void _setBackgroundEnabled(bool value) {
    setState(() {
      _backgroundEnabled = value;
    });

    widget.onBackgroundEnabledChanged(value);
  }

  void _setBackgroundOpacity(double value) {
    setState(() {
      _backgroundOpacity = value;
    });

    widget.onBackgroundOpacityChanged(value);
  }

  void _resetAppearance() {
    setState(() {
      _backgroundEnabled = true;
      _backgroundOpacity = 0.90;
    });

    widget.onResetAppearance();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Appearance settings were reset.'),
      ),
    );
  }

  void _showAboutClipMood() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgRadius,
          ),
          title: const Row(
            children: [
              Icon(
                Icons.movie_creation_rounded,
                color: AppColors.secondary,
              ),
              SizedBox(width: AppSpacing.sm),
              Text('About ClipMood'),
            ],
          ),
          content: const Text(
            'ClipMood helps you discover eye-catching moments, '
            'trim videos, and save clips that are worth sharing.',
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            const _SettingsHeader(),
            const SizedBox(height: AppSpacing.lg),

            const _SectionTitle(
              title: 'Appearance',
              icon: Icons.palette_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            _GlassSettingsCard(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 2,
                  ),
                  value: _backgroundEnabled,
                  onChanged: _setBackgroundEnabled,
                  secondary: const _SettingsIcon(
                    icon: Icons.image_outlined,
                  ),
                  title: const Text(
                    'App background',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: const Text(
                    'Show the ClipMood background image on every screen.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
                const _SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const _SettingsIcon(
                        icon: Icons.opacity_rounded,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Background strength',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Adjust how strongly the image appears.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(_backgroundOpacity * 100).round()}%',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: _backgroundOpacity,
                  min: 0.35,
                  max: 1.0,
                  divisions: 13,
                  label: '${(_backgroundOpacity * 100).round()}%',
                  onChanged:
                      _backgroundEnabled ? _setBackgroundOpacity : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: _resetAppearance,
                    icon: const Icon(
                      Icons.restart_alt_rounded,
                    ),
                    label: const Text('Reset Appearance'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(
              title: 'Library & Plan',
              icon: Icons.folder_open_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            _GlassSettingsCard(
              children: [
                _SettingsActionTile(
                  icon: Icons.video_library_outlined,
                  title: 'Saved Clips',
                  subtitle: 'View and manage your exported clips.',
                  onTap: widget.onOpenSavedClips,
                ),
                const _SettingsDivider(),
                _SettingsActionTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Premium',
                  subtitle: 'Review premium features and future upgrades.',
                  trailingLabel: 'FREE',
                  onTap: widget.onOpenPremium,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(
              title: 'Video Tools',
              icon: Icons.tune_rounded,
            ),
            const SizedBox(height: AppSpacing.sm),
            const _GlassSettingsCard(
              children: [
                _InformationTile(
                  icon: Icons.auto_awesome,
                  title: 'AI Scan',
                  subtitle:
                      'The free AI scan currently supports videos from 1 to 5 minutes.',
                ),
                _SettingsDivider(),
                _InformationTile(
                  icon: Icons.content_cut_rounded,
                  title: 'Manual Trim',
                  subtitle:
                      'Manual trimming can be used for videos of any supported length.',
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(
              title: 'About',
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.sm),
            _GlassSettingsCard(
              children: [
                _SettingsActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About ClipMood',
                  subtitle: 'Learn what the application is designed to do.',
                  onTap: _showAboutClipMood,
                ),
                const _SettingsDivider(),
                const _InformationTile(
                  icon: Icons.verified_outlined,
                  title: 'App version',
                  subtitle: 'Development build',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.lgRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 18,
          sigmaY: 18,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: const Color(0xA817193A),
            borderRadius: AppRadius.lgRadius,
            border: Border.all(
              color: Colors.white.withAlpha(35),
            ),
          ),
          child: const Row(
            children: [
              _SettingsIcon(
                icon: Icons.settings_rounded,
                large: true,
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customize ClipMood',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage appearance, your library, and app information.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
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
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: AppColors.secondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GlassSettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _GlassSettingsCard({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.lgRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 16,
          sigmaY: 16,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xB3171938),
            borderRadius: AppRadius.lgRadius,
            border: Border.all(
              color: Colors.white.withAlpha(31),
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailingLabel;
  final VoidCallback onTap;

  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      onTap: onTap,
      leading: _SettingsIcon(
        icon: icon,
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      trailing: trailingLabel == null
          ? const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackgroundSubtle,
                    borderRadius: AppRadius.pillRadius,
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Text(
                    trailingLabel!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
    );
  }
}

class _InformationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InformationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: _SettingsIcon(
        icon: icon,
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          height: 1.3,
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  final IconData icon;
  final bool large;

  const _SettingsIcon({
    required this.icon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 52.0 : 42.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          large ? 17 : 14,
        ),
        gradient: AppGradients.hero,
        boxShadow: AppShadows.glow(
          AppColors.primary,
        ),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: large ? 25 : 20,
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: AppSpacing.md,
      endIndent: AppSpacing.md,
      color: AppColors.border,
    );
  }
}
