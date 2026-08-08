import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/selected_video.dart';

/// Result returned after checking whether a selected video is allowed.
///
/// The class keeps its original name so existing ClipMood code that already
/// uses [VideoDurationValidationResult] continues to compile.
class VideoDurationValidationResult {
  final bool isValid;
  final Duration? duration;
  final int? fileSizeBytes;
  final String? message;

  const VideoDurationValidationResult._({
    required this.isValid,
    this.duration,
    this.fileSizeBytes,
    this.message,
  });

  const VideoDurationValidationResult.valid(
    Duration? duration, {
    int? fileSizeBytes,
  }) : this._(
          isValid: true,
          duration: duration,
          fileSizeBytes: fileSizeBytes,
        );

  const VideoDurationValidationResult.invalid({
    Duration? duration,
    int? fileSizeBytes,
    required String message,
  }) : this._(
          isValid: false,
          duration: duration,
          fileSizeBytes: fileSizeBytes,
          message: message,
        );
}

class VideoPickerService {
  /// AI Scan limits.
  static const Duration freeMinVideoDuration = Duration(minutes: 1);
  static const Duration freeMaxVideoDuration = Duration(minutes: 5);
  static const int aiMaxVideoSizeBytes = 500 * 1024 * 1024;

  /// Manual Trim has no duration restriction here, but very large files are
  /// blocked before opening the editor to avoid excessive memory/storage load.
  static const int manualTrimMaxVideoSizeBytes = 1024 * 1024 * 1024;

  static const String aiMaxVideoSizeLabel = '500 MB';
  static const String manualTrimMaxVideoSizeLabel = '1 GB';

  final ImagePicker _picker = ImagePicker();

  Future<SelectedVideo?> pickVideoFromGallery() async {
    final XFile? pickedFile = await _picker.pickVideo(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) {
      return null;
    }

    final file = File(pickedFile.path);

    return SelectedVideo(
      path: pickedFile.path,
      name: file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'selected_video.mp4',
    );
  }

  /// Validates a video selected for AI Scan.
  ///
  /// The file-size check happens before [VideoPlayerController] is created so
  /// an oversized file is rejected before heavier video initialization starts.
  Future<VideoDurationValidationResult> validateAiScanVideo(
    String videoPath, {
    Duration minDuration = freeMinVideoDuration,
    Duration maxDuration = freeMaxVideoDuration,
    int maxFileSizeBytes = aiMaxVideoSizeBytes,
  }) async {
    final videoFile = File(videoPath);

    if (!await videoFile.exists()) {
      return const VideoDurationValidationResult.invalid(
        message: 'Selected video file does not exist.',
      );
    }

    int fileSizeBytes;

    try {
      fileSizeBytes = await videoFile.length();
    } catch (error) {
      return VideoDurationValidationResult.invalid(
        message: 'Could not read the selected video file size: $error',
      );
    }

    if (fileSizeBytes > maxFileSizeBytes) {
      return VideoDurationValidationResult.invalid(
        fileSizeBytes: fileSizeBytes,
        message:
            'AI Scan supports videos up to $aiMaxVideoSizeLabel and '
            '${formatDuration(maxDuration)} long. '
            'This video is ${formatFileSize(fileSizeBytes)}.',
      );
    }

    VideoPlayerController? controller;

    try {
      controller = VideoPlayerController.file(videoFile);
      await controller.initialize();

      final duration = controller.value.duration;

      if (duration <= Duration.zero) {
        return VideoDurationValidationResult.invalid(
          fileSizeBytes: fileSizeBytes,
          message: 'Could not read the selected video duration.',
        );
      }

      if (duration.compareTo(minDuration) < 0) {
        return VideoDurationValidationResult.invalid(
          duration: duration,
          fileSizeBytes: fileSizeBytes,
          message:
              'AI Scan requires videos to be at least '
              '${formatDuration(minDuration)} long. '
              'This video is ${formatDuration(duration)}.',
        );
      }

      if (duration.compareTo(maxDuration) > 0) {
        return VideoDurationValidationResult.invalid(
          duration: duration,
          fileSizeBytes: fileSizeBytes,
          message:
              'AI Scan supports videos up to ${formatDuration(maxDuration)} '
              'and $aiMaxVideoSizeLabel. '
              'This video is ${formatDuration(duration)} long.',
        );
      }

      return VideoDurationValidationResult.valid(
        duration,
        fileSizeBytes: fileSizeBytes,
      );
    } catch (error) {
      return VideoDurationValidationResult.invalid(
        fileSizeBytes: fileSizeBytes,
        message: 'Could not validate this video: $error',
      );
    } finally {
      await controller?.dispose();
    }
  }

  /// Backwards-compatible method used by older ClipMood code.
  ///
  /// It now performs the complete AI Scan validation, including the 500 MB
  /// limit, so any existing call automatically gets the new protection.
  Future<VideoDurationValidationResult> validateFreeVideoDuration(
    String videoPath, {
    Duration minDuration = freeMinVideoDuration,
    Duration maxDuration = freeMaxVideoDuration,
  }) {
    return validateAiScanVideo(
      videoPath,
      minDuration: minDuration,
      maxDuration: maxDuration,
    );
  }

  /// Validates a video selected for Manual Trim.
  ///
  /// Manual Trim intentionally has no duration limit. Only file existence and
  /// the 1 GB safety limit are checked.
  Future<VideoDurationValidationResult> validateManualTrimVideo(
    String videoPath, {
    int maxFileSizeBytes = manualTrimMaxVideoSizeBytes,
  }) async {
    final videoFile = File(videoPath);

    if (!await videoFile.exists()) {
      return const VideoDurationValidationResult.invalid(
        message: 'Selected video file does not exist.',
      );
    }

    try {
      final fileSizeBytes = await videoFile.length();

      if (fileSizeBytes > maxFileSizeBytes) {
        return VideoDurationValidationResult.invalid(
          fileSizeBytes: fileSizeBytes,
          message:
              'Manual Trim supports videos up to $manualTrimMaxVideoSizeLabel. '
              'This video is ${formatFileSize(fileSizeBytes)}.',
        );
      }

      return VideoDurationValidationResult.valid(
        null,
        fileSizeBytes: fileSizeBytes,
      );
    } catch (error) {
      return VideoDurationValidationResult.invalid(
        message: 'Could not validate this video file: $error',
      );
    }
  }

  static String formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    if (minutes <= 0) {
      return '$seconds sec';
    }

    if (seconds == 0) {
      return '$minutes min';
    }

    return '$minutes min ${seconds.toString().padLeft(2, '0')} sec';
  }

  static String formatFileSize(int bytes) {
    const int kilobyte = 1024;
    const int megabyte = 1024 * 1024;
    const int gigabyte = 1024 * 1024 * 1024;

    if (bytes >= gigabyte) {
      final value = bytes / gigabyte;
      return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} GB';
    }

    if (bytes >= megabyte) {
      final value = bytes / megabyte;
      return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} MB';
    }

    if (bytes >= kilobyte) {
      return '${(bytes / kilobyte).toStringAsFixed(0)} KB';
    }

    return '$bytes bytes';
  }
}
