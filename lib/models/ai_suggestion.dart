class AiSuggestion {
  final String title;
  final String mood;
  final int startSeconds;
  final int endSeconds;

  /// Existing app score. Keep using this in old UI.
  final double confidence;

  /// New: final clip quality score after all signals and penalties.
  final double score;

  /// New: confirms that the clip really matches its category/mood.
  /// Example: a Funny clip should be confirmed by laughter, smile, comedy words, etc.
  final double categoryPrecision;

  /// New: how many signal types agreed: audio, transcript, visual, face, etc.
  final int sourceDiversity;

  final List<String> reason;

  const AiSuggestion({
    required this.title,
    required this.mood,
    required this.startSeconds,
    required this.endSeconds,
    required this.confidence,
    this.score = 0.0,
    this.categoryPrecision = 0.0,
    this.sourceDiversity = 0,
    this.reason = const [],
  });

  int get durationSeconds => endSeconds - startSeconds;

  // Backward compatibility for older UI code.
  String get label => mood;

  int get confidencePercent => (confidence.clamp(0.0, 1.0) * 100).round();

  int get scorePercent => (score.clamp(0.0, 1.0) * 100).round();

  int get categoryPrecisionPercent =>
      (categoryPrecision.clamp(0.0, 1.0) * 100).round();

  factory AiSuggestion.fromJson(Map<String, dynamic> json) {
    return AiSuggestion(
      title: json['title'] as String? ?? 'Suggested Clip',
      mood: json['mood'] as String? ?? json['label'] as String? ?? 'highlight',
      startSeconds: json['start_seconds'] as int? ?? 0,
      endSeconds: json['end_seconds'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.75,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      categoryPrecision:
          (json['category_precision'] as num?)?.toDouble() ?? 0.0,
      sourceDiversity: (json['source_diversity'] as num?)?.round() ?? 0,
      reason: (json['reason'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'mood': mood,
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'confidence': confidence,
      'score': score,
      'category_precision': categoryPrecision,
      'source_diversity': sourceDiversity,
      'reason': reason,
    };
  }
}
