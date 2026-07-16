import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class YamnetPrediction {
  final String label;
  final double score;

  const YamnetPrediction({
    required this.label,
    required this.score,
  });
}

class YamnetWindowResult {
  final int startSecond;
  final int endSecond;
  final double highlightScore;
  final List<YamnetPrediction> predictions;

  const YamnetWindowResult({
    required this.startSecond,
    required this.endSecond,
    required this.highlightScore,
    required this.predictions,
  });
}

class YamnetAudioClassifierService {
  static const String _modelPath = 'assets/models/yamnet.tflite';
  static const String _labelsPath = 'assets/labels/yamnet_class_map.csv';

  static const int _sampleRate = 16000;
  static const int _yamnetWindowSamples = 15600;
  static const int _windowStepSamples = 8000;

  Interpreter? _interpreter;
  List<String> _labels = [];
  Future<void>? _loadFuture;

  bool get isLoaded => _interpreter != null && _labels.isNotEmpty;

  Future<void> load() {
    return _loadFuture ??= _loadInternal();
  }

  Future<void> _loadInternal() async {
    try {
      if (_interpreter == null) {
        final options = InterpreterOptions()
          ..threads = min(4, max(1, Platform.numberOfProcessors));

        _interpreter = await Interpreter.fromAsset(
          _modelPath,
          options: options,
        );
      }

      if (_labels.isEmpty) {
        _labels = await _loadLabels();
      }
    } catch (_) {
      _loadFuture = null;
      rethrow;
    }
  }

Future<List<YamnetWindowResult>> classifyVideoWindows(
  String videoPath, {
  int maxWindows = 30,
}) async {
  await load();

  final videoFile = File(videoPath);

  if (!await videoFile.exists()) {
    throw Exception('Video file does not exist.');
  }

  final rawAudioPath = await _extractRawAudio(videoPath);
  final rawFile = File(rawAudioPath);

  if (!await rawFile.exists()) {
    throw Exception('YAMNet audio extraction failed.');
  }

  final bytes = await rawFile.readAsBytes();

  try {
    await rawFile.delete();
  } catch (_) {}

  final samples = _pcm16ToFloat32(bytes);

  if (samples.isEmpty) {
    return const [];
  }

  if (samples.length < _yamnetWindowSamples) {
    final padded = Float32List(_yamnetWindowSamples);

    for (int i = 0; i < samples.length; i++) {
      padded[i] = samples[i];
    }

    final predictions = await classifySamples(padded);

    return [
      YamnetWindowResult(
        startSecond: 0,
        endSecond: max(1, samples.length ~/ _sampleRate),
        highlightScore: _calculateHighlightScore(predictions),
        predictions: predictions,
      ),
    ];
  }

  final startPositions = _buildSampleStartPositions(
    totalSamples: samples.length,
    maxWindows: maxWindows,
  );

  final results = <YamnetWindowResult>[];

  for (final startSample in startPositions) {
    final window = Float32List.sublistView(
      samples,
      startSample,
      startSample + _yamnetWindowSamples,
    );

    final predictions = await classifySamples(window);

    final startSecond = startSample ~/ _sampleRate;
    final endSecond = min(
      (startSample + _yamnetWindowSamples) ~/ _sampleRate,
      samples.length ~/ _sampleRate,
    );

    results.add(
      YamnetWindowResult(
        startSecond: startSecond,
        endSecond: max(startSecond + 1, endSecond),
        highlightScore: _calculateHighlightScore(predictions),
        predictions: predictions,
      ),
    );
  }

  results.sort(
    (a, b) => b.highlightScore.compareTo(a.highlightScore),
  );

  return results;
}




List<int> _buildSampleStartPositions({
  required int totalSamples,
  required int maxWindows,
}) {
  final safeMaxWindows = max(1, maxWindows);
  final maxStartSample = totalSamples - _yamnetWindowSamples;

  if (maxStartSample <= 0 || safeMaxWindows == 1) {
    return [0];
  }

  final naturalCount = (maxStartSample ~/ _windowStepSamples) + 1;

  // Preserve dense natural sampling when it already fits the budget.
  if (naturalCount <= safeMaxWindows) {
    final positions = <int>[];

    for (
      int startSample = 0;
      startSample <= maxStartSample;
      startSample += _windowStepSamples
    ) {
      positions.add(startSample);
    }

    if (positions.isEmpty || positions.last != maxStartSample) {
      positions.add(maxStartSample);
    }

    return positions;
  }

  // Otherwise distribute the exact budget across the complete video.
  final positions = <int>{};
  final step = maxStartSample / (safeMaxWindows - 1);

  for (int i = 0; i < safeMaxWindows; i++) {
    positions.add((i * step).round().clamp(0, maxStartSample));
  }

  positions
    ..add(0)
    ..add(maxStartSample);

  final sorted = positions.toList()..sort();

  if (sorted.length <= safeMaxWindows) {
    return sorted;
  }

  // Rounding can create one extra point. Re-sample deterministically.
  return List<int>.generate(
    safeMaxWindows,
    (index) {
      final ratio = index / (safeMaxWindows - 1);
      return (ratio * maxStartSample).round().clamp(0, maxStartSample);
    },
    growable: false,
  );
}

