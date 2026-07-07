import 'dart:math';
import 'ai_signal.dart';
import 'ai_suggestion.dart';

class ClipCandidate {
  final int startSeconds;
  final int endSeconds;
  final String title;
  final String mood;
  final double score;
  final double confidence;
  final double categoryPrecision;
  final List<AiSignal> signals;
  final List<String> reasons;

  const ClipCandidate({
    required this.startSeconds,
    required this.endSeconds,
    required this.title,
    required this.mood,
    required this.score,
    required this.confidence,
    this.categoryPrecision = 0.0,
    this.signals = const [],
    this.reasons = const [],
  });

  int get durationSeconds => endSeconds - startSeconds;

  bool get isValid => endSeconds > startSeconds && durationSeconds >= 2;

  Set<AiSignalSource> get sources {
    return signals.map((signal) => signal.source).toSet();
  }

  int get sourceDiversity => sources.length;

  double get signalStrength {
    if (signals.isEmpty) return 0.0;

    final positiveSignals = signals.where((signal) => !signal.isNegative).toList();
    if (positiveSignals.isEmpty) return 0.0;

    final total = positiveSignals.fold<double>(
      0.0,
      (sum, signal) => sum + signal.weightedScore.abs(),
    );

    return (total / positiveSignals.length).clamp(0.0, 1.0).toDouble();
  }

  bool overlaps(ClipCandidate other) {
    return startSeconds < other.endSeconds && endSeconds > other.startSeconds;
  }

  int overlapSeconds(ClipCandidate other) {
    if (!overlaps(other)) return 0;
    return min(endSeconds, other.endSeconds) - max(startSeconds, other.startSeconds);
  }

  double overlapRatio(ClipCandidate other) {
    final overlap = overlapSeconds(other);
    if (overlap <= 0) return 0.0;
    final smallerDuration = max(1, min(durationSeconds, other.durationSeconds));
    return (overlap / smallerDuration).clamp(0.0, 1.0).toDouble();
  }

  ClipCandidate mergeWith(
    ClipCandidate other, {
    required int durationSeconds,
    int maxClipSeconds = 45,
  }) {
    final mergedStart = max(0, min(startSeconds, other.startSeconds));
    final mergedEnd = min(durationSeconds, max(endSeconds, other.endSeconds));

    final trimmedEnd = mergedEnd - mergedStart > maxClipSeconds
        ? min(durationSeconds, mergedStart + maxClipSeconds)
        : mergedEnd;

    final mergedSignals = <AiSignal>[...signals, ...other.signals];
    final better = score >= other.score ? this : other;

    return ClipCandidate(
      startSeconds: mergedStart,
      endSeconds: max(mergedStart + 2, trimmedEnd),
      title: better.title,
      mood: better.mood,
      score: max(score, other.score) + 0.04,
      confidence: max(confidence, other.confidence),
      categoryPrecision: max(categoryPrecision, other.categoryPrecision),
      signals: mergedSignals,
      reasons: _uniqueStrings([
        ...reasons,
        ...other.reasons,
        'Merged because multiple signals pointed to the same moment',
      ]),
    );
  }

  AiSuggestion toSuggestion() {
    return AiSuggestion(
      title: title,
      mood: mood,
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      score: score.clamp(0.0, 1.0).toDouble(),
      categoryPrecision: categoryPrecision.clamp(0.0, 1.0).toDouble(),
      sourceDiversity: sourceDiversity,
      reason: _uniqueStrings(reasons).take(6).toList(),
    );
  }

  ClipCandidate copyWith({
    int? startSeconds,
    int? endSeconds,
    String? title,
    String? mood,
    double? score,
    double? confidence,
    double? categoryPrecision,
    List<AiSignal>? signals,
    List<String>? reasons,
  }) {
    return ClipCandidate(
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      title: title ?? this.title,
      mood: mood ?? this.mood,
      score: score ?? this.score,
      confidence: confidence ?? this.confidence,
      categoryPrecision: categoryPrecision ?? this.categoryPrecision,
      signals: signals ?? this.signals,
      reasons: reasons ?? this.reasons,
    );
  }

  static List<String> _uniqueStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];

    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) result.add(trimmed);
    }

    return result;
  }
}
