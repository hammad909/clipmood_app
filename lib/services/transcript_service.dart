import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/speech_transcription_task.dart';
import '../models/transcript_segment.dart';
import 'on_device_transcription_engine.dart';
import 'yamnet_audio_classifier_service.dart';

class TranscriptService {
  final OnDeviceTranscriptionEngine _engine;
  final bool writeGeneratedTranscriptSidecar;
  final bool allowShortVideoFullTranscriptionFallback;

  TranscriptService({
    OnDeviceTranscriptionEngine engine = const NoOpOnDeviceTranscriptionEngine(),
    this.writeGeneratedTranscriptSidecar = true,
    this.allowShortVideoFullTranscriptionFallback = true,
  }) : _engine = engine;

  /// Local/no-backend transcript pipeline.
  ///
  /// 1. If a local transcript sidecar JSON exists, use it immediately.
  /// 2. Build speech-only chunks from YAMNet windows.
  /// 3. If no chunks exist but the video is short enough, transcribe the full
  ///    short video as a fallback.
  /// 4. Run the injected on-device engine. For Step 9 this is WhisperKit.
  /// 5. Cache the generated transcript as a sidecar JSON so the same video does
  ///    not need to be transcribed again every scan.
  Future<TranscriptAnalysisResult> transcribeVideo(
    String videoPath, {
    List<YamnetWindowResult> yamnetWindows = const [],
    int? durationSeconds,
    int? maxSpeechTasks,
    bool allowEngineRun = true,
  }) async {
    final localSidecar = await _findTranscriptSidecar(videoPath);

    if (localSidecar != null) {
      final segments = await _readTranscriptSidecar(localSidecar);

      return TranscriptAnalysisResult(
        segments: segments,
        source: 'Local transcript cache: ${localSidecar.path}',
        speechCandidateCount: segments.length,
        engineReady: true,
        usedLocalSidecar: true,
      );
    }

    final allSpeechTasks = buildSpeechTranscriptionTasks(
      yamnetWindows,
      durationSeconds: durationSeconds,
    );
    final speechTasks = _limitSpeechTasks(allSpeechTasks, maxSpeechTasks);

    if (!allowEngineRun) {
      return TranscriptAnalysisResult(
        segments: const [],
        source: allSpeechTasks.isEmpty
            ? 'No cached transcript was found and no strong speech chunks were prepared.'
            : 'Prepared ${allSpeechTasks.length} speech chunk(s), but this scan mode skipped heavy local Whisper. No backend/API was called.',
        speechCandidateCount: allSpeechTasks.length,
        engineReady: false,
      );
    }

    final engineReady = await _engine.isReady();

    if (!engineReady) {
      return TranscriptAnalysisResult(
        segments: const [],
        source: speechTasks.isEmpty
            ? 'Local transcription engine is not ready. No backend/API was called.'
            : 'Prepared ${allSpeechTasks.length} speech chunk(s), but local transcription engine is not ready. No backend/API was called.',
        speechCandidateCount: allSpeechTasks.length,
        engineReady: false,
      );
    }

    if (speechTasks.isEmpty) {
      return const TranscriptAnalysisResult(
        segments: [],
        source: 'No strong speech was detected for local transcription.',
        speechCandidateCount: 0,
        engineReady: true,
        ranOnDevice: true,
      );
    }

    final generatedSegments = await _engine.transcribeSpeechTasks(
      videoPath: videoPath,
      tasks: speechTasks,
    );

    final usableSegments = generatedSegments
        .where((segment) => segment.isUsable)
        .toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    if (usableSegments.isNotEmpty && writeGeneratedTranscriptSidecar) {
      await _writeTranscriptSidecar(videoPath, usableSegments);
    }

    return TranscriptAnalysisResult(
      segments: usableSegments,
      source: usableSegments.isEmpty
          ? 'Local Whisper ran, but no usable transcript text was returned.'
          : 'On-device Whisper transcript generated and scored.',
      speechCandidateCount: allSpeechTasks.length,
      engineReady: true,
      ranOnDevice: true,
    );
  }

