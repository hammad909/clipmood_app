import 'dart:io';
import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:path_provider/path_provider.dart';
import '../models/ai_suggestion.dart';
import '../utils/clip_file_name_helper.dart';

/// Result of exporting a single AI-suggested clip as part of a batch.
class ClipExportResult {
  final AiSuggestion suggestion;
  final String? outputPath;
  final Object? error;

  const ClipExportResult({
    required this.suggestion,
    this.outputPath,
    this.error,
  });

  bool get isSuccess => outputPath != null && error == null;
}

/// Centralizes clip trimming/export so the single-clip editor and the
/// bulk "Save All / Save Selected" flow behave identically.
class ClipExportService {
  Future<Directory> _clipsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory('${appDir.path}/clips');

    if (!await clipsDir.exists()) {
      await clipsDir.create(recursive: true);
    }

    return clipsDir;
  }

  /// Trims [videoPath] between [startSeconds] and [endSeconds] and writes
  /// the result into the app's clips directory. Returns the output path.
  Future<String> exportClip({
    required String videoPath,
    required String title,
    required int startSeconds,
    required int endSeconds,
    void Function(double progress)? onProgress,
  }) async {
    final clipsDir = await _clipsDirectory();

    final fileName = ClipFileNameHelper.buildClipFileName(
      title: title,
      startSeconds: startSeconds,
      endSeconds: endSeconds,
    );

    final outputPath = '${clipsDir.path}/$fileName';

    final editor = VideoEditorBuilder(videoPath: videoPath).trim(
      startTimeMs: startSeconds * 1000,
      endTimeMs: endSeconds * 1000,
    );

    final exportedPath = await editor.export(
      outputPath: outputPath,
      onProgress: (progress) {
        if (onProgress == null) return;
        final normalized = progress > 1 ? progress / 100 : progress;
        onProgress(normalized.clamp(0.0, 1.0).toDouble());
      },
    );

    if (exportedPath == null || exportedPath.isEmpty) {
      throw Exception('Export returned no output path.');
    }

    return exportedPath;
  }

  /// Exports many AI suggestions in sequence, reporting overall progress.
  /// A failure on one clip does not stop the rest of the batch.
  Future<List<ClipExportResult>> exportSuggestions({
    required String videoPath,
    required List<AiSuggestion> suggestions,
    void Function(int index, int total, double clipProgress)? onProgress,
  }) async {
    final results = <ClipExportResult>[];

    for (var i = 0; i < suggestions.length; i++) {
      final suggestion = suggestions[i];

      onProgress?.call(i, suggestions.length, 0.0);

      try {
        final path = await exportClip(
          videoPath: videoPath,
          title: suggestion.title,
          startSeconds: suggestion.startSeconds,
          endSeconds: suggestion.endSeconds,
          onProgress: (clipProgress) {
            onProgress?.call(i, suggestions.length, clipProgress);
          },
        );

        results.add(ClipExportResult(suggestion: suggestion, outputPath: path));
      } catch (e) {
        results.add(ClipExportResult(suggestion: suggestion, error: e));
      }
    }

    return results;
  }
}