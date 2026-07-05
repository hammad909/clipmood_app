import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:video_player/video_player.dart';

import '../models/ai_scan_options.dart';
import '../models/ai_scan_progress.dart';
import '../models/ai_signal.dart';
import '../models/ai_suggestion.dart';
import '../models/clip_intent.dart';
import '../models/transcript_segment.dart';
import '../models/face_reaction_signal.dart';
import 'ai_scan_cancellation_token.dart';
import 'ai_signal_builder_service.dart';
import 'audio_peak_analyzer_service.dart';
import 'multi_signal_clip_scorer.dart';
import 'transcript_service.dart';
import 'whisper_kit_transcription_engine.dart';
import 'visual_highlight_analyzer_service.dart';
import 'face_reaction_analyzer_service.dart';
import 'yamnet_audio_classifier_service.dart';

class AiClipAnalyzerResult {
  final List<AiSuggestion> suggestions;
  final List<AiDebugEntry> debugEntries;

  const AiClipAnalyzerResult({
    required this.suggestions,
    this.debugEntries = const [],
  });
}

class AiDebugEntry {
  final int startSeconds;
  final int endSeconds;
  final String source;
  final String mood;
  final double score;
  final double confidence;
  final bool accepted;
  final List<String> topSignals;
  final List<String> notes;

  const AiDebugEntry({
    required this.startSeconds,
    required this.endSeconds,
    required this.source,
    required this.mood,
    required this.score,
    required this.confidence,
    required this.accepted,
    this.topSignals = const [],
    this.notes = const [],
  });
}

class AiClipAnalyzerService {
  final YamnetAudioClassifierService _yamnetService = YamnetAudioClassifierService();
  final AudioPeakAnalyzerService _audioPeakAnalyzer = AudioPeakAnalyzerService();
  final TranscriptService _transcriptService = TranscriptService(
    engine: WhisperKitTranscriptionEngine(),
  );
  final VisualHighlightAnalyzerService _visualAnalyzer = VisualHighlightAnalyzerService();
  final FaceReactionAnalyzerService _faceReactionAnalyzer = FaceReactionAnalyzerService();
  final AiSignalBuilderService _signalBuilder = AiSignalBuilderService();
  final MultiSignalClipScorer _clipScorer = MultiSignalClipScorer();

