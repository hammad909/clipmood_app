import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class AudioPeak {
  final int second;
  final double score;

  const AudioPeak({
    required this.second,
    required this.score,
  });
}

class AudioPeakAnalyzerService {
  Future<List<AudioPeak>> analyzeAudioPeaks(String videoPath) async {
    final videoFile = File(videoPath);

    if (!await videoFile.exists()) {
      throw Exception('Video file does not exist.');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rawAudioPath = '${tempDir.path}/clipmood_audio_$timestamp.raw';

    await _extractRawAudio(
      videoPath: videoPath,
      outputPath: rawAudioPath,
    );

    final rawFile = File(rawAudioPath);

    if (!await rawFile.exists()) {
      throw Exception('Audio extraction failed.');
    }

    final bytes = await rawFile.readAsBytes();

    try {
      await rawFile.delete();
    } catch (_) {}

    return _calculatePeaksFromPcm(
      bytes: bytes,
      sampleRate: 8000,
    );
  }

  Future<void> _extractRawAudio({
    required String videoPath,
    required String outputPath,
  }) async {
    final command = [
      '-y',
      '-i',
      _quote(videoPath),
      '-vn',
      '-ac',
      '1',
      '-ar',
      '8000',
      '-f',
      's16le',
      _quote(outputPath),
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg audio extraction failed: $logs');
    }
  }

  String _quote(String value) {
    return '"${value.replaceAll('"', r'\"')}"';
  }

  List<AudioPeak> _calculatePeaksFromPcm({
    required Uint8List bytes,
    required int sampleRate,
  }) {
    const bytesPerSample = 2;

    final bytesPerSecond = sampleRate * bytesPerSample;

    if (bytes.isEmpty || bytes.length < bytesPerSecond) {
      return const [];
    }

    final totalSeconds = bytes.length ~/ bytesPerSecond;
    final peaks = <AudioPeak>[];

    for (int second = 0; second < totalSeconds; second++) {
      final startByte = second * bytesPerSecond;
      final endByte = min(startByte + bytesPerSecond, bytes.length);

      double sumSquares = 0;
      int sampleCount = 0;

      for (int i = startByte; i + 1 < endByte; i += 2) {
        final sample = _readInt16LittleEndian(bytes, i);
        final normalized = sample / 32768.0;

        sumSquares += normalized * normalized;
        sampleCount++;
      }

      if (sampleCount == 0) continue;

      final rms = sqrt(sumSquares / sampleCount);

      peaks.add(
        AudioPeak(
          second: second,
          score: rms.clamp(0.0, 1.0).toDouble(),
        ),
      );
    }

    peaks.sort((a, b) => b.score.compareTo(a.score));

    return peaks.take(10).toList();
  }

  int _readInt16LittleEndian(Uint8List bytes, int index) {
    final byteData = ByteData.sublistView(bytes, index, index + 2);
    return byteData.getInt16(0, Endian.little);
  }
}