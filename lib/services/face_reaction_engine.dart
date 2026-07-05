import '../models/face_reaction_signal.dart';

abstract class FaceReactionEngine {
  Future<List<FaceReactionFrameSignal>> analyzeVideoFrames(
    String videoPath, {
    required int durationSeconds,
    required int sampleEverySeconds,
  });

  Future<void> dispose() async {}
}