  Future<List<YamnetPrediction>> classifySamples(Float32List samples) async {
    if (!isLoaded) {
      await load();
    }

    final interpreter = _interpreter;

    if (interpreter == null) {
      throw Exception('YAMNet interpreter is not loaded.');
    }

    final inputShape = interpreter.getInputTensor(0).shape;
    final input = _createInputFromSamples(samples, inputShape);

    final outputTensors = interpreter.getOutputTensors();
    final outputs = <int, Object>{};

    for (int i = 0; i < outputTensors.length; i++) {
      outputs[i] = _createEmptyOutput(outputTensors[i].shape);
    }

    interpreter.runForMultipleInputs(
      [input],
      outputs,
    );

    final scores = _extractScores(outputs[0]);

    return _topPredictions(scores, limit: 8);
  }

  Future<List<YamnetPrediction>> testWithSilence() async {
    final silence = Float32List(_yamnetWindowSamples);
    return classifySamples(silence);
  }

  Future<String> _extractRawAudio(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rawAudioPath = '${tempDir.path}/yamnet_audio_$timestamp.raw';

    final command = [
      '-y',
      '-i',
      _quote(videoPath),
      '-vn',
      '-ac',
      '1',
      '-ar',
      _sampleRate.toString(),
      '-f',
      's16le',
      _quote(rawAudioPath),
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg audio extraction failed: $logs');
    }

    return rawAudioPath;
  }

  String _quote(String value) {
    return '"${value.replaceAll('"', r'\"')}"';
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      final byteIndex = i * 2;
      final byteData = ByteData.sublistView(bytes, byteIndex, byteIndex + 2);
      final intValue = byteData.getInt16(0, Endian.little);

      samples[i] = (intValue / 32768.0).clamp(-1.0, 1.0).toDouble();
    }

    return samples;
  }

Object _createInputFromSamples(
  Float32List samples,
  List<int> inputShape,
) {
  if (inputShape.length == 1) {
    final expectedLength = inputShape[0] <= 0 ? samples.length : inputShape[0];

    final input = List<double>.filled(expectedLength, 0.0);
    final copyLength = min(samples.length, expectedLength);

    for (int i = 0; i < copyLength; i++) {
      input[i] = samples[i];
    }

    return input;
  }

  if (inputShape.length == 2) {
    final batch = inputShape[0] <= 0 ? 1 : inputShape[0];
    final length = inputShape[1] <= 0 ? samples.length : inputShape[1];

    return List.generate(
      batch,
      (_) {
        final row = List<double>.filled(length, 0.0);
        final copyLength = min(samples.length, length);

        for (int i = 0; i < copyLength; i++) {
          row[i] = samples[i];
        }

        return row;
      },
    );
  }

  throw Exception('Unsupported YAMNet input shape: $inputShape');
}

