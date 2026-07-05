/// Progress state for the local AI scan pipeline.
///
/// This is intentionally UI-friendly: the video editor can display the stage,
/// message, progress bar, and a cancel button without knowing detector internals.
enum AiScanStage {
  idle,
  loadingVideo,
  audioEvents,
  audioPeaks,
  transcription,
  visualSignals,
  faceReactions,
  scoring,
  completed,
  cancelled,
  failed,
}

extension AiScanStageX on AiScanStage {
  String get label {
    switch (this) {
      case AiScanStage.idle:
        return 'Idle';
      case AiScanStage.loadingVideo:
        return 'Loading video';
      case AiScanStage.audioEvents:
        return 'Audio AI';
      case AiScanStage.audioPeaks:
        return 'Audio peaks';
      case AiScanStage.transcription:
        return 'Local transcription';
      case AiScanStage.visualSignals:
        return 'Visual signals';
      case AiScanStage.faceReactions:
        return 'Face reactions';
      case AiScanStage.scoring:
        return 'Ranking clips';
      case AiScanStage.completed:
        return 'Completed';
      case AiScanStage.cancelled:
        return 'Cancelled';
      case AiScanStage.failed:
        return 'Failed';
    }
  }
}

class AiScanProgress {
  final AiScanStage stage;
  final double progress;
  final String message;
  final String? detail;
  final bool canCancel;

  const AiScanProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.detail,
    this.canCancel = true,
  });

  const AiScanProgress.idle()
      : stage = AiScanStage.idle,
        progress = 0.0,
        message = 'Ready to scan',
        detail = null,
        canCancel = false;

  const AiScanProgress.completed(String message)
      : stage = AiScanStage.completed,
        progress = 1.0,
        message = message,
        detail = null,
        canCancel = false;

  const AiScanProgress.cancelled()
      : stage = AiScanStage.cancelled,
        progress = 0.0,
        message = 'Scan cancelled',
        detail = null,
        canCancel = false;

  AiScanProgress copyWith({
    AiScanStage? stage,
    double? progress,
    String? message,
    String? detail,
    bool? canCancel,
  }) {
    return AiScanProgress(
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      canCancel: canCancel ?? this.canCancel,
    );
  }
}
