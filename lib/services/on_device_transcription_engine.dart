import '../models/speech_transcription_task.dart';
import '../models/transcript_segment.dart';

/// Interface for a future local speech-to-text engine.
///
/// Keep this app free/no-backend by implementing this with an on-device model.
/// Do not call a cloud API from here.
abstract class OnDeviceTranscriptionEngine {
  Future<bool> isReady();

  Future<List<TranscriptSegment>> transcribeSpeechTasks({
    required String videoPath,
    required List<SpeechTranscriptionTask> tasks,
  });
}

/// Safe default engine.
///
/// It intentionally does not fake transcripts. Until you plug in a real
/// on-device speech-to-text model, it returns no transcript segments and the
/// rest of the AI continues using YAMNet/audio peaks normally.
class NoOpOnDeviceTranscriptionEngine implements OnDeviceTranscriptionEngine {
  const NoOpOnDeviceTranscriptionEngine();

  @override
  Future<bool> isReady() async => false;

  @override
  Future<List<TranscriptSegment>> transcribeSpeechTasks({
    required String videoPath,
    required List<SpeechTranscriptionTask> tasks,
  }) async {
    return const [];
  }
}
