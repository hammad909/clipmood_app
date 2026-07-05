class TranscriptSegment {
  final int startSeconds;
  final int endSeconds;
  final String text;
  final double confidence;
  final String source;

  const TranscriptSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
    this.confidence = 0.75,
    this.source = 'on-device',
  });

  int get durationSeconds => endSeconds - startSeconds;

  String get normalizedText => text.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool get isUsable => normalizedText.length >= 4 && endSeconds > startSeconds;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    final start = json['start_seconds'] ??
        json['startSecond'] ??
        json['start'] ??
        json['start_time'] ??
        0;

    final end = json['end_seconds'] ??
        json['endSecond'] ??
        json['end'] ??
        json['end_time'] ??
        0;

    return TranscriptSegment(
      startSeconds: _numberToSeconds(start),
      endSeconds: _numberToSeconds(end),
      text: json['text']?.toString() ?? json['transcript']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.75,
      source: json['source']?.toString() ?? 'on-device',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'text': text,
      'confidence': confidence,
      'source': source,
    };
  }

  static int _numberToSeconds(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.round();

    final parsed = double.tryParse(value?.toString() ?? '0') ?? 0;
    return parsed.round();
  }
}

class TranscriptAnalysisResult {
  final List<TranscriptSegment> segments;
  final String source;

  /// Number of speech chunks the app prepared for local transcription.
  /// This is useful before the real TFLite/STT engine is plugged in.
  final int speechCandidateCount;

  /// True only when a local/on-device transcription engine is available.
  final bool engineReady;

  /// True when transcript segments came from the local/on-device engine.
  final bool ranOnDevice;

  /// True when transcript segments came from a local JSON sidecar file.
  /// This is only for testing/tuning; it is not a backend call.
  final bool usedLocalSidecar;

  const TranscriptAnalysisResult({
    required this.segments,
    required this.source,
    this.speechCandidateCount = 0,
    this.engineReady = false,
    this.ranOnDevice = false,
    this.usedLocalSidecar = false,
  });

  bool get hasTranscript => segments.isNotEmpty;

  bool get hasSpeechCandidates => speechCandidateCount > 0;
}