Object _createEmptyOutput(List<int> originalShape) {
  final shape = originalShape.map((value) {
    if (value <= 0) return 1;
    return value;
  }).toList();

  if (shape.length == 1) {
    return List<double>.filled(shape[0], 0.0);
  }

  if (shape.length == 2) {
    return List.generate(
      shape[0],
      (_) => List<double>.filled(shape[1], 0.0),
    );
  }

  if (shape.length == 3) {
    return List.generate(
      shape[0],
      (_) => List.generate(
        shape[1],
        (_) => List<double>.filled(shape[2], 0.0),
      ),
    );
  }

  throw Exception('Unsupported YAMNet output shape: $originalShape');
}

List<double> _extractScores(Object? output) {
  if (output == null) {
    return const [];
  }

  final flattened = <double>[];
  _flattenNumbers(output, flattened);

  return flattened;
}

  void _flattenNumbers(Object value, List<double> result) {
    if (value is num) {
      result.add(value.toDouble());
      return;
    }

    if (value is Float32List) {
      result.addAll(value);
      return;
    }

    if (value is List) {
      for (final item in value) {
        _flattenNumbers(item, result);
      }
    }
  }

  List<YamnetPrediction> _topPredictions(
    List<double> scores, {
    required int limit,
  }) {
    final count = min(scores.length, _labels.length);
    final predictions = <YamnetPrediction>[];

    for (int i = 0; i < count; i++) {
      predictions.add(
        YamnetPrediction(
          label: _labels[i],
          score: scores[i],
        ),
      );
    }

    predictions.sort((a, b) => b.score.compareTo(a.score));

    return predictions.take(limit).toList();
  }

  double _calculateHighlightScore(List<YamnetPrediction> predictions) {
    double score = 0.0;

    for (final prediction in predictions) {
      final label = prediction.label.toLowerCase();

      if (_isStrongHighlightLabel(label)) {
        score += prediction.score * 1.0;
      } else if (_isMediumHighlightLabel(label)) {
        score += prediction.score * 0.55;
      } else if (_isLowHighlightLabel(label)) {
        score += prediction.score * 0.25;
      }
    }

    return score.clamp(0.0, 1.0).toDouble();
  }

  bool _isStrongHighlightLabel(String label) {
    return label.contains('laughter') ||
        label.contains('giggle') ||
        label.contains('chuckle') ||
        label.contains('applause') ||
        label.contains('cheering') ||
        label.contains('crowd') ||
        label.contains('shout') ||
        label.contains('yell') ||
        label.contains('scream');
  }

  bool _isMediumHighlightLabel(String label) {
    return label.contains('speech') ||
        label.contains('conversation') ||
        label.contains('music') ||
        label.contains('singing') ||
        label.contains('clapping') ||
        label.contains('whoop') ||
        label.contains('crying') ||
        label.contains('sob');
  }

  bool _isLowHighlightLabel(String label) {
    return label.contains('sound effect') ||
        label.contains('beat') ||
        label.contains('drum') ||
        label.contains('bass') ||
        label.contains('silence');
  }

  Future<List<String>> _loadLabels() async {
    final csvText = await rootBundle.loadString(_labelsPath);
    final lines = csvText.split('\n');

    final labels = <String>[];

    for (final rawLine in lines.skip(1)) {
      final line = rawLine.trim();

      if (line.isEmpty) continue;

      final columns = _splitCsvLine(line);

      if (columns.length >= 3) {
        labels.add(columns[2]);
      }
    }

    return labels;
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();

    bool insideQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        insideQuotes = !insideQuotes;
      } else if (char == ',' && !insideQuotes) {
        result.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    result.add(buffer.toString().trim());

    return result;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}