  /// Builds speech ranges from YAMNet results.
  ///
  /// This keeps local Whisper faster because we transcribe speech-heavy ranges,
  /// not every silent/music/noise-only second.
  List<SpeechTranscriptionTask> buildSpeechTranscriptionTasks(
    List<YamnetWindowResult> yamnetWindows, {
    int? durationSeconds,
  }) {
    final rawTasks = <SpeechTranscriptionTask>[];

    for (final window in yamnetWindows) {
      final speechScore = _speechScoreForWindow(window);

      if (speechScore < 0.18) continue;

      final start = max(0, window.startSecond - 1);
      final endLimit = durationSeconds ?? window.endSecond + 2;
      final end = min(endLimit, window.endSecond + 2);

      rawTasks.add(
        SpeechTranscriptionTask(
          startSeconds: start,
          endSeconds: max(start + 1, end),
          priority: speechScore.clamp(0.0, 1.0).toDouble(),
          reason: 'YAMNet detected speech/conversation',
        ),
      );
    }

    if (rawTasks.isEmpty) {
      if (allowShortVideoFullTranscriptionFallback &&
          durationSeconds != null &&
          durationSeconds > 3 &&
          durationSeconds <= 120) {
        return [
          SpeechTranscriptionTask(
            startSeconds: 0,
            endSeconds: durationSeconds,
            priority: 0.35,
            reason: 'Short video fallback transcription because no YAMNet speech chunks were created',
          ),
        ];
      }

      return const [];
    }

    rawTasks.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    final merged = <SpeechTranscriptionTask>[];

    for (final task in rawTasks) {
      if (merged.isEmpty) {
        merged.add(task);
        continue;
      }

      final previous = merged.last;
      final shouldMerge = task.startSeconds <= previous.endSeconds + 2;
      final mergedDuration = max(previous.endSeconds, task.endSeconds) - previous.startSeconds;

      if (shouldMerge && mergedDuration <= 28) {
        merged[merged.length - 1] = SpeechTranscriptionTask(
          startSeconds: previous.startSeconds,
          endSeconds: max(previous.endSeconds, task.endSeconds),
          priority: max(previous.priority, task.priority),
          reason: 'Merged nearby speech windows for Whisper',
        );
      } else {
        merged.add(task);
      }
    }

    merged.sort((a, b) => b.priority.compareTo(a.priority));

    return merged.take(80).toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
  }


  List<SpeechTranscriptionTask> _limitSpeechTasks(
    List<SpeechTranscriptionTask> tasks,
    int? maxSpeechTasks,
  ) {
    if (tasks.isEmpty) return const [];
    if (maxSpeechTasks == null || maxSpeechTasks <= 0) return tasks;

    final selected = [...tasks]
      ..sort((a, b) {
        final priorityCompare = b.priority.compareTo(a.priority);
        if (priorityCompare != 0) return priorityCompare;
        return a.startSeconds.compareTo(b.startSeconds);
      });

    return selected.take(maxSpeechTasks).toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
  }

  double _speechScoreForWindow(YamnetWindowResult window) {
    double score = 0.0;

    for (final prediction in window.predictions) {
      final label = prediction.label.toLowerCase();
      final value = prediction.score;

      if (label.contains('speech') ||
          label.contains('conversation') ||
          label.contains('narration') ||
          label.contains('monologue') ||
          label.contains('dialogue') ||
          label.contains('talking') ||
          label.contains('chatter')) {
        score = max(score, value);
      }

      if (label.contains('silence')) {
        score -= value * 0.5;
      }

      if (label.contains('music') && value > 0.65) {
        score -= value * 0.25;
      }
    }

    return score.clamp(0.0, 1.0).toDouble();
  }

  Future<File?> _findTranscriptSidecar(String videoPath) async {
    final candidates = <String>{
      '$videoPath.clipmood_transcript.json',
      '$videoPath.on_device_transcript.json',
      _replaceExtension(videoPath, '.clipmood_transcript.json'),
      _replaceExtension(videoPath, '.on_device_transcript.json'),
      _replaceExtension(videoPath, '.transcript.json'),
    };

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }

    return null;
  }

  Future<List<TranscriptSegment>> _readTranscriptSidecar(File transcriptFile) async {
    final rawJson = await transcriptFile.readAsString();
    final decoded = jsonDecode(rawJson);
    final segments = _parseSegments(decoded)
        .where((segment) => segment.isUsable)
        .toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    return segments;
  }

  Future<void> _writeTranscriptSidecar(
    String videoPath,
    List<TranscriptSegment> segments,
  ) async {
    try {
      final file = File(_replaceExtension(videoPath, '.clipmood_transcript.json'));
      final payload = {
        'source': 'clipmood_on_device_whisper',
        'created_at': DateTime.now().toIso8601String(),
        'segments': segments.map((segment) => segment.toJson()).toList(),
      };

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    } catch (_) {
      // Caching is helpful but not required. Do not fail analysis because of it.
    }
  }

  String _replaceExtension(String path, String newExtension) {
    final slashIndex = path.lastIndexOf(Platform.pathSeparator);
    final dotIndex = path.lastIndexOf('.');

    if (dotIndex > slashIndex) {
      return '${path.substring(0, dotIndex)}$newExtension';
    }

    return '$path$newExtension';
  }

  List<TranscriptSegment> _parseSegments(Object decoded) {
    final rawSegments = decoded is Map<String, dynamic> ? decoded['segments'] : decoded;

    if (rawSegments is! List) return const [];

    return rawSegments
        .whereType<Map>()
        .map((item) => TranscriptSegment.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
