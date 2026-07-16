import 'dart:math';

/// Controls how much local AI work ClipMood performs for one scan.
///
/// Balanced keeps every signal family enabled, but samples the video more
/// efficiently so typical 1–5 minute videos can finish much faster.
/// Accurate keeps the heavier scan for users who are willing to wait.
enum AiScanMode {
  balanced,
  accurate,
}

extension AiScanModeX on AiScanMode {
  String get label {
    switch (this) {
      case AiScanMode.balanced:
        return 'Balanced';
      case AiScanMode.accurate:
        return 'Accurate';
    }
  }

  String get helperText {
    switch (this) {
      case AiScanMode.balanced:
        return 'Recommended for normal use. Keeps audio, Whisper, visual, and face signals with a faster sampling budget.';
      case AiScanMode.accurate:
        return 'Heavier scan with more audio windows and Whisper chunks. Best used only when extra detail matters.';
    }
  }

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

  /// When false, TranscriptService may still read a transcript cache, but it
  /// does not run the heavier on-device Whisper engine.
  final bool allowTranscriptionEngineRun;

  /// Maximum number of speech chunks that Whisper may process.
  final int maxSpeechTranscriptionTasks;

  /// Optional hard cap for YAMNet windows.
  final int? maxYamnetWindowsOverride;

  const AiScanOptions({
    this.mode = AiScanMode.balanced,
    this.enableAudioEvents = true,
    this.enableAudioPeaks = true,
    this.enableTranscription = true,
    this.enableVisualSignals = true,
    this.enableFaceReaction = true,
    this.allowTranscriptionEngineRun = true,
    this.maxSpeechTranscriptionTasks = 6,
    this.maxYamnetWindowsOverride,
  });

  factory AiScanOptions.forMode(AiScanMode mode) {
    switch (mode) {
      case AiScanMode.balanced:
        return const AiScanOptions(
          mode: AiScanMode.balanced,
          enableAudioEvents: true,
          enableAudioPeaks: true,
          enableTranscription: true,
          enableVisualSignals: true,
          enableFaceReaction: true,
          allowTranscriptionEngineRun: true,
          maxSpeechTranscriptionTasks: 6,
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

  /// Balanced windows are distributed across the complete video rather than
  /// concentrating on the beginning.
  int maxYamnetWindowsForDuration(int durationSeconds) {
    if (maxYamnetWindowsOverride != null) {
      return max(1, maxYamnetWindowsOverride!);
    }

    switch (mode) {
      case AiScanMode.balanced:
        if (durationSeconds <= 60) return 30;
        if (durationSeconds <= 180) return 42;
        if (durationSeconds <= 600) return 60;
        return 72;

      case AiScanMode.accurate:
        if (durationSeconds <= 60) return 90;
        if (durationSeconds <= 180) return 140;
        if (durationSeconds <= 600) return 200;
        return 260;
    }
  }

  int visualSampleEverySecondsForDuration(int durationSeconds) {
    switch (mode) {
      case AiScanMode.balanced:
        if (durationSeconds <= 60) return 1;
        if (durationSeconds <= 180) return 2;
        if (durationSeconds <= 600) return 3;
        return 5;

      case AiScanMode.accurate:
        if (durationSeconds <= 60) return 1;
        if (durationSeconds <= 180) return 2;
        if (durationSeconds <= 600) return 4;
        if (durationSeconds <= 1200) return 6;
        return 8;
    }
  }

  int faceSampleEverySecondsForDuration(int durationSeconds) {
    switch (mode) {
      case AiScanMode.balanced:
        if (durationSeconds <= 60) return 2;
        if (durationSeconds <= 180) return 3;
        if (durationSeconds <= 600) return 5;
        return 7;

      case AiScanMode.accurate:
        if (durationSeconds <= 45) return 1;
        if (durationSeconds <= 180) return 2;
        if (durationSeconds <= 600) return 3;
        return 4;
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
