import 'dart:math';

import '../models/ai_signal.dart';
import '../models/ai_suggestion.dart';
import '../models/clip_candidate.dart';
import '../models/clip_intent.dart';

class MultiSignalClipScorer {
  List<AiSuggestion> buildSuggestions({
    required List<AiSignal> signals,
    required int durationSeconds,
    ClipIntent intent = ClipIntent.general,
    int? targetCount,
  }) {
    if (durationSeconds <= 5) {
      return [
        AiSuggestion(
          title: 'Short Highlight',
          mood: 'highlight',
          startSeconds: 0,
          endSeconds: max(1, durationSeconds),
          confidence: 0.72,
          reason: const [
            'This video is already short enough to use as one clip.',
          ],
        ),
      ];
    }

    // Product decision: main ClipMood flow is automatic. The scorer always
    // searches all useful clip types, then groups them for the creator.
    final count = targetCount ?? chooseTargetCount(durationSeconds);

    final candidates = _signalsToCandidates(
      signals: signals,
      durationSeconds: durationSeconds,
    );

    if (candidates.isEmpty) return const [];

    final merged = _mergeNearbyCandidates(
      candidates,
      durationSeconds: durationSeconds,
    );

    final ranked = merged
        .map(
          (candidate) => _scoreCandidate(
            candidate,
            durationSeconds: durationSeconds,
          ),
        )
        .where(_passesQualityGate)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (ranked.isEmpty) return const [];

    final selected = _selectCategorySections(
      ranked,
      targetCount: count,
      durationSeconds: durationSeconds,
    );

    return selected.map((candidate) => candidate.toSuggestion()).toList();
  }

  int chooseTargetCount(int durationSeconds, [ClipIntent intent = ClipIntent.general]) {
    if (durationSeconds <= 30) return 8;
    if (durationSeconds <= 90) return 14;
    if (durationSeconds <= 300) return 22;
    if (durationSeconds <= 900) return 30;
    return 36;
  }

  List<ClipCandidate> _signalsToCandidates({
    required List<AiSignal> signals,
    required int durationSeconds,
  }) {
    final candidates = <ClipCandidate>[];

    for (final signal in signals.where((signal) => signal.isUsable)) {
      final mood = _canonicalMood(signal.mood);
      if (!_isPublicCategory(mood)) continue;

      final minClipLength = _clipLengthForMood(mood, durationSeconds: durationSeconds);
      final padding = _paddingForMood(mood, source: signal.source);
      final range = _rangeAroundSignal(
        signal,
        durationSeconds: durationSeconds,
        minClipLength: minClipLength,
        preRollSeconds: padding.preRollSeconds,
        postRollSeconds: padding.postRollSeconds,
      );

      candidates.add(
        ClipCandidate(
          startSeconds: range.start,
          endSeconds: range.end,
          title: _titleForMood(mood),
          mood: mood,
          score: signal.weightedScore.abs(),
          confidence: _candidateConfidence(signal),
          signals: [signal],
          reasons: _candidateReasonsFromSignal(signal, mood),
        ),
      );
    }

    candidates.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return candidates;
  }

  ClipCandidate _scoreCandidate(
    ClipCandidate candidate, {
    required int durationSeconds,
  }) {
    final positiveSignals = candidate.signals.where((signal) => !signal.isNegative).toList();
    final negativeSignals = candidate.signals.where((signal) => signal.isNegative).toList();

    final signalScore = positiveSignals.isEmpty
        ? 0.0
        : positiveSignals.fold<double>(0.0, (sum, signal) => sum + signal.weightedScore.abs()) /
            positiveSignals.length;

    final bestSignalScore = positiveSignals.isEmpty
        ? 0.0
        : positiveSignals.map((signal) => signal.weightedScore.abs()).reduce(max);

    final sourceDiversityBonus = _sourceDiversityBonus(candidate);
    final categoryEvidenceBonus = _categoryEvidenceBonus(candidate);
    final supportBonus = _supportBonus(candidate);
    final durationScore = _durationQualityScore(candidate);
    final boringPenalty = _boringPenalty(candidate);
    final weakCategoryPenalty = _weakCategoryPenalty(candidate);
    final negativePenalty = negativeSignals.length * 0.10;

    final finalScore = ((signalScore * 0.40) +
            (bestSignalScore * 0.23) +
            sourceDiversityBonus +
            categoryEvidenceBonus +
            supportBonus +
            (durationScore * 0.08) -
            boringPenalty -
            weakCategoryPenalty -
            negativePenalty)
        .clamp(0.0, 1.0)
        .toDouble();

    final confidence = ((candidate.confidence * 0.55) +
            (bestSignalScore * 0.22) +
            (sourceDiversityBonus * 0.65) +
            (categoryEvidenceBonus * 0.60) +
            (durationScore * 0.08))
        .clamp(0.0, 0.96)
        .toDouble();

    return candidate.copyWith(
      score: finalScore,
      confidence: confidence,
      title: _titleForMood(candidate.mood),
      reasons: _rankedPublicReasons(candidate, finalScore: finalScore),
    );
  }

