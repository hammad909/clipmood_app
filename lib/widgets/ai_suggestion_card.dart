import 'package:flutter/material.dart';

import '../models/ai_suggestion.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';

class AiSuggestionCard extends StatelessWidget {
  final AiSuggestion suggestion;
  final bool selected;
  final bool isSaving;
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback? onQuickSave;

  const AiSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onPreview,
    required this.onEdit,
    this.selected = false,
    this.isSaving = false,
    this.onSelectedChanged,
    this.onQuickSave,
  });

  Duration get _start => Duration(seconds: suggestion.startSeconds);
  Duration get _end => Duration(seconds: suggestion.endSeconds);
  int get _durationSeconds => suggestion.endSeconds - suggestion.startSeconds;

  Color _moodColor(BuildContext context) {
    switch (suggestion.mood.toLowerCase()) {
      case 'funny':
        return Colors.amberAccent;
      case 'sad':
        return Colors.lightBlueAccent;
      case 'emotional':
        return Colors.pinkAccent;
      case 'action':
        return Colors.deepOrangeAccent;
      case 'reaction':
        return Colors.purpleAccent;
      case 'hook':
        return Colors.cyanAccent;
      case 'info':
      case 'informative':
      case 'information':
        return Colors.tealAccent;
      case 'music':
      case 'exciting':
        return Colors.greenAccent;
      case 'viral':
        return Colors.orangeAccent;
      case 'weird':
      case 'strange':
        return Colors.indigoAccent;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData get _moodIcon {
    switch (suggestion.mood.toLowerCase()) {
      case 'funny':
        return Icons.sentiment_very_satisfied;
      case 'sad':
        return Icons.water_drop;
      case 'emotional':
        return Icons.favorite;
      case 'action':
        return Icons.local_fire_department;
      case 'reaction':
        return Icons.face_retouching_natural;
      case 'hook':
        return Icons.format_quote;
      case 'info':
      case 'informative':
      case 'information':
        return Icons.lightbulb_outline;
      case 'music':
      case 'exciting':
        return Icons.music_note;
      case 'viral':
        return Icons.local_fire_department;
      case 'weird':
      case 'strange':
        return Icons.psychology_alt;
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _moodColor(context);
    final confidencePercent = (suggestion.confidence.clamp(0.0, 1.0) * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.10) : AppColors.cardBackground,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(
          color: selected ? color.withValues(alpha: 0.55) : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onSelectedChanged != null)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs, top: 2),
                    child: Checkbox(
                      value: selected,
                      onChanged: isSaving
                          ? null
                          : (value) => onSelectedChanged?.call(value ?? false),
                      activeColor: color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: AppRadius.mdRadius,
                  ),
                  child: Icon(_moodIcon, color: color, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${TimeFormatter.formatDuration(_start)} - '
                        '${TimeFormatter.formatDuration(_end)}  ·  ${_durationSeconds}s',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    '$confidencePercent%',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                suggestion.reason.first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isSaving ? null : onPreview,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isSaving ? null : onEdit,
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ),
                if (onQuickSave != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isSaving ? null : onQuickSave,
                      icon: isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt, size: 16),
                      label: const Text('Save'),
                      style: FilledButton.styleFrom(
                        backgroundColor: color.withValues(alpha: 0.85),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}