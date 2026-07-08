class AiSuggestion {
  final String title;
  final String mood;
  final int startSeconds;
  final int endSeconds;

  /// Global confidence: how sure the AI is about this suggested clip.
  /// This is not a category/mood.
  final double confidence;

  /// Final clip quality score after all signals, support bonuses, and penalties.
  final double score;

  /// Confirms that the selected mood/category really matches the evidence.
  final double categoryPrecision;

  /// How many different AI signal types agreed: audio, transcript, visual, face, etc.
  final int sourceDiversity;

  /// Category scores in the prompt format.
  /// Only categories with score >= 0.4 are stored here.
  /// Example keys: sad, happy, action, weird, emotional, romantic, angry,
  /// funny, entertaining, fight.
  final Map<String, double> categoryScores;

  /// Logic justification for the top 2 categories only.
  /// Keys match [categoryScores].
  final Map<String, String> logicJustifications;

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
    this.categoryScores = const {},
    this.logicJustifications = const {},
    this.reason = const [],
  });

  int get durationSeconds => endSeconds - startSeconds;

  // Backward compatibility for older UI code.
  String get label => mood;

  int get confidencePercent => (confidence.clamp(0.0, 1.0) * 100).round();

  int get scorePercent => (score.clamp(0.0, 1.0) * 100).round();

  int get categoryPrecisionPercent =>
      (categoryPrecision.clamp(0.0, 1.0) * 100).round();

  String get topCategory {
    if (categoryScores.isEmpty) return mood;
    final sorted = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  double get topCategoryScore {
    if (categoryScores.isEmpty) return 0.0;
    final sorted = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.value.clamp(0.0, 1.0).toDouble();
  }

  double get secondCategoryScore {
    if (categoryScores.length < 2) return 0.0;
    final sorted = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted[1].value.clamp(0.0, 1.0).toDouble();
  }

  double get categoryDominanceGap =>
      (topCategoryScore - secondCategoryScore).clamp(0.0, 1.0).toDouble();

  /// JSON output matching your system prompt.
  /// Returns only categories >= 0.4, and includes logic justification only
  /// for the top 2 categories.
  Map<String, dynamic> toCategoryAnalysisJson() {
    if (categoryScores.isEmpty) return <String, dynamic>{};

    final sortedEntries = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final categories = <String, dynamic>{};

    for (final entry in sortedEntries) {
      final category = entry.key;
      final justification = logicJustifications[category];

      categories[category] = {
        'score': _roundScore(entry.value),
        if (justification != null && justification.trim().isNotEmpty)
          'logic_justification': justification,
      };
    }

    return {
      'categories': categories,
      'confidence': _roundScore(confidence),
    };
  }

  factory AiSuggestion.fromJson(Map<String, dynamic> json) {
    final rawCategoryScores = json['category_scores'];
    final rawLogic = json['logic_justifications'];

    return AiSuggestion(
      title: json['title'] as String? ?? 'Suggested Clip',
      mood: json['mood'] as String? ?? json['label'] as String? ?? 'highlight',
      startSeconds: _numberToInt(json['start_seconds']),
      endSeconds: _numberToInt(json['end_seconds']),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.75,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      categoryPrecision:
          (json['category_precision'] as num?)?.toDouble() ?? 0.0,
      sourceDiversity: (json['source_diversity'] as num?)?.round() ?? 0,
      categoryScores: _readScoreMap(rawCategoryScores),
      logicJustifications: _readStringMap(rawLogic),
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
      'category_scores': categoryScores,
      'logic_justifications': logicJustifications,
      'category_analysis': toCategoryAnalysisJson(),
      'reason': reason,
    };
  }

  static int _numberToInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, double> _readScoreMap(Object? value) {
    if (value is! Map) return const {};

    final result = <String, double>{};
    value.forEach((key, raw) {
      final score = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
      if (score == null) return;
      result[key.toString()] = score.clamp(0.0, 1.0).toDouble();
    });
    return result;
  }

  static Map<String, String> _readStringMap(Object? value) {
    if (value is! Map) return const {};

    final result = <String, String>{};
    value.forEach((key, raw) {
      final text = raw?.toString().trim() ?? '';
      if (text.isEmpty) return;
      result[key.toString()] = text;
    });
    return result;
  }

  static double _roundScore(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return double.parse(clamped.toStringAsFixed(2));
  }
}
