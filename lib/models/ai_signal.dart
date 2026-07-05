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
  final String mood;
  final double strength;
  final double confidence;
  final double weight;
  final List<String> tags;
  final List<String> reasons;
  final Map<String, Object?> metadata;

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
    this.isNegative = false,
  });

  int get durationSeconds => endSeconds - startSeconds;

  double get normalizedStrength => strength.clamp(0.0, 1.0).toDouble();

  double get normalizedConfidence => confidence.clamp(0.0, 1.0).toDouble();

  double get weightedScore {
    final base = normalizedStrength * normalizedConfidence * weight;
    return (isNegative ? -base : base).clamp(-1.0, 1.0).toDouble();
  }

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
      'is_negative': isNegative,
      'weighted_score': weightedScore,
    };
  }
}
