import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../models/selected_video.dart';

class VideoPickerService {
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
}