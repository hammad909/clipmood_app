import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VisualFrameSignal {
  final int second;
  final int sampleEverySeconds;
  final double brightnessScore;
  final double brightnessChangeScore;
  final double motionScore;
  final double sceneChangeScore;

  const VisualFrameSignal({
    required this.second,
    required this.sampleEverySeconds,
    required this.brightnessScore,
    required this.brightnessChangeScore,
    required this.motionScore,
    required this.sceneChangeScore,
  });

  double get visualEnergyScore {
    return ((motionScore * 0.45) +
            (sceneChangeScore * 0.35) +
            (brightnessChangeScore * 0.20))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool get isStrongSceneChange => sceneChangeScore >= 0.45;

  bool get isStrongMotion => motionScore >= 0.35;
}

class VisualHighlightAnalyzerService {
  static const int _frameWidth = 32;
  static const int _frameHeight = 18;
  static const int _bytesPerPixel = 3;
  static const int _frameBytes = _frameWidth * _frameHeight * _bytesPerPixel;

  Future<List<VisualFrameSignal>> analyzeVisualSignals(
    String videoPath, {
    required int durationSeconds,
  }) async {
    final videoFile = File(videoPath);

    if (!await videoFile.exists()) {
      throw Exception('Video file does not exist.');
    }

    if (durationSeconds <= 1) {
      return const [];
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rawVideoPath = '${tempDir.path}/clipmood_visual_$timestamp.raw';
    final sampleEverySeconds = _chooseSampleEverySeconds(durationSeconds);

    await _extractLowResolutionFrames(
      videoPath: videoPath,
      outputPath: rawVideoPath,
      sampleEverySeconds: sampleEverySeconds,
    );

    final rawFile = File(rawVideoPath);

    if (!await rawFile.exists()) {
      throw Exception('Visual frame extraction failed.');
    }

    final bytes = await rawFile.readAsBytes();

    try {
      await rawFile.delete();
    } catch (_) {}

    return _calculateVisualSignals(
      bytes: bytes,
      durationSeconds: durationSeconds,
      sampleEverySeconds: sampleEverySeconds,
    );
  }

  Future<void> _extractLowResolutionFrames({
    required String videoPath,
    required String outputPath,
    required int sampleEverySeconds,
  }) async {
    final fpsExpression = sampleEverySeconds <= 1 ? '1' : '1/$sampleEverySeconds';

    final command = [
      '-y',
      '-i',
      _quote(videoPath),
      '-vf',
      _quote('fps=$fpsExpression,scale=$_frameWidth:$_frameHeight:flags=fast_bilinear'),
      '-an',
      '-pix_fmt',
      'rgb24',
      '-f',
      'rawvideo',
      _quote(outputPath),
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg visual frame extraction failed: $logs');
    }
  }

  List<VisualFrameSignal> _calculateVisualSignals({
    required Uint8List bytes,
    required int durationSeconds,
    required int sampleEverySeconds,
  }) {
    if (bytes.length < _frameBytes) {
      return const [];
    }

    final totalFrames = bytes.length ~/ _frameBytes;
    final signals = <VisualFrameSignal>[];

    List<double>? previousLumaValues;
    double? previousBrightness;

    for (int frameIndex = 0; frameIndex < totalFrames; frameIndex++) {
      final offset = frameIndex * _frameBytes;
      final frameBytes = bytes.sublist(offset, offset + _frameBytes);
      final frameStats = _calculateFrameStats(frameBytes);

      double brightnessChangeScore = 0.0;
      double motionScore = 0.0;
      double sceneChangeScore = 0.0;

      if (previousLumaValues != null && previousBrightness != null) {
        final averagePixelDifference = _averageLumaDifference(
          previousLumaValues,
          frameStats.lumaValues,
        );

        brightnessChangeScore = (frameStats.brightness - previousBrightness).abs();

        // Small camera noise should not become a highlight. Motion starts becoming
        // useful after about 6% average luma movement between sampled frames.
        motionScore = ((averagePixelDifference - 0.06) / 0.34)
            .clamp(0.0, 1.0)
            .toDouble();

        // Scene changes are stronger, sudden visual jumps. These are useful for
        // cuts, reactions, punchline switches, sports action, and edit transitions.
        sceneChangeScore = ((averagePixelDifference - 0.14) / 0.36)
            .clamp(0.0, 1.0)
            .toDouble();
      }

      final second = min(durationSeconds, frameIndex * sampleEverySeconds);

      signals.add(
        VisualFrameSignal(
          second: second,
          sampleEverySeconds: sampleEverySeconds,
          brightnessScore: frameStats.brightness.clamp(0.0, 1.0).toDouble(),
          brightnessChangeScore: brightnessChangeScore.clamp(0.0, 1.0).toDouble(),
          motionScore: motionScore,
          sceneChangeScore: sceneChangeScore,
        ),
      );

      previousLumaValues = frameStats.lumaValues;
      previousBrightness = frameStats.brightness;
    }

    return signals;
  }

  _FrameStats _calculateFrameStats(Uint8List frameBytes) {
    final lumaValues = <double>[];
    double brightnessSum = 0.0;

    for (int i = 0; i + 2 < frameBytes.length; i += 3) {
      final r = frameBytes[i] / 255.0;
      final g = frameBytes[i + 1] / 255.0;
      final b = frameBytes[i + 2] / 255.0;

      final luma = (0.299 * r) + (0.587 * g) + (0.114 * b);
      lumaValues.add(luma);
      brightnessSum += luma;
    }

    final brightness = lumaValues.isEmpty ? 0.0 : brightnessSum / lumaValues.length;

    return _FrameStats(
      brightness: brightness,
      lumaValues: lumaValues,
    );
  }

  double _averageLumaDifference(
    List<double> previous,
    List<double> current,
  ) {
    final length = min(previous.length, current.length);

    if (length == 0) return 0.0;

    double totalDifference = 0.0;

    for (int i = 0; i < length; i++) {
      totalDifference += (current[i] - previous[i]).abs();
    }

    return (totalDifference / length).clamp(0.0, 1.0).toDouble();
  }

  int _chooseSampleEverySeconds(int durationSeconds) {
    if (durationSeconds <= 60) return 1;
    if (durationSeconds <= 180) return 2;
    if (durationSeconds <= 600) return 4;
    if (durationSeconds <= 1200) return 6;
    return 8;
  }

  String _quote(String value) {
    return '"${value.replaceAll('"', r'\"')}"';
  }
}

class _FrameStats {
  final double brightness;
  final List<double> lumaValues;

  const _FrameStats({
    required this.brightness,
    required this.lumaValues,
  });
}
