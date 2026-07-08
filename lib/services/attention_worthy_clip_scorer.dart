// services/attention_worthy_clip_scorer.dart

import 'dart:math';

import '../models/ai_signal.dart';
import '../models/ai_suggestion.dart';

class AttentionWorthyClipScorer {
  List<AiSuggestion> buildSuggestions({
    required List<AiSignal> signals,
    required int durationSeconds,
    int? targetCount,
  }) {
    if (durationSeconds <= 5) {
      return [
        AiSuggestion(
          title: 'Shareable Clip',
          mood: 'attention',
          startSeconds: 0,
          endSeconds: max(1, durationSeconds),
          confidence: 0.75,
          reason: const [
            'This video is already short enough to use as one attention clip.',
          ],
        ),
      ];
    }

    final usableSignals = signals.where((s) => s.isUsable && !s.isNegative).toList();
    if (usableSignals.isEmpty) return const [];

    final windows = <_AttentionWindow>[];

    for (final signal in usableSignals) {
      final attentionScore = _attentionScore(signal);

      if (attentionScore < 0.26) continue;

      final range = _rangeAroundSignal(
        signal,
        durationSeconds: durationSeconds,
      );

      windows.add(
        _AttentionWindow(
          startSeconds: range.start,
          endSeconds: range.end,
          score: attentionScore,
          confidence: signal.normalizedConfidence,
          signals: [signal],
        ),
      );
    }

    if (windows.isEmpty) return const [];

    final merged = _mergeNearbyWindows(
      windows,
      durationSeconds: durationSeconds,
    );

    final ranked = merged.map(_scoreWindow).where((w) {
      return w.score >= 0.42 && w.confidence >= 0.45;
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final selected = _selectNonOverlapping(
      ranked,
      targetCount: targetCount ?? _targetCount(durationSeconds),
    );

    selected.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    return selected.map((window) {
      final title = _titleForWindow(window);

      return AiSuggestion(
        title: title,
        mood: 'attention',
        startSeconds: window.startSeconds,
        endSeconds: window.endSeconds,
        confidence: window.confidence.clamp(0.0, 0.96).toDouble(),
        reason: _reasonsForWindow(window),
      );
    }).toList();
  }

  int _targetCount(int durationSeconds) {
    if (durationSeconds <= 60) return 6;
    if (durationSeconds <= 180) return 10;
    if (durationSeconds <= 600) return 16;
    return 24;
  }

  double _attentionScore(AiSignal signal) {
    final tags = signal.tags.map((e) => e.toLowerCase()).toList();

    double score = 0.0;

    final viral = signal.categoryScoreFor('viral');
    final hook = signal.categoryScoreFor('hook');
    final entertaining = signal.categoryScoreFor('entertaining');
    final reaction = signal.categoryScoreFor('reaction');
    final action = signal.categoryScoreFor('action');
    final fight = signal.categoryScoreFor('fight');
    final music = signal.categoryScoreFor('music');
    final weird = signal.categoryScoreFor('weird');
    final info = signal.categoryScoreFor('info');

    score += viral * 0.24;
    score += hook * 0.22;
    score += entertaining * 0.18;
    score += reaction * 0.14;
    score += action * 0.12;
    score += fight * 0.10;
    score += music * 0.08;
    score += weird * 0.12;
    score += info * 0.10;

    score += signal.normalizedStrength * 0.18;
    score += signal.normalizedConfidence * 0.12;

    if (_hasAny(tags, ['question', 'hook phrase', 'watch this', 'strong statement'])) {
      score += 0.16;
    }

    if (_hasAny(tags, ['laughter', 'crowd', 'hype', 'strong delivery'])) {
      score += 0.14;
    }

    if (_hasAny(tags, ['scene change', 'motion', 'visual energy', 'brightness jump'])) {
      score += 0.12;
    }

    if (_hasAny(tags, ['reaction', 'strong face reaction', 'head movement', 'eye expression'])) {
      score += 0.12;
    }

    if (_hasAny(tags, ['action sound', 'fight / impact sound', 'loudness peak'])) {
      score += 0.11;
    }

    if (_hasAny(tags, ['weird', 'unexpected', 'strange'])) {
      score += 0.10;
    }

    if (_hasAny(tags, ['speech', 'quote-sized segment', 'informative wording'])) {
      score += 0.08;
    }

    if (_hasAny(tags, ['silence'])) {
      score -= 0.30;
    }

    return score.clamp(0.0, 1.0).toDouble();
  }

  _AttentionWindow _scoreWindow(_AttentionWindow window) {
    final signals = window.signals.where((s) => !s.isNegative).toList();

    final avgAttention = signals.isEmpty
        ? 0.0
        : signals.map(_attentionScore).reduce((a, b) => a + b) / signals.length;

    final bestAttention = signals.isEmpty
        ? 0.0
        : signals.map(_attentionScore).reduce(max);

    final sourceDiversity = signals.map((s) => s.source).toSet().length;

    double diversityBonus = 0.0;
    if (sourceDiversity >= 2) diversityBonus += 0.08;
    if (sourceDiversity >= 3) diversityBonus += 0.07;

    final durationScore = _durationScore(window);

    final finalScore = ((avgAttention * 0.45) +
            (bestAttention * 0.30) +
            diversityBonus +
            (durationScore * 0.10))
        .clamp(0.0, 1.0)
        .toDouble();

    final confidence = ((window.confidence * 0.50) +
            (bestAttention * 0.30) +
            diversityBonus +
            (durationScore * 0.10))
        .clamp(0.0, 0.96)
        .toDouble();

    return window.copyWith(
      score: finalScore,
      confidence: confidence,
    );
  }

  double _durationScore(_AttentionWindow window) {
    final duration = window.endSeconds - window.startSeconds;
    const ideal = 18;
    final distance = (duration - ideal).abs();

    return (1.0 - (distance / ideal)).clamp(0.0, 1.0).toDouble();
  }

  _ClipRange _rangeAroundSignal(
    AiSignal signal, {
    required int durationSeconds,
  }) {
    var start = max(0, signal.startSeconds - 2);
    var end = min(durationSeconds, signal.endSeconds + 5);

    const minLength = 10;
    const maxLength = 35;

    if (end - start < minLength) {
      final missing = minLength - (end - start);
      start = max(0, start - (missing ~/ 2));
      end = min(durationSeconds, start + minLength);
    }

    if (end - start > maxLength) {
      end = start + maxLength;
    }

    return _ClipRange(start, max(start + 1, end));
  }

  List<_AttentionWindow> _mergeNearbyWindows(
    List<_AttentionWindow> windows, {
    required int durationSeconds,
  }) {
    final sorted = [...windows]..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    final merged = <_AttentionWindow>[];

    for (final window in sorted) {
      if (merged.isEmpty) {
        merged.add(window);
        continue;
      }

      final last = merged.last;
      final gap = window.startSeconds - last.endSeconds;
      final overlap = _overlapRatio(last, window);

      if (gap <= 5 || overlap >= 0.25) {
        final start = min(last.startSeconds, window.startSeconds);
        final end = min(durationSeconds, max(last.endSeconds, window.endSeconds));

        merged[merged.length - 1] = _AttentionWindow(
          startSeconds: start,
          endSeconds: min(start + 35, end),
          score: max(last.score, window.score),
          confidence: max(last.confidence, window.confidence),
          signals: [...last.signals, ...window.signals],
        );
      } else {
        merged.add(window);
      }
    }

    return merged;
  }

  List<_AttentionWindow> _selectNonOverlapping(
    List<_AttentionWindow> ranked, {
    required int targetCount,
  }) {
    final selected = <_AttentionWindow>[];

    for (final window in ranked) {
      if (selected.length >= targetCount) break;

      final duplicate = selected.any((existing) {
        return _overlapRatio(existing, window) >= 0.50 ||
            (existing.startSeconds - window.startSeconds).abs() <= 4;
      });

      if (!duplicate) selected.add(window);
    }

    return selected;
  }

  String _titleForWindow(_AttentionWindow window) {
    final tags = window.signals.expand((s) => s.tags).map((e) => e.toLowerCase()).toList();

    if (_hasAny(tags, ['hook phrase', 'question', 'strong statement'])) {
      return 'Strong Hook Clip';
    }

    if (_hasAny(tags, ['crowd', 'hype', 'laughter', 'strong delivery'])) {
      return 'High Attention Clip';
    }

    if (_hasAny(tags, ['scene change', 'motion', 'visual energy', 'brightness jump'])) {
      return 'Eye-Catching Clip';
    }

    if (_hasAny(tags, ['reaction', 'strong face reaction', 'head movement'])) {
      return 'Reaction Clip';
    }

    if (_hasAny(tags, ['action sound', 'fight / impact sound', 'loudness peak'])) {
      return 'Action Attention Clip';
    }

    return 'Share-Worthy Clip';
  }

  List<String> _reasonsForWindow(_AttentionWindow window) {
    final tags = window.signals.expand((s) => s.tags).map((e) => e.toLowerCase()).toList();
    final reasons = <String>[];

    if (_hasAny(tags, ['hook phrase', 'question', 'strong statement'])) {
      reasons.add('This moment has hook-style wording that can make viewers stop scrolling.');
    }

    if (_hasAny(tags, ['crowd', 'hype', 'laughter', 'strong delivery'])) {
      reasons.add('Audio energy suggests this part may feel exciting or shareable.');
    }

    if (_hasAny(tags, ['scene change', 'motion', 'visual energy', 'brightness jump'])) {
      reasons.add('Visual movement or scene change makes this moment more eye-catching.');
    }

    if (_hasAny(tags, ['reaction', 'strong face reaction', 'head movement', 'eye expression'])) {
      reasons.add('Face or reaction signals suggest this part can catch attention.');
    }

    if (_hasAny(tags, ['action sound', 'fight / impact sound', 'loudness peak'])) {
      reasons.add('Impact, loudness, or action-style signals make this clip more engaging.');
    }

    if (window.signals.map((s) => s.source).toSet().length >= 2) {
      reasons.add('Multiple AI signals supported the same moment.');
    }

    if (reasons.isEmpty) {
      reasons.add('This moment scored high for viewer attention and share potential.');
    }

    return reasons.take(5).toList();
  }

  bool _hasAny(List<String> values, List<String> needles) {
    return values.any((value) {
      return needles.any((needle) => value.contains(needle));
    });
  }

  double _overlapRatio(_AttentionWindow a, _AttentionWindow b) {
    final overlapStart = max(a.startSeconds, b.startSeconds);
    final overlapEnd = min(a.endSeconds, b.endSeconds);

    if (overlapEnd <= overlapStart) return 0.0;

    final overlap = overlapEnd - overlapStart;
    final shortest = min(
      a.endSeconds - a.startSeconds,
      b.endSeconds - b.startSeconds,
    );

    if (shortest <= 0) return 0.0;

    return overlap / shortest;
  }
}

class _AttentionWindow {
  final int startSeconds;
  final int endSeconds;
  final double score;
  final double confidence;
  final List<AiSignal> signals;

  const _AttentionWindow({
    required this.startSeconds,
    required this.endSeconds,
    required this.score,
    required this.confidence,
    required this.signals,
  });

  _AttentionWindow copyWith({
    int? startSeconds,
    int? endSeconds,
    double? score,
    double? confidence,
    List<AiSignal>? signals,
  }) {
    return _AttentionWindow(
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      score: score ?? this.score,
      confidence: confidence ?? this.confidence,
      signals: signals ?? this.signals,
    );
  }
}

class _ClipRange {
  final int start;
  final int end;

  const _ClipRange(this.start, this.end);
}