import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/selected_video.dart';

/// Result returned after checking whether a selected video is allowed for the
/// current plan.
class VideoDurationValidationResult {
  final bool isValid;
  final Duration? duration;
  final String? message;

  const VideoDurationValidationResult._({
    required this.isValid,
    this.duration,
    this.message,
  });

  const VideoDurationValidationResult.valid(Duration duration)
      : this._(
          isValid: true,
          duration: duration,
        );

  const VideoDurationValidationResult.invalid({
    Duration? duration,
    required String message,
  }) : this._(
          isValid: false,
          duration: duration,
          message: message,
        );
}

class VideoPickerService {
  static const Duration freeMinVideoDuration = Duration(minutes: 1);
  static const Duration freeMaxVideoDuration = Duration(minutes: 5);

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

  /// Free-plan validation used immediately after the user selects a video.
  ///
  /// The gallery picker cannot reliably block files before selection on all
  /// platforms, so the app checks duration after selection and refuses to open
  /// AI/manual editing when the video is outside the allowed range.
  Future<VideoDurationValidationResult> validateFreeVideoDuration(
    String videoPath, {
    Duration minDuration = const Duration(minutes: 1),
    Duration maxDuration = const Duration(minutes: 5),
  }) async {
    final videoFile = File(videoPath);

    if (!await videoFile.exists()) {
      return const VideoDurationValidationResult.invalid(
        message: 'Selected video file does not exist.',
      );
    }

    VideoPlayerController? controller;

    try {
      controller = VideoPlayerController.file(videoFile);
      await controller.initialize();

      final duration = controller.value.duration;

      if (duration <= Duration.zero) {
        return const VideoDurationValidationResult.invalid(
          message: 'Could not read the selected video duration.',
        );
      }

      if (duration.compareTo(minDuration) < 0) {
        return VideoDurationValidationResult.invalid(
          duration: duration,
          message:
              'Free version requires videos to be at least ${formatDuration(minDuration)} long. '
              'This video is ${formatDuration(duration)}.',
        );
      }

      if (duration.compareTo(maxDuration) > 0) {
        return VideoDurationValidationResult.invalid(
          duration: duration,
          message:
              'Free version supports videos up to ${formatDuration(maxDuration)}. '
              'This video is ${formatDuration(duration)}.',
        );
      }

      return VideoDurationValidationResult.valid(duration);
    } catch (e) {
      return VideoDurationValidationResult.invalid(
        message: 'Could not validate this video duration: $e',
      );
    } finally {
      await controller?.dispose();
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
}