  bool _passesQualityGate(ClipCandidate candidate) {
    final mood = _canonicalMood(candidate.mood);
    final hasRequiredEvidence = _hasRequiredEvidence(candidate, mood);
    if (!hasRequiredEvidence) return false;

    final minScore = _minScoreForMood(mood);
    if (candidate.score < minScore) return false;

    // Do not keep weak generic highlights when better category clips exist.
    if (mood == 'highlight' && candidate.score < 0.30) return false;

    return true;
  }

  List<ClipCandidate> _mergeNearbyCandidates(
    List<ClipCandidate> candidates, {
    required int durationSeconds,
  }) {
    if (candidates.isEmpty) return const [];

    final byMood = <String, List<ClipCandidate>>{};
    for (final candidate in candidates) {
      byMood.putIfAbsent(candidate.mood, () => []).add(candidate);
    }

    final mergedAll = <ClipCandidate>[];

    for (final entry in byMood.entries) {
      final mood = entry.key;
      final sorted = [...entry.value]
        ..sort((a, b) {
          final startCompare = a.startSeconds.compareTo(b.startSeconds);
          if (startCompare != 0) return startCompare;
          return b.score.compareTo(a.score);
        });

      final merged = <ClipCandidate>[];
      final maxGap = _mergeGapForMood(mood);

      for (final candidate in sorted) {
        if (merged.isEmpty) {
          merged.add(candidate);
          continue;
        }

        final last = merged.last;
        final gap = candidate.startSeconds > last.endSeconds
            ? candidate.startSeconds - last.endSeconds
            : last.startSeconds - candidate.endSeconds;
        final shouldMerge = candidate.overlapRatio(last) >= 0.20 || gap <= maxGap;

        if (shouldMerge) {
          merged[merged.length - 1] = last.mergeWith(
            candidate,
            durationSeconds: durationSeconds,
            maxClipSeconds: _maxClipLengthForMood(mood),
          ).copyWith(
            mood: mood,
            title: _titleForMood(mood),
          );
        } else {
          merged.add(candidate);
        }
      }

      mergedAll.addAll(merged.where((candidate) => candidate.isValid));
    }

    return mergedAll;
  }

  List<ClipCandidate> _selectCategorySections(
    List<ClipCandidate> ranked, {
    required int targetCount,
    required int durationSeconds,
  }) {
    final selected = <ClipCandidate>[];
    final sectionOrder = _sectionOrder;
    final maxPerSection = _maxPerSectionForTarget(targetCount);

    bool duplicateOfSelected(ClipCandidate candidate) {
      return selected.any((existing) {
        final overlap = candidate.overlapRatio(existing);
        final startDistance = (candidate.startSeconds - existing.startSeconds).abs();
        return overlap >= 0.52 || startDistance <= 4;
      });
    }

    // First pass: guarantee variety across sections where real evidence exists.
    for (final mood in sectionOrder) {
      final sectionCandidates = ranked
          .where((candidate) => candidate.mood == mood)
          .where((candidate) => !duplicateOfSelected(candidate))
          .take(maxPerSection)
          .toList();
      selected.addAll(sectionCandidates);
      if (selected.length >= targetCount) break;
    }

    // Second pass: fill the rest with the best remaining moments, still no duplicates.
    for (final candidate in ranked) {
      if (selected.length >= targetCount) break;
      if (selected.contains(candidate)) continue;
      if (duplicateOfSelected(candidate)) continue;
      selected.add(candidate);
    }

    selected.sort((a, b) {
      final sectionCompare = _sectionRank(a.mood).compareTo(_sectionRank(b.mood));
      if (sectionCompare != 0) return sectionCompare;
      return b.score.compareTo(a.score);
    });

    return selected.take(targetCount).toList();
  }

