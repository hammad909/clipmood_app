import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'attention_worthy_clip_scorer.dart';
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
  final AttentionWorthyClipScorer _attentionScorer = AttentionWorthyClipScorer();

  /// Load the small YAMNet model before the user presses Scan.
  /// Call this from the editor's initState() to remove cold-start time.
  Future<void> warmUp() async {
    try {
      await _yamnetService.load();
    } catch (error) {
      debugPrint('[AI warm-up] YAMNet warm-up failed safely: $error');
    }
  }

  Future<AiClipAnalyzerResult> analyzeVideo(
    String videoPath, {
    ClipIntent intent = ClipIntent.general,
    AiScanOptions options = const AiScanOptions(),
    AiScanCancellationToken? cancellationToken,
    void Function(AiScanProgress progress)? onProgress,
  }) async {
    final totalStopwatch = Stopwatch()..start();
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

      Future<T> runStage<T>({
        required String name,
        required T fallback,
        required Future<T> Function() action,
      }) async {
        final stopwatch = Stopwatch()..start();

        try {
          final value = await action();
          debugPrint(
            '[AI timing] $name: '
            '${stopwatch.elapsedMilliseconds} ms',
          );
          return value;
        } catch (error, stackTrace) {
          debugPrint(
            '[AI timing] $name failed safely after '
            '${stopwatch.elapsedMilliseconds} ms: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
          return fallback;
        }
      }

      emit(
        AiScanStage.audioEvents,
        0.10,
        'Analyzing audio and video in parallel...',
        detail:
            'Audio events, energy, motion, and face reactions are running together.',
      );

      // These four layers do not depend on one another. Starting them together
      // reduces wall-clock time without changing the final scorer.
      final yamnetFuture = options.enableAudioEvents
          ? runStage<List<YamnetWindowResult>>(
              name: 'YAMNet',
              fallback: const <YamnetWindowResult>[],
              action: () => _yamnetService.classifyVideoWindows(
                videoPath,
                maxWindows:
                    options.maxYamnetWindowsForDuration(durationSeconds),
              ),
            )
          : Future.value(const <YamnetWindowResult>[]);

      final audioPeaksFuture = options.enableAudioPeaks
          ? runStage<List<AudioPeak>>(
              name: 'Audio peaks',
              fallback: const <AudioPeak>[],
              action: () =>
                  _audioPeakAnalyzer.analyzeAudioPeaks(videoPath),
            )
          : Future.value(const <AudioPeak>[]);

      final visualFuture = options.enableVisualSignals
          ? runStage<List<VisualFrameSignal>>(
              name: 'Visual signals',
              fallback: const <VisualFrameSignal>[],
              action: () => _visualAnalyzer.analyzeVisualSignals(
                videoPath,
                durationSeconds: durationSeconds,
                sampleEverySecondsOverride:
                    options.visualSampleEverySecondsForDuration(
                  durationSeconds,
                ),
              ),
            )
          : Future.value(const <VisualFrameSignal>[]);

      final faceFuture = options.enableFaceReaction
          ? runStage<List<FaceReactionFrameSignal>>(
              name: 'Face reactions',
              fallback: const <FaceReactionFrameSignal>[],
              action: () => _faceReactionAnalyzer.analyzeFaceReactions(
                videoPath,
                durationSeconds: durationSeconds,
                sampleEverySecondsOverride:
                    options.faceSampleEverySecondsForDuration(
                  durationSeconds,
                ),
              ),
            )
          : Future.value(const <FaceReactionFrameSignal>[]);

      // Transcript selection depends on YAMNet speech windows, so it begins as
      // soon as YAMNet finishes while the other layers continue in parallel.
      final yamnetWindows = await yamnetFuture;
      checkCancelled();

      emit(
        AiScanStage.transcription,
        0.46,
        options.allowTranscriptionEngineRun
            ? 'Transcribing the strongest speech moments...'
            : 'Checking cached transcript...',
        detail:
            'Other visual and face analysis is continuing in the background.',
      );

      final transcriptFuture = options.enableTranscription
          ? runStage<TranscriptAnalysisResult>(
              name: 'Transcript',
              fallback: const TranscriptAnalysisResult(
                segments: [],
                source:
                    'Transcript layer failed safely. Other analysis continued.',
              ),
              action: () => _transcriptService.transcribeVideo(
                videoPath,
                yamnetWindows: yamnetWindows,
                durationSeconds: durationSeconds,
                maxSpeechTasks: options.maxSpeechTranscriptionTasks,
                allowEngineRun: options.allowTranscriptionEngineRun,
              ),
            )
          : Future.value(
              const TranscriptAnalysisResult(
                segments: [],
                source: 'Transcript layer disabled for this scan.',
              ),
            );

      final audioPeaks = await audioPeaksFuture;
      checkCancelled();

      final visualSignals = await visualFuture;
      checkCancelled();

      final faceReactionSignals = await faceFuture;
      checkCancelled();

      final transcriptResult = await transcriptFuture;
      checkCancelled();

      checkCancelled();

      emit(
        AiScanStage.scoring,
        0.90,
        'Finding attention-worthy clips...',
         detail: 'AI is ranking moments by hook strength, visual energy, reaction value, audio impact, and share potential.',
      );

      final signals = _signalBuilder.buildSignals(
        durationSeconds: durationSeconds,
        intent: intent,
        yamnetWindows: yamnetWindows,
        audioPeaks: audioPeaks,
        transcriptSegments: transcriptResult.segments,
        visualSignals: visualSignals,
        faceReactionSignals: faceReactionSignals,
      );

      final suggestions = _attentionScorer.buildSuggestions(
       signals: signals,
        durationSeconds: durationSeconds,
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
      totalStopwatch.stop();
      debugPrint(
        '[AI timing] Complete scan: '
        '${totalStopwatch.elapsedMilliseconds} ms',
      );
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
          'Auto category scan with category-confirmation scoring',
          'Scan mode: ${options.mode.label}',
          options.allowTranscriptionEngineRun
              ? 'Local Whisper was allowed for this scan.'
              : 'Heavy local Whisper was skipped unless cached transcript existed.',
          'Audio, transcript, visual, and face/reaction signals plug into the same category scorer.',
          'Clips are now accepted only when the final category has strong evidence, not just a high raw score.',
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
