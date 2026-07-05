import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_kit/whisper_kit.dart';

import '../models/speech_transcription_task.dart';
import '../models/transcript_segment.dart';
import 'on_device_transcription_engine.dart';

/// On-device Whisper transcription engine for ClipMood.
///
/// This engine does not call your backend and does not use a paid API.
/// It converts selected speech chunks to 16 kHz WAV locally, then runs Whisper
/// through whisper_kit / whisper.cpp on the device.
class WhisperKitTranscriptionEngine implements OnDeviceTranscriptionEngine {
  final WhisperModel model;
  final String language;
  final int threads;
  final int maxChunksPerScan;
  final bool cacheChunkWavs;
  final String? modelDir;

  Whisper? _whisper;
  bool _initializationFailed = false;

  WhisperKitTranscriptionEngine({
    this.model = WhisperModel.base,
    this.language = 'auto',
    this.threads = 4,
    this.maxChunksPerScan = 30,
    this.cacheChunkWavs = false,
    this.modelDir,
  });

  @override
  Future<bool> isReady() async {
    if (_initializationFailed) return false;

    try {
      _whisper ??= Whisper(
        model: model,
        modelDir: modelDir,
      );
      return true;
    } catch (_) {
      _initializationFailed = true;
      return false;
    }
  }

  @override
  Future<List<TranscriptSegment>> transcribeSpeechTasks({
    required String videoPath,
    required List<SpeechTranscriptionTask> tasks,
  }) async {
    if (tasks.isEmpty) return const [];

    final ready = await isReady();
    if (!ready || _whisper == null) return const [];

    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      throw Exception('Video file does not exist for local transcription.');
    }

    final selectedTasks = _chooseBestTasks(tasks);
    final tempRoot = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final chunksDir = Directory('${tempRoot.path}/clipmood_whisper_$timestamp');
    await chunksDir.create(recursive: true);

    final segments = <TranscriptSegment>[];

    try {
      for (var i = 0; i < selectedTasks.length; i++) {
        final task = selectedTasks[i];
        if (!task.isUsable) continue;

        final chunkPath = '${chunksDir.path}/speech_${i.toString().padLeft(3, '0')}_${task.startSeconds}_${task.endSeconds}.wav';

        final exported = await _exportSpeechChunkToWav(
          videoPath: videoPath,
          outputPath: chunkPath,
          startSeconds: task.startSeconds,
          durationSeconds: task.durationSeconds,
        );

        if (!exported) continue;

        final response = await _whisper!.transcribe(
          transcribeRequest: TranscribeRequest(
            audio: chunkPath,
            language: language,
            threads: threads,
            isNoTimestamps: false,
            splitOnWord: false,
            isTranslate: false,
          ),
        );

        final responseSegments = response.segments;

        if (responseSegments != null && responseSegments.isNotEmpty) {
          for (final item in responseSegments) {
            final text = item.text.trim();
            if (!_isUsableText(text)) continue;

            final localStart = item.fromTs.inSeconds;
            final localEnd = max(localStart + 1, item.toTs.inSeconds);

            segments.add(
              TranscriptSegment(
                startSeconds: task.startSeconds + localStart,
                endSeconds: min(task.endSeconds, task.startSeconds + localEnd),
                text: text,
                confidence: _estimateConfidence(text, task.priority),
                source: 'whisper_kit_on_device',
              ),
            );
          }
        } else {
          final text = response.text.trim();
          if (_isUsableText(text)) {
            segments.add(
              TranscriptSegment(
                startSeconds: task.startSeconds,
                endSeconds: task.endSeconds,
                text: text,
                confidence: _estimateConfidence(text, task.priority),
                source: 'whisper_kit_on_device',
              ),
            );
          }
        }
      }
    } finally {
      if (!cacheChunkWavs && await chunksDir.exists()) {
        await chunksDir.delete(recursive: true);
      }
    }

    return _cleanAndMergeTranscriptSegments(segments);
  }

  List<SpeechTranscriptionTask> _chooseBestTasks(List<SpeechTranscriptionTask> tasks) {
    final sorted = [...tasks]
      ..sort((a, b) {
        final priorityCompare = b.priority.compareTo(a.priority);
        if (priorityCompare != 0) return priorityCompare;
        return a.startSeconds.compareTo(b.startSeconds);
      });

    // Whisper is the slowest local layer. Limit chunks so scan does not feel stuck.
    final chosen = sorted.take(maxChunksPerScan).toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    return chosen;
  }

  Future<bool> _exportSpeechChunkToWav({
    required String videoPath,
    required String outputPath,
    required int startSeconds,
    required int durationSeconds,
  }) async {
    final safeDuration = max(1, durationSeconds);

    final command = [
      '-y',
      '-ss',
      startSeconds.toString(),
      '-t',
      safeDuration.toString(),
      '-i',
      _quote(videoPath),
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-sample_fmt',
      's16',
      _quote(outputPath),
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) return false;

    final outputFile = File(outputPath);
    return outputFile.existsSync() && outputFile.lengthSync() > 1200;
  }

  String _quote(String value) {
    return '"${value.replaceAll('"', '\\"')}"';
  }

  bool _isUsableText(String text) {
    final cleaned = text.trim();
    if (cleaned.length < 4) return false;

    final lower = cleaned.toLowerCase();
    const badTexts = {
      '[music]',
      '(music)',
      '[silence]',
      '(silence)',
      '[applause]',
      '(applause)',
      'you',
      'thank you',
    };

    return !badTexts.contains(lower);
  }

  double _estimateConfidence(String text, double taskPriority) {
    final wordCount = text.split(RegExp(r'\s+')).where((word) => word.trim().isNotEmpty).length;
    final lengthBoost = (wordCount / 18).clamp(0.0, 0.2).toDouble();
    return (0.66 + (taskPriority * 0.18) + lengthBoost).clamp(0.55, 0.96).toDouble();
  }

  List<TranscriptSegment> _cleanAndMergeTranscriptSegments(List<TranscriptSegment> rawSegments) {
    final usable = rawSegments
        .where((segment) => segment.isUsable)
        .toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    if (usable.isEmpty) return const [];

    final merged = <TranscriptSegment>[];

    for (final segment in usable) {
      if (merged.isEmpty) {
        merged.add(segment);
        continue;
      }

      final previous = merged.last;
      final close = segment.startSeconds <= previous.endSeconds + 1;
      final combinedLength = previous.normalizedText.length + segment.normalizedText.length;

      if (close && combinedLength <= 260) {
        merged[merged.length - 1] = TranscriptSegment(
          startSeconds: previous.startSeconds,
          endSeconds: max(previous.endSeconds, segment.endSeconds),
          text: '${previous.normalizedText} ${segment.normalizedText}'.trim(),
          confidence: max(previous.confidence, segment.confidence),
          source: 'whisper_kit_on_device',
        );
      } else {
        merged.add(segment);
      }
    }

    return merged;
  }
}
