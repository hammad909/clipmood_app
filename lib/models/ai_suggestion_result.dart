import 'ai_suggestion.dart';

class AiSuggestionResult {
  final String videoId;
  final String videoName;
  final int durationSeconds;
  final String modelVersion;
  final List<AiSuggestion> suggestions;

  const AiSuggestionResult({
    required this.videoId,
    required this.videoName,
    required this.durationSeconds,
    required this.modelVersion,
    required this.suggestions,
  });

  factory AiSuggestionResult.fromJson(Map<String, dynamic> json) {
    final suggestionsJson = json['suggestions'] as List? ?? [];

    return AiSuggestionResult(
      videoId: json['video_id'] as String? ?? '',
      videoName: json['video_name'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      modelVersion: json['model_version'] as String? ?? 'local-v1',
      suggestions: suggestionsJson
          .map((item) => AiSuggestion.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
      'video_name': videoName,
      'duration_seconds': durationSeconds,
      'model_version': modelVersion,
      'suggestions': suggestions.map((item) => item.toJson()).toList(),
    };
  }
}