  double _sourceDiversityBonus(ClipCandidate candidate) {
    final sources = candidate.sources;
    double bonus = 0.0;

    if (sources.length >= 2) bonus += 0.07;
    if (sources.length >= 3) bonus += 0.06;
    if (sources.contains(AiSignalSource.transcript)) bonus += 0.05;
    if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.05;
    if (sources.contains(AiSignalSource.audioEvent) &&
        (sources.contains(AiSignalSource.transcript) ||
            sources.contains(AiSignalSource.visualMotion) ||
            sources.contains(AiSignalSource.sceneChange) ||
            sources.contains(AiSignalSource.faceReaction))) {
      bonus += 0.05;
    }

    return bonus.clamp(0.0, 0.24).toDouble();
  }

  double _categoryEvidenceBonus(ClipCandidate candidate) {
    final mood = _canonicalMood(candidate.mood);
    final sources = candidate.sources;
    final tags = _allTags(candidate);
    double bonus = 0.0;

    switch (mood) {
      case 'funny':
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('laughter'))) bonus += 0.10;
        if (sources.contains(AiSignalSource.faceReaction) && tags.any((tag) => tag.contains('smile'))) bonus += 0.09;
        if (sources.contains(AiSignalSource.transcript)) bonus += 0.07;
        break;
      case 'sad':
        if (sources.contains(AiSignalSource.transcript)) bonus += 0.10;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('cry') || tag.contains('sad'))) bonus += 0.10;
        if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.06;
        break;
      case 'emotional':
        if (sources.contains(AiSignalSource.transcript)) bonus += 0.10;
        if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.07;
        if (sources.contains(AiSignalSource.audioEvent)) bonus += 0.05;
        break;
      case 'action':
        if (sources.contains(AiSignalSource.visualMotion)) bonus += 0.08;
        if (sources.contains(AiSignalSource.sceneChange)) bonus += 0.07;
        if (sources.contains(AiSignalSource.audioPeak)) bonus += 0.07;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('action'))) bonus += 0.10;
        break;
      case 'reaction':
        if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.10;
        if (sources.contains(AiSignalSource.audioEvent)) bonus += 0.06;
        if (sources.contains(AiSignalSource.visualMotion) || sources.contains(AiSignalSource.sceneChange)) bonus += 0.05;
        break;
      case 'hook':
      case 'info':
        if (sources.contains(AiSignalSource.transcript)) bonus += 0.14;
        break;
      case 'music':
        if (sources.contains(AiSignalSource.audioEvent)) bonus += 0.09;
        if (sources.contains(AiSignalSource.audioPeak)) bonus += 0.06;
        if (sources.contains(AiSignalSource.sceneChange)) bonus += 0.05;
        break;
      case 'viral':
        if (sources.contains(AiSignalSource.audioEvent)) bonus += 0.08;
        if (sources.contains(AiSignalSource.audioPeak)) bonus += 0.06;
        if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.06;
        break;
      case 'weird':
        if (sources.contains(AiSignalSource.transcript)) bonus += 0.08;
        if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.06;
        if (sources.contains(AiSignalSource.audioEvent)) bonus += 0.05;
        break;
      default:
        bonus += 0.0;
    }

    return bonus.clamp(0.0, 0.22).toDouble();
  }

  bool _hasRequiredEvidence(ClipCandidate candidate, String mood) {
    final sources = candidate.sources;
    final tags = _allTags(candidate);

    switch (mood) {
      case 'funny':
        return (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('laughter'))) ||
            (sources.contains(AiSignalSource.faceReaction) && tags.any((tag) => tag.contains('smile'))) ||
            (sources.contains(AiSignalSource.transcript) && tags.any((tag) => tag.contains('comedy')));
      case 'sad':
        return sources.contains(AiSignalSource.transcript) ||
            (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('sad') || tag.contains('cry'))) ||
            sources.contains(AiSignalSource.faceReaction);
      case 'emotional':
        return sources.contains(AiSignalSource.transcript) ||
            sources.contains(AiSignalSource.faceReaction) ||
            sources.contains(AiSignalSource.audioEvent);
      case 'action':
        return sources.contains(AiSignalSource.visualMotion) ||
            sources.contains(AiSignalSource.sceneChange) ||
            sources.contains(AiSignalSource.audioPeak) ||
            (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('action') || tag.contains('crowd')));
      case 'reaction':
        return sources.contains(AiSignalSource.faceReaction) ||
            sources.contains(AiSignalSource.audioEvent) ||
            sources.contains(AiSignalSource.visualMotion) ||
            sources.contains(AiSignalSource.sceneChange);
      case 'hook':
      case 'info':
        return sources.contains(AiSignalSource.transcript);
      case 'music':
        return sources.contains(AiSignalSource.audioEvent) || sources.contains(AiSignalSource.audioPeak);
      case 'viral':
        return sources.contains(AiSignalSource.audioEvent) ||
            sources.contains(AiSignalSource.audioPeak) ||
            sources.contains(AiSignalSource.faceReaction);
      case 'weird':
        return sources.contains(AiSignalSource.transcript) ||
            sources.contains(AiSignalSource.audioEvent) ||
            sources.contains(AiSignalSource.faceReaction);
      case 'highlight':
        return candidate.sourceDiversity >= 2 || candidate.signalStrength >= 0.28;
      default:
        return false;
    }
  }

  double _supportBonus(ClipCandidate candidate) {
    final signalCount = candidate.signals.where((signal) => !signal.isNegative).length;
    if (signalCount >= 5) return 0.08;
    if (signalCount >= 4) return 0.07;
    if (signalCount >= 3) return 0.05;
    if (signalCount >= 2) return 0.03;
    return 0.0;
  }

  double _durationQualityScore(ClipCandidate candidate) {
    final ideal = _idealClipLengthForMood(candidate.mood);
    final distance = (candidate.durationSeconds - ideal).abs();
    return (1.0 - (distance / ideal)).clamp(0.0, 1.0).toDouble();
  }

  double _boringPenalty(ClipCandidate candidate) {
    final tags = _allTags(candidate);
    double penalty = 0.0;

    if (tags.any((tag) => tag.contains('silence'))) penalty += 0.22;
    if (candidate.sourceDiversity == 1 && candidate.mood == 'highlight') penalty += 0.12;
    if (candidate.signalStrength < 0.11) penalty += 0.10;

    return penalty.clamp(0.0, 0.34).toDouble();
  }

  double _weakCategoryPenalty(ClipCandidate candidate) {
    final mood = _canonicalMood(candidate.mood);
    final sources = candidate.sources;
    double penalty = 0.0;

    if ((mood == 'funny' || mood == 'sad' || mood == 'emotional' || mood == 'hook' || mood == 'info') &&
        sources.length == 1 &&
        sources.contains(AiSignalSource.audioPeak)) {
      penalty += 0.35;
    }

    if ((mood == 'hook' || mood == 'info') && !sources.contains(AiSignalSource.transcript)) {
      penalty += 0.30;
    }

    if (mood == 'funny' && !sources.contains(AiSignalSource.audioEvent) && !sources.contains(AiSignalSource.faceReaction) && !sources.contains(AiSignalSource.transcript)) {
      penalty += 0.25;
    }

    return penalty.clamp(0.0, 0.42).toDouble();
  }

  int _clipLengthForMood(String mood, {required int durationSeconds}) {
    if (durationSeconds <= 20) return min(durationSeconds, 10);

    switch (_canonicalMood(mood)) {
      case 'hook':
      case 'info':
        return 22;
      case 'sad':
      case 'emotional':
        return 24;
      case 'funny':
      case 'reaction':
        return 14;
      case 'action':
      case 'viral':
        return 15;
      case 'music':
        return 14;
      case 'weird':
        return 12;
      default:
        return 16;
    }
  }

  _ClipPadding _paddingForMood(String mood, {required AiSignalSource source}) {
    if (source == AiSignalSource.transcript) {
      if (mood == 'hook' || mood == 'info') return const _ClipPadding(3, 4);
      return const _ClipPadding(2, 3);
    }

    switch (_canonicalMood(mood)) {
      case 'funny':
        return const _ClipPadding(3, 4);
      case 'sad':
      case 'emotional':
        return const _ClipPadding(4, 5);
      case 'hook':
      case 'info':
        return const _ClipPadding(3, 4);
      case 'action':
        return const _ClipPadding(1, 4);
      case 'viral':
      case 'reaction':
        return const _ClipPadding(2, 5);
      case 'music':
        return const _ClipPadding(1, 4);
      case 'weird':
        return const _ClipPadding(2, 3);
      default:
        return const _ClipPadding(2, 4);
    }
  }

  _ClipRange _rangeAroundSignal(
    AiSignal signal, {
    required int durationSeconds,
    required int minClipLength,
    required int preRollSeconds,
    required int postRollSeconds,
  }) {
    var start = max(0, signal.startSeconds - preRollSeconds);
    var end = min(durationSeconds, signal.endSeconds + postRollSeconds);

    if (end - start < minClipLength) {
      final missing = minClipLength - (end - start);
      final addBefore = missing ~/ 2;
      final addAfter = missing - addBefore;

      start = max(0, start - addBefore);
      end = min(durationSeconds, end + addAfter);

      if (end - start < minClipLength && start == 0) {
        end = min(durationSeconds, minClipLength);
      }

      if (end - start < minClipLength && end == durationSeconds) {
        start = max(0, durationSeconds - minClipLength);
      }
    }

    return _ClipRange(start, max(start + 1, end));
  }

  String _canonicalMood(String mood) {
    final value = mood.toLowerCase().trim();
    switch (value) {
      case 'exciting':
        return 'music';
      case 'information':
      case 'informative':
      case 'educational':
        return 'info';
      case 'strange':
        return 'weird';
      default:
        return value;
    }
  }

  bool _isPublicCategory(String mood) {
    return _sectionOrder.contains(_canonicalMood(mood));
  }

  String _titleForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
        return 'Funny Clip';
      case 'sad':
        return 'Sad Clip';
      case 'emotional':
        return 'Emotional Clip';
      case 'action':
        return 'Action Clip';
      case 'reaction':
        return 'Reaction Clip';
      case 'hook':
        return 'Hook / Quote Clip';
      case 'info':
        return 'Informative Clip';
      case 'music':
        return 'Music / Edit Clip';
      case 'viral':
        return 'High Energy Clip';
      case 'weird':
        return 'Weird / Unexpected Clip';
      default:
        return 'Highlight Clip';
    }
  }

  double _candidateConfidence(AiSignal signal) {
    final sourceBonus = signal.source.basePriority * 0.018;
    return ((signal.normalizedConfidence * 0.62) +
            (signal.normalizedStrength * 0.28) +
            sourceBonus)
        .clamp(0.0, 0.94)
        .toDouble();
  }

  List<String> _candidateReasonsFromSignal(AiSignal signal, String mood) {
    return _uniqueStrings([
      _publicReasonForMood(mood),
      ...signal.reasons.where((reason) => !_isTechnicalReason(reason)),
      if (signal.tags.isNotEmpty) 'Detected: ${signal.tags.take(4).join(', ')}',
    ]).take(5).toList();
  }

  List<String> _rankedPublicReasons(
    ClipCandidate candidate, {
    required double finalScore,
  }) {
    final reasons = <String>[
      _publicReasonForMood(candidate.mood),
      if (candidate.sourceDiversity >= 2) 'Multiple AI signals pointed to this same moment.',
      if (candidate.signals.any((signal) => signal.source == AiSignalSource.transcript))
        'Speech meaning helped identify this clip.',
      if (candidate.signals.any((signal) => signal.source == AiSignalSource.audioEvent))
        'Audio events helped identify this clip.',
      if (candidate.signals.any((signal) =>
          signal.source == AiSignalSource.visualMotion ||
          signal.source == AiSignalSource.sceneChange ||
          signal.source == AiSignalSource.faceReaction))
        'Visual or face/reaction signals helped identify this clip.',
      ...candidate.reasons.where((reason) => !_isTechnicalReason(reason)),
    ];

    return _uniqueStrings(reasons).take(5).toList();
  }

  bool _isTechnicalReason(String reason) {
    final lower = reason.toLowerCase();
    return lower.contains('score') ||
        lower.contains('confidence') ||
        lower.contains('search intent') ||
        lower.contains('source:') ||
        lower.startsWith('signals:') ||
        lower.contains('best audio category') ||
        lower.contains('best transcript category') ||
        lower.contains('best face/reaction category');
  }

  String _publicReasonForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
        return 'This part has comedy, laughter, smile, or funny reaction evidence.';
      case 'sad':
        return 'This part has sad, crying, loss, or serious emotional evidence.';
      case 'emotional':
        return 'This part has heartfelt or emotionally important evidence.';
      case 'action':
        return 'This part has motion, impact, scene change, or high action energy.';
      case 'reaction':
        return 'This part has reaction-style face, sound, or visual change evidence.';
      case 'hook':
        return 'This part may contain a strong hook, quote, or attention-grabbing line.';
      case 'info':
        return 'This part may contain useful information, tips, or explanation.';
      case 'music':
        return 'This part may work well for a music or edit-style clip.';
      case 'viral':
        return 'This part has high-energy or crowd/hype evidence.';
      case 'weird':
        return 'This part has weird, unexpected, or unusual evidence.';
      default:
        return 'This moment looks useful for a creator clip.';
    }
  }

  int _mergeGapForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'hook':
      case 'info':
      case 'sad':
      case 'emotional':
        return 6;
      case 'music':
      case 'action':
      case 'weird':
        return 3;
      default:
        return 5;
    }
  }

  int _maxClipLengthForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'hook':
      case 'info':
      case 'sad':
      case 'emotional':
        return 45;
      case 'music':
        return 24;
      case 'action':
      case 'weird':
        return 26;
      default:
        return 32;
    }
  }

  int _idealClipLengthForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'hook':
      case 'info':
        return 24;
      case 'sad':
      case 'emotional':
        return 26;
      case 'music':
        return 14;
      case 'action':
      case 'viral':
        return 15;
      case 'funny':
      case 'reaction':
        return 15;
      case 'weird':
        return 12;
      default:
        return 18;
    }
  }

  double _minScoreForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'hook':
      case 'info':
      case 'funny':
      case 'weird':
        return 0.18;
      case 'sad':
      case 'emotional':
      case 'reaction':
      case 'music':
        return 0.16;
      case 'action':
      case 'viral':
        return 0.14;
      case 'highlight':
        return 0.24;
      default:
        return 0.18;
    }
  }

  int _maxPerSectionForTarget(int targetCount) {
    if (targetCount <= 10) return 3;
    if (targetCount <= 20) return 4;
    return 5;
  }

  List<String> get _sectionOrder => const [
        'funny',
        'sad',
        'emotional',
        'action',
        'reaction',
        'hook',
        'info',
        'music',
        'viral',
        'weird',
        'highlight',
      ];

  int _sectionRank(String mood) {
    final index = _sectionOrder.indexOf(_canonicalMood(mood));
    return index < 0 ? 999 : index;
  }

  List<String> _allTags(ClipCandidate candidate) {
    return candidate.signals
        .expand((signal) => signal.tags)
        .map((tag) => tag.toLowerCase())
        .toList();
  }

  List<String> _uniqueStrings(List<String> values) {
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

class _ClipPadding {
  final int preRollSeconds;
  final int postRollSeconds;

  const _ClipPadding(this.preRollSeconds, this.postRollSeconds);
}

class _ClipRange {
  final int start;
  final int end;

  const _ClipRange(this.start, this.end);
}
