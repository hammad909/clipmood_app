class SpeechTranscriptionTask {
  final int startSeconds;
  final int endSeconds;
  final double priority;
  final String reason;

  const SpeechTranscriptionTask({
    required this.startSeconds,
    required this.endSeconds,
    required this.priority,
    required this.reason,
  });

  int get durationSeconds => endSeconds - startSeconds;

  bool get isUsable => endSeconds > startSeconds && durationSeconds >= 1;

  Map<String, dynamic> toJson() {
    return {
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'priority': priority,
      'reason': reason,
    };
  }
}
