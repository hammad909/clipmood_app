import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'saved_clips_screen.dart';

class PremiumComingSoonScreen extends StatelessWidget {
  const PremiumComingSoonScreen({super.key});

  void _onBottomNavSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SavedClipsScreen()),
        );
        break;
      case 2:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Plans'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: (index) => _onBottomNavSelected(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Premium',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 660;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                compact ? AppSpacing.md : AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(compact: compact),
                  SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: constraints.maxWidth - (AppSpacing.xl * 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            _PlanDetailsCard(
                              title: 'Free',
                              price: r'$0',
                              badge: 'Available now',
                              icon: Icons.auto_awesome,
                              highlighted: true,
                              features: [
                                'AI clip detection for 1–5 minute videos',
                                'Manual trim for any video length',
                                'Mood/category scoring for interesting moments',
                                'Save clips locally to your library',
                              ],
                            ),
                            SizedBox(height: AppSpacing.md),
                            _PlanDetailsCard(
                              title: 'Premium',
                              price: r'$49',
                              badge: 'Coming soon',
                              icon: Icons.workspace_premium,
                              highlighted: false,
                              features: [
                                'Paste YouTube or supported platform links',
                                'Import content directly from supported platforms',
                                'More powerful AI for better clip precision',
                                'Direct clip discovery from long-form videos',
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.upcoming),
                    label: Text('Premium coming in next update'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: AppRadius.lgRadius,
        boxShadow: AppShadows.glow(AppColors.primary),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 46 : 54,
            height: compact ? 46 : 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: AppRadius.mdRadius,
            ),
            child: Icon(
              Icons.workspace_premium,
              color: Colors.white,
              size: compact ? 24 : 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Premium is on its way',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'No buying system yet — this is an info preview for the next update.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanDetailsCard extends StatelessWidget {
  final String title;
  final String price;
  final String badge;
  final IconData icon;
  final bool highlighted;
  final List<String> features;

  const _PlanDetailsCard({
    required this.title,
    required this.price,
    required this.badge,
    required this.icon,
    required this.highlighted,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.cardBackgroundSubtle : AppColors.cardBackground,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(
          color: highlighted ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Icon(
                  icon,
                  color: highlighted ? AppColors.primary : AppColors.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                price,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: highlighted ? AppColors.primary : AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    highlighted ? Icons.check_circle : Icons.schedule,
                    color: highlighted ? AppColors.success : AppColors.secondary,
                    size: 17,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
