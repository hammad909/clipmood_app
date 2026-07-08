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
      final categoryScores = _candidateCategoryScoresForSignal(signal);
      if (categoryScores.isEmpty) continue;

      for (final entry in categoryScores.entries) {
        final mood = _canonicalMood(entry.key);
        if (!_isPublicCategory(mood)) continue;

        final categoryStrength = entry.value.clamp(0.0, 1.0).toDouble();
        if (categoryStrength < _minSignalCategoryScore(mood)) continue;

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
            score: (categoryStrength * signal.normalizedConfidence * signal.weight)
                .clamp(0.0, 1.0)
                .toDouble(),
            confidence: _candidateConfidence(signal),
            categoryScores: _publicSignalCategoryScores(signal),
            signals: [signal],
            reasons: _candidateReasonsFromSignal(signal, mood),
          ),
        );
      }
    }

    candidates.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return candidates;
  }

  Map<String, double> _candidateCategoryScoresForSignal(AiSignal signal) {
    final all = _publicSignalCategoryScores(signal);
    if (all.isEmpty) return const {};

    final sorted = all.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Keep the top few categories per signal. This is the key upgrade:
    // one signal can create funny + happy + entertaining candidates, and the
    // final scorer decides which category actually wins for that moment.
    return Map<String, double>.fromEntries(sorted.take(4));
  }

  Map<String, double> _publicSignalCategoryScores(AiSignal signal) {
    final result = <String, double>{};

    for (final entry in signal.normalizedCategoryScores.entries) {
      final mood = _canonicalMood(entry.key);
      if (!_isPublicCategory(mood)) continue;
      final value = entry.value.clamp(0.0, 1.0).toDouble();
      if (value <= 0) continue;
      result[mood] = max(result[mood] ?? 0.0, value).toDouble();
    }

    return result;
  }

  double _minSignalCategoryScore(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
      case 'happy':
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
      case 'fight':
      case 'weird':
        return 0.16;
      case 'hook':
      case 'info':
        return 0.15;
      default:
        return 0.12;
    }
  }

  ClipCandidate _scoreCandidate(
    ClipCandidate candidate, {
    required int durationSeconds,
  }) {
    final positiveSignals = candidate.signals.where((signal) => !signal.isNegative).toList();
    final negativeSignals = candidate.signals.where((signal) => signal.isNegative).toList();

    final categorySignalValues = positiveSignals
        .map((signal) =>
            signal.categoryScoreFor(candidate.mood) * signal.normalizedConfidence * signal.weight)
        .where((value) => value > 0)
        .map((value) => value.clamp(0.0, 1.0).toDouble())
        .toList();

    final signalScore = categorySignalValues.isEmpty
        ? 0.0
        : categorySignalValues.fold<double>(0.0, (sum, value) => sum + value) /
            categorySignalValues.length;

    final bestSignalScore = categorySignalValues.isEmpty
        ? 0.0
        : categorySignalValues.reduce(max);

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

    final categoryPrecision = _categoryPrecisionScore(candidate, candidate.mood);
    final categoryScores = _buildPromptCategoryScores(
      candidate,
      finalScore: finalScore,
      confidence: confidence,
      categoryPrecision: categoryPrecision,
    );
    final logicJustifications = _buildTopLogicJustifications(
      candidate,
      categoryScores,
    );

    return candidate.copyWith(
      score: finalScore,
      confidence: confidence,
      categoryPrecision: categoryPrecision,
      categoryScores: categoryScores,
      logicJustifications: logicJustifications,
      title: _titleForMood(candidate.mood),
      reasons: _rankedPublicReasons(candidate, finalScore: finalScore),
    );
  }

  bool _passesQualityGate(ClipCandidate candidate) {
    final mood = _canonicalMood(candidate.mood);

    // First gate: the category must have real evidence. A high score alone is
    // not enough, because loudness or motion can otherwise be mislabelled as
    // funny/sad/emotional.
    if (!_hasRequiredEvidence(candidate, mood)) return false;

    // Second gate: confirm that the detected reason/category is precise enough.
    final precisionScore = _categoryPrecisionScore(candidate, mood);
    if (precisionScore < _minPrecisionForMood(mood)) return false;

    final minScore = _minScoreForMood(mood);
    if (candidate.score < minScore) return false;

    // Prompt rule: categories below 0.4 are filtered out. If this candidate
    // has no category that reaches 0.4, it is not interesting enough to show.
    if (candidate.categoryScores.isEmpty) return false;

    // New precision rule: because every moment is scored against all categories,
    // the chosen mood must actually be the best fitting category with a clear
    // enough gap over the next category. This prevents action clips being shown
    // as fight, happy clips being shown as funny, etc.
    if (!_chosenCategoryWins(candidate, mood)) return false;

    // Avoid accepting very low-confidence clips, even when one weak tag matched.
    if (candidate.confidence < _minConfidenceForMood(mood)) return false;

    // Do not keep weak generic highlights when better category clips exist.
    if (mood == 'highlight' && candidate.score < 0.36) return false;

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
    final perMoodCount = <String, int>{};
    final maxPerSection = _maxPerSectionForTarget(targetCount);

    bool duplicateOfSelected(ClipCandidate candidate) {
      return selected.any((existing) {
        final overlap = candidate.overlapRatio(existing);
        final startDistance = (candidate.startSeconds - existing.startSeconds).abs();
        return overlap >= 0.52 || startDistance <= 4;
      });
    }

    // Rank-first selection: when the same moment can be funny/happy/entertaining,
    // only the highest-scoring category survives. This is more precise than
    // filling categories in a fixed section order.
    for (final candidate in ranked) {
      if (selected.length >= targetCount) break;
      if (duplicateOfSelected(candidate)) continue;

      final mood = _canonicalMood(candidate.mood);
      final usedForMood = perMoodCount[mood] ?? 0;
      if (usedForMood >= maxPerSection) continue;

      selected.add(candidate);
      perMoodCount[mood] = usedForMood + 1;
    }

    selected.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
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
      case 'happy':
        if (sources.contains(AiSignalSource.faceReaction) && tags.any((tag) => tag.contains('happy face') || tag.contains('smile'))) bonus += 0.11;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('happy') || tag.contains('celebration') || tag.contains('crowd'))) bonus += 0.09;
        if (sources.contains(AiSignalSource.transcript) && tags.any((tag) => tag.contains('happy wording'))) bonus += 0.08;
        break;
      case 'romantic':
        if (sources.contains(AiSignalSource.transcript) && tags.any((tag) => tag.contains('romantic'))) bonus += 0.11;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('romantic') || tag.contains('tender'))) bonus += 0.08;
        if (sources.contains(AiSignalSource.faceReaction)) bonus += 0.04;
        break;
      case 'angry':
        if (sources.contains(AiSignalSource.transcript) && tags.any((tag) => tag.contains('angry'))) bonus += 0.11;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('angry') || tag.contains('argument'))) bonus += 0.10;
        if (sources.contains(AiSignalSource.faceReaction) && tags.any((tag) => tag.contains('angry') || tag.contains('serious'))) bonus += 0.07;
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
      case 'fight':
        if (sources.contains(AiSignalSource.visualMotion)) bonus += 0.08;
        if (sources.contains(AiSignalSource.sceneChange)) bonus += 0.07;
        if (sources.contains(AiSignalSource.audioPeak)) bonus += 0.07;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('fight') || tag.contains('impact'))) bonus += 0.11;
        if (sources.contains(AiSignalSource.transcript) && tags.any((tag) => tag.contains('fight'))) bonus += 0.08;
        break;
      case 'entertaining':
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('entertaining') || tag.contains('laughter') || tag.contains('crowd'))) bonus += 0.09;
        if (sources.contains(AiSignalSource.faceReaction) && tags.any((tag) => tag.contains('entertaining') || tag.contains('smile') || tag.contains('reaction'))) bonus += 0.08;
        if (sources.contains(AiSignalSource.visualMotion) || sources.contains(AiSignalSource.sceneChange)) bonus += 0.05;
        if (sources.contains(AiSignalSource.transcript) && tags.any((tag) => tag.contains('entertaining'))) bonus += 0.07;
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

    bool hasTag(List<String> needles) {
      return tags.any((tag) => needles.any((needle) => tag.contains(needle)));
    }

    switch (mood) {
      case 'funny':
        return hasTag(['laughter', 'smile', 'comedy']);
      case 'happy':
        return hasTag(['happy face', 'happy wording', 'smile', 'celebration', 'crowd', 'hype']);
      case 'romantic':
        return hasTag(['romantic', 'tender', 'love', 'wedding']);
      case 'angry':
        return hasTag(['angry', 'argument', 'serious']) ||
            (sources.contains(AiSignalSource.audioEvent) && hasTag(['shout', 'yell']));
      case 'sad':
        return hasTag(['sad', 'cry', 'sobbing', 'loss', 'pain']);
      case 'emotional':
        return hasTag(['emotional', 'heartfelt', 'tender', 'proud', 'family', 'gratitude']) ||
            (sources.contains(AiSignalSource.transcript) && candidate.sourceDiversity >= 2);
      case 'action':
        return sources.contains(AiSignalSource.visualMotion) ||
            sources.contains(AiSignalSource.sceneChange) ||
            sources.contains(AiSignalSource.audioPeak) ||
            (sources.contains(AiSignalSource.audioEvent) && hasTag(['action', 'impact', 'crowd']));
      case 'fight':
        final hasFightAnchor = hasTag(['fight', 'impact', 'punch', 'hit', 'slap', 'attack', 'argument']);
        final hasPhysicalSupport = sources.contains(AiSignalSource.visualMotion) ||
            sources.contains(AiSignalSource.sceneChange) ||
            sources.contains(AiSignalSource.audioPeak) ||
            sources.contains(AiSignalSource.audioEvent);
        return hasFightAnchor && hasPhysicalSupport;
      case 'entertaining':
        return hasTag(['entertaining', 'laughter', 'crowd', 'hype', 'smile', 'music', 'reaction']) ||
            (candidate.sourceDiversity >= 2 && candidate.signalStrength >= 0.26);
      case 'reaction':
        return sources.contains(AiSignalSource.faceReaction) || hasTag(['reaction', 'face', 'head movement', 'eye expression']);
      case 'hook':
      case 'info':
        return sources.contains(AiSignalSource.transcript);
      case 'music':
        return hasTag(['music', 'beat', 'song']) || sources.contains(AiSignalSource.audioPeak);
      case 'viral':
        return hasTag(['crowd', 'hype', 'strong delivery']) ||
            (candidate.sourceDiversity >= 2 && candidate.signalStrength >= 0.30);
      case 'weird':
        return hasTag(['weird', 'unexpected', 'strange']);
      case 'highlight':
        return candidate.sourceDiversity >= 2 || candidate.signalStrength >= 0.35;
      default:
        return false;
    }
  }

  double _categoryPrecisionScore(ClipCandidate candidate, String mood) {
    final canonicalMood = _canonicalMood(mood);
    final sources = candidate.sources;
    final tags = _allTags(candidate);
    final positiveSignalCount = candidate.signals.where((signal) => !signal.isNegative).length;

    double score = 0.0;

    if (_hasStrongCategoryAnchor(candidate, canonicalMood)) score += 0.38;
    if (candidate.sourceDiversity >= 2) score += 0.16;
    if (candidate.sourceDiversity >= 3) score += 0.08;
    if (positiveSignalCount >= 2) score += 0.08;
    if (positiveSignalCount >= 3) score += 0.06;
    if (candidate.signalStrength >= 0.30) score += 0.10;
    if (candidate.signalStrength >= 0.45) score += 0.06;
    if (candidate.confidence >= 0.65) score += 0.10;

    switch (canonicalMood) {
      case 'funny':
        if (tags.any((tag) => tag.contains('laughter'))) score += 0.18;
        if (tags.any((tag) => tag.contains('smile'))) score += 0.12;
        if (tags.any((tag) => tag.contains('comedy'))) score += 0.12;
        break;
      case 'happy':
        if (tags.any((tag) => tag.contains('happy face') || tag.contains('happy wording'))) score += 0.18;
        if (tags.any((tag) => tag.contains('smile'))) score += 0.12;
        if (tags.any((tag) => tag.contains('celebration') || tag.contains('crowd') || tag.contains('hype'))) score += 0.12;
        break;
      case 'romantic':
        if (tags.any((tag) => tag.contains('romantic') || tag.contains('tender'))) score += 0.22;
        if (sources.contains(AiSignalSource.transcript)) score += 0.12;
        if (sources.contains(AiSignalSource.audioEvent)) score += 0.08;
        break;
      case 'angry':
        if (tags.any((tag) => tag.contains('angry') || tag.contains('argument') || tag.contains('serious'))) score += 0.22;
        if (sources.contains(AiSignalSource.transcript)) score += 0.10;
        if (sources.contains(AiSignalSource.audioEvent)) score += 0.10;
        if (sources.contains(AiSignalSource.faceReaction)) score += 0.06;
        break;
      case 'sad':
        if (tags.any((tag) => tag.contains('sad') || tag.contains('cry'))) score += 0.22;
        if (sources.contains(AiSignalSource.transcript)) score += 0.10;
        if (sources.contains(AiSignalSource.faceReaction)) score += 0.06;
        break;
      case 'emotional':
        if (tags.any((tag) => tag.contains('emotional'))) score += 0.16;
        if (sources.contains(AiSignalSource.transcript)) score += 0.12;
        if (sources.contains(AiSignalSource.faceReaction)) score += 0.08;
        break;
      case 'action':
        if (sources.contains(AiSignalSource.visualMotion)) score += 0.12;
        if (sources.contains(AiSignalSource.sceneChange)) score += 0.10;
        if (sources.contains(AiSignalSource.audioEvent) && tags.any((tag) => tag.contains('action'))) score += 0.14;
        if (sources.contains(AiSignalSource.audioPeak)) score += 0.08;
        break;
      case 'fight':
        if (tags.any((tag) => tag.contains('fight') || tag.contains('impact'))) score += 0.20;
        if (sources.contains(AiSignalSource.visualMotion)) score += 0.10;
        if (sources.contains(AiSignalSource.sceneChange)) score += 0.08;
        if (sources.contains(AiSignalSource.audioEvent)) score += 0.10;
        if (sources.contains(AiSignalSource.audioPeak)) score += 0.06;
        break;
      case 'entertaining':
        if (tags.any((tag) => tag.contains('entertaining') || tag.contains('laughter') || tag.contains('crowd') || tag.contains('hype'))) score += 0.18;
        if (sources.contains(AiSignalSource.faceReaction)) score += 0.10;
        if (sources.contains(AiSignalSource.visualMotion) || sources.contains(AiSignalSource.sceneChange)) score += 0.06;
        if (candidate.sourceDiversity >= 2) score += 0.08;
        break;
      case 'reaction':
        if (sources.contains(AiSignalSource.faceReaction)) score += 0.16;
        if (tags.any((tag) => tag.contains('reaction'))) score += 0.14;
        if (sources.contains(AiSignalSource.audioEvent)) score += 0.06;
        break;
      case 'hook':
      case 'info':
        if (sources.contains(AiSignalSource.transcript)) score += 0.22;
        break;
      case 'music':
        if (sources.contains(AiSignalSource.audioEvent)) score += 0.12;
        if (sources.contains(AiSignalSource.audioPeak)) score += 0.10;
        if (tags.any((tag) => tag.contains('music'))) score += 0.12;
        break;
      case 'viral':
        if (tags.any((tag) => tag.contains('crowd') || tag.contains('hype') || tag.contains('strong'))) score += 0.12;
        if (sources.contains(AiSignalSource.audioPeak)) score += 0.08;
        if (candidate.sourceDiversity >= 2) score += 0.08;
        break;
      case 'weird':
        if (tags.any((tag) => tag.contains('weird') || tag.contains('unexpected'))) score += 0.20;
        if (sources.contains(AiSignalSource.transcript)) score += 0.08;
        if (sources.contains(AiSignalSource.audioEvent)) score += 0.08;
        break;
      case 'highlight':
        if (candidate.sourceDiversity >= 2) score += 0.16;
        if (candidate.signalStrength >= 0.40) score += 0.12;
        break;
    }

    // One weak source can suggest a candidate, but should not fully confirm it.
    if (candidate.sourceDiversity == 1 && positiveSignalCount == 1) score -= 0.08;

    return score.clamp(0.0, 1.0).toDouble();
  }

  bool _hasStrongCategoryAnchor(ClipCandidate candidate, String mood) {
    final canonicalMood = _canonicalMood(mood);
    final sources = candidate.sources;
    final tags = _allTags(candidate);

    switch (canonicalMood) {
      case 'funny':
        return tags.any((tag) => tag.contains('laughter') || tag.contains('smile') || tag.contains('comedy'));
      case 'happy':
        return tags.any((tag) =>
            tag.contains('happy face') ||
            tag.contains('happy wording') ||
            tag.contains('smile') ||
            tag.contains('celebration') ||
            tag.contains('crowd') ||
            tag.contains('hype'));
      case 'romantic':
        return tags.any((tag) => tag.contains('romantic') || tag.contains('tender'));
      case 'angry':
        return tags.any((tag) => tag.contains('angry') || tag.contains('argument') || tag.contains('serious'));
      case 'sad':
        return tags.any((tag) => tag.contains('sad') || tag.contains('cry'));
      case 'emotional':
        return tags.any((tag) => tag.contains('emotional')) || sources.contains(AiSignalSource.transcript);
      case 'action':
        return tags.any((tag) => tag.contains('action') || tag.contains('motion') || tag.contains('scene change') || tag.contains('loudness'));
      case 'fight':
        return tags.any((tag) => tag.contains('fight') || tag.contains('impact') || tag.contains('action')) ||
            sources.contains(AiSignalSource.audioPeak);
      case 'entertaining':
        return tags.any((tag) => tag.contains('entertaining') || tag.contains('laughter') || tag.contains('crowd') || tag.contains('hype') || tag.contains('smile')) ||
            candidate.sourceDiversity >= 2;
      case 'reaction':
        return tags.any((tag) => tag.contains('reaction') || tag.contains('face') || tag.contains('head movement') || tag.contains('eye expression'));
      case 'hook':
      case 'info':
        return sources.contains(AiSignalSource.transcript);
      case 'music':
        return tags.any((tag) => tag.contains('music')) || sources.contains(AiSignalSource.audioPeak);
      case 'viral':
        return tags.any((tag) => tag.contains('crowd') || tag.contains('hype') || tag.contains('strong delivery')) ||
            candidate.sourceDiversity >= 2;
      case 'weird':
        return tags.any((tag) => tag.contains('weird') || tag.contains('unexpected') || tag.contains('strange'));
      case 'highlight':
        return candidate.sourceDiversity >= 2 || candidate.signalStrength >= 0.35;
      default:
        return false;
    }
  }


  bool _chosenCategoryWins(ClipCandidate candidate, String mood) {
    final canonicalMood = _canonicalMood(mood);
    final categoryScore = candidate.categoryScoreFor(canonicalMood);
    if (categoryScore < _minTopCategoryScoreForMood(canonicalMood)) return false;

    final sorted = candidate.categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) return false;

    final top = sorted.first;
    if (top.key != canonicalMood && top.value > categoryScore + 0.02) {
      return false;
    }

    final second = candidate.secondCategoryScoreFor(canonicalMood);
    final gap = categoryScore - second;
    final requiredGap = _minDominanceGapForMood(canonicalMood);

    // Very strong anchor categories can still pass with a slightly smaller gap.
    if (categoryScore >= 0.82 && _hasStrongCategoryAnchor(candidate, canonicalMood)) {
      return gap >= requiredGap * 0.55;
    }

    return gap >= requiredGap || candidate.categoryScores.length == 1;
  }

  double _minTopCategoryScoreForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
      case 'happy':
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
      case 'fight':
      case 'weird':
        return 0.48;
      case 'action':
      case 'entertaining':
      case 'reaction':
        return 0.44;
      default:
        return 0.40;
    }
  }

  double _minDominanceGapForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
      case 'happy':
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
      case 'fight':
      case 'weird':
        return 0.10;
      case 'action':
      case 'entertaining':
      case 'reaction':
      case 'viral':
        return 0.07;
      default:
        return 0.06;
    }
  }

  Map<String, double> _buildPromptCategoryScores(
    ClipCandidate candidate, {
    required double finalScore,
    required double confidence,
    required double categoryPrecision,
  }) {
    final result = <String, double>{};
    final tags = _allTags(candidate);
    final positiveSignals = candidate.signals.where((signal) => !signal.isNegative).toList();

    for (final category in _promptCategories) {
      final categorySignalScores = positiveSignals
          .map((signal) =>
              signal.categoryScoreFor(category) * signal.normalizedConfidence * signal.weight)
          .where((score) => score > 0)
          .map((score) => score.clamp(0.0, 1.0).toDouble())
          .toList();

      final strongestCategorySignal = categorySignalScores.isEmpty
          ? 0.0
          : categorySignalScores.reduce(max).clamp(0.0, 1.0).toDouble();

      final averageCategorySignal = categorySignalScores.isEmpty
          ? 0.0
          : (categorySignalScores.fold<double>(0.0, (sum, value) => sum + value) /
                  categorySignalScores.length)
              .clamp(0.0, 1.0)
              .toDouble();

      double score = 0.0;

      // Direct category evidence from the actual signal mood.
      score += strongestCategorySignal * 0.46;
      score += averageCategorySignal * 0.20;

      // Strong category anchors are evidence like laughter for funny, crying for sad,
      // fight/impact tags for fight, romantic words for romantic, etc.
      if (_tagsSupportPromptCategory(tags, category)) score += 0.20;
      if (_hasRequiredEvidence(candidate, category)) score += 0.10;

      // If this candidate's main mood is this category, use the final scorer's
      // confidence and precision to lift the matching category.
      if (_canonicalMood(candidate.mood) == category) {
        score += finalScore * 0.16;
        score += categoryPrecision * 0.16;
        score += confidence * 0.08;
      } else if (candidate.sourceDiversity >= 2 && strongestCategorySignal >= 0.16) {
        // Secondary categories can appear, but only when real signals exist.
        score += 0.07;
      }

      // A single weak signal should not push a category over the public threshold.
      if (categorySignalScores.length <= 1 && !_tagsSupportPromptCategory(tags, category)) {
        score -= 0.08;
      }

      final normalized = score.clamp(0.0, 1.0).toDouble();
      if (normalized >= 0.40) {
        result[category] = _roundScore(normalized);
      }
    }

    final sorted = result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Map<String, double>.fromEntries(sorted);
  }

  Map<String, String> _buildTopLogicJustifications(
    ClipCandidate candidate,
    Map<String, double> categoryScores,
  ) {
    if (categoryScores.isEmpty) return const {};

    final topEntries = categoryScores.entries.take(2);
    final result = <String, String>{};

    for (final entry in topEntries) {
      result[entry.key] = _logicJustificationForPromptCategory(candidate, entry.key);
    }

    return result;
  }

  String _logicJustificationForPromptCategory(ClipCandidate candidate, String category) {
    final tags = _allTags(candidate);
    final sources = candidate.sources;
    final evidence = <String>[];

    void add(String text) {
      if (!evidence.contains(text)) evidence.add(text);
    }

    switch (_canonicalMood(category)) {
      case 'funny':
        if (tags.any((tag) => tag.contains('laughter'))) add('laughter audio');
        if (tags.any((tag) => tag.contains('smile'))) add('smiling face reaction');
        if (tags.any((tag) => tag.contains('comedy'))) add('comedy wording');
        break;
      case 'happy':
        if (tags.any((tag) => tag.contains('happy') || tag.contains('smile'))) add('positive facial reaction');
        if (tags.any((tag) => tag.contains('celebration') || tag.contains('crowd') || tag.contains('hype'))) add('celebration or crowd energy');
        break;
      case 'sad':
        if (tags.any((tag) => tag.contains('sad') || tag.contains('cry'))) add('sad or crying evidence');
        if (sources.contains(AiSignalSource.transcript)) add('sad speech meaning');
        break;
      case 'emotional':
        if (tags.any((tag) => tag.contains('emotional'))) add('heartfelt emotional wording or sound');
        if (sources.contains(AiSignalSource.faceReaction)) add('face/reaction evidence');
        break;
      case 'romantic':
        if (tags.any((tag) => tag.contains('romantic') || tag.contains('tender'))) add('romantic or tender evidence');
        if (sources.contains(AiSignalSource.transcript)) add('love/relationship wording');
        break;
      case 'angry':
        if (tags.any((tag) => tag.contains('angry') || tag.contains('argument'))) add('anger, argument, or shouting evidence');
        if (tags.any((tag) => tag.contains('serious'))) add('serious face reaction');
        break;
      case 'action':
        if (sources.contains(AiSignalSource.visualMotion)) add('strong visual motion');
        if (sources.contains(AiSignalSource.sceneChange)) add('scene change energy');
        if (tags.any((tag) => tag.contains('action'))) add('action sound');
        if (sources.contains(AiSignalSource.audioPeak)) add('audio peak');
        break;
      case 'fight':
        if (tags.any((tag) => tag.contains('fight') || tag.contains('impact'))) add('fight or impact evidence');
        if (sources.contains(AiSignalSource.visualMotion)) add('physical movement');
        if (sources.contains(AiSignalSource.audioPeak)) add('impact-like audio peak');
        break;
      case 'weird':
        if (tags.any((tag) => tag.contains('weird') || tag.contains('unexpected') || tag.contains('strange'))) add('weird or unexpected evidence');
        if (sources.contains(AiSignalSource.faceReaction)) add('reaction face');
        break;
      case 'entertaining':
        if (tags.any((tag) => tag.contains('entertaining') || tag.contains('laughter') || tag.contains('crowd') || tag.contains('hype'))) add('fun/crowd/laughter evidence');
        if (candidate.sourceDiversity >= 2) add('multiple AI signals agreed');
        break;
    }

    if (evidence.isEmpty && candidate.sourceDiversity >= 2) {
      add('multiple AI signals supported this moment');
    }
    if (evidence.isEmpty) {
      add(_publicReasonForMood(category));
    }

    return '${evidence.take(3).join(', ')}.';
  }

  bool _tagsSupportPromptCategory(List<String> tags, String category) {
    switch (_canonicalMood(category)) {
      case 'funny':
        return tags.any((tag) => tag.contains('laughter') || tag.contains('comedy'));
      case 'happy':
        return tags.any((tag) => tag.contains('happy') || tag.contains('smile') || tag.contains('celebration') || tag.contains('crowd') || tag.contains('hype'));
      case 'sad':
        return tags.any((tag) => tag.contains('sad') || tag.contains('cry'));
      case 'emotional':
        return tags.any((tag) => tag.contains('emotional') || tag.contains('tender'));
      case 'romantic':
        return tags.any((tag) => tag.contains('romantic') || tag.contains('tender'));
      case 'angry':
        return tags.any((tag) => tag.contains('angry') || tag.contains('argument') || tag.contains('serious'));
      case 'action':
        return tags.any((tag) => tag.contains('action') || tag.contains('motion') || tag.contains('scene change') || tag.contains('loudness'));
      case 'fight':
        return tags.any((tag) => tag.contains('fight') || tag.contains('impact') || tag.contains('punch') || tag.contains('hit'));
      case 'weird':
        return tags.any((tag) => tag.contains('weird') || tag.contains('unexpected') || tag.contains('strange'));
      case 'entertaining':
        return tags.any((tag) => tag.contains('entertaining') || tag.contains('laughter') || tag.contains('crowd') || tag.contains('hype') || tag.contains('smile'));
      default:
        return false;
    }
  }

  double _roundScore(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return double.parse(clamped.toStringAsFixed(2));
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

    if ((mood == 'funny' || mood == 'happy' || mood == 'sad' || mood == 'emotional' || mood == 'romantic' || mood == 'angry' || mood == 'entertaining' || mood == 'hook' || mood == 'info') &&
        sources.length == 1 &&
        sources.contains(AiSignalSource.audioPeak)) {
      penalty += 0.35;
    }

    if ((mood == 'hook' || mood == 'info') && !sources.contains(AiSignalSource.transcript)) {
      penalty += 0.30;
    }

    if ((mood == 'funny' || mood == 'happy' || mood == 'romantic' || mood == 'angry' || mood == 'entertaining') &&
        !sources.contains(AiSignalSource.audioEvent) &&
        !sources.contains(AiSignalSource.faceReaction) &&
        !sources.contains(AiSignalSource.transcript)) {
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
      case 'romantic':
      case 'angry':
        return 24;
      case 'funny':
      case 'happy':
      case 'entertaining':
      case 'reaction':
        return 14;
      case 'action':
      case 'fight':
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
      case 'happy':
        return const _ClipPadding(3, 4);
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
        return const _ClipPadding(4, 5);
      case 'hook':
      case 'info':
        return const _ClipPadding(3, 4);
      case 'action':
      case 'fight':
        return const _ClipPadding(1, 4);
      case 'viral':
      case 'entertaining':
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
      case 'joy':
      case 'joyful':
      case 'celebration':
      case 'celebrate':
        return 'happy';
      case 'love':
      case 'romance':
      case 'couple':
        return 'romantic';
      case 'mad':
      case 'anger':
      case 'argument':
        return 'angry';
      case 'fighting':
      case 'combat':
        return 'fight';
      case 'entertainment':
      case 'fun':
      case 'interesting':
        return 'entertaining';
      case 'strange':
      case 'unexpected':
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
      case 'happy':
        return 'Happy Clip';
      case 'sad':
        return 'Sad Clip';
      case 'romantic':
        return 'Romantic Clip';
      case 'angry':
        return 'Angry Clip';
      case 'emotional':
        return 'Emotional Clip';
      case 'action':
        return 'Action Clip';
      case 'fight':
        return 'Fight Clip';
      case 'entertaining':
        return 'Entertaining Clip';
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
      if (_categoryPrecisionScore(candidate, candidate.mood) >= _minPrecisionForMood(candidate.mood))
        'The clip was checked against all categories and this category matched best.',
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
      case 'happy':
        return 'This part has smile, celebration, joy, or positive reaction evidence.';
      case 'sad':
        return 'This part has sad, crying, loss, or serious emotional evidence.';
      case 'romantic':
        return 'This part has romantic, love, couple, wedding, or tender emotional evidence.';
      case 'angry':
        return 'This part has anger, argument, shouting, serious face, or conflict evidence.';
      case 'emotional':
        return 'This part has heartfelt or emotionally important evidence.';
      case 'action':
        return 'This part has motion, impact, scene change, or high action energy.';
      case 'fight':
        return 'This part has fight, hit, punch, attack, impact, or physical conflict evidence.';
      case 'entertaining':
        return 'This part has fun, retention, laughter, crowd, music, visual, or reaction evidence.';
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
      case 'romantic':
      case 'angry':
        return 6;
      case 'music':
      case 'action':
      case 'fight':
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
      case 'romantic':
      case 'angry':
        return 45;
      case 'music':
        return 24;
      case 'action':
      case 'fight':
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
      case 'romantic':
      case 'angry':
        return 26;
      case 'music':
        return 14;
      case 'action':
      case 'fight':
      case 'viral':
        return 15;
      case 'funny':
      case 'happy':
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
      case 'funny':
      case 'happy':
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
      case 'weird':
        return 0.34;
      case 'hook':
      case 'info':
        return 0.32;
      case 'action':
      case 'fight':
      case 'entertaining':
      case 'reaction':
      case 'music':
      case 'viral':
        return 0.28;
      case 'highlight':
        return 0.36;
      default:
        return 0.32;
    }
  }

  double _minPrecisionForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
      case 'happy':
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
      case 'weird':
        return 0.72;
      case 'hook':
      case 'info':
        return 0.68;
      case 'action':
      case 'entertaining':
      case 'reaction':
      case 'viral':
        return 0.66;
      case 'fight':
        return 0.72;
      case 'music':
        return 0.62;
      case 'highlight':
        return 0.58;
      default:
        return 0.65;
    }
  }

  double _minConfidenceForMood(String mood) {
    switch (_canonicalMood(mood)) {
      case 'funny':
      case 'happy':
      case 'sad':
      case 'emotional':
      case 'romantic':
      case 'angry':
      case 'hook':
      case 'info':
      case 'weird':
        return 0.55;
      case 'highlight':
        return 0.50;
      default:
        return 0.48;
    }
  }

  int _maxPerSectionForTarget(int targetCount) {
    if (targetCount <= 10) return 3;
    if (targetCount <= 20) return 4;
    return 5;
  }

  List<String> get _promptCategories => const [
        'sad',
        'happy',
        'action',
        'weird',
        'emotional',
        'romantic',
        'angry',
        'funny',
        'entertaining',
        'fight',
      ];

  List<String> get _sectionOrder => const [
        'funny',
        'happy',
        'sad',
        'emotional',
        'romantic',
        'angry',
        'action',
        'fight',
        'weird',
        'entertaining',
        'reaction',
        'hook',
        'info',
        'music',
        'viral',
        'highlight',
      ];


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