  Future<AiClipAnalyzerResult> analyzeVideo(
    String videoPath, {
    ClipIntent intent = ClipIntent.general,
    AiScanOptions options = const AiScanOptions(),
    AiScanCancellationToken? cancellationToken,
    void Function(AiScanProgress progress)? onProgress,
  }) async {
    final videoFile = File(videoPath);

    void emit(
      AiScanStage stage,
      double progress,
      String message, {
      String? detail,
      bool canCancel = true,
    }) {
      onProgress?.call(
        AiScanProgress(
          stage: stage,
          progress: progress.clamp(0.0, 1.0).toDouble(),
          message: message,
          detail: detail,
          canCancel: canCancel,
        ),
      );
    }

    void checkCancelled() {
      cancellationToken?.throwIfCancelled();
    }

    emit(
      AiScanStage.loadingVideo,
      0.03,
      'Loading video metadata...',
      detail: 'Mode: ${options.mode.label} • Auto category scan',
    );

    if (!await videoFile.exists()) {
      emit(
        AiScanStage.failed,
        0.0,
        'Video file does not exist.',
        canCancel: false,
      );
      throw Exception('Video file does not exist.');
    }

    final controller = VideoPlayerController.file(videoFile);

    try {
      checkCancelled();
      await controller.initialize();
      checkCancelled();

      final durationSeconds = controller.value.duration.inSeconds;

      if (durationSeconds <= 0) {
        emit(
          AiScanStage.completed,
          1.0,
          'Video has no usable duration.',
          canCancel: false,
        );
        return const AiClipAnalyzerResult(suggestions: []);
      }

      List<YamnetWindowResult> yamnetWindows = const [];
      List<AudioPeak> audioPeaks = const [];
      List<VisualFrameSignal> visualSignals = const [];
      List<FaceReactionFrameSignal> faceReactionSignals = const [];
      TranscriptAnalysisResult transcriptResult = const TranscriptAnalysisResult(
        segments: [],
        source: 'Local transcript layer not run yet.',
      );

      if (options.enableAudioEvents) {
        emit(
          AiScanStage.audioEvents,
          0.10,
          'Running YAMNet audio event detection...',
          detail: 'Finding laughter, speech, music, cheering, silence, and other audio events.',
        );

        try {
          yamnetWindows = await _yamnetService.classifyVideoWindows(
            videoPath,
            maxWindows: options.maxYamnetWindowsForDuration(durationSeconds),
          );
        } catch (_) {
          yamnetWindows = const [];
        }
      }

      checkCancelled();

      if (options.enableAudioPeaks) {
        emit(
          AiScanStage.audioPeaks,
          0.24,
          'Checking audio energy peaks...',
          detail: 'Finding loud moments, beat drops, reactions, and sudden audio spikes.',
        );

        try {
          audioPeaks = await _audioPeakAnalyzer.analyzeAudioPeaks(videoPath);
        } catch (_) {
          audioPeaks = const [];
        }
      }

      checkCancelled();

      if (options.enableTranscription) {
        emit(
          AiScanStage.transcription,
          0.40,
          options.allowTranscriptionEngineRun
              ? 'Running local Whisper transcription...'
              : 'Checking cached transcript only...',
          detail: options.allowTranscriptionEngineRun
              ? 'This is the slowest local layer, but it improves hooks, punchlines, quotes, and emotional lines.'
              : 'Fast mode skips heavy Whisper work unless a transcript cache already exists.',
        );

        try {
          transcriptResult = await _transcriptService.transcribeVideo(
            videoPath,
            yamnetWindows: yamnetWindows,
            durationSeconds: durationSeconds,
            maxSpeechTasks: options.maxSpeechTranscriptionTasks,
            allowEngineRun: options.allowTranscriptionEngineRun,
          );
        } catch (_) {
          transcriptResult = const TranscriptAnalysisResult(
            segments: [],
            source: 'Transcript layer failed safely. Audio/visual analysis continued.',
          );
        }
      } else {
        transcriptResult = const TranscriptAnalysisResult(
          segments: [],
          source: 'Transcript layer disabled for this scan.',
        );
      }

      checkCancelled();

      if (options.enableVisualSignals) {
        emit(
          AiScanStage.visualSignals,
          0.62,
          'Analyzing visual motion and scene changes...',
          detail: 'Looking for cuts, movement, brightness changes, and visual energy.',
        );

        try {
          visualSignals = await _visualAnalyzer.analyzeVisualSignals(
            videoPath,
            durationSeconds: durationSeconds,
          );
        } catch (_) {
          visualSignals = const [];
        }
      }

      checkCancelled();

      if (options.enableFaceReaction) {
        emit(
          AiScanStage.faceReactions,
          0.76,
          'Analyzing face/reaction moments...',
          detail: 'Looking for smiles, face changes, and reaction-style frames.',
        );

        try {
          faceReactionSignals = await _faceReactionAnalyzer.analyzeFaceReactions(
            videoPath,
            durationSeconds: durationSeconds,
          );
        } catch (_) {
          faceReactionSignals = const [];
        }
      }

      checkCancelled();

      emit(
        AiScanStage.scoring,
        0.90,
        'Combining AI signals and ranking clips...',
        detail: 'Audio + transcript + visual + face signals are being merged and de-duplicated.',
      );

      final signals = _signalBuilder.buildSignals(
        durationSeconds: durationSeconds,
        intent: ClipIntent.general,
        yamnetWindows: yamnetWindows,
        audioPeaks: audioPeaks,
        transcriptSegments: transcriptResult.segments,
        visualSignals: visualSignals,
        faceReactionSignals: faceReactionSignals,
      );

      final suggestions = _clipScorer.buildSuggestions(
        signals: signals,
        durationSeconds: durationSeconds,
        intent: ClipIntent.general,
      );

      final debugEntries = _buildDebugEntries(
        durationSeconds: durationSeconds,
        signals: signals,
        transcriptResult: transcriptResult,
        yamnetCount: yamnetWindows.length,
        audioPeakCount: audioPeaks.length,
        visualSignalCount: visualSignals.length,
        faceReactionSignalCount: faceReactionSignals.length,
        intent: intent,
        options: options,
      );

      emit(
        AiScanStage.completed,
        1.0,
        'Found ${suggestions.length} clip suggestion(s).',
        detail: 'Mode: ${options.mode.label}',
        canCancel: false,
      );

      return AiClipAnalyzerResult(
        suggestions: suggestions,
        debugEntries: debugEntries,
      );
    } on AiScanCancelledException {
      emit(
        AiScanStage.cancelled,
        0.0,
        'Scan cancelled.',
        canCancel: false,
      );
      rethrow;
    } catch (e) {
      emit(
        AiScanStage.failed,
        0.0,
        'AI scan failed.',
        detail: e.toString(),
        canCancel: false,
      );
      rethrow;
    } finally {
      await controller.dispose();
    }
  }

