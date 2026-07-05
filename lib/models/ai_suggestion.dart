class AiSuggestion {
  final String title;
  final String mood;
  final int startSeconds;
  final int endSeconds;
  final double confidence;
  final List<String> reason;

  const AiSuggestion({
    required this.title,
    required this.mood,
    required this.startSeconds,
    required this.endSeconds,
    required this.confidence,
    this.reason = const [],
  });

  int get durationSeconds => endSeconds - startSeconds;

  // Backward compatibility for older UI code
  String get label => mood;

  factory AiSuggestion.fromJson(Map<String, dynamic> json) {
    return AiSuggestion(
      title: json['title'] as String? ?? 'Suggested Clip',
      mood: json['mood'] as String? ?? json['label'] as String? ?? 'highlight',
      startSeconds: json['start_seconds'] as int? ?? 0,
      endSeconds: json['end_seconds'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.75,
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
      'reason': reason,
    };
  }
}