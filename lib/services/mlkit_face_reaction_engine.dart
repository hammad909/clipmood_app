import 'dart:io';
import 'dart:math';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import '../models/face_reaction_signal.dart';
import 'face_reaction_engine.dart';

class MlKitFaceReactionEngine implements FaceReactionEngine {
  final FaceDetector _faceDetector;

  MlKitFaceReactionEngine({FaceDetector? faceDetector})
      : _faceDetector = faceDetector ??
            FaceDetector(
              options: FaceDetectorOptions(
                enableClassification: true,
                enableTracking: true,
                enableLandmarks: false,
                enableContours: false,
                minFaceSize: 0.08,
                performanceMode: FaceDetectorMode.fast,
              ),
            );

  @override
  Future<List<FaceReactionFrameSignal>> analyzeVideoFrames(
    String videoPath, {
    required int durationSeconds,
    required int sampleEverySeconds,
  }) async {
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      throw Exception('Video file does not exist.');
    }

    final tempRoot = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final framesDir = Directory('${tempRoot.path}/clipmood_faces_$timestamp');
    await framesDir.create(recursive: true);

    try {
      await _extractFrames(
        videoPath: videoPath,
        outputPattern: '${framesDir.path}/face_%05d.jpg',
        sampleEverySeconds: sampleEverySeconds,
      );

      final frameFiles = framesDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final signals = <FaceReactionFrameSignal>[];
      _FrameFaceStats? previousStats;

      for (int index = 0; index < frameFiles.length; index++) {
        final second = min(durationSeconds, index * sampleEverySeconds);
        final inputImage = InputImage.fromFilePath(frameFiles[index].path);
        final faces = await _faceDetector.processImage(inputImage);
        final stats = _calculateFrameFaceStats(faces, previousStats);

        signals.add(
          FaceReactionFrameSignal(
            second: second,
            sampleEverySeconds: sampleEverySeconds,
            faceCount: faces.length,
            smilingScore: stats.smilingScore,
            eyeExpressionScore: stats.eyeExpressionScore,
            headMovementScore: stats.headMovementScore,
            facePresenceScore: stats.facePresenceScore,
            faceChangeScore: stats.faceChangeScore,
            reactionScore: stats.reactionScore,
          ),
        );

        previousStats = stats;
      }

      return signals;
    } finally {
      try {
        await framesDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _extractFrames({
    required String videoPath,
    required String outputPattern,
    required int sampleEverySeconds,
  }) async {
    final fpsExpression = sampleEverySeconds <= 1 ? '1' : '1/$sampleEverySeconds';

    final command = [
      '-y',
      '-i',
      _quote(videoPath),
      '-vf',
      _quote('fps=$fpsExpression,scale=640:-1:flags=fast_bilinear'),
      '-an',
      '-q:v',
      '4',
      _quote(outputPattern),
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg face frame extraction failed: $logs');
    }
  }

  _FrameFaceStats _calculateFrameFaceStats(
    List<Face> faces,
    _FrameFaceStats? previousStats,
  ) {
    if (faces.isEmpty) {
      final faceChange = previousStats == null || previousStats.faceCount == 0 ? 0.0 : 0.35;
      return _FrameFaceStats(
        faceCount: 0,
        smilingScore: 0,
        eyeExpressionScore: 0,
        headMovementScore: 0,
        facePresenceScore: 0,
        faceChangeScore: faceChange,
        reactionScore: faceChange * 0.25,
      );
    }

    double smileSum = 0.0;
    double eyeExpressionSum = 0.0;
    double headMovementSum = 0.0;

    for (final face in faces) {
      final smile = face.smilingProbability ?? 0.0;
      final leftEyeOpen = face.leftEyeOpenProbability ?? 0.5;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 0.5;
      final averageEyeOpen = ((leftEyeOpen + rightEyeOpen) / 2).clamp(0.0, 1.0).toDouble();

      final eyeExpression = (1.0 - averageEyeOpen).clamp(0.0, 1.0).toDouble();
      final headMovement = max(
        ((face.headEulerAngleX ?? 0).abs() / 35.0),
        max(
          ((face.headEulerAngleY ?? 0).abs() / 35.0),
          ((face.headEulerAngleZ ?? 0).abs() / 35.0),
        ),
      ).clamp(0.0, 1.0).toDouble();

      smileSum += smile.clamp(0.0, 1.0).toDouble();
      eyeExpressionSum += eyeExpression;
      headMovementSum += headMovement;
    }

    final count = faces.length;
    final smilingScore = (smileSum / count).clamp(0.0, 1.0).toDouble();
    final eyeExpressionScore = (eyeExpressionSum / count).clamp(0.0, 1.0).toDouble();
    final headMovementScore = (headMovementSum / count).clamp(0.0, 1.0).toDouble();
    final facePresenceScore = min(1.0, count / 3.0).toDouble();

    double faceChangeScore = 0.0;
    if (previousStats != null) {
      final countChange = (count - previousStats.faceCount).abs() >= 1 ? 0.18 : 0.0;
      final smileChange = (smilingScore - previousStats.smilingScore).abs() * 0.55;
      final headChange = (headMovementScore - previousStats.headMovementScore).abs() * 0.35;
      faceChangeScore = (countChange + smileChange + headChange).clamp(0.0, 1.0).toDouble();
    }

    final reactionScore = ((smilingScore * 0.38) +
            (faceChangeScore * 0.24) +
            (headMovementScore * 0.18) +
            (facePresenceScore * 0.12) +
            (eyeExpressionScore * 0.08))
        .clamp(0.0, 1.0)
        .toDouble();

    return _FrameFaceStats(
      faceCount: count,
      smilingScore: smilingScore,
      eyeExpressionScore: eyeExpressionScore,
      headMovementScore: headMovementScore,
      facePresenceScore: facePresenceScore,
      faceChangeScore: faceChangeScore,
      reactionScore: reactionScore,
    );
  }

  String _quote(String pathOrExpression) {
    return '"${pathOrExpression.replaceAll('"', '\\"')}"';
  }

  @override
  Future<void> dispose() async {
    await _faceDetector.close();
  }
}

class _FrameFaceStats {
  final int faceCount;
  final double smilingScore;
  final double eyeExpressionScore;
  final double headMovementScore;
  final double facePresenceScore;
  final double faceChangeScore;
  final double reactionScore;

  const _FrameFaceStats({
    required this.faceCount,
    required this.smilingScore,
    required this.eyeExpressionScore,
    required this.headMovementScore,
    required this.facePresenceScore,
    required this.faceChangeScore,
    required this.reactionScore,
  });
}
