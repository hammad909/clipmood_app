import 'package:flutter/material.dart';

import '../services/ai_clip_analyzer_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_formatter.dart';

enum _EntryStatusFilter { all, selected, skipped }

class AiDebugResultsScreen extends StatefulWidget {
  final List<AiDebugEntry> entries;

  const AiDebugResultsScreen({
    super.key,
    required this.entries,
  });

  @override
  State<AiDebugResultsScreen> createState() => _AiDebugResultsScreenState();
}

class _AiDebugResultsScreenState extends State<AiDebugResultsScreen> {
  _EntryStatusFilter _statusFilter = _EntryStatusFilter.all;
  String _selectedCategory = 'All';
  String _selectedSource = 'All';

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;
    final acceptedCount = widget.entries.where((entry) => entry.accepted).length;
    final skippedCount = widget.entries.length - acceptedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Scan Report'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: widget.entries.isEmpty
            ? const _EmptyReportState()
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        0,
                      ),
                      child: _ReportHeader(
                        totalCount: widget.entries.length,
                        selectedCount: acceptedCount,
                        skippedCount: skippedCount,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        14,
                        AppSpacing.lg,
                        0,
                      ),
                      child: _buildFilters(),
                    ),
                  ),
                  if (entries.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _NoFilteredResultsState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        14,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == entries.length - 1 ? 0 : AppSpacing.md,
                              ),
                              child: _AiScanEntryCard(entry: entries[index]),
                            );
                          },
                          childCount: entries.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildFilters() {
    final categories = _categoryFilters;
    final sources = _sourceFilters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterCard(
          title: 'Status',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _FilterChipButton(
                label: 'All',
                selected: _statusFilter == _EntryStatusFilter.all,
                onTap: () => setState(() => _statusFilter = _EntryStatusFilter.all),
              ),
              _FilterChipButton(
                label: 'Selected',
                selected: _statusFilter == _EntryStatusFilter.selected,
                onTap: () => setState(() => _statusFilter = _EntryStatusFilter.selected),
              ),
              _FilterChipButton(
                label: 'Skipped',
                selected: _statusFilter == _EntryStatusFilter.skipped,
                onTap: () => setState(() => _statusFilter = _EntryStatusFilter.skipped),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _FilterCard(
          title: 'Clip Type',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((category) {
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _FilterChipButton(
                    label: category,
                    selected: _selectedCategory == category,
                    onTap: () => setState(() => _selectedCategory = category),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _FilterCard(
          title: 'AI Source',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: sources.map((source) {
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _FilterChipButton(
                    label: source,
                    selected: _selectedSource == source,
                    onTap: () => setState(() => _selectedSource = source),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  List<String> get _categoryFilters {
    final values = widget.entries
        .map((entry) => _friendlyCategory(entry.mood))
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...values];
  }

  List<String> get _sourceFilters {
    final values = widget.entries
        .map((entry) => _friendlySource(entry.source))
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...values];
  }

  List<AiDebugEntry> get _filteredEntries {
    return widget.entries.where((entry) {
      final bool statusMatches;
      if (_statusFilter == _EntryStatusFilter.selected) {
        statusMatches = entry.accepted;
      } else if (_statusFilter == _EntryStatusFilter.skipped) {
        statusMatches = !entry.accepted;
      } else {
        statusMatches = true;
      }

      final categoryMatches = _selectedCategory == 'All' ||
          _friendlyCategory(entry.mood) == _selectedCategory;

      final sourceMatches = _selectedSource == 'All' ||
          _friendlySource(entry.source) == _selectedSource;

      return statusMatches && categoryMatches && sourceMatches;
    }).toList();
  }
}

class _ReportHeader extends StatelessWidget {
  final int totalCount;
  final int selectedCount;
  final int skippedCount;

  const _ReportHeader({
    required this.totalCount,
    required this.selectedCount,
    required this.skippedCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRate = totalCount == 0 ? 0.0 : selectedCount / totalCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: AppRadius.xlRadius,
        gradient: AppGradients.headerCard(context),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Scan Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Review how ClipMood selected useful moments.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          ClipRRect(
            borderRadius: AppRadius.pillRadius,
            child: LinearProgressIndicator(
              value: selectedRate.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryStatTile(
                  label: 'Selected',
                  value: selectedCount.toString(),
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryStatTile(
                  label: 'Skipped',
                  value: skippedCount.toString(),
                  icon: Icons.block,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryStatTile(
                  label: 'Signals',
                  value: totalCount.toString(),
                  icon: Icons.timeline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundSubtle,
        borderRadius: AppRadius.xlRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: AppRadius.pillRadius,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.20)
              : AppColors.cardBackgroundSubtle,
          borderRadius: AppRadius.pillRadius,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.60)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? theme.colorScheme.primary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AiScanEntryCard extends StatelessWidget {
  final AiDebugEntry entry;

  const _AiScanEntryCard({
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _friendlyCategory(entry.mood);
    final source = _friendlySource(entry.source);
    final timeRange =
        '${TimeFormatter.formatSeconds(entry.startSeconds)} - ${TimeFormatter.formatSeconds(entry.endSeconds)}';
    final strength = _signalStrengthLabel(entry.score, entry.confidence);
    final color = _colorForCategory(context, category);
    final visibleNotes = entry.notes.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundSubtle,
        borderRadius: AppRadius.xlRadius,
        border: Border.all(
          color: entry.accepted
              ? color.withValues(alpha: 0.35)
              : AppColors.border,
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
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: AppRadius.lgRadius,
                  ),
                  child: Icon(
                    _iconForCategory(category),
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _StatusBadge(accepted: entry.accepted),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        timeRange,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _InfoPill(
                  icon: Icons.memory,
                  label: source,
                ),
                const SizedBox(width: AppSpacing.sm),
                _InfoPill(
                  icon: Icons.bolt,
                  label: strength,
                ),
              ],
            ),
            if (entry.topSignals.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: entry.topSignals.take(6).map((signal) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.38),
                      borderRadius: AppRadius.pillRadius,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      signal,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (visibleNotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: AppRadius.lgRadius,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI reasoning',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...visibleNotes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check,
                              color: entry.accepted ? color : AppColors.textDisabled,
                              size: 16,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                note,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool accepted;

  const _StatusBadge({
    required this.accepted,
  });

  @override
  Widget build(BuildContext context) {
    final color = accepted ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        accepted ? 'Selected' : 'Skipped',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: AppRadius.pillRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'No scan report yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Scan a video first. ClipMood will show selected and skipped moments here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoFilteredResultsState extends StatelessWidget {
  const _NoFilteredResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 48,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'No matching scan entries',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Try changing the status, clip type, or AI source filter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyCategory(String mood) {
  final value = mood.trim().toLowerCase();

  switch (value) {
    case 'funny':
      return 'Funny';
    case 'sad':
      return 'Sad';
    case 'emotional':
      return 'Emotional';
    case 'action':
      return 'Action';
    case 'reaction':
      return 'Reaction';
    case 'hook':
      return 'Hook / Quote';
    case 'informative':
      return 'Informative';
    case 'music':
    case 'exciting':
      return 'Music / Edit';
    case 'viral':
      return 'High Energy';
    case 'weird':
    case 'unexpected':
      return 'Weird / Unexpected';
    case 'highlight':
    default:
      return 'Highlight';
  }
}

String _friendlySource(Object? source) {
  final raw = source?.toString().trim() ?? '';
  final value = raw.toLowerCase();

  if (value.contains('yamnet') || value.contains('audioevent')) {
    return 'Audio Events';
  }
  if (value.contains('peak')) {
    return 'Audio Energy';
  }
  if (value.contains('transcript') || value.contains('whisper')) {
    return 'Transcript';
  }
  if (value.contains('face')) {
    return 'Face / Reaction';
  }
  if (value.contains('visual') || value.contains('scene')) {
    return 'Visual Signals';
  }
  if (value.contains('multi')) {
    return 'Multi-Signal AI';
  }

  return raw.isEmpty ? 'AI Signal' : raw;
}

String _signalStrengthLabel(double score, double confidence) {
  final value = score > 0 ? score : confidence;

  if (value >= 0.72) return 'Strong signal';
  if (value >= 0.48) return 'Good signal';
  if (value >= 0.25) return 'Light signal';
  return 'Weak signal';
}

IconData _iconForCategory(String category) {
  switch (category) {
    case 'Funny':
      return Icons.sentiment_very_satisfied;
    case 'Sad':
      return Icons.water_drop;
    case 'Emotional':
      return Icons.favorite;
    case 'Action':
      return Icons.local_fire_department;
    case 'Reaction':
      return Icons.face;
    case 'Hook / Quote':
      return Icons.format_quote;
    case 'Informative':
      return Icons.lightbulb;
    case 'Music / Edit':
      return Icons.music_note;
    case 'High Energy':
      return Icons.flash_on;
    case 'Weird / Unexpected':
      return Icons.psychology;
    default:
      return Icons.auto_awesome;
  }
}

Color _colorForCategory(BuildContext context, String category) {
  final scheme = Theme.of(context).colorScheme;

  switch (category) {
    case 'Funny':
      return Colors.amberAccent;
    case 'Sad':
      return Colors.lightBlueAccent;
    case 'Emotional':
      return Colors.pinkAccent;
    case 'Action':
      return Colors.deepOrangeAccent;
    case 'Reaction':
      return Colors.purpleAccent;
    case 'Hook / Quote':
      return Colors.cyanAccent;
    case 'Informative':
      return Colors.tealAccent;
    case 'Music / Edit':
      return Colors.greenAccent;
    case 'High Energy':
      return Colors.orangeAccent;
    case 'Weird / Unexpected':
      return Colors.indigoAccent;
    default:
      return scheme.primary;
  }
}