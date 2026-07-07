import 'package:flutter/material.dart';

import '../models/ai_scan_progress.dart';
import '../theme/app_theme.dart';

/// A professional, at-a-glance view of the local AI scan pipeline.
///
/// Instead of a single progress bar, this shows every stage the scan will
/// pass through, marks which ones are done, which one is active right now,
/// and how far along the whole scan is overall — so waiting feels informative
/// rather than a black box.
class AiScanProgressPanel extends StatelessWidget {
  static const List<AiScanStage> _steps = [
    AiScanStage.loadingVideo,
    AiScanStage.audioEvents,
    AiScanStage.audioPeaks,
    AiScanStage.transcription,
    AiScanStage.visualSignals,
    AiScanStage.faceReactions,
    AiScanStage.scoring,
  ];

  final AiScanProgress progress;
  final VoidCallback onCancel;

  const AiScanProgressPanel({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  static IconData _iconFor(AiScanStage stage) {
    switch (stage) {
      case AiScanStage.loadingVideo:
        return Icons.movie_outlined;
      case AiScanStage.audioEvents:
        return Icons.graphic_eq;
      case AiScanStage.audioPeaks:
        return Icons.equalizer;
      case AiScanStage.transcription:
        return Icons.subtitles_outlined;
      case AiScanStage.visualSignals:
        return Icons.visibility_outlined;
      case AiScanStage.faceReactions:
        return Icons.emoji_emotions_outlined;
      case AiScanStage.scoring:
        return Icons.leaderboard_outlined;
      default:
        return Icons.auto_awesome;
    }
  }

  int get _currentIndex => _steps.indexOf(progress.stage);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final isIndeterminate = progress.progress <= 0 || progress.progress >= 1;
    final percent = (progress.progress.clamp(0.0, 1.0) * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: isIndeterminate ? null : progress.progress,
                      strokeWidth: 4,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.stage.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      progress.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    if (progress.detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        progress.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardBackgroundSubtle,
              borderRadius: AppRadius.mdRadius,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildStepRows(color),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: progress.canCancel ? onCancel : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Cancel Scan'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStepRows(Color color) {
    final currentIndex = _currentIndex;
    final allDone = progress.stage == AiScanStage.completed;

    return List.generate(_steps.length, (index) {
      final stage = _steps[index];
      final isDone = allDone || currentIndex > index;
      final isActive = !allDone && currentIndex == index;
      final isLast = index == _steps.length - 1;

      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
        child: Row(
          children: [
            _StepDot(
              icon: _iconFor(stage),
              isDone: isDone,
              isActive: isActive,
              color: color,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                stage.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isDone || isActive ? null : AppColors.textFaint,
                ),
              ),
            ),
            if (isActive)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else if (isDone)
              const Icon(Icons.check_circle, size: 16, color: AppColors.success),
          ],
        ),
      );
    });
  }
}

class _StepDot extends StatelessWidget {
  final IconData icon;
  final bool isDone;
  final bool isActive;
  final Color color;

  const _StepDot({
    required this.icon,
    required this.isDone,
    required this.isActive,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final background = isDone
        ? AppColors.success.withValues(alpha: 0.15)
        : isActive
            ? color.withValues(alpha: 0.15)
            : AppColors.surfaceElevated;

    final iconColor = isDone
        ? AppColors.success
        : isActive
            ? color
            : AppColors.textFaint;

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: Icon(icon, size: 14, color: iconColor),
    );
  }
}