import '../models/face_reaction_signal.dart';
import 'face_reaction_engine.dart';
import 'mlkit_face_reaction_engine.dart';

class FaceReactionAnalyzerService {
  final FaceReactionEngine _engine;

  FaceReactionAnalyzerService({FaceReactionEngine? engine})
      : _engine = engine ?? MlKitFaceReactionEngine();

  Future<List<FaceReactionFrameSignal>> analyzeFaceReactions(
    String videoPath, {
    required int durationSeconds,
  }) async {
    if (durationSeconds <= 1) return const [];

    final sampleEverySeconds = _chooseSampleEverySeconds(durationSeconds);

    final signals = await _engine.analyzeVideoFrames(
      videoPath,
      durationSeconds: durationSeconds,
      sampleEverySeconds: sampleEverySeconds,
    );

    return signals
        .where((signal) => signal.hasFace)
        .toList()
      ..sort((a, b) => a.second.compareTo(b.second));
  }

  int _chooseSampleEverySeconds(int durationSeconds) {
    if (durationSeconds <= 45) return 1;
    if (durationSeconds <= 180) return 2;
    if (durationSeconds <= 600) return 3;
    return 4;
  }

  Future<void> dispose() => _engine.dispose();
}
