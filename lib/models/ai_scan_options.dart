import 'dart:math';

/// Controls how much local AI work ClipMood should do for one scan.
///
/// This keeps the product practical on real phones. Creators can choose quick
/// previews or slower/high-accuracy scans without changing the AI architecture.
enum AiScanMode {
  fast,
  balanced,
  accurate,
}

extension AiScanModeX on AiScanMode {
  String get label {
    switch (this) {
      case AiScanMode.fast:
        return 'Fast';
      case AiScanMode.balanced:
        return 'Balanced';
      case AiScanMode.accurate:
        return 'Accurate';
    }
  }

  String get helperText {
    switch (this) {
      case AiScanMode.fast:
        return 'Quick scan. Uses audio + light visual signals. Does not run slow Whisper transcription unless a cached transcript already exists.';
      case AiScanMode.balanced:
        return 'Recommended. Uses audio, selected local Whisper chunks, visual signals, and face/reaction signals.';
      case AiScanMode.accurate:
        return 'Best quality. Scans more windows and allows more local Whisper chunks. Slower on phones.';
    }
  }

  bool get isFast => this == AiScanMode.fast;
  bool get isBalanced => this == AiScanMode.balanced;
  bool get isAccurate => this == AiScanMode.accurate;
}

class AiScanOptions {
  final AiScanMode mode;
  final bool enableAudioEvents;
  final bool enableAudioPeaks;
  final bool enableTranscription;
  final bool enableVisualSignals;
  final bool enableFaceReaction;

  /// If false, TranscriptService can still read an existing transcript cache,
  /// but it will not run the heavy on-device Whisper engine.
  final bool allowTranscriptionEngineRun;

  /// Limits how many speech chunks local Whisper can process in one scan.
  final int maxSpeechTranscriptionTasks;

  /// Optional hard cap for YAMNet windows. Leave null to use mode defaults.
  final int? maxYamnetWindowsOverride;

  const AiScanOptions({
    this.mode = AiScanMode.balanced,
    this.enableAudioEvents = true,
    this.enableAudioPeaks = true,
    this.enableTranscription = true,
    this.enableVisualSignals = true,
    this.enableFaceReaction = true,
    this.allowTranscriptionEngineRun = true,
    this.maxSpeechTranscriptionTasks = 18,
    this.maxYamnetWindowsOverride,
  });

  factory AiScanOptions.forMode(AiScanMode mode) {
    switch (mode) {
      case AiScanMode.fast:
        return const AiScanOptions(
          mode: AiScanMode.fast,
          enableAudioEvents: true,
          enableAudioPeaks: true,
          enableTranscription: true,
          enableVisualSignals: true,
          enableFaceReaction: false,
          allowTranscriptionEngineRun: false,
          maxSpeechTranscriptionTasks: 0,
        );
      case AiScanMode.balanced:
        return const AiScanOptions(
          mode: AiScanMode.balanced,
          enableAudioEvents: true,
          enableAudioPeaks: true,
          enableTranscription: true,
          enableVisualSignals: true,
          enableFaceReaction: true,
          allowTranscriptionEngineRun: true,
          maxSpeechTranscriptionTasks: 18,
        );
      case AiScanMode.accurate:
        return const AiScanOptions(
          mode: AiScanMode.accurate,
          enableAudioEvents: true,
          enableAudioPeaks: true,
          enableTranscription: true,
          enableVisualSignals: true,
          enableFaceReaction: true,
          allowTranscriptionEngineRun: true,
          maxSpeechTranscriptionTasks: 40,
        );
    }
  }

  int maxYamnetWindowsForDuration(int durationSeconds) {
    if (maxYamnetWindowsOverride != null) {
      return max(1, maxYamnetWindowsOverride!);
    }

    switch (mode) {
      case AiScanMode.fast:
        if (durationSeconds <= 60) return 40;
        if (durationSeconds <= 180) return 60;
        if (durationSeconds <= 600) return 80;
        return 100;
      case AiScanMode.balanced:
        if (durationSeconds <= 60) return 60;
        if (durationSeconds <= 180) return 90;
        if (durationSeconds <= 600) return 120;
        return 150;
      case AiScanMode.accurate:
        if (durationSeconds <= 60) return 90;
        if (durationSeconds <= 180) return 140;
        if (durationSeconds <= 600) return 200;
        return 260;
    }
  }

  AiScanOptions copyWith({
    AiScanMode? mode,
    bool? enableAudioEvents,
    bool? enableAudioPeaks,
    bool? enableTranscription,
    bool? enableVisualSignals,
    bool? enableFaceReaction,
    bool? allowTranscriptionEngineRun,
    int? maxSpeechTranscriptionTasks,
    int? maxYamnetWindowsOverride,
  }) {
    return AiScanOptions(
      mode: mode ?? this.mode,
      enableAudioEvents: enableAudioEvents ?? this.enableAudioEvents,
      enableAudioPeaks: enableAudioPeaks ?? this.enableAudioPeaks,
      enableTranscription: enableTranscription ?? this.enableTranscription,
      enableVisualSignals: enableVisualSignals ?? this.enableVisualSignals,
      enableFaceReaction: enableFaceReaction ?? this.enableFaceReaction,
      allowTranscriptionEngineRun:
          allowTranscriptionEngineRun ?? this.allowTranscriptionEngineRun,
      maxSpeechTranscriptionTasks:
          maxSpeechTranscriptionTasks ?? this.maxSpeechTranscriptionTasks,
      maxYamnetWindowsOverride:
          maxYamnetWindowsOverride ?? this.maxYamnetWindowsOverride,
    );
  }
}
