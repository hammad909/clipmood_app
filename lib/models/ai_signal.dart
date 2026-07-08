enum AiSignalSource {
  audioEvent,
  audioPeak,
  transcript,
  visualMotion,
  sceneChange,
  faceReaction,
  userFeedback,
}

extension AiSignalSourceX on AiSignalSource {
  String get label {
    switch (this) {
      case AiSignalSource.audioEvent:
        return 'Audio Event';
      case AiSignalSource.audioPeak:
        return 'Audio Peak';
      case AiSignalSource.transcript:
        return 'Transcript';
      case AiSignalSource.visualMotion:
        return 'Visual Motion';
      case AiSignalSource.sceneChange:
        return 'Scene Change';
      case AiSignalSource.faceReaction:
        return 'Face / Reaction';
      case AiSignalSource.userFeedback:
        return 'User Feedback';
    }
  }

  int get basePriority {
    switch (this) {
      case AiSignalSource.transcript:
        return 5;
      case AiSignalSource.faceReaction:
        return 5;
      case AiSignalSource.audioEvent:
        return 4;
      case AiSignalSource.sceneChange:
        return 3;
      case AiSignalSource.visualMotion:
        return 3;
      case AiSignalSource.audioPeak:
        return 2;
      case AiSignalSource.userFeedback:
        return 6;
    }
  }
}

class AiSignal {
  final int startSeconds;
  final int endSeconds;
  final AiSignalSource source;

  /// Backward-compatible main category label. The scorer now also uses
  /// [categoryScores] so one signal can support multiple possible categories.
  final String mood;
  final double strength;
  final double confidence;
  final double weight;
  final List<String> tags;
  final List<String> reasons;
  final Map<String, Object?> metadata;

  /// Scores for all categories this signal supports.
  /// Example: laughter can support funny, happy, entertaining, and reaction.
  /// Values must stay between 0.0 and 1.0.
  final Map<String, double> categoryScores;

  /// A negative signal means "do not prefer this moment".
  /// Example: mostly silence, damaged audio, unusable transcript, etc.
  final bool isNegative;

  const AiSignal({
    required this.startSeconds,
    required this.endSeconds,
    required this.source,
    required this.mood,
    required this.strength,
    required this.confidence,
    this.weight = 1.0,
    this.tags = const [],
    this.reasons = const [],
    this.metadata = const {},
    this.categoryScores = const {},
    this.isNegative = false,
  });

  int get durationSeconds => endSeconds - startSeconds;

  double get normalizedStrength => strength.clamp(0.0, 1.0).toDouble();

  double get normalizedConfidence => confidence.clamp(0.0, 1.0).toDouble();

  double get weightedScore {
    final base = normalizedStrength * normalizedConfidence * weight;
    return (isNegative ? -base : base).clamp(-1.0, 1.0).toDouble();
  }

  /// Returns the category score for a category. If old code creates a signal
  /// without [categoryScores], this falls back to the main [mood].
  double categoryScoreFor(String category) {
    final key = _canonicalCategory(category);
    final direct = categoryScores[key];
    if (direct != null) return direct.clamp(0.0, 1.0).toDouble();
    return _canonicalCategory(mood) == key ? normalizedStrength : 0.0;
  }

  /// Safe category map for scorer usage. Includes the old [mood] as fallback.
  Map<String, double> get normalizedCategoryScores {
    final result = <String, double>{};
    for (final entry in categoryScores.entries) {
      final key = _canonicalCategory(entry.key);
      final value = entry.value.clamp(0.0, 1.0).toDouble();
      if (value <= 0) continue;
      final existing = result[key] ?? 0.0;
      if (value > existing) result[key] = value;
    }

    if (result.isEmpty && mood.trim().isNotEmpty) {
      result[_canonicalCategory(mood)] = normalizedStrength;
    }

    return result;
  }

  String get topCategory {
    final entries = normalizedCategoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.isEmpty ? _canonicalCategory(mood) : entries.first.key;
  }

  double get topCategoryScore {
    final entries = normalizedCategoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.isEmpty ? normalizedStrength : entries.first.value;
  }

  double get secondCategoryScore {
    final entries = normalizedCategoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.length < 2 ? 0.0 : entries[1].value;
  }

  double get categoryDominanceGap =>
      (topCategoryScore - secondCategoryScore).clamp(0.0, 1.0).toDouble();

  bool get isUsable {
    return endSeconds > startSeconds && !isNegative && weightedScore >= 0.06;
  }

  bool overlapsRange(int start, int end) {
    return startSeconds < end && endSeconds > start;
  }

  bool isNear(AiSignal other, {int maxGapSeconds = 4}) {
    if (overlapsRange(other.startSeconds, other.endSeconds)) return true;

    final gap = startSeconds > other.endSeconds
        ? startSeconds - other.endSeconds
        : other.startSeconds - endSeconds;

    return gap <= maxGapSeconds;
  }

  AiSignal copyWith({
    int? startSeconds,
    int? endSeconds,
    AiSignalSource? source,
    String? mood,
    double? strength,
    double? confidence,
    double? weight,
    List<String>? tags,
    List<String>? reasons,
    Map<String, Object?>? metadata,
    Map<String, double>? categoryScores,
    bool? isNegative,
  }) {
    return AiSignal(
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      source: source ?? this.source,
      mood: mood ?? this.mood,
      strength: strength ?? this.strength,
      confidence: confidence ?? this.confidence,
      weight: weight ?? this.weight,
      tags: tags ?? this.tags,
      reasons: reasons ?? this.reasons,
      metadata: metadata ?? this.metadata,
      categoryScores: categoryScores ?? this.categoryScores,
      isNegative: isNegative ?? this.isNegative,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'source': source.name,
      'mood': mood,
      'strength': strength,
      'confidence': confidence,
      'weight': weight,
      'tags': tags,
      'reasons': reasons,
      'metadata': metadata,
      'category_scores': normalizedCategoryScores,
      'top_category': topCategory,
      'top_category_score': topCategoryScore,
      'second_category_score': secondCategoryScore,
      'category_dominance_gap': categoryDominanceGap,
      'is_negative': isNegative,
      'weighted_score': weightedScore,
    };
  }

  static String _canonicalCategory(String value) {
    final lower = value.toLowerCase().trim();
    switch (lower) {
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
      case 'exciting':
        return 'music';
      case 'information':
      case 'informative':
      case 'educational':
        return 'info';
      default:
        return lower;
    }
  }
}