  List<AiDebugEntry> _buildDebugEntries({
    required int durationSeconds,
    required List<AiSignal> signals,
    required TranscriptAnalysisResult transcriptResult,
    required int yamnetCount,
    required int audioPeakCount,
    required int visualSignalCount,
    required int faceReactionSignalCount,
    required ClipIntent intent,
    required AiScanOptions options,
  }) {
    final entries = <AiDebugEntry>[];

    entries.add(
      AiDebugEntry(
        startSeconds: 0,
        endSeconds: min(durationSeconds, 1),
        source: 'Multi-Signal Brain',
        mood: intent.defaultMood,
        score: signals.isEmpty
            ? 0
            : signals
                .where((signal) => !signal.isNegative)
                .fold<double>(0.0, (sum, signal) => sum + signal.weightedScore.abs()) /
                max(1, signals.where((signal) => !signal.isNegative).length),
        confidence: signals.isEmpty ? 0 : 0.72,
        accepted: signals.any((signal) => signal.isUsable),
        topSignals: [
          '$yamnetCount YAMNet window(s)',
          '$audioPeakCount audio peak(s)',
          '$visualSignalCount visual frame signal(s)',
          '$faceReactionSignalCount face/reaction signal(s)',
          '${transcriptResult.segments.length} transcript segment(s)',
          'Scan mode: ${options.mode.label}',
        ],
        notes: [
          'Final suggestions come from audio, transcript, visual, and face/reaction signals, then are auto-sorted into sections.',
          'Auto category scan',
          'Scan mode: ${options.mode.label}',
          options.allowTranscriptionEngineRun
              ? 'Local Whisper was allowed for this scan.'
              : 'Heavy local Whisper was skipped unless cached transcript existed.',
          'Audio, transcript, visual, and face/reaction signals plug into the same category scorer.',
        ],
      ),
    );

    if (transcriptResult.segments.isEmpty) {
      entries.add(
        AiDebugEntry(
          startSeconds: 0,
          endSeconds: min(durationSeconds, 1),
          source: 'Transcript',
          mood: 'not connected',
          score: 0,
          confidence: 0,
          accepted: false,
          topSignals: [
            transcriptResult.speechCandidateCount > 0
                ? '${transcriptResult.speechCandidateCount} speech chunk(s) prepared'
                : 'No transcript segments',
          ],
          notes: [
            transcriptResult.source,
            transcriptResult.speechCandidateCount > 0
                ? 'Speech was detected and prepared for future local STT.'
                : 'No strong speech chunk was prepared for transcription.',
            transcriptResult.ranOnDevice
                ? 'Local Whisper was used. No backend/API transcription was called.'
                : 'No backend/API transcription was called.',
          ],
        ),
      );
    }

    if (visualSignalCount == 0) {
      entries.add(
        AiDebugEntry(
          startSeconds: 0,
          endSeconds: min(durationSeconds, 1),
          source: 'Visual',
          mood: 'not available',
          score: 0,
          confidence: 0,
          accepted: false,
          topSignals: const ['No visual frame signals'],
          notes: const [
            'Visual analysis did not return frame signals.',
            'The app still works using audio/transcript signals.',
          ],
        ),
      );
    }

    if (faceReactionSignalCount == 0) {
      entries.add(
        AiDebugEntry(
          startSeconds: 0,
          endSeconds: min(durationSeconds, 1),
          source: 'Face / Reaction',
          mood: 'not available',
          score: 0,
          confidence: 0,
          accepted: false,
          topSignals: const ['No face/reaction signals'],
          notes: const [
            'Face/reaction analysis did not return signals.',
            'Check that google_mlkit_face_detection is installed and the video has visible faces.',
            'The app still works using audio, transcript, and visual-motion signals.',
          ],
        ),
      );
    }


    for (final signal in signals) {
      entries.add(
        AiDebugEntry(
          startSeconds: signal.startSeconds,
          endSeconds: signal.endSeconds,
          source: signal.source.label,
          mood: signal.mood,
          score: signal.weightedScore.abs().clamp(0.0, 1.0).toDouble(),
          confidence: signal.normalizedConfidence,
          accepted: signal.isUsable,
          topSignals: signal.tags.isEmpty ? [_scoreLabel(signal)] : signal.tags,
          notes: [
            ...signal.reasons,
            'Strength: ${(signal.normalizedStrength * 100).toStringAsFixed(0)}%',
            'Confidence: ${(signal.normalizedConfidence * 100).toStringAsFixed(0)}%',
            'Weighted score: ${(signal.weightedScore * 100).toStringAsFixed(0)}%',
          ],
        ),
      );
    }

    entries.sort((a, b) {
      final timeCompare = a.startSeconds.compareTo(b.startSeconds);
      if (timeCompare != 0) return timeCompare;
      return b.score.compareTo(a.score);
    });

    return entries.take(240).toList();
  }

  String _scoreLabel(AiSignal signal) {
    return '${signal.source.label} ${(signal.weightedScore.abs() * 100).toStringAsFixed(0)}%';
  }


  void dispose() {
    _yamnetService.dispose();
    unawaited(_faceReactionAnalyzer.dispose());
  }
